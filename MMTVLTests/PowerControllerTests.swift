import CoreAudio
import Foundation
import Testing
@testable import MMTVL

/// Everything the power button did, in order.
final class PowerLog {
    var events: [String] = []
    var toasts: [String] = []
    var sleeps: [Duration] = []
    /// M7m L23: `keepMacAwake` calls, kept out of `events` so the order checks stay as they were.
    var keepAwake: [Bool] = []
    /// Whether sleeping or restarting the Mac could be asked for (pmset or the Apple event went out).
    var macRequestsSucceed = true

    /// Fakes for every effect: nothing sleeps the displays, sleeps or restarts the Mac, or relaunches.
    var effects: PowerEffects {
        PowerEffects(
            sleepDisplays: { self.events.append("displays.sleep") },
            wakeDisplays: { self.events.append("displays.wake") },
            keepMacAwake: { self.keepAwake.append($0) },
            sleepMac: {
                self.events.append("mac.sleep")
                return self.macRequestsSucceed
            },
            restartMac: {
                self.events.append("mac.restart")
                return self.macRequestsSucceed
            },
            relaunch: { self.events.append("relaunch") },
            logOutputDevice: { self.events.append("outputDevice.log") },
            sleep: { self.sleeps.append($0) }
        )
    }
}

final class FakePowerTV: PowerTV {
    let log: PowerLog
    var isConfigured = true
    /// A MAC is set.
    var canTurnOn = true
    var on: Bool
    /// Wake-on-LAN brings it up (else `powerOn` gives up, as after 30 s).
    var wakes = true

    init(log: PowerLog, on: Bool) {
        self.log = log
        self.on = on
    }

    func isOn() async -> Bool {
        log.events.append("tv.isOn")
        return on
    }

    /// Like `TVController.powerOff`: the key only when it answers.
    func powerOff() async -> Bool {
        guard on else { return false }
        log.events.append("tv.powerKey")
        on = false
        return true
    }

    func powerOn() async -> Bool {
        log.events.append("tv.wakeOnLAN")
        if wakes { on = true }
        return on
    }
}

final class FakePowerReceiver: PowerReceiver {
    let log: PowerLog
    var isSetUp = true
    /// Step 1: a power command may get no reply; `send` only says whether it was written.
    var written = true

    init(log: PowerLog) { self.log = log }

    func send(_ command: ReceiverCommand) async -> Bool {
        log.events.append("receiver.\(command)")
        return written
    }
}

/// M7h L14: Power's short press turns the TV, receiver and displays off or on; L15's actions go to their effects.
struct PowerControllerTests {
    let log = PowerLog()

    private func makePower(tv: (any PowerTV)?, receiver: (any PowerReceiver)?) -> PowerController {
        let power = PowerController(tv: tv, receiver: receiver, effects: log.effects)
        power.onToast = { [log] in log.toasts.append($0) }
        return power
    }

    /// Presses and waits for the sequence, and after power-on for the output-device log (the fake sleep returns at
    /// once), so it's always last.
    private func press(_ power: PowerController) async {
        #expect(power.powerButton())
        await power.task?.value
        await power.outputLogTask?.value
    }

