import AppKit
import CoreAudio
import Foundation
import IOKit.pwr_mgt
import os

// M7h L14, D45: the power button. Off: the TV's power key (only when it's set up and answering, since the key
// toggles), the receiver's power off (if set up; a missing reply is fine, the TV's own CEC may have turned it off),
// then display sleep. On: wake the displays, Wake-on-LAN until the TV answers (at most 30 s), the receiver's power
// on. Which one: on when MMTVL turned things off (in memory only) or a set-up TV doesn't answer; otherwise off. Never
// from the receiver's `?P` (after the TV's CEC standby, Pioneer answers "on" while off, step 1). The TV is a network
// VIERA (`TVController`) or, from step 9 (reopened), HDMI-CEC through the DisplayPort tunnel (`HDMICEC`); after a CEC
// "on", the Mac's HDMI display must be back within 20 s, else a toast asks to switch the receiver's input. Step 9c:
// the receiver may be on HDMI-CEC too (`PowerReceiverSelector`).
// L15's menu also sleeps the Mac, restarts it and relaunches MMTVL. Every effect is injected so tests use fakes;
// the real ones run fixed programs with fixed arguments (no shell, nothing built from input).

/// The TV, as the power button uses it (`TVController`, `HDMICEC`, through `PowerTVSelector`).
protocol PowerTV: AnyObject {
    var isConfigured: Bool { get }
    /// A MAC is set, so Wake-on-LAN can turn it on (HDMI-CEC: the tunnel isn't known to be unusable).
    var canTurnOn: Bool { get }
    /// The off command toggles (VIERA's power key), so it's sent only when the TV answered. HDMI-CEC's Standby to all
    /// doesn't, so it's always sent.
    var powerOffToggles: Bool { get }
    /// After turning on, check that the Mac's HDMI display came back (HDMI-CEC, `hdmiDisplayReturned`).
    var checksHDMIAfterPowerOn: Bool { get }
    func isOn() async -> Bool
    func powerOff() async -> Bool
    func powerOn() async -> Bool
    func hdmiDisplayReturned() async -> Bool
}

extension PowerTV {
    var powerOffToggles: Bool { true }
    var checksHDMIAfterPowerOn: Bool { false }
    func hdmiDisplayReturned() async -> Bool { true }
}

extension TVController: PowerTV {
    var canTurnOn: Bool { mac != nil }
}

/// The TV the power button uses: HDMI-CEC when `tvBrand` is `cec`, else the network TV. Both follow `settings.json`.
final class PowerTVSelector: PowerTV {
    private let network: (any PowerTV)?
    private let cec: (any PowerTV)?

    init(network: (any PowerTV)?, cec: (any PowerTV)?) {
        self.network = network
        self.cec = cec
    }

    private var current: (any PowerTV)? {
        if let cec, cec.isConfigured { return cec }
        return network
    }

    var isConfigured: Bool { current?.isConfigured ?? false }
    var canTurnOn: Bool { current?.canTurnOn ?? false }
    var powerOffToggles: Bool { current?.powerOffToggles ?? true }
    var checksHDMIAfterPowerOn: Bool { current?.checksHDMIAfterPowerOn ?? false }
    func isOn() async -> Bool { await current?.isOn() ?? false }
    func powerOff() async -> Bool { await current?.powerOff() ?? false }
    func powerOn() async -> Bool { await current?.powerOn() ?? false }
    func hdmiDisplayReturned() async -> Bool { await current?.hdmiDisplayReturned() ?? true }
}

/// The receiver, as the power button uses it (`ReceiverController`).
protocol PowerReceiver: AnyObject {
    /// A brand is set (and, over the network, a usable address).
    var isSetUp: Bool { get }
    func send(_ command: ReceiverCommand) async -> Bool
    /// Step 9c: MMTVL's "off" ran (whether or not this receiver was sent anything: a CEC TV's `4F:36` covers a CEC
    /// receiver).
    func noteTurnedOff()
    /// Step 9c: MMTVL's "on" ran.
    func noteTurnedOn()
}

extension PowerReceiver {
    func noteTurnedOff() {}
    func noteTurnedOn() {}
}

extension ReceiverController: PowerReceiver {
    var isSetUp: Bool { brand != .none }
}

/// Step 9c: a receiver over HDMI-CEC. Off is `45:36`, on is Power On Function (`45:44:6D` + `45:45`).
extension CECAudioSystem: PowerReceiver {
    var isSetUp: Bool { isEnabled }

