import Foundation
import os

/// M7h L11, L17: carries a receiver's bytes (`SerialPort`, `ReceiverTCPTransport`; a fake in tests).
protocol ReceiverTransport: AnyObject {
    /// For logs: "USB serial port (FT232R USB UART)", "192.168.1.20:60128". Never a device path or a URL.
    var name: String { get }
    /// Each received line, without its delimiter.
    var onLine: ((String) -> Void)? { get set }
    /// Once, when the port goes away (unplugged) or the connection fails or ends.
    var onClose: (() -> Void)? { get set }
    /// L17: whether bytes can be written yet. A serial port is up when made; a TCP connection once it's established.
    var isReady: Bool { get }
    /// L17: once, when a transport that wasn't ready when made becomes ready (a TCP connection). Serial never calls it.
    var onReady: (() -> Void)? { get set }
    /// L17: true when it closed because of how it's set up, not the network (a host name that resolved outside the
    /// LAN): retrying can't help until it's set up again.
    var closedForConfiguration: Bool { get }
    /// M7h step 11: why the connection didn't come up or ended, in plain words for Settings ("Connection refused",
    /// "No answer"); nil when unknown. Never an address.
    var failureReason: String? { get }
    @discardableResult func write(_ bytes: [UInt8]) -> Bool
    func close()
}

extension ReceiverTransport {
    var isReady: Bool { true }

    var closedForConfiguration: Bool { false }

    var failureReason: String? { nil }

    var onReady: (() -> Void)? {
        get { nil }
        set {}
    }
}

/// The time `ReceiverController` waits on, injected so tests run without real time.
protocol ReceiverClock: AnyObject {
    /// Time since an arbitrary start, monotonic.
    var now: Duration { get }
    func sleep(for duration: Duration) async
}

final class SystemReceiverClock: ReceiverClock {
    private let start = ContinuousClock.now

    var now: Duration { start.duration(to: .now) }

    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

nonisolated struct ReceiverVolume: Equatable, Sendable {
    var raw: Int
    var dB: Double?
}

/// L11: the last known status, from replies and unsolicited lines. nil = not known yet.
nonisolated struct ReceiverState: Equatable, Sendable {
    var power: Bool?
    var volume: ReceiverVolume?
    var muted: Bool?

    var isEmpty: Bool { power == nil && volume == nil && muted == nil }

    mutating func apply(_ status: ReceiverStatus) {
        switch status {
        case .power(let on): power = on
        case .volume(let raw, let dB): volume = ReceiverVolume(raw: raw, dB: dB)
        case .muted(let on): muted = on
        }
    }
}

/// M15 step 6b: the receiver's power as it last reported it. `unknown` until a power line arrives on the open
/// connection, and again once the connection closes.
nonisolated enum ReceiverPower: String, Equatable, Sendable {
    case unknown, on, off

    init(_ on: Bool?) {
        switch on {
        case .some(true): self = .on
        case .some(false): self = .off
        case nil: self = .unknown
        }
    }

    /// A receiver over HDMI-CEC: its last Report Power Status (`CECAudioSystem.power`; nil: none, or no answer).
    init(cec status: CECPowerStatus?) {
        self.init(status.map(\.isOn))
    }
}

/// M7h step 10 (security): what a `request` is. Only commands keep a network connection from its idle close (L17).
nonisolated enum ReceiverRequestKind: Sendable {
    /// A button press: counts as activity, and reopens a connection closed for being idle.
    case command
    /// A query a press asked for (the receiver wasn't answering): reopens an idle-closed connection (the press is
    /// the user's), but doesn't count as activity, so the idle close still comes.
    case probe
    /// A query nobody pressed for (a transport came up): neither counts as activity nor reopens anything, so it
    /// can't keep a link that drops and reconnects from idling out.
    case passiveProbe
}

/// L12: Test Connection's replies to the brand's read-only queries; nil = no answer to that query.
typealias ReceiverTestResult = ReceiverState

/// M7h L11, L12, L17: one receiver on one transport. Commands go through a queue that keeps the brand's minimum gap,
/// sends Pioneer's power-on twice and waits after Denon's; replies and unsolicited lines update `state`. When the
/// port goes away it reopens it (serial every 5 s; network after 1, 2, 5, then every 10 s, `ReceiverLink`). A
/// network connection is closed after 5 minutes without commands (some receivers allow one client only) and opened
/// again by the next command. A missing reply is never an error here (power commands often get none, step 1). Main
/// actor.
final class ReceiverController {
    typealias TransportFactory = (_ link: ReceiverLink, _ codec: any ReceiverProtocol) -> (any ReceiverTransport)?

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")