    @Test func pressTurnsTheTVReceiverAndDisplaysOffInOrder() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.events == ["tv.isOn", "tv.powerKey", "receiver.powerOff", "displays.sleep"])
        #expect(power.poweredOffByMMTVL)
        #expect(!power.isRunning)
        #expect(log.toasts == ["Turning Off…"])
    }

    @Test func nextPressWakesTheDisplaysThenTheTVThenTheReceiver() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        log.events = []
        log.toasts = []
        await press(power)
        // The TV is checked first (L14 amended); it doesn't answer: on. Wake-on-LAN (until it answers) before the
        // receiver. 10 s later, the output device is logged.
        #expect(log.events == ["tv.isOn", "displays.wake", "tv.wakeOnLAN", "receiver.powerOn", "outputDevice.log"])
        #expect(log.sleeps == [.seconds(10)])
        #expect(!power.poweredOffByMMTVL)
        #expect(tv.on)
        #expect(log.toasts == ["Turning On…"])
        // And the next press turns off again.
        log.events = []
        await press(power)
        #expect(log.events == ["tv.isOn", "tv.powerKey", "receiver.powerOff", "displays.sleep"])
    }

    /// M15 L16: the app goes home first, before the TV, the receiver and the displays; the power menu's Turn Off TV &
    /// Receiver too (the same `runOff`).
    @Test func powerOffCallsOnPowerOffFirst() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        power.onPowerOff = { [log] in log.events.append("onPowerOff") }
        await press(power)
        #expect(log.events == ["tv.isOn", "onPowerOff", "tv.powerKey", "receiver.powerOff", "displays.sleep"])

        log.events = []
        tv.on = true
        #expect(power.turnOff())
        await power.task?.value
        #expect(log.events == ["tv.isOn", "onPowerOff", "tv.powerKey", "receiver.powerOff", "displays.sleep"])
    }

    @Test func powerOnDoesntCallOnPowerOff() async {
        let tv = FakePowerTV(log: log, on: false)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        var offs = 0
        power.onPowerOff = { offs += 1 }
        power.onPowerOn = { [log] in log.events.append("onPowerOn") }
        await press(power)
        #expect(offs == 0)
        #expect(log.events == ["tv.isOn", "displays.wake", "onPowerOn", "tv.wakeOnLAN", "receiver.powerOn",
                               "outputDevice.log"])
    }

    @Test func withoutATVOnlyTheReceiverAndDisplays() async {
        for tv in [nil, { let tv = FakePowerTV(log: log, on: true); tv.isConfigured = false; return tv }()] as [FakePowerTV?] {
            log.events = []
            let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
            await press(power)
            #expect(log.events == ["receiver.powerOff", "displays.sleep"])
            log.events = []
            await press(power)
            #expect(log.events == ["displays.wake", "receiver.powerOn", "outputDevice.log"])
        }
    }

    @Test func withoutAReceiverOnlyTheTVAndDisplays() async {
        let receiver = FakePowerReceiver(log: log)
        receiver.isSetUp = false
        let power = makePower(tv: FakePowerTV(log: log, on: true), receiver: receiver)
        await press(power)
        #expect(log.events == ["tv.isOn", "tv.powerKey", "displays.sleep"])
        log.events = []
        await press(power)
        #expect(log.events == ["tv.isOn", "displays.wake", "tv.wakeOnLAN", "outputDevice.log"])
    }

    @Test func aMissingReceiverReplyIsNotAFailure() async {
        let receiver = FakePowerReceiver(log: log)
        receiver.written = false
        let power = makePower(tv: nil, receiver: receiver)
        await press(power)
        #expect(log.events == ["receiver.powerOff", "displays.sleep"])
        #expect(power.poweredOffByMMTVL)
    }

    /// L14: a set-up TV that doesn't answer is off (whatever the receiver says); the press turns everything on.
    @Test func aTVThatDoesntAnswerIsTreatedAsOff() async {
        let tv = FakePowerTV(log: log, on: false)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.events == ["tv.isOn", "displays.wake", "tv.wakeOnLAN", "receiver.powerOn", "outputDevice.log"])
        #expect(tv.on)
        #expect(!power.poweredOffByMMTVL)
    }

    @Test func aTVThatDoesntWakeSaysSo() async {
        let tv = FakePowerTV(log: log, on: false)
        tv.wakes = false
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.toasts == ["Turning On…", "TV Didn't Turn On"])
        // The receiver comes on anyway.
        #expect(log.events == ["tv.isOn", "displays.wake", "tv.wakeOnLAN", "receiver.powerOn", "outputDevice.log"])
    }

    /// A press while a sequence runs is ignored (not queued), with a toast every time, the TV check included (QA Q3).
    @Test func aPressWhileOneRunsIsIgnored() async {
        let power = makePower(tv: FakePowerTV(log: log, on: true), receiver: FakePowerReceiver(log: log))
        #expect(power.powerButton())
        #expect(power.isRunning)
        #expect(power.phase == .checking)
        #expect(!power.powerButton())
        #expect(!power.turnOff())
        #expect(log.toasts == ["Checking the TV…", "Checking the TV…"])
        await power.task?.value
        #expect(log.events == ["tv.isOn", "tv.powerKey", "receiver.powerOff", "displays.sleep"])
        #expect(!power.isRunning)
        #expect(power.powerButton())
        await power.task?.value
    }

    /// L14 amended (user decision 2026-11-06): a set-up TV's answer decides; the flag only without a TV.
    @Test func directionRules() {
        #expect(PowerController.direction(poweredOffByMMTVL: true, tvAnswers: nil) == .on)
        #expect(PowerController.direction(poweredOffByMMTVL: true, tvAnswers: true) == .off)
        #expect(PowerController.direction(poweredOffByMMTVL: true, tvAnswers: false) == .on)
        #expect(PowerController.direction(poweredOffByMMTVL: false, tvAnswers: false) == .on)
        #expect(PowerController.direction(poweredOffByMMTVL: false, tvAnswers: true) == .off)
        #expect(PowerController.direction(poweredOffByMMTVL: false, tvAnswers: nil) == .off)
    }

    /// L14 amended: MMTVL turned things off, then the TV was turned on by its own remote: the press turns off.
    @Test func afterAnMMTVLPowerOffATVThatAnswersTurnsOff() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(power.poweredOffByMMTVL)
        tv.on = true   // the TV's own remote
        log.events = []
        await press(power)
        #expect(log.events == ["tv.isOn", "tv.powerKey", "receiver.powerOff", "displays.sleep"])
    }

    /// L14 amended: after an MMTVL power-off a TV that doesn't answer turns on; so does one MMTVL didn't turn off.
    @Test func aTVThatDoesntAnswerTurnsOnWhateverTheFlag() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        log.events = []
        await press(power)
        #expect(log.events.prefix(3) == ["tv.isOn", "displays.wake", "tv.wakeOnLAN"])
        #expect(!power.poweredOffByMMTVL)
    }

    /// No TV set up: the flag decides (off, on, off).
    @Test func withoutATVTheFlagDecides() async {
        let power = makePower(tv: nil, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.events == ["receiver.powerOff", "displays.sleep"])
        log.events = []
        await press(power)
        #expect(log.events == ["displays.wake", "receiver.powerOn", "outputDevice.log"])
        log.events = []
        await press(power)
        #expect(log.events == ["receiver.powerOff", "displays.sleep"])
    }

    /// QA minor (pre-build 2): a TV without a MAC isn't woken and no "TV Didn't Turn On" toast; the rest goes on.
    @Test func aTVWithoutAMACIsSkippedQuietly() async {
        let tv = FakePowerTV(log: log, on: false)
        tv.canTurnOn = false
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.events == ["tv.isOn", "displays.wake", "receiver.powerOn", "outputDevice.log"])
        #expect(log.toasts == ["Turning On…"])
        log.events = []
        log.toasts = []
        await press(power)
        #expect(!log.events.contains("tv.wakeOnLAN"))
        #expect(!log.toasts.contains("TV Didn't Turn On"))
    }

    /// L15's Turn Off TV & Receiver is always off; the TV's key only when it answers.
    @Test func menuTurnOffIsAlwaysOff() async {
        let tv = FakePowerTV(log: log, on: false)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        #expect(power.turnOff())
        await power.task?.value
        #expect(log.events == ["tv.isOn", "receiver.powerOff", "displays.sleep"])
        #expect(power.poweredOffByMMTVL)
    }

    /// QA Q3: the phase is set when the sequence starts, so presses during it get the right toast.
    @Test func ignoredPressesSayWhatsRunning() async {
        let tv = FakePowerTV(log: log, on: true)
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))
        #expect(power.turnOff())
        #expect(power.phase == .off)
        #expect(!power.powerButton())
        await power.task?.value
        #expect(power.phase == nil)
        #expect(power.powerButton())   // a set-up TV is always checked first
        #expect(power.phase == .checking)
        #expect(!power.powerButton())
        await power.task?.value
        await power.outputLogTask?.value
        #expect(log.toasts == ["Turning Off…", "Turning Off…", "Checking the TV…", "Turning On…"])
        // Without a TV, MMTVL's own power-off decides at once.
        let flagOnly = makePower(tv: nil, receiver: FakePowerReceiver(log: log))
        await press(flagOnly)
        #expect(flagOnly.powerButton())
        #expect(flagOnly.phase == .on)
        await flagOnly.task?.value
        await flagOnly.outputLogTask?.value
        // Without a TV: off at once.
        let noTV = makePower(tv: nil, receiver: FakePowerReceiver(log: log))
        #expect(noTV.powerButton())
        #expect(noTV.phase == .off)
        await noTV.task?.value
    }

    @Test func menuActionsRunTheirEffects() async {
        let power = makePower(tv: nil, receiver: nil)
        power.sleepMac()
        await power.actionTask?.value
        power.restartMac()
        await power.actionTask?.value
        power.relaunch()
        #expect(log.events == ["mac.sleep", "mac.restart", "relaunch"])
        #expect(log.toasts.isEmpty)
    }

    /// M15 L8: after an update's relaunch during Power-off, nothing is sent to the TV, the receiver or the displays,
    /// the Mac is kept awake again, and the next press (no TV set up) turns things on.
    @Test func restorePoweredOffNeverSendsCommands() async {
        let power = makePower(tv: nil, receiver: FakePowerReceiver(log: log))
        power.restorePoweredOff()
        #expect(log.events.isEmpty)
        #expect(log.toasts.isEmpty)
        #expect(log.keepAwake == [true])
        #expect(power.poweredOffByMMTVL)
        #expect(!power.isRunning)

        await press(power)
        #expect(log.events == ["displays.wake", "receiver.powerOn", "outputDevice.log"])
        #expect(!power.poweredOffByMMTVL)
        #expect(log.keepAwake == [true, false])
    }

    /// M7m L23: the off holds the Mac awake, and does so before the displays sleep.
    @Test func offKeepsTheMacAwakeBeforeTheDisplaysSleep() async {
        var effects = log.effects
        effects.keepMacAwake = { [log] in
            log.keepAwake.append($0)
            log.events.append("mac.keepAwake.\($0)")
        }
        let power = PowerController(tv: FakePowerTV(log: log, on: true), receiver: FakePowerReceiver(log: log),
                                    effects: effects)
        await press(power)
        #expect(log.keepAwake == [true])
        #expect(log.events == ["tv.isOn", "tv.powerKey", "receiver.powerOff", "mac.keepAwake.true", "displays.sleep"])
    }

    /// M7m L23: the next on lets the Mac idle-sleep again, before the displays wake.
    @Test func onLetsTheMacSleepAgain() async {
        var effects = log.effects
        effects.keepMacAwake = { [log] in
            log.keepAwake.append($0)
            log.events.append("mac.keepAwake.\($0)")
        }
        let power = PowerController(tv: FakePowerTV(log: log, on: true), receiver: FakePowerReceiver(log: log),
                                    effects: effects)
        await press(power)
        log.events = []
        await press(power)
        #expect(log.keepAwake == [true, false])
        #expect(log.events.prefix(3) == ["tv.isOn", "mac.keepAwake.false", "displays.wake"])
    }

    /// M7m L23: the power menu's Turn Off TV & Receiver holds it too.
    @Test func powerMenuTurnOffKeepsTheMacAwake() async {
        let power = makePower(tv: FakePowerTV(log: log, on: false), receiver: FakePowerReceiver(log: log))
        #expect(power.turnOff())
        await power.task?.value
        #expect(log.keepAwake == [true])
    }

    /// M7m L23: Sleep Mac mini neither takes nor drops it (explicit sleep isn't blocked by it).
    @Test func sleepMacDoesntChangeIt() async {
        let power = makePower(tv: nil, receiver: FakePowerReceiver(log: log))
        await press(power)
        #expect(log.keepAwake == [true])
        power.sleepMac()
        await power.actionTask?.value
        #expect(log.keepAwake == [true])
        #expect(log.events.last == "mac.sleep")
    }

    /// QA Q2: a request that couldn't be sent says so.
    @Test func sleepOrRestartThatCantBeSentSaysSo() async {
        log.macRequestsSucceed = false
        let power = makePower(tv: nil, receiver: nil)
        power.restartMac()
        await power.actionTask?.value
        power.sleepMac()
        await power.actionTask?.value
        #expect(log.toasts == ["Couldn't Restart the Mac mini", "Couldn't Sleep the Mac mini"])
    }

    /// With the real `TVController` (scripted network): the power key over SOAP only when port 55000 answers, then
    /// Wake-on-LAN every 2 s until it answers again.
    @Test func withTheRealTVController() async {
        let network = FakeTVNetwork()
        network.replies["urn:panasonic-com:service:p00NetworkControl:1#X_SendKey"] = (200, Data())
        var tvIsOn = true
        network.answers = { _ in tvIsOn ? "192.168.1.30" : nil }
        network.onWake = { rounds in if rounds == 2 { tvIsOn = true } }
        let tv = network.controller()
        tv.configure(brand: .panasonic, host: "192.168.1.30", mac: "02:00:5e:00:10:ab")
        let power = makePower(tv: tv, receiver: FakePowerReceiver(log: log))

        await press(power)
        #expect(network.requests.map(\.action) == ["urn:panasonic-com:service:p00NetworkControl:1#X_SendKey"])
        #expect(log.events == ["receiver.powerOff", "displays.sleep"])
        tvIsOn = false

        log.events = []
        await press(power)
        #expect(network.wakes.count == 2)
        #expect(network.requests.count == 1)
        #expect(log.events == ["displays.wake", "receiver.powerOn", "outputDevice.log"])

        // A real TVController without a MAC: never woken, no failure toast.
        let noMAC = network.controller()
        noMAC.configure(brand: .panasonic, host: "192.168.1.30", mac: nil)
        #expect(!noMAC.canTurnOn)
        #expect(tv.canTurnOn)
    }

    @Test func transportNames() {
        #expect(SystemPower.transportName(kAudioDeviceTransportTypeHDMI) == "HDMI")
        #expect(SystemPower.transportName(kAudioDeviceTransportTypeBuiltIn) == "built-in")
        #expect(SystemPower.transportName(0) == "other")
    }
}