    func send(_ command: ReceiverCommand) async -> Bool {
        switch command {
        case .powerOff: await powerOff()
        case .powerOn: await powerOn()
        default: false
        }
    }
}

/// Step 9c (L14): the receiver the power button uses. Over HDMI-CEC (`receiverConnection` `cec`) only with a TV that
/// isn't on HDMI-CEC: a CEC TV's Standby to all (`4F:36`) already takes the receiver down, and its wake brings it up
/// (probe 2), so nothing more is sent to it. Otherwise the serial or network receiver.
final class PowerReceiverSelector: PowerReceiver {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Power")

    private let receiver: (any PowerReceiver)?
    private let cec: (any PowerReceiver)?
    private let tvUsesCEC: () -> Bool

    init(receiver: (any PowerReceiver)?, cec: (any PowerReceiver)?, tvUsesCEC: @escaping () -> Bool) {
        self.receiver = receiver
        self.cec = cec
        self.tvUsesCEC = tvUsesCEC
    }

    private var current: (any PowerReceiver)? {
        if let cec, cec.isSetUp { return tvUsesCEC() ? nil : cec }
        return receiver
    }

    var isSetUp: Bool { current?.isSetUp ?? false }

    func send(_ command: ReceiverCommand) async -> Bool {
        await current?.send(command) ?? false
    }

    /// A receiver over HDMI-CEC hears of every "off" and "on", with a CEC TV too (its `4F:36` turns the receiver off).
    func noteTurnedOff() {
        if let cec, cec.isSetUp {
            // QA minor: the line that said this used to sit in `send`, which isn't called then (`isSetUp` is false).
            if tvUsesCEC() {
                Self.logger.notice("Power: the receiver is on HDMI-CEC with the TV; the TV's Standby to all covers it")
            }
            cec.noteTurnedOff()
        } else {
            receiver?.noteTurnedOff()
        }
    }

    func noteTurnedOn() {
        if let cec, cec.isSetUp { cec.noteTurnedOn() } else { receiver?.noteTurnedOn() }
    }
}

/// What the power button and menu do to the Mac and MMTVL. `system(relaunch:)` is the real thing.
struct PowerEffects {
    var sleepDisplays: () -> Void
    var wakeDisplays: () -> Void
    /// M7m L23: true from just before the displays sleep (off) until the next on, so the Mac doesn't idle-sleep (and
    /// a Siri Remote reconnecting in a dark wake doesn't wake the display and the TV with it). Idempotent.
    var keepMacAwake: (Bool) -> Void
    /// True once the request went out (pmset, else the Apple event); false: it couldn't be sent.
    var sleepMac: () async -> Bool
    /// True once the Apple event went out.
    var restartMac: () async -> Bool
    var relaunch: () -> Void
    /// 10 s after power-on: the default output device's name and transport, in the `Power` log.
    var logOutputDevice: () -> Void
    var sleep: (Duration) async -> Void
}

/// Main actor. One power sequence runs at a time: a short press while one runs is ignored (not queued), with a toast.
final class PowerController {
    enum Direction: String, Equatable { case off, on }
    /// The running sequence: checking the TV (before it knows which way), then off or on.
    enum Phase: Equatable { case checking, off, on }

    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Power")
    static let outputLogDelay: Duration = .seconds(10)
    /// Step 9 (reopened): after an HDMI-CEC "on", the Mac's HDMI display should be back by then.
    static let displayCheckDelay: Duration = .seconds(20)
    static let switchInputMessage = "Switch the receiver to the Mac's input"

    /// L14 (amended 2026-11-06): set by turning off, cleared by turning on; decides only when no TV is set up (a set-up
    /// TV's answer always decides). Memory only: a relaunch forgets it.
    private(set) var poweredOffByMMTVL = false
    /// A sequence (off or on) is running.
    var isRunning: Bool { task != nil }
    /// The running sequence's phase, set when it starts (QA Q3: a press during the TV check is answered too).
    private(set) var phase: Phase?
    /// Sleep or Restart from the menu (tests await it).
    private(set) var actionTask: Task<Void, Never>?
    /// The running sequence (tests await it).
    private(set) var task: Task<Void, Never>?
    /// The output-device log after power-on (tests await it).
    private(set) var outputLogTask: Task<Void, Never>?
    /// The HDMI display check after an HDMI-CEC power-on (tests await it).
    private(set) var displayCheckTask: Task<Void, Never>?
    /// "Turning Off…", "Turning On…", "TV Didn't Turn On" (L8's toast in the app).
    var onToast: (String) -> Void = { _ in }
    /// M7h L16 (D45): turning on, right after the displays wake. The app marks Plex to restart on its next open and
    /// shows its home screen like a Home press (user decision 2026-11-06, `PowerController.powerOnHandler`).
    var onPowerOn: () -> Void = {}
    /// M15 L16 (amends D45): turning off, first, before the TV and receiver are sent off. The app stops its own
    /// playback and shows its home screen like a Home press; other apps keep running behind it (D18).
    var onPowerOff: () -> Void = {}
    /// QA minor (pre-build 2): "no MAC, can't turn the TV on" is logged once, not toasted at every power-on.
    private var loggedNoMAC = false