    /// Test Connection waits this long for each query's reply.
    static let replyTimeout: Duration = .seconds(1)
    /// L12: Find Receiver gives each brand this long to answer.
    static let findTimeout: Duration = .seconds(2)
    static let reconnectInterval: Duration = .seconds(5)
    static let pollInterval: Duration = .milliseconds(20)
    /// L17: a network connection is closed after this long without commands.
    static let networkIdleTimeout: Duration = .seconds(300)
    /// L17: a command waits this long for a TCP connection to come up (covers a fallback port too).
    static let readyTimeout: Duration = .seconds(5)
    /// Step 10 (QA minor 3): a volume press waits only this long for one, so an unreachable receiver doesn't hold it.
    static let volumeReadyTimeout: Duration = .milliseconds(1500)
    /// L17: the reconnect backoff starts over only once a connection stayed up this long, or a reply parsed (a host
    /// that accepts and closes at once isn't retried every second).
    static let stableConnection: Duration = .seconds(10)

    private(set) var brand: ReceiverBrand = .none
    private(set) var link: ReceiverLink?
    /// Serial: the configured port, nil = the first USB serial port.
    var portPath: String? {
        if case .serial(let path) = link { path } else { nil }
    }
    private(set) var state = ReceiverState()
    /// When the last line that parsed arrived (`clock.now`), nil before any.
    private(set) var lastReplyAt: Duration?
    /// A port is open, or (L17) a TCP connection is open or still coming up.
    var isConnected: Bool { transport != nil }
    /// M7h step 10: volume can go to the receiver now. It's set up; its link is open or coming up, or was closed only
    /// for being idle (the next command opens it again); it has answered since it was set up; and the last `request`
    /// got its reply. A receiver that stops answering turns false at its first unanswered `request` and true again at
    /// its next reply (to a query, or unsolicited).
    var isAnswering: Bool {
        guard codec != nil, !refusedAsConfigured, answeredSinceConfigure, !lastRequestUnanswered else { return false }
        return transport != nil || closedForIdle
    }
    var onStatusChange: (() -> Void)?
    /// M15 step 6b: from every parsed power line (replies and unsolicited ones, step 6a); `unknown` until the first on
    /// the open connection and again once it closes. Asked for once per connection (`queryPowerOnLinkUp`), never on
    /// a timer.
    var power: ReceiverPower { ReceiverPower(state.power) }
    /// M15 step 6b: `power` changed (a power line, or the connection closed).
    var onPowerChange: (() -> Void)?
    /// M7h step 11: why the link isn't up, for Test Connection ("Connection refused", "No serial port found"); nil
    /// once it's up or a reply came. Never an address or a device path.
    private(set) var lastConnectError: String?
    /// M7h step 11 (QA major): `isConnected`, `isAnswering` or `lastConnectError` changed (a connection came up,
    /// failed or ended, the receiver stopped or started answering). Only on a change, so a receiver that keeps
    /// failing the same way calls it once per reconnect at most.
    var onLinkChange: (() -> Void)?
    /// M7h step 10 (QA minor 2): a transport came up (attached ready, or a TCP connection became ready), so a
    /// volume probe can make the receiver ready without waiting for a press.
    var onLinkUp: (() -> Void)?