/// A fake tunnel for `HDMICEC` and (step 9c) `CECAudioSystem`: availability answers in order (the last repeats);
/// frames and queries go to the log ("cec.40:8F"-style hex for frames, "cec.status" for the TV's power status,
/// "cec.status.receiver" for the receiver's, "cec.query.45:71" for queries).
nonisolated final class FakeCECLink: CECLink, @unchecked Sendable {
    let log: PowerLog
    var availabilities: [CECAvailability] = [.ready]
    var status: CECPowerStatus?
    /// Step 9c: the receiver's (address 5) power status.
    var receiverStatus: CECPowerStatus?
    var sendResult: CECSendResult = .sent
    /// Step 9c: per frame (by hex), overrides `sendResult`.
    var sendResults: [String: CECSendResult] = [:]
    /// Step 9c: per frame (by hex), results used once each, in order, before `sendResults`.
    var sendSequences: [String: [CECSendResult]] = [:]
    /// Step 9c: each query's answer, by the query frame's hex; missing = no answer.
    var queryReplies: [String: [UInt8]] = [:]
    /// Step 9c: the timeouts queries were given.
    private(set) var queryTimeouts: [Duration] = []
    private(set) var availabilityChecks = 0
    private(set) var invalidations = 0

    init(log: PowerLog) { self.log = log }

    func availability() async -> CECAvailability {
        let answer = availabilities[min(availabilityChecks, availabilities.count - 1)]
        availabilityChecks += 1
        return answer
    }

    func send(_ frame: CECFrame) async -> CECSendResult {
        let log = log
        let hex = frame.hex
        // Every frame a test sends must pass the tunnel's table.
        precondition(CECFrame.isAllowed(frame.bytes))
        await MainActor.run { log.events.append("cec.\(hex)") }
        if var sequence = sendSequences[hex], !sequence.isEmpty {
            let next = sequence.removeFirst()
            sendSequences[hex] = sequence
            return next
        }
        return sendResults[hex] ?? sendResult
    }

    func powerStatus(of device: CECDevice) async -> CECPowerStatus? {
        let log = log
        await MainActor.run { log.events.append(device == .tv ? "cec.status" : "cec.status.receiver") }
        return device == .tv ? status : receiverStatus
    }

    func query(_ frame: CECFrame, reply: CECReplyPattern, timeout: Duration) async -> [UInt8]? {
        let log = log
        let hex = frame.hex
        precondition(CECFrame.isAllowed(frame.bytes))
        queryTimeouts.append(timeout)
        await MainActor.run { log.events.append("cec.query.\(hex)") }
        guard let answer = queryReplies[hex], reply.matches(answer) else { return nil }
        return answer
    }

    func invalidate() { invalidations += 1 }

    func resetChecks() { availabilityChecks = 0 }
}