    private let tv: (any PowerTV)?
    private let receiver: (any PowerReceiver)?
    private let effects: PowerEffects

    init(tv: (any PowerTV)?, receiver: (any PowerReceiver)?, effects: PowerEffects) {
        self.tv = tv
        self.receiver = receiver
        self.effects = effects
    }

    // MARK: The button and the menu

    /// The short press: off or on (L14). False when ignored because a sequence is running.
    @discardableResult
    func powerButton() -> Bool {
        // L14 amended (2026-11-06): a set-up TV is always checked first (≤ 1 s).
        let phase: Phase = tv?.isConfigured == true ? .checking : poweredOffByMMTVL ? .on : .off
        return start(reason: "Power button", phase: phase) { [weak self] in
            guard let self else { return }
            let tvAnswers = await tvAnswers()
            switch Self.direction(poweredOffByMMTVL: poweredOffByMMTVL, tvAnswers: tvAnswers) {
            case .off: await runOff(tvAnswers: tvAnswers)
            case .on: await runOn()
            }
        }
    }

    /// L15's Turn Off TV & Receiver: always off. False when ignored because a sequence is running.
    @discardableResult
    func turnOff() -> Bool {
        start(reason: "Power menu: Turn Off TV & Receiver", phase: .off) { [weak self] in
            guard let self else { return }
            await runOff(tvAnswers: await tvAnswers())
        }
    }

    func sleepMac() {
        Self.logger.notice("Power menu: Sleep Mac mini")
        let effects = effects
        actionTask = Task { [weak self] in
            if await !effects.sleepMac() { self?.onToast("Couldn't Sleep the Mac mini") }
        }
    }

    /// Behind the PIN when one is set (`AppRouter`).
    func restartMac() {
        Self.logger.notice("Power menu: Restart Mac mini")
        let effects = effects
        actionTask = Task { [weak self] in
            if await !effects.restartMac() { self?.onToast("Couldn't Restart the Mac mini") }
        }
    }

    /// Behind the PIN when one is set (`AppRouter`).
    func relaunch() {
        Self.logger.notice("Power menu: Relaunch MMTVL")
        effects.relaunch()
    }

    /// M15 L8: MMTVL relaunched after an update installed during Power-off (`update-relaunch.json`), so the next press
    /// turns things on, as it would have before the relaunch. Keeps the Mac awake again (the assertion died with the
    /// old process). Sends nothing to the TV, the receiver or the displays.
    func restorePoweredOff() {
        poweredOffByMMTVL = true
        phase = .off
        effects.keepMacAwake(true)
    }

    /// L14's choice (amended 2026-11-06). Pure. `tvAnswers`: nil without a TV set up. A set-up TV decides: it answers
    /// → off (even after MMTVL turned things off and the TV was turned on by its own remote), it doesn't → on. Without
    /// a TV, `poweredOffByMMTVL` decides.
    static func direction(poweredOffByMMTVL: Bool, tvAnswers: Bool?) -> Direction {
        if let tvAnswers { return tvAnswers ? .off : .on }
        return poweredOffByMMTVL ? .on : .off
    }

    // MARK: Sequences

    private func start(reason: String, phase: Phase, _ work: @escaping () async -> Void) -> Bool {
        guard task == nil else {
            Self.logger.notice("\(reason, privacy: .public): ignored, a power sequence is running")
            onToast(Self.busyMessage(self.phase ?? phase))
            return false
        }
        Self.logger.notice("\(reason, privacy: .public)")
        self.phase = phase
        task = Task { [weak self] in
            await work()
            self?.task = nil
            self?.phase = nil
        }
        return true
    }

    /// The toast for a press while a sequence runs.
    static func busyMessage(_ phase: Phase) -> String {
        switch phase {
        case .checking: "Checking the TV…"
        case .off: "Turning Off…"
        case .on: "Turning On…"
        }
    }