    private let clock: any ReceiverClock
    private let makeTransport: TransportFactory
    private var codec: (any ReceiverProtocol)?
    private var transport: (any ReceiverTransport)?
    /// Bumped on every attach and detach, so a closed transport's late callbacks are ignored.
    private var generation = 0
    /// Bumped by `configure` and `stop`: work queued before (commands, Test, Find's reopening) is dropped.
    private var configGeneration = 0
    /// The brand's wake bytes are still to be sent on this transport.
    private var needsWake = false
    private var lastWriteAt: Duration?
    /// Nothing is written before this (Denon's pause after power-on).
    private var notBefore: Duration = .zero
    private var tail: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// Failed reconnects since the link was last up: the index into `link.reconnectDelays`.
    private var reconnectAttempt = 0
    /// L17: network only, closes the connection after `networkIdleTimeout` without commands.
    private var idleTask: Task<Void, Never>?
    private var lastActivityAt: Duration = .zero
    /// The connection was closed for being idle: the next command opens it.
    private(set) var closedForIdle = false
    /// L17: the link can't work as set up (the host resolved outside the LAN): no reconnecting, and no reopening
    /// after the idle close, until `configure` runs again.
    private var refusedAsConfigured = false
    /// When the current transport came up (`clock.now`), nil while it hasn't (or there is none).
    private var readyAt: Duration?
    private var replyCount = 0
    /// Step 10: a line parsed since the last `configure`.
    private var answeredSinceConfigure = false
    /// Step 10: the last `request` wasn't written or got no reply; the next reply clears it.
    private var lastRequestUnanswered = false
    private var lastReplies: [ReceiverStatus.Kind: (count: Int, status: ReceiverStatus)] = [:]

    private struct LinkSnapshot: Equatable {
        var isConnected: Bool
        var isAnswering: Bool
        var lastConnectError: String?
    }

    private var lastLink = LinkSnapshot(isConnected: false, isAnswering: false)

    /// Calls `onLinkChange` when what Settings shows about the link changed since the last call.
    private func noteLinkChange() {
        let now = LinkSnapshot(isConnected: isConnected, isAnswering: isAnswering, lastConnectError: lastConnectError)
        guard now != lastLink else { return }
        lastLink = now
        onLinkChange?()
    }

    init(clock: any ReceiverClock = SystemReceiverClock(), makeTransport: @escaping TransportFactory) {
        self.clock = clock
        self.makeTransport = makeTransport
    }

    /// Sets the brand and serial port and opens the port (`.none` closes it). A port that isn't there yet is retried.
    func configure(brand: ReceiverBrand, serialPort: String?) {
        configure(brand: brand, link: .serial(path: serialPort))
    }

    /// Sets the brand and link and opens it (`.none` closes it). A port that isn't there yet, or a connection that
    /// fails, is retried (`link.reconnectDelays`).
    func configure(brand: ReceiverBrand, link: ReceiverLink) {
        stop()
        self.brand = brand
        self.link = link
        codec = brand.codec
        state = ReceiverState()
        answeredSinceConfigure = false
        lastRequestUnanswered = false
        reconnectAttempt = 0
        closedForIdle = false
        refusedAsConfigured = false
        lastConnectError = nil
        guard codec != nil else { return }
        lastActivityAt = clock.now
        scheduleIdleClose()
        if !connect() {
            if link.isNetwork {
                Self.logger.notice("Receiver: \(brand.rawValue, privacy: .public), can't open the connection yet; retrying")
            } else {
                Self.logger.notice("Receiver: \(brand.rawValue, privacy: .public), no serial port yet; retrying every 5 s")
            }
            scheduleReconnect()
        }
        noteLinkChange()
    }

    /// Closes the port and stops reconnecting. `configure` starts again.
    func stop() {
        configGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        idleTask?.cancel()
        idleTask = nil
        detach()
        noteLinkChange()
    }

    /// Queues `command`; true once it was written (not that the receiver answered). Over the network, opens the
    /// connection again if it was closed for being idle.
    @discardableResult
    func send(_ command: ReceiverCommand) async -> Bool {
        let config = configGeneration
        lastActivityAt = clock.now
        return await enqueue { await self.write(command, config: config) }
    }

    /// M7h step 10: queues `command`, then waits up to `replyTimeout` for the reply it should bring (a volume line for
    /// volume commands, a mute line for mute ones; commands without one return nil at once). nil when it wasn't
    /// written or nothing came in time: `isAnswering` is then false until the next reply.
    /// `readyTimeout`: how long to wait for a TCP connection to come up first. `kind`: see `ReceiverRequestKind`.
    func request(_ command: ReceiverCommand, readyTimeout: Duration = ReceiverController.readyTimeout,
                 kind requestKind: ReceiverRequestKind = .command) async -> ReceiverStatus? {
        guard let kind = Self.replyKind(of: command) else {
            await send(command)
            return nil
        }
        let config = configGeneration
        if requestKind == .command { lastActivityAt = clock.now }
        let reopens = requestKind != .passiveProbe
        let reply = await enqueue { () async -> ReceiverStatus? in
            let before = self.replyCount
            guard await self.write(command, config: config, readyTimeout: readyTimeout, reopensIfIdle: reopens)
            else { return nil }
            return await self.waitForReply(kind, after: before)
        }
        if reply == nil, config == configGeneration { lastRequestUnanswered = true }
        noteLinkChange()
        return reply
    }