/// Holds sleeps until released (main actor).
final class SleepGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { continuations.count }

    func wait() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func releaseAll() {
        let all = continuations
        continuations = []
        all.forEach { $0.resume() }
    }
}

/// M7h step 9 (reopened): Power with the TV over HDMI-CEC (a real `HDMICEC` on a fake tunnel).
struct PowerControllerCECTests {
    let log = PowerLog()
    let clock = FakeReceiverClock()

    private func makeCEC(_ link: FakeCECLink, address: CECPhysicalAddress? = CECPhysicalAddress(high: 0x23, low: 0x00)) -> HDMICEC {
        let cec = HDMICEC(link: link, clock: clock, physicalAddress: { address })
        cec.configure(brand: .cec)
        return cec
    }

    private func makePower(tv: any PowerTV) -> PowerController {
        let power = PowerController(tv: tv, receiver: FakePowerReceiver(log: log), effects: log.effects)
        power.onToast = { [log] in log.toasts.append($0) }
        return power
    }

    private func press(_ power: PowerController) async {
        #expect(power.powerButton())
        await power.task?.value
        await power.outputLogTask?.value
        await power.displayCheckTask?.value
    }

    @Test func offSendsStandbyToAllBeforeTheReceiverAndDisplaySleep() async {
        let link = FakeCECLink(log: log)
        link.status = .on
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "cec.4F:36", "receiver.powerOff", "displays.sleep"])
        #expect(log.toasts == ["Turning Off…"])
    }

    @Test func turnOffSendsStandbyEvenWithoutAnAnswer() async {
        // Standby to all isn't a toggle (unlike VIERA's power key).
        let link = FakeCECLink(log: log)
        let power = makePower(tv: makeCEC(link))
        #expect(power.turnOff())
        await power.task?.value
        #expect(log.events == ["cec.status", "cec.4F:36", "receiver.powerOff", "displays.sleep"])
    }

    @Test func onWaitsForTheTunnelThenImageViewOnAndActiveSource() async {
        let link = FakeCECLink(log: log)
        link.status = .standby
        // The status check finds it ready; after the wake the proxies are gone for two checks (HPD low).
        link.availabilities = [.ready, .noDisplay, .noDisplay, .ready]
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "cec.40:04", "cec.4F:82:23:00", "receiver.powerOn",
                               "outputDevice.log"])
        // Two 250 ms waits for the tunnel, then 300 ms before Active Source.
        #expect(clock.now == .milliseconds(800))
        #expect(log.toasts == ["Turning On…"])
        // The display check found the HDMI display (opening the device again first).
        #expect(log.sleeps.contains(.seconds(20)))
        #expect(link.invalidations == 1)
    }

    @Test func onGivesUpWhenTheTunnelIsntBackIn5Seconds() async {
        let link = FakeCECLink(log: log)
        link.status = .standby
        link.availabilities = [.ready, .noDisplay]
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "receiver.powerOn", "outputDevice.log"])
        #expect(clock.now == .seconds(5))
        #expect(log.toasts == ["Turning On…", "TV Didn't Turn On"])
        #expect(!log.sleeps.contains(.seconds(20)))
    }

    @Test func noPhysicalAddressSendsImageViewOnOnly() async {
        let link = FakeCECLink(log: log)
        link.status = nil
        let power = makePower(tv: makeCEC(link, address: nil))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "cec.40:04", "receiver.powerOn", "outputDevice.log"])
    }

    @Test func noHDMIDisplay20SecondsAfterOnShowsTheInputToast() async {
        let link = FakeCECLink(log: log)
        link.status = .standby
        // Status check, the "on", then the display check 20 s later: the receiver re-routed and HDMI went away.
        link.availabilities = [.ready, .ready, .noDisplay]
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.sleeps.contains(.seconds(20)))
        #expect(log.toasts == ["Turning On…", "Switch the receiver to the Mac's input"])
    }

    /// QA major: the dev Mac (tunneling on, no address in the mask) or a tunnel that never comes back. "On" still
    /// waits 5 s after the wake, then says so; nothing is sent.
    @Test func notAvailableAfterTheWakeSaysTheTVDidntTurnOn() async {
        let link = FakeCECLink(log: log)
        link.availabilities = [.notAvailable]
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "receiver.powerOn", "outputDevice.log"])
        #expect(clock.now == .seconds(5))
        #expect(log.toasts == ["Turning On…", "TV Didn't Turn On"])
    }

    /// QA major: the tunnel read "not available" while the displays slept; after the wake it's ready, so "on" goes on.
    @Test func notAvailableBeforeTheWakeDoesntSkipTurningOn() async {
        let link = FakeCECLink(log: log)
        link.status = nil
        link.availabilities = [.notAvailable, .ready]
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "cec.40:04", "cec.4F:82:23:00", "receiver.powerOn",
                               "outputDevice.log"])
        #expect(log.toasts == ["Turning On…"])
    }

    @Test func aFailedImageViewOnSaysTheTVDidntTurnOn() async {
        let link = FakeCECLink(log: log)
        link.sendResult = .notAcknowledged
        let power = makePower(tv: makeCEC(link))
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "cec.40:04", "receiver.powerOn", "outputDevice.log"])
        #expect(log.toasts == ["Turning On…", "TV Didn't Turn On"])
    }

    /// QA minor: "off", or another "on", cancels a pending 20 s display check.
    @Test func offAndAnotherOnCancelThePendingDisplayCheck() async {
        let gate = SleepGate()
        var effects = log.effects
        effects.sleep = { duration in
            if duration == PowerController.displayCheckDelay { await gate.wait() }
        }
        let link = FakeCECLink(log: log)
        // Every display check would find no HDMI display (and toast) if it ran.
        link.availabilities = [.ready, .ready, .noDisplay]
        let cec = makeCEC(link)

        let power = PowerController(tv: cec, receiver: FakePowerReceiver(log: log), effects: effects)
        power.onToast = { [log] in log.toasts.append($0) }
        #expect(power.powerButton())
        await power.task?.value
        let pending = power.displayCheckTask
        #expect(gate.waiting == 1)
        #expect(power.turnOff())
        await power.task?.value
        gate.releaseAll()
        await pending?.value
        #expect(!log.toasts.contains(PowerController.switchInputMessage))

        // A second "on" replaces the first check: only the new one toasts.
        // Two presses' status checks and "on"s, then display checks that find no HDMI display.
        link.availabilities = [.ready, .ready, .ready, .ready, .noDisplay]
        link.resetChecks()
        log.toasts = []
        #expect(power.powerButton())
        await power.task?.value
        let first = power.displayCheckTask
        #expect(power.powerButton())
        await power.task?.value
        let second = power.displayCheckTask
        #expect(gate.waiting == 2)
        gate.releaseAll()
        await first?.value
        await second?.value
        #expect(log.toasts.filter { $0 == PowerController.switchInputMessage }.count == 1)
    }

    @Test func selectorUsesCECOnlyForTheCECBrand() async {
        let link = FakeCECLink(log: log)
        link.status = .on
        let cec = makeCEC(link)
        let network = FakePowerTV(log: log, on: true)
        let selector = PowerTVSelector(network: network, cec: cec)
        #expect(await selector.isOn())
        #expect(!selector.powerOffToggles)
        #expect(selector.checksHDMIAfterPowerOn)
        #expect(log.events == ["cec.status"])
        cec.configure(brand: .panasonic)
        log.events = []
        #expect(await selector.isOn())
        #expect(selector.powerOffToggles)
        #expect(!selector.checksHDMIAfterPowerOn)
        #expect(log.events == ["tv.isOn"])
        // A network TV never sends CEC; a TVController with brand cec isn't configured.
        let tv = TVController()
        tv.configure(brand: .cec, host: "192.168.1.30", mac: "02:00:5e:00:10:ab")
        #expect(!tv.isConfigured)
    }
}