    /// nil without a TV set up.
    private func tvAnswers() async -> Bool? {
        guard let tv, tv.isConfigured else { return nil }
        return await tv.isOn()
    }

    private func runOff(tvAnswers: Bool?) async {
        Self.logger.notice("Power: turning off")
        phase = .off
        onPowerOff()
        onToast("Turning Off…")
        poweredOffByMMTVL = true
        outputLogTask?.cancel()
        outputLogTask = nil
        displayCheckTask?.cancel()
        displayCheckTask = nil
        if let tv, tvAnswers == true || (tv.isConfigured && !tv.powerOffToggles) {
            let sent = await tv.powerOff()
            Self.logger.notice("Power: TV off \(sent ? "sent" : "not accepted", privacy: .public)")
        } else if tvAnswers == false {
            Self.logger.notice("Power: the TV doesn't answer; no power key")
        }
        if let receiver, receiver.isSetUp {
            // Step 1: the receiver may not reply (or be off already, after the TV's CEC); not a failure.
            let written = await receiver.send(.powerOff)
            Self.logger.notice("Power: receiver power off \(written ? "sent" : "not written", privacy: .public)")
        }
        // Step 9c: a receiver over HDMI-CEC is off now (even when a CEC TV's Standby to all did it).
        receiver?.noteTurnedOff()
        effects.keepMacAwake(true)
        Self.logger.notice("Power: displays to sleep")
        effects.sleepDisplays()
    }

    private func runOn() async {
        Self.logger.notice("Power: turning on")
        phase = .on
        poweredOffByMMTVL = false
        effects.keepMacAwake(false)
        effects.wakeDisplays()
        onPowerOn()
        onToast("Turning On…")
        if let tv, tv.isConfigured, !tv.canTurnOn {
            // Settings already says the TV can't be turned on without a MAC.
            if !loggedNoMAC {
                loggedNoMAC = true
                Self.logger.debug("Power: the TV can't be turned on (no MAC address, or HDMI-CEC not available); not waking it")
            }
        } else if let tv, tv.isConfigured {
            if await tv.powerOn() {
                Self.logger.notice("Power: TV is on")
                if tv.checksHDMIAfterPowerOn { startDisplayCheck(tv) }
            } else {
                Self.logger.notice("Power: the TV didn't turn on")
                onToast("TV Didn't Turn On")
            }
        }
        if let receiver, receiver.isSetUp {
            let written = await receiver.send(.powerOn)
            Self.logger.notice("Power: receiver power on \(written ? "sent" : "not written", privacy: .public)")
        }
        // Step 9c: a receiver over HDMI-CEC is asked again once it's had a moment to come up.
        receiver?.noteTurnedOn()
        outputLogTask?.cancel()
        let effects = effects
        outputLogTask = Task {
            await effects.sleep(Self.outputLogDelay)
            guard !Task.isCancelled else { return }
            effects.logOutputDevice()
        }
    }

    /// Probe 2: a receiver left on can re-route away from the Mac when CEC wakes the TV, and the Mac's HDMI display
    /// goes away. 20 s after the "on", if it isn't back: a log line and a toast. The receiver's input isn't switched
    /// automatically (not planned).
    private func startDisplayCheck(_ tv: any PowerTV) {
        displayCheckTask?.cancel()
        let effects = effects
        displayCheckTask = Task { [weak self] in
            await effects.sleep(Self.displayCheckDelay)
            guard !Task.isCancelled else { return }
            let returned = await tv.hdmiDisplayReturned()
            guard !Task.isCancelled else { return }
            if returned {
                Self.logger.notice("Power: the Mac's HDMI display is there after the HDMI-CEC power-on")
            } else {
                Self.logger.notice("Power: the Mac's HDMI display hasn't returned \(Self.displayCheckDelay.components.seconds, privacy: .public) s after the HDMI-CEC power-on; the receiver may be on another input")
                self?.onToast(Self.switchInputMessage)
            }
        }
    }
}

extension PowerController {
    /// M7h user decision (2026-11-06): what a power-on does in the app. Plex is marked to restart whether or not it
    /// was in front (MMTVL is about to cover it, right after the hot-plug), then MMTVL's home screen comes forward
    /// like a global Home press (`goHome`).
    static func powerOnHandler(launcher: AppLauncher, goHome: @escaping () -> Void) -> () -> Void {
        {
            launcher.notePowerOn()
            goHome()
        }
    }
}

// MARK: The real effects