    /// L12: the brand's read-only queries on the open port, each reply awaited up to `replyTimeout`. The brand's
    /// wake bytes go first each time (the receiver may have gone to standby since the port opened).
    func test() async -> ReceiverTestResult {
        let config = configGeneration
        lastActivityAt = clock.now
        return await enqueue { await self.runTest(config: config) }
    }

    /// M15 step 6b (user, 2026-11-24): asks for the receiver's power once when its link comes up, so `power` is known
    /// from the start (AppDelegate calls it from `onLinkUp`, after the volume probe, which then goes first). Once per
    /// connection, never on a timer. Passive like that probe: not activity (the idle close still comes), it reopens
    /// nothing, and a missing reply changes nothing (`isAnswering` stays as it was).
    func queryPowerOnLinkUp() {
        guard codec != nil, let transport, transport.isReady else { return }
        let config = configGeneration
        let current = generation
        Task { [weak self] in
            guard let self else { return }
            _ = await enqueue { () async -> Bool in
                // Only on the connection that came up.
                guard self.generation == current else { return false }
                return await self.write(.queryPower, config: config, reopensIfIdle: false)
            }
        }
    }

    /// L12: each brand's read-only queries at its own serial settings on `path` (nil = the first USB serial port),
    /// `findTimeout` per brand; the first brand that answers. The configured port is reopened afterwards.
    func find(onPort path: String?) async -> ReceiverBrand? {
        await enqueue { await self.runFind(path) }
    }

    /// The app's factory: a serial port (`SerialPort`) or a TCP connection (`ReceiverTCPTransport`, L17).
    static func systemTransport(link: ReceiverLink, codec: any ReceiverProtocol) -> (any ReceiverTransport)? {
        switch link {
        case .serial(let path): SerialPort.receiverTransport(path: path, codec: codec)
        case .network(let host, let port): ReceiverTCPTransport.receiverTransport(host: host, port: port, codec: codec)
        }
    }

    // MARK: Queue