/// M7h step 9c (L14): a receiver over HDMI-CEC gets its own power frames only with a TV that isn't on HDMI-CEC.
struct PowerControllerCECReceiverTests {
    let log = PowerLog()
    let clock = FakeReceiverClock()

    private func cecReceiver(_ link: FakeCECLink) -> CECAudioSystem {
        let system = CECAudioSystem(link: link)
        system.configure(enabled: true)
        return system
    }

    private func press(_ power: PowerController) async {
        #expect(power.powerButton())
        await power.task?.value
        await power.outputLogTask?.value
        await power.displayCheckTask?.value
    }

    @Test func aNetworkTVWithACECReceiverSendsItsStandbyAndPowerOn() async {
        let link = FakeCECLink(log: log)
        let receiver = cecReceiver(link)
        await receiver.probeTask?.value
        log.events = []
        let tv = FakePowerTV(log: log, on: true)
        let selector = PowerReceiverSelector(receiver: FakePowerReceiver(log: log), cec: receiver, tvUsesCEC: { false })
        let power = PowerController(tv: tv, receiver: selector, effects: log.effects)
        await press(power)
        #expect(log.events == ["tv.isOn", "tv.powerKey", "cec.45:36", "displays.sleep"])
        log.events = []
        await press(power)
        // After the TV is on: Power On Function, Pressed then Released.
        #expect(log.events == ["tv.isOn", "displays.wake", "tv.wakeOnLAN", "cec.45:44:6D", "cec.45:45", "outputDevice.log"])
    }

