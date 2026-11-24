import Foundation
import os

/// What `SparkleBridge` tells `SoftwareUpdater` (M15). No Sparkle type crosses.
enum UpdateEvent {
    /// A user-initiated check began (`showUserInitiatedUpdateCheck`).
    case checking
    /// `didFindValidUpdate` / `showUpdateFound`.
    case found(AvailableUpdate, userInitiated: Bool)
    case notFound
    /// L12: the failure and the error's domain and code only, never its text (it can hold the feed URL).
    case failed(UpdateFailure, UpdateErrorCode)
    case downloadStarted
    case downloadProgress(Double?)
    case extracting
    /// `willInstallUpdateOnQuit`: downloaded and staged by Sparkle's installer; `installNow` installs and relaunches.
    case staged(AvailableUpdate, installNow: () -> Void)
    /// `updaterWillRelaunchApplication`.
    case willRelaunch
    /// `dismissUpdateInstallation`.
    case dismissed
}

/// `SoftwareUpdater`'s answer to `showUpdateFound` and `showReadyToInstallAndRelaunch`.
enum UpdateChoice: Equatable {
    case install, dismiss
}

/// An error's domain and code (L12: what the log shows of it).
nonisolated struct UpdateErrorCode: Equatable, Sendable {
    var domain: String
    var code: Int

    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    init(_ error: any Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code)
    }
}

/// Where `SparkleBridge` (and `FakeUpdaterEngine`) send Sparkle's callbacks. `SoftwareUpdater` is the one sink.
protocol UpdateEventSink: AnyObject {
    /// Every callback without an answer. For `.staged` it returns whether the install block is held (Sparkle then
    /// waits for it); otherwise the result means nothing.
    @discardableResult func handle(_ event: UpdateEvent) -> Bool
    /// `showUpdateFound`: install (an Install press is under way) or dismiss (L6: no session is kept open).
    func choice(forFound update: AvailableUpdate, userInitiated: Bool) async -> UpdateChoice
    /// `showReadyToInstallAndRelaunch`: the quit is allowed first.
    func choiceForReadyToInstall() async -> UpdateChoice
    /// `showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)`.
    func installingUpdate(applicationTerminated: Bool, retry: @escaping () -> Void)
    /// `show(_ permissionRequest)`: `settings.json`'s `updateChecks` (L5).
    var allowsAutomaticChecks: Bool { get }
}