    /// Runs `work` after everything queued before it.
    private func enqueue<T: Sendable>(_ work: @escaping () async -> T) async -> T {
        let previous = tail
        let task = Task { () async -> T in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    /// Writes `command` with the current codec, unless `configure` or `stop` ran since it was queued (`config`).
    private func write(_ command: ReceiverCommand, config: Int,
                       readyTimeout: Duration = ReceiverController.readyTimeout, reopensIfIdle: Bool = true) async -> Bool {
        if reopensIfIdle { reopenIfIdle(config: config) }
        guard config == configGeneration, let codec else { return false }
        let rule = codec.wakeRule
        let count = command == .powerOn ? max(1, rule.powerOnCount) : 1
        for index in 0..<count {
            let gap = index == 0 ? codec.minimumGap : max(codec.minimumGap, rule.powerOnRepeatGap)
            guard await writeBytes(codec.encode(command), gap: gap, codec: codec, config: config,
                                   readyTimeout: readyTimeout) else { return false }
        }
        if command == .powerOn, rule.pauseAfterPowerOn > .zero {
            notBefore = clock.now + rule.pauseAfterPowerOn
        }
        return true
    }

    private func writeBytes(_ bytes: [UInt8], gap: Duration, codec: any ReceiverProtocol, config: Int,
                            readyTimeout: Duration) async -> Bool {
        guard await waitUntilReady(config: config, timeout: readyTimeout) else { return false }
        if needsWake {
            needsWake = false
            let wake = codec.wakeRule.onOpen
            if !wake.isEmpty {
                await waitForGap(codec.minimumGap)
                guard config == configGeneration, let transport else { return false }
                transport.write(wake)
                lastWriteAt = clock.now
            }
        }
        await waitForGap(gap)
        // Gone, or reconfigured to another brand or port, while waiting.
        guard config == configGeneration, let transport else { return false }
        let written = transport.write(bytes)
        lastWriteAt = clock.now
        return written
    }

    /// L17: a TCP connection takes a moment to come up; serial is ready at once (no wait).
    private func waitUntilReady(config: Int, timeout: Duration) async -> Bool {
        let deadline = clock.now + timeout
        while true {
            guard config == configGeneration, let transport else { return false }
            if transport.isReady { return true }
            guard clock.now < deadline else { return false }
            await clock.sleep(for: Self.pollInterval)
        }
    }

    private func waitForGap(_ gap: Duration) async {
        var earliest = notBefore
        if let lastWriteAt { earliest = max(earliest, lastWriteAt + gap) }
        let now = clock.now
        if earliest > now { await clock.sleep(for: earliest - now) }
    }

    // MARK: Test and find (L12)

    private func runTest(config: Int) async -> ReceiverTestResult {
        var result = ReceiverTestResult()
        reopenIfIdle(config: config)
        guard config == configGeneration, let codec, transport != nil else { return result }
        needsWake = true
        for query in codec.probeQueries where query.isQuery {
            let before = replyCount
            guard await write(query, config: config) else { break }
            guard let kind = Self.replyKind(of: query) else { continue }
            if let status = await waitForReply(kind, after: before) { result.apply(status) }
        }
        return result
    }

    private func waitForReply(_ kind: ReceiverStatus.Kind, after count: Int) async -> ReceiverStatus? {
        let deadline = clock.now + Self.replyTimeout
        while true {
            if let reply = lastReplies[kind], reply.count > count { return reply.status }
            guard transport != nil, clock.now < deadline else { return nil }
            await clock.sleep(for: Self.pollInterval)
        }
    }

    private static func replyKind(of query: ReceiverCommand) -> ReceiverStatus.Kind? {
        switch query {
        case .queryPower: .power
        case .queryVolume, .volumeUp, .volumeDown: .volume
        case .queryMute, .mute: .muted
        case .powerOn, .powerOff: nil
        }
    }

    private final class ProbeState {
        var answered = false
        var closed = false
    }

    private func runFind(_ path: String?) async -> ReceiverBrand? {
        let config = configGeneration
        reconnectTask?.cancel()
        reconnectTask = nil
        detach()
        defer {
            // Reopen the configured port, unless `configure` or `stop` ran during the search.
            if config == configGeneration, codec != nil, !connect() { scheduleReconnect() }
            noteLinkChange()
        }
        for candidate in ReceiverBrand.supported {
            guard let codec = candidate.codec, let probe = makeTransport(.serial(path: path), codec) else { continue }
            if await Self.probe(probe, codec: codec, clock: clock) {
                Self.logger.notice("Find Receiver: \(candidate.rawValue, privacy: .public) answered on \(probe.name, privacy: .public)")
                return candidate
            }
        }
        Self.logger.notice("Find Receiver: no brand answered")
        return nil
    }

    /// L12: `codec`'s read-only queries (after its wake bytes) on `transport`, which isn't attached to a controller;
    /// true once a reply line parses within `timeout`. Waits up to `readyTimeout` for a TCP connection to come up
    /// first (serial is up at once). Closes `transport`. Used by Find Receiver (serial) and Find on Network (L17).
    static func probe(_ transport: any ReceiverTransport, codec: any ReceiverProtocol, clock: any ReceiverClock,
                      timeout: Duration = findTimeout, readyTimeout: Duration = readyTimeout) async -> Bool {
        let probeState = ProbeState()
        transport.onLine = { line in
            if codec.parse(line: line) != nil { probeState.answered = true }
        }
        transport.onClose = { probeState.closed = true }
        defer {
            transport.onLine = nil
            transport.onClose = nil
            transport.onReady = nil
            transport.close()
        }
        let readyStart = clock.now
        while !transport.isReady, !probeState.closed, clock.now - readyStart < readyTimeout {
            await clock.sleep(for: pollInterval)
        }
        guard transport.isReady, !probeState.closed else { return false }
        let start = clock.now
        var last: Duration?
        if !codec.wakeRule.onOpen.isEmpty {
            transport.write(codec.wakeRule.onOpen)
            last = clock.now
        }
        for query in codec.probeQueries where query.isQuery && !probeState.answered {
            if let last, last + codec.minimumGap > clock.now {
                await clock.sleep(for: last + codec.minimumGap - clock.now)
            }
            transport.write(codec.encode(query))
            last = clock.now
        }
        while !probeState.answered, !probeState.closed, clock.now - start < timeout {
            await clock.sleep(for: pollInterval)
        }
        return probeState.answered
    }

    // MARK: Transport

    @discardableResult
    private func connect() -> Bool {
        guard let codec, let link else { return false }
        guard let transport = makeTransport(link, codec) else {
            lastConnectError = link.isNetwork ? "Not a LAN address or name" : "No serial port found"
            noteLinkChange()
            return false
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        attach(transport)
        noteLinkChange()
        Self.logger.info("Receiver: \(self.brand.rawValue, privacy: .public) on \(transport.name, privacy: .public)")
        return true
    }

    private func attach(_ transport: any ReceiverTransport) {
        generation += 1
        let current = generation
        transport.onLine = { [weak self] line in
            guard let self, generation == current else { return }
            received(line)
        }
        transport.onClose = { [weak self] in
            guard let self, generation == current else { return }
            portGone()
        }
        transport.onReady = { [weak self] in
            guard let self, generation == current else { return }
            readyAt = clock.now
            lastConnectError = nil
            noteLinkChange()
            onLinkUp?()
        }
        readyAt = transport.isReady ? clock.now : nil
        if transport.isReady { lastConnectError = nil }
        // Serial's reconnect wait is fixed; a TCP connection starts the backoff over once it proves stable (L17).
        if transport.isReady, link?.isNetwork != true { reconnectAttempt = 0 }
        self.transport = transport
        needsWake = true
        if transport.isReady { onLinkUp?() }
    }

    private func detach() {
        generation += 1
        guard let transport else { return }
        transport.onLine = nil
        transport.onClose = nil
        transport.onReady = nil
        transport.close()
        self.transport = nil
        readyAt = nil
        // M15 step 6b: nothing is known about the power once the connection is gone.
        if state.power != nil {
            state.power = nil
            onStatusChange?()
            onPowerChange?()
        }
    }

    private func portGone() {
        if transport?.closedForConfiguration == true {
            // Logged once: nothing retries until the receiver is set up again.
            Self.logger.notice("Receiver: the address isn't on the LAN; not reconnecting until the receiver is set up again")
            lastConnectError = transport?.failureReason ?? "The address isn't on this network"
            refusedAsConfigured = true
            reconnectTask?.cancel()
            reconnectTask = nil
            detach()
            noteLinkChange()
            return
        }
        if link?.isNetwork == true {
            if let readyAt {
                if clock.now - readyAt >= Self.stableConnection { reconnectAttempt = 0 }
                Self.logger.notice("Receiver connection closed")
                lastConnectError = "The receiver closed the connection"
            } else {
                Self.logger.notice("Receiver: no connection to \(self.transport?.name ?? "the receiver", privacy: .public)")
                lastConnectError = transport?.failureReason ?? "No answer"
            }
        } else {
            Self.logger.notice("Receiver port gone")
            lastConnectError = "The serial port went away"
        }
        detach()
        scheduleReconnect()
        noteLinkChange()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        guard codec != nil else { return }
        let config = configGeneration
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let (clock, delay) = self?.nextReconnectDelay() else { return }
                await clock.sleep(for: delay)
                guard !Task.isCancelled, let self, config == configGeneration, codec != nil else { return }
                if connect() { return }   // connect() clears reconnectTask
            }
        }
    }

    /// The wait before the next reconnect attempt (`link.reconnectDelays`, the last repeating), counting it.
    private func nextReconnectDelay() -> (any ReceiverClock, Duration) {
        let delays = link?.reconnectDelays ?? [Self.reconnectInterval]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt += 1
        return (clock, delay)
    }

    // MARK: Idle close (L17, network only)

    private func scheduleIdleClose() {
        idleTask?.cancel()
        idleTask = nil
        guard link?.isNetwork == true, codec != nil else { return }
        let config = configGeneration
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let (clock, wait) = self?.idleWait(config: config) else { return }
                if wait > .zero {
                    await clock.sleep(for: wait)
                    continue
                }
                guard !Task.isCancelled, let self, config == configGeneration else { return }
                closeIdle()
                return
            }
        }
    }