    @Test func aCECTVCoversTheCECReceiver() async {
        let link = FakeCECLink(log: log)
        link.status = .on
        let receiver = cecReceiver(link)
        await receiver.probeTask?.value
        log.events = []
        let tv = HDMICEC(link: link, clock: clock, physicalAddress: { CECPhysicalAddress(high: 0x23, low: 0x00) })
        tv.configure(brand: .cec)
        let selector = PowerReceiverSelector(receiver: FakePowerReceiver(log: log), cec: receiver,
                                             tvUsesCEC: { tv.isConfigured })
        #expect(!selector.isSetUp)
        let power = PowerController(tv: tv, receiver: selector, effects: log.effects)
        await press(power)
        // Standby to all only; no 45:36.
        #expect(log.events == ["cec.status", "cec.4F:36", "displays.sleep"])
        link.status = .standby
        log.events = []
        await press(power)
        #expect(log.events == ["cec.status", "displays.wake", "cec.40:04", "cec.4F:82:23:00", "outputDevice.log"])
    }

    @Test func withoutACECReceiverTheSerialOneIsUsed() async {
        let link = FakeCECLink(log: log)
        let receiver = CECAudioSystem(link: link)
        receiver.configure(enabled: false)
        let selector = PowerReceiverSelector(receiver: FakePowerReceiver(log: log), cec: receiver, tvUsesCEC: { false })
        #expect(selector.isSetUp)
        #expect(await selector.send(.powerOff))
        #expect(log.events == ["receiver.powerOff"])
        let none = PowerReceiverSelector(receiver: nil, cec: receiver, tvUsesCEC: { true })
        #expect(!none.isSetUp)
        #expect(await !none.send(.powerOn))
    }
}