extension PowerEffects {
    /// `relaunch`: `AppRelauncher.relaunch` with the kiosk lock's quit guard lifted (AppDelegate).
    static func system(relaunch: @escaping () -> Void) -> PowerEffects {
        // M7m L23: one assertion, memory only (a relaunch drops it, like `poweredOffByMMTVL`). Sleep Mac mini still
        // sleeps (the system-sleep type only stops idle sleep).
        let awake = SleepAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep, name: "MMTVL: TV and receiver off",
                                   category: "Power")
        var keepingAwake = false
        return PowerEffects(
            sleepDisplays: {
                Task { _ = await SystemPower.run(SystemPower.pmset, ["displaysleepnow"]) }
            },
            wakeDisplays: { SystemPower.declareUserActivity() },
            keepMacAwake: { on in
                guard on != keepingAwake else { return }
                // A failed hold (logged by `SleepAssertion`) leaves it false, so the next off tries again.
                keepingAwake = awake.hold(on)
                if on, keepingAwake {
                    PowerController.logger.notice("Power: keeping the Mac awake while off")
                } else if !on {
                    PowerController.logger.notice("Power: the Mac may idle-sleep again")
                }
            },
            sleepMac: {
                if await SystemPower.run(SystemPower.pmset, ["sleepnow"]) { return true }
                PowerController.logger.notice("Power: pmset sleepnow failed; asking loginwindow")
                return await SystemPower.sendToLoginWindow(AEEventID(kAESleep), name: "sleep")
            },
            restartMac: { await SystemPower.sendToLoginWindow(AEEventID(kAERestart), name: "restart") },
            relaunch: relaunch,
            logOutputDevice: {
                if let device = SystemPower.defaultOutputDevice() {
                    PowerController.logger.notice("Power: default output \(device.name, privacy: .public) (\(device.transport, privacy: .public))")
                } else {
                    PowerController.logger.notice("Power: no default output device")
                }
            },
            sleep: { try? await Task.sleep(for: $0) }
        )
    }
}

/// The real calls behind `PowerEffects.system`. Fixed programs and arguments only.
enum SystemPower {
    static let pmset = "/usr/bin/pmset"

    /// Runs `path` with `arguments` (no shell); true when it exited with status 0.
    static func run(_ path: String, _ arguments: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let name = arguments.first ?? ""
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
        guard let status else {
            PowerController.logger.error("Power: couldn't run pmset \(name, privacy: .public)")
            return false
        }
        PowerController.logger.notice("Power: pmset \(name, privacy: .public) exited \(status, privacy: .public)")
        return status == 0
    }

    /// Wakes the displays like a key press (`IOPMAssertionDeclareUserActivity`, public IOKit).
    static func declareUserActivity() {
        var assertion = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity("MMTVL power on" as CFString, kIOPMUserActiveLocal, &assertion)
        guard result == kIOReturnSuccess else {
            PowerController.logger.error("Power: couldn't wake the displays (\(result, privacy: .public))")
            return
        }
        PowerController.logger.notice("Power: displays woken")
        // The activity counts at once; the assertion is released a little later, as `caffeinate -u -t 5` would.
        Task {
            try? await Task.sleep(for: .seconds(5))
            IOPMAssertionRelease(assertion)
        }
    }

    /// Technical Q&A QA1134: `kAESleep` / `kAERestart` to loginwindow, without waiting for a reply. macOS may ask for
    /// Automation the first time (`NSAppleEventsUsageDescription`; unverified on macOS 26); sending can wait on that
    /// prompt, so it's sent off the main actor. True once it went out.
    static func sendToLoginWindow(_ eventID: AEEventID, name: String) async -> Bool {
        let error = await Task.detached { () -> String? in
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
                                               targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            do {
                _ = try event.sendEvent(options: [.noReply], timeout: 10)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let error {
            PowerController.logger.error("Power: loginwindow \(name, privacy: .public) failed: \(error, privacy: .public)")
            return false
        }
        PowerController.logger.notice("Power: asked loginwindow to \(name, privacy: .public)")
        return true
    }

    struct OutputDevice: Equatable {
        var name: String
        var transport: String
    }

    static func defaultOutputDevice() -> OutputDevice? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }

        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
        let deviceName = nameStatus == noErr ? (name?.takeRetainedValue() as String?) ?? "?" : "?"

        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        let transportStatus = AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport)
        return OutputDevice(name: deviceName, transport: transportStatus == noErr ? transportName(transport) : "unknown")
    }

    /// Pure.
    static func transportName(_ transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeBuiltIn: "built-in"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeVirtual: "virtual"
        case kAudioDeviceTransportTypeAggregate: "aggregate"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        default: "other"
        }
    }
}