    /// How long until the connection has been idle for `networkIdleTimeout`; nil once reconfigured.
    private func idleWait(config: Int) -> (any ReceiverClock, Duration)? {
        guard config == configGeneration else { return nil }
        return (clock, lastActivityAt + Self.networkIdleTimeout - clock.now)
    }

    private func closeIdle() {
        idleTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        closedForIdle = true
        reconnectAttempt = 0
        if transport != nil {
            Self.logger.notice("Receiver: closed the connection after 5 minutes without commands")
        } else {
            Self.logger.notice("Receiver: stopped reconnecting after 5 minutes without commands")
        }
        detach()
        noteLinkChange()
    }

    /// L17: a command or Test after the idle close opens the connection again. While reconnecting with backoff,
    /// commands fail at once instead (they'd each wait for a connection that just failed).
    private func reopenIfIdle(config: Int) {
        guard config == configGeneration, closedForIdle, !refusedAsConfigured, codec != nil, link?.isNetwork == true,
              transport == nil
        else { return }
        closedForIdle = false
        reconnectAttempt = 0
        lastActivityAt = clock.now
        if idleTask == nil { scheduleIdleClose() }
        if !connect() { scheduleReconnect() }
    }

    private func received(_ line: String) {
        guard let status = codec?.parse(line: line) else { return }
        // A receiver that answers is a working link: the backoff starts over (L17).
        reconnectAttempt = 0
        replyCount += 1
        lastReplies[status.kind] = (replyCount, status)
        lastReplyAt = clock.now
        answeredSinceConfigure = true
        lastRequestUnanswered = false
        lastConnectError = nil
        noteLinkChange()
        let old = state
        state.apply(status)
        if state != old {
            Self.logger.debug("Receiver status: \(String(describing: status), privacy: .public)")
            onStatusChange?()
            if state.power != old.power { onPowerChange?() }
        }
    }
}