/// M7h step 9c (coordinator decision): MMTVL's "off" makes a receiver over HDMI-CEC not answering at once, and its
/// "on" asks it again once it's had a moment to come up.
struct PowerControllerCECReceiverReadinessTests {
    final class Setup {
        let log = PowerLog()
        let link: FakeCECLink
        let cec: CECAudioSystem
        var volume: VolumeController!
        var time: TimeInterval = 0
        var sleeps: [TimeInterval] = []

        init() {
            link = FakeCECLink(log: log)
            weak var setup: Setup?
            cec = CECAudioSystem(link: link, now: { setup?.time ?? 0 }, sleep: { seconds in
                setup?.sleeps.append(seconds)
                setup?.time += seconds
            })
            volume = VolumeController(mode: { .auto }, isLauncherActive: { true }, applyAppVolume: { _ in },
                                      cecReceiver: cec, soundSourceRunning: { false }, systemSettable: { false },
                                      now: { setup?.time ?? 0 }, sleep: { setup?.time += $0 })
            setup = self
        }

        func ready() async {
            link.receiverStatus = .on
            cec.configure(enabled: true)
            await cec.probeTask?.value
            #expect(volume.cecReceiverReady)
            log.events = []
        }

        /// What reached address 5 (frames and status queries).
        var toReceiver: [String] {
            log.events.filter { $0.hasPrefix("cec.45:") || $0 == "cec.status.receiver" || $0.hasPrefix("cec.query.45:") }
        }