/// N1: the feed Sparkle will read, as Sparkle reads it (`SPUUpdater retrieveFeedURL`, `SUHost objectForKey`): user
/// defaults first (`defaults write`, or the `-SUFeedURL` argument), then Info.plist. Only its host is kept.
nonisolated struct UpdateFeed: Equatable, Sendable {
    static let key = "SUFeedURL"

    /// The effective feed's host, lowercased ("github.com"); "none" when there's no usable URL.
    var host: String
    /// The user-defaults value differs from Info.plist's (step 14's test feed, or one left behind).
    var isTestFeed: Bool

    init(userDefaultsValue: String?, infoPlistValue: String?) {
        let effective = userDefaultsValue ?? infoPlistValue
        host = effective.flatMap { URL(string: Self.stripped($0))?.host()?.lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "none"
        isTestFeed = userDefaultsValue != nil && userDefaultsValue.map(Self.stripped) != infoPlistValue.map(Self.stripped)
    }

    static var current: UpdateFeed {
        UpdateFeed(userDefaultsValue: UserDefaults.standard.object(forKey: key) as? String,
                   infoPlistValue: Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    /// "Feed: github.com", plus " (test feed)". Never the URL.
    var logLine: String { isTestFeed ? "Feed: \(host) (test feed)" : "Feed: \(host)" }

    /// Sparkle strips quotes some feed publishers add (`_stripFeedString`).
    private static func stripped(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

/// M15: the update state machine behind Settings → System → Software Update and the home notice. It owns the engine
/// (Sparkle, or a fake), the held install block, the idle loop and the quit permission. Main actor.
///
/// Off (L4): Debug builds and `-windowed` have no engine and make no request. Off mode (L6) never holds a Sparkle
/// session: a found update is dismissed and remembered. When Idle / At Night hold the staged update's block and call
/// it when `UpdateIdlePolicy` allows. Every install path allows the quit first and takes it back after 60 s if MMTVL is
/// still running (L14).
@Observable
final class SoftwareUpdater: UpdateEventSink {
    /// Runs `work` after the delay on the main actor; the returned closure cancels it. Tests inject a manual clock.
    typealias Schedule = @MainActor (Duration, @escaping () -> Void) -> () -> Void

    /// What the updater does to the app (AppDelegate's closures).
    struct Hooks {
        /// The updater's own quit permission (AppDelegate's `updateQuitAllowed`), so the kiosk lock's quit guard lets
        /// Sparkle's quit through.
        var allowQuit: () -> Void = {}
        /// Takes only that permission back (security L-b: a logout's or ⌘Q's `allowsTermination` stays).
        var revokeQuit: () -> Void = {}
        /// What the idle loop sees each tick.
        var snapshot: () -> UpdateIdleSnapshot = { SoftwareUpdater.notIdle }
        /// L8: `update-relaunch.json`, before an idle install's block is called with the TV off.
        var writeMarker: () -> Void = {}
        /// L8, security L-c: removes it again when that install doesn't happen.
        var deleteMarker: () -> Void = {}
        var showToast: (String) -> Void = { _ in }
        var now: () -> Date = { Date() }
        var schedule: Schedule = SoftwareUpdater.scheduleOnMainActor
    }

    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Updater")
    /// L14.
    static let quitRevokeDelay: Duration = .seconds(60)
    static let idleTickInterval: Duration = .seconds(60)
    /// L6: with checks on and mode Off, a probe this long after launch brings the home notice back after a relaunch.
    static let launchProbeDelay: Duration = .seconds(30)
    static let installFailedToast = "Couldn't Install the Update"
    /// `SUSparkleErrorDomain`'s value (`SUConstants.m`).
    static let sparkleErrorDomain = "SUSparkleErrorDomain"
    /// A snapshot in which nothing allows an install.
    static let notIdle = UpdateIdleSnapshot(mmtvlFrontmost: false, exitedToDesktop: false, mirroring: false,
                                            poweredOffByMMTVL: false, screenSaverOurs: false, stillPhase: .awake,
                                            videoPlaying: false, hour: 12)

    private(set) var status: UpdateStatus
    /// Step 8: Settings' status refresh and the home label.
    @ObservationIgnored var onStatusChange: (UpdateStatus) -> Void = { _ in }
    /// N1: nil while updates are off.
    let feed: UpdateFeed?
    let installed: AppVersion

    @ObservationIgnored private let engine: (any UpdaterEngine)?
    @ObservationIgnored private let hooks: Hooks
    @ObservationIgnored private var checks = true
    @ObservationIgnored private var mode: AutomaticUpdates = .off

    private enum Intent { case report, install }
    /// What the user asked for in the running session (Check Now or Install); nil for Sparkle's own checks.
    @ObservationIgnored private var intent: Intent?
    /// The last update the feed offered (cleared when it says there's none).
    @ObservationIgnored private var knownUpdate: AvailableUpdate?
    /// When Idle / At Night: Sparkle's immediate-install block for the staged update.
    @ObservationIgnored private var heldInstall: (update: AvailableUpdate, installNow: () -> Void)?
    /// Set while the quit is allowed for an install; cancels the 60-s revoke.
    @ObservationIgnored private var cancelQuitRevoke: (() -> Void)?
    /// QA: the held block was called and its 60 s haven't run out, so it isn't called again meanwhile.
    @ObservationIgnored private var heldAttemptInFlight = false
    /// QA, security L-a: held attempts that didn't finish for the staged update; after the second the block is dropped.
    @ObservationIgnored private var heldTimeouts = 0
    /// The idle loop wrote `update-relaunch.json` for the attempt under way.
    @ObservationIgnored private var markerWritten = false
    @ObservationIgnored private var cancelIdleTick: (() -> Void)?
    @ObservationIgnored private var cancelProbe: (() -> Void)?
    /// `showInstallingUpdate`'s retry is used once per install.
    @ObservationIgnored private var retriedTermination = false
    @ObservationIgnored private var installLogged = false
    /// Sparkle reports some things twice (delegate and user driver): the same line within 5 s is logged once.
    @ObservationIgnored private var lastLog: (text: String, at: Date)?

    /// Updates are off (L4): no engine, nothing is ever requested.
    init(off reason: UpdateStatus.OffReason, installed: AppVersion = .current) {
        status = .off(reason)
        engine = nil
        feed = nil
        hooks = Hooks()
        self.installed = installed
    }

    init(engine: any UpdaterEngine, feed: UpdateFeed, installed: AppVersion = .current, hooks: Hooks) {
        status = .idle(lastChecked: nil)
        self.engine = engine
        self.feed = feed
        self.hooks = hooks
        self.installed = installed
    }

    /// L4: Debug builds never update; `-windowed` neither (Sparkle's relaunch drops the arguments).
    static func offReason(debugBuild: Bool, windowed: Bool) -> UpdateStatus.OffReason? {
        if debugBuild { return .developmentBuild }
        if windowed { return .windowed }
        return nil
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var feedHost: String? { feed?.host }
    var isTestFeed: Bool { feed?.isTestFeed ?? false }
    var lastUpdateCheckDate: Date? { engine?.lastUpdateCheckDate }
    /// L11: "Update Available: 1.5.0" while an update is available, downloading, installing or ready.
    var homeLabel: String? { status.homeLabel(installed: installed) }

    // MARK: Control

    /// At launch: the feed's host (N1), the settings (checks first, then downloads), then Sparkle. A start error is
    /// `.failed(.checkFailed)`, logged. With checks on and mode Off, a probe 30 s later (L6).
    func start(checks: Bool, mode: AutomaticUpdates) {
        guard let engine, let feed else {
            if case .off(let reason) = status { log("Updates are off (\(reason.logText))") }
            return
        }
        log(feed.logLine)
        engine.events = self
        apply(checks: checks, mode: mode)
        do {
            try engine.start()
        } catch {
            log(Self.logLine(for: .checkFailed, UpdateErrorCode(error)))
            set(.failed(.checkFailed))
            return
        }
        if case .idle = status { set(.idle(lastChecked: engine.lastUpdateCheckDate)) }
        if checks && mode == .off {
            cancelProbe = hooks.schedule(Self.launchProbeDelay) { [weak self] in self?.probe() }
        }
    }

    /// `settings.json` changed (or at start): checks, then downloads (Sparkle ignores the downloads setter while
    /// automatic updates aren't allowed). Checks off: no notice, unless an update is staged or on its way.
    func apply(checks: Bool, mode: AutomaticUpdates) {
        self.checks = checks
        self.mode = mode
        guard let engine else { return }
        engine.automaticallyChecksForUpdates = checks
        engine.automaticallyDownloadsUpdates = checks && mode != .off
        if !checks {
            switch status {
            case .available, .upToDate, .failed: set(.idle(lastChecked: engine.lastUpdateCheckDate))
            default: break
            }
        }
        updateIdleLoop()
    }

    /// Check Now: a user-initiated check that only reports.
    func checkNow() {
        guard let engine, heldInstall == nil, !engine.sessionInProgress else { return }
        intent = .report
        set(.checking)
        logChecking()
        engine.checkForUpdates()
    }

    /// Install: the held block (the silent path), else a fresh user-initiated check answered Install all the way.
    /// While Sparkle's own session runs (an automatic download), nothing.
    func install() {
        guard let engine else { return }
        if heldInstall != nil {
            installHeld(reason: "Install")
            return
        }
        guard !engine.sessionInProgress else { return }
        intent = .install
        logChecking()
        engine.checkForUpdates()
    }

    /// L15: Relaunch MMTVL (Settings, the power menu) installs a staged update, since Sparkle would install it at
    /// that quit anyway, and this way MMTVL comes back. False: nothing staged; relaunch as usual.
    /// True during an attempt too (QA), so Relaunch doesn't also run `AppRelauncher` mid-install.
    func installStagedForRelaunch() -> Bool {
        guard heldInstall != nil else { return false }
        installHeld(reason: "relaunch")
        return true
    }

    /// `applicationWillTerminate`: the idle loop and the launch probe stop.
    func cancelIdleLoop() {
        cancelIdleTick?()
        cancelIdleTick = nil
        cancelProbe?()
        cancelProbe = nil
    }

    // MARK: UpdateEventSink

    var allowsAutomaticChecks: Bool { checks }

    @discardableResult
    func handle(_ event: UpdateEvent) -> Bool {
        guard let engine else { return false }
        switch event {
        case .checking:
            // An Install press keeps showing the update it's installing.
            if intent != .install, heldInstall == nil { set(.checking) }
        case .found(let update, _):
            knownUpdate = update
            logOnce("Update available: \(update.version) build \(update.build)")
            switch status {
            case .ready, .downloading, .installing: break
            default: set(.available(update))
            }
        case .notFound:
            knownUpdate = nil
            intent = nil
            logOnce("Up to date")
            if heldInstall == nil { set(.upToDate(lastChecked: engine.lastUpdateCheckDate ?? hooks.now())) }
        case .failed(let failure, let code):
            logOnce(Self.logLine(for: failure, code))
            let userAsked = intent != nil
            intent = nil
            // QA: a check failure keeps a staged update (and an attempt under way); an install failure drops it.
            if failure == .installFailed || heldInstall == nil {
                heldInstall = nil
                heldAttemptInFlight = false
                undoPrepareToQuit()
                resetInstall()
                deleteMarkerIfWritten()
            }
            // A failed background check keeps the notice of an update already found.
            if failure == .checkFailed, !userAsked, status.update != nil { break }
            set(.failed(failure))
        case .downloadStarted:
            if let knownUpdate { set(.downloading(knownUpdate, fraction: nil)) }
        case .downloadProgress(let fraction):
            if let knownUpdate { set(.downloading(knownUpdate, fraction: fraction)) }
        case .extracting:
            if let knownUpdate { set(.installing(knownUpdate)) }
        case .staged(let update, let installNow):
            knownUpdate = update
            guard mode != .off else { return false }
            heldInstall = (update, installNow)
            heldAttemptInFlight = false
            heldTimeouts = 0
            intent = nil
            log("Downloaded \(update.version) build \(update.build); installs \(mode.installPhrase)")
            set(.ready(update))
            return true
        case .willRelaunch:
            prepareToQuit()
            if !installLogged, let update = heldInstall?.update ?? knownUpdate { logInstalling(update, reason: "relaunching") }
        case .dismissed:
            intent = nil
            guard heldInstall == nil else { break }
            undoPrepareToQuit()
            resetInstall()
            deleteMarkerIfWritten()
            switch status {
            case .checking, .downloading, .installing:
                if let knownUpdate { set(.available(knownUpdate)) } else { set(.idle(lastChecked: engine.lastUpdateCheckDate)) }
            default: break
            }
        }
        return true
    }

    func choice(forFound update: AvailableUpdate, userInitiated: Bool) async -> UpdateChoice {
        guard handle(.found(update, userInitiated: userInitiated)) else { return .dismiss }
        if intent == .install { return .install }
        intent = nil
        return .dismiss
    }

    func choiceForReadyToInstall() async -> UpdateChoice {
        guard intent == .install else { return .dismiss }
        prepareToQuit()
        if let knownUpdate {
            logInstalling(knownUpdate, reason: "Install")
            set(.installing(knownUpdate))
        }
        return .install
    }

    func installingUpdate(applicationTerminated: Bool, retry: @escaping () -> Void) {
        guard engine != nil else { return }
        if let knownUpdate { set(.installing(knownUpdate)) }
        guard !applicationTerminated else { return }
        prepareToQuit()
        guard !retriedTermination else { return }
        retriedTermination = true
        retry()
    }

    // MARK: Installing

    /// One call of the block per attempt (QA): while one is under way (its 60 s), another press does nothing.
    private func installHeld(reason: String) {
        guard let held = heldInstall, !heldAttemptInFlight else { return }
        heldAttemptInFlight = true
        prepareToQuit()
        logInstalling(held.update, reason: reason)
        set(.installing(held.update))
        held.installNow()
    }

    /// L14: lets the next quit through, and takes that back after 60 s if MMTVL is still running.
    private func prepareToQuit() {
        hooks.allowQuit()
        cancelQuitRevoke?()
        cancelQuitRevoke = hooks.schedule(Self.quitRevokeDelay) { [weak self] in self?.installDidNotFinish() }
    }

    private func undoPrepareToQuit() {
        guard let cancel = cancelQuitRevoke else { return }
        cancel()
        cancelQuitRevoke = nil
        hooks.revokeQuit()
    }

    /// L14, amended (QA, security L-a): one retry, then let go. After the first held attempt that didn't finish the
    /// update is `.ready` again (the next allowed tick, Install or Relaunch tries once more); after the second the
    /// block is dropped, so Relaunch is a plain relaunch and Check Now works (Sparkle still installs at the next quit).
    private func installDidNotFinish() {
        cancelQuitRevoke = nil
        hooks.revokeQuit()
        intent = nil
        resetInstall()
        deleteMarkerIfWritten()
        let wasHeldAttempt = heldAttemptInFlight
        heldAttemptInFlight = false
        if wasHeldAttempt, let held = heldInstall, heldTimeouts == 0 {
            heldTimeouts = 1
            log("Install didn't finish; quit allowed again (will retry)")
            set(.ready(held.update))
        } else {
            if wasHeldAttempt { heldInstall = nil }
            log("Install didn't finish; quit allowed again")
            set(.failed(.installFailed))
        }
        hooks.showToast(Self.installFailedToast)
    }

    private func deleteMarkerIfWritten() {
        guard markerWritten else { return }
        markerWritten = false
        hooks.deleteMarker()
    }

    private func resetInstall() {
        retriedTermination = false
        installLogged = false
    }

    // MARK: The idle loop

    /// Runs only while a staged update is held and the mode is When Idle or At Night.
    private var idleLoopShouldRun: Bool {
        guard heldInstall != nil, case .ready = status else { return false }
        return mode == .whenIdle || mode == .atNight
    }

    private func updateIdleLoop() {
        if idleLoopShouldRun {
            if cancelIdleTick == nil { scheduleIdleTick() }
        } else {
            cancelIdleTick?()
            cancelIdleTick = nil
        }
    }

    private func scheduleIdleTick() {
        cancelIdleTick = hooks.schedule(Self.idleTickInterval) { [weak self] in
            guard let self else { return }
            cancelIdleTick = nil
            idleTick()
            updateIdleLoop()
        }
    }

    /// One attempt when the policy allows: the marker (TV off), the quit allowed, then the block.
    private func idleTick() {
        guard idleLoopShouldRun else { return }
        let snapshot = hooks.snapshot()
        guard UpdateIdlePolicy.mayInstall(mode, snapshot) else { return }
        if snapshot.poweredOffByMMTVL {
            hooks.writeMarker()
            markerWritten = true
        }
        installHeld(reason: Self.idleReason(snapshot))
    }

    static func idleReason(_ snapshot: UpdateIdleSnapshot) -> String {
        if snapshot.poweredOffByMMTVL && snapshot.mmtvlFrontmost { return "the TV is off" }
        if snapshot.screenSaverOurs { return "screen saver" }
        return "at night, nothing playing"
    }

    private func probe() {
        cancelProbe = nil
        guard let engine, checks, !engine.sessionInProgress else { return }
        logChecking()
        engine.checkForUpdateInformation()
    }

    // MARK: Status and log

    private func set(_ new: UpdateStatus) {
        guard new != status else { return }
        status = new
        onStatusChange(new)
        updateIdleLoop()
    }

    /// L12: Sparkle's errors as a failure and a domain and code. nil for "no update" (reported as not found) and for
    /// an install that needs authorization later (Sparkle comes back through the user driver).
    static func failureEvent(for error: any Error) -> UpdateEvent? {
        let code = UpdateErrorCode(error)
        guard code.domain == sparkleErrorDomain else { return .failed(.checkFailed, code) }
        switch code.code {
        case 1001, 4008: return nil   // SUNoUpdateError, SUInstallationAuthorizeLaterError
        case 2000...: return .failed(.installFailed, code)   // download, extraction, installation
        default: return .failed(.checkFailed, code)   // configuration and appcast
        }
    }

    /// "Couldn't check: <domain> <code>"; never the error's text.
    static func logLine(for failure: UpdateFailure, _ code: UpdateErrorCode) -> String {
        switch failure {
        case .checkFailed: "Couldn't check: \(code.domain) \(code.code)"
        case .installFailed: "Couldn't install: \(code.domain) \(code.code)"
        }
    }

    private func logChecking() {
        log("Checking for updates (\(feed?.host ?? "none"))")
    }

    private func logInstalling(_ update: AvailableUpdate, reason: String) {
        installLogged = true
        log("Installing \(update.version) build \(update.build) (\(reason))")
    }

    private func logOnce(_ text: String) {
        let now = hooks.now()
        if let lastLog, lastLog.text == text, abs(now.timeIntervalSince(lastLog.at)) < 5 { return }
        lastLog = (text, now)
        log(text)
    }

    /// Versions, hosts, error domains and codes only (L12).
    private func log(_ text: String) {
        Self.logger.notice("\(text, privacy: .public)")
    }

    /// The live `Schedule`: a main-actor task.
    static func scheduleOnMainActor(_ delay: Duration, _ work: @escaping () -> Void) -> () -> Void {
        let task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
        return { task.cancel() }
    }
}

private extension UpdateStatus.OffReason {
    var logText: String {
        switch self {
        case .developmentBuild: "a development build"
        case .windowed: "in a window"
        }
    }
}

private extension AutomaticUpdates {
    var installPhrase: String {
        switch self {
        case .off: "on quit"
        case .whenIdle: "when idle"
        case .atNight: "at night"
        }
    }
}