/// M15 step 6b (D45 amended): the set-up receiver's power (serial, network or HDMI-CEC; never the TV's network), fed by
/// AppDelegate on every change. When it turns off without MMTVL's Power (`on` → `off`, not within
/// `ownPowerOffWindow` of MMTVL's own Power-off, never from `unknown`), `onTurnedOff` runs: the TV was turned off with
/// its own remote (the receiver following over HDMI-CEC), or the receiver with its own. Main actor.
final class ReceiverPowerWatch {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")

    /// An "off" this soon after MMTVL's own Power-off is that Power-off's (the receiver's reply, a CEC TV's Standby).
    static let ownPowerOffWindow: TimeInterval = 30
    /// Security L-1: `onTurnedOff` runs at most this often, so a host posing as the network receiver (or a CEC device)
    /// flipping on and off can't keep pulling the screen home.
    static let turnedOffInterval: TimeInterval = 60

    private(set) var power: ReceiverPower = .unknown
    /// The receiver reports on (`unknown` isn't on).
    var isOn: Bool { power == .on }
    var onTurnedOff: () -> Void = {}

    private var ownPowerOffAt: TimeInterval?
    private var lastTurnedOffAt: TimeInterval?
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// MMTVL's Power-off started (`PowerController.onPowerOff`).
    func noteOwnPowerOff() {
        ownPowerOffAt = now()
    }

    func update(_ new: ReceiverPower) {
        let old = power
        guard new != old else { return }
        power = new
        Self.logger.debug("Receiver power: \(old.rawValue, privacy: .public) → \(new.rawValue, privacy: .public)")
        guard old == .on, new == .off else { return }
        let time = now()
        if let ownPowerOffAt, time - ownPowerOffAt < Self.ownPowerOffWindow { return }
        if let lastTurnedOffAt, time - lastTurnedOffAt < Self.turnedOffInterval {
            Self.logger.debug("Receiver power: off again within 60 s; not going home again")
            return
        }
        lastTurnedOffAt = time
        onTurnedOff()
    }

    /// What AppDelegate runs when the receiver turned off without MMTVL's Power: the first half of Power-off (no
    /// `poweredOffByMMTVL`, nothing sent, the displays stay as they are).
    static func turnedOffHandler(stopPlayback: @escaping () -> Void, goHome: @escaping () -> Void) -> () -> Void {
        {
            stopPlayback()
            goHome()
            PowerController.logger.notice("Power: the receiver turned off; stopped playback, home")
        }
    }
}