        func press(_ action: VolumeAction) async -> VolumeOutcome? {
            var result: VolumeOutcome?
            volume.perform(action) { result = $0 }
            await volume.receiverTask?.value
            return result
        }

        func run(_ power: PowerController, _ start: () -> Bool) async {
            #expect(start())
            await power.task?.value
            await power.outputLogTask?.value
            await power.displayCheckTask?.value
        }
    }

    @Test func offWithANetworkTVThenOnWithAProbe() async {
        let setup = Setup()
        await setup.ready()
        let selector = PowerReceiverSelector(receiver: nil, cec: setup.cec, tvUsesCEC: { false })
        let power = PowerController(tv: FakePowerTV(log: setup.log, on: true), receiver: selector,
                                    effects: setup.log.effects)
        await setup.run(power) { power.powerButton() }
        #expect(setup.toReceiver == ["cec.45:36"])
        #expect(!setup.cec.isAnswering)
        #expect(!setup.volume.cecReceiverReady)
        #expect(!setup.volume.consumesVolumeKeys())

        // A press goes to the next route (MMTVL's own volume), and nothing reaches address 5.
        setup.log.events = []
        #expect(await setup.press(.up)?.route == .app)
        #expect(await setup.press(.mute)?.route == .app)
        #expect(setup.toReceiver.isEmpty)

        // "On": Power On Function, then 5 s later a check (within 10 s of the "off": the one bypass); "on" → ready.
        await setup.run(power) { power.powerButton() }
        await setup.cec.powerOnProbeTask?.value
        await setup.cec.probeTask?.value
        #expect(setup.toReceiver == ["cec.45:44:6D", "cec.45:45", "cec.status.receiver"])
        #expect(setup.sleeps == [CECAudioSystem.powerOnProbeDelay])
        #expect(setup.time < VolumeController.probeInterval)
        #expect(setup.cec.isAnswering)
        #expect(await setup.press(.up)?.route == .cecReceiver)
    }

    @Test func aCECTVsStandbyToAllAlsoMarksItOff() async {
        let setup = Setup()
        await setup.ready()
        setup.link.status = .on
        let clock = FakeReceiverClock()
        let tv = HDMICEC(link: setup.link, clock: clock, physicalAddress: { CECPhysicalAddress(high: 0x23, low: 0x00) })
        tv.configure(brand: .cec)
        let selector = PowerReceiverSelector(receiver: nil, cec: setup.cec, tvUsesCEC: { tv.isConfigured })
        let power = PowerController(tv: tv, receiver: selector, effects: setup.log.effects)
        await setup.run(power) { power.turnOff() }
        #expect(setup.log.events.contains("cec.4F:36"))
        #expect(setup.toReceiver.isEmpty)
        #expect(!setup.cec.isAnswering)
        #expect(await setup.press(.down)?.route == .app)
        #expect(setup.toReceiver.isEmpty)

        // On: the TV's wake (nothing to address 5), then the check finds the receiver on.
        setup.link.status = .standby
        await setup.run(power) { power.powerButton() }
        await setup.cec.powerOnProbeTask?.value
        await setup.cec.probeTask?.value
        #expect(setup.toReceiver == ["cec.status.receiver"])
        #expect(setup.cec.isAnswering)
    }

    /// After "off", presses don't ask the receiver for 10 s (it could still read "on" while going down); a power-on
    /// check that finds it in standby leaves it not ready.
    @Test func offHoldsChecksForTheIntervalAndAStandbyAnswerStaysOff() async {
        let setup = Setup()
        await setup.ready()
        setup.cec.noteTurnedOff()
        setup.time = 9
        _ = await setup.press(.up)
        #expect(setup.toReceiver.isEmpty)
        setup.time = 10
        setup.link.receiverStatus = .standby
        _ = await setup.press(.up)
        await setup.cec.probeTask?.value
        #expect(setup.toReceiver == ["cec.status.receiver"])
        #expect(!setup.cec.isAnswering)
        // "Off" right after "on" cancels the pending check.
        setup.log.events = []
        setup.cec.noteTurnedOn()
        setup.cec.noteTurnedOff()
        #expect(setup.cec.powerOnProbeTask == nil)
        for _ in 0..<10 { await Task.yield() }
        #expect(setup.toReceiver.isEmpty)
    }
}
