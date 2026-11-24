import CoreGraphics
import Foundation
import Testing
@testable import MMTVL

/// Backs `PhoneRemoteEnvironment` with recorded state.
final class PhoneRemoteRecorder {
    var isActive = true
    var canPost = true
    var acceptsText = true
    var dispatched: [(RemoteCommand, Bool)] = []
    var posted: [ExternalKey] = []
    var edits: [TextEdit] = []
    var returns = 0
    var volumeResult: VolumeFeedback = .sentKeys
    var volumeActions: [VolumeAction] = []
    var now = Date(timeIntervalSinceReferenceDate: 0)
    var codes = ["1234", "5678", "9012", "3456"]
    var tokenCount = 0
    var statusChanges = 0
    var pointerActions: [PointerAction] = []
    /// The edge inset each pointer action was given.
    var pointerInsets: [CGFloat] = []
    /// Security: the kiosk gate for the app in front, and the edge inset while the lock is in force.
    var gate: KioskGuard.PointerGate = .allowed
    var edgeInset: CGFloat = 0
    /// `PairingCode.random(using:)` instead of `codes`, seeded so a lucky guess can't make a run flaky.
    var randomCodes = false
    var generator = SeededGenerator(seed: 0x4D4D_5456_4C21)
    var repairs = false
    var repairCalls = 0
    /// M7m L20: the screen saver shows; each input it swallows is recorded, with its command (M15 step 6b; nil for
    /// text and Return).
    var screenSaverShowing = false
    var screenSaverInputs: [ScreenSaverInput] = []

    struct ScreenSaverInput: Equatable {
        var name: String
        var command: RemoteCommand?

        init(_ name: String, _ command: RemoteCommand?) {
            self.name = name
            self.command = command
        }
    }

    var environment: PhoneRemoteEnvironment {
        PhoneRemoteEnvironment(
            isLauncherActive: { self.isActive },
            dispatch: { self.dispatched.append(($0, $1)) },
            canPostEvents: { self.canPost },
            postExternal: { self.posted.append($0) },
            typeEdit: { self.edits.append($0) },
            postReturn: { self.returns += 1 },
            launcherAcceptsText: { self.acceptsText },
            frontAppName: { self.isActive ? "MMTVL" : "Plex HTPC" },
            volume: { action, done in
                self.volumeActions.append(action)
                done(self.volumeResult)
            },
            now: { self.now },
            makeCode: {
                self.randomCodes || self.codes.isEmpty ? PairingCode.random(using: &self.generator) : self.codes.removeFirst()
            },
            makeToken: {
                self.tokenCount += 1
                return "tok\(self.tokenCount)"
            },
            pointer: { action, inset in
                self.pointerActions.append(action)
                self.pointerInsets.append(inset)
            },
            repairForeground: {
                self.repairCalls += 1
                return self.repairs
            },
            endsScreenSaver: { input, command in
                guard self.screenSaverShowing else { return false }
                self.screenSaverInputs.append(ScreenSaverInput(input, command))
                return true
            },
            inputGate: { self.gate },
            pointerEdgeInset: { self.edgeInset }
        )
    }
}

/// SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct PhoneRemoteTests {
    let transport = FakeTransport()
    let recorder = PhoneRemoteRecorder()
    let store = PairedPhoneStore.inMemory()
    let remote: PhoneRemote

    init() {
        remote = PhoneRemote(transport: transport, store: store, environment: recorder.environment)
        remote.onStatusChange = { [recorder] in recorder.statusChanges += 1 }
    }

    private func send(_ json: String, from session: RemoteSessionID = 1) {
        remote.receive(Data(json.utf8), from: session)
    }

    private func pair(_ code: String, from session: RemoteSessionID = 1, name: String = "iPhone") {
        send(#"{"type":"pair","code":"\#(code)","name":"\#(name)"}"#, from: session)
    }

    /// Pairs session 1 with "tok1" and clears the recordings.
    private func paired(session: RemoteSessionID = 1) {
        remote.setPairing(true)
        pair(remote.pairing!.code, from: session)
        transport.sent = []
    }

    private func status() -> ServerMessage {
        .status(frontApp: recorder.isActive ? "MMTVL" : "Plex HTPC", launcherActive: recorder.isActive)
    }

    @Test func unauthenticatedMessagesAreIgnored() {
        // Security L-3: nor do they end the screen saver.
        recorder.screenSaverShowing = true
        send(#"{"type":"command","command":"up"}"#)
        send(#"{"type":"text","value":"abc"}"#)
        send(#"{"type":"volume","action":"up"}"#)
        send(#"{"type":"submit"}"#)
        send(#"{"type":"textBegin"}"#)
        #expect(recorder.dispatched.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(recorder.edits.isEmpty)
        #expect(recorder.returns == 0)
        #expect(recorder.volumeActions.isEmpty)
        #expect(recorder.screenSaverInputs.isEmpty)
        #expect(transport.sent.isEmpty)
    }

    @Test func badHelloFailsButStaysOpen() {
        send(#"{"type":"hello","token":"nope"}"#)
        #expect(transport.messages(to: 1) == [.authFailed])
        #expect(transport.closed.isEmpty)
        #expect(transport.authenticated.isEmpty)
    }

    @Test func pairWithoutPairing() {
        pair("1234")
        #expect(transport.messages(to: 1) == [.pairFailed(PhoneRemote.openPairingMessage)])
    }

    @Test func pairing() {
        remote.setPairing(true)
        #expect(remote.pairing?.code == "1234")
        pair("0000")
        #expect(transport.messages(to: 1).last == .pairFailed("Wrong code"))
        for _ in 0..<3 {
            recorder.now += 1
            pair("0000")
        }
        recorder.now += 1
        pair("0000")
        #expect(transport.messages(to: 1).last == .pairFailed("Wrong code. A new code is on the TV"))
        #expect(remote.pairing?.code == "5678")

        transport.sent = []
        let changesBefore = recorder.statusChanges
        recorder.now += 1
        pair("5678")
        #expect(transport.messages(to: 1) == [.paired(token: "tok1"), status()])
        #expect(transport.authenticated == [1])
        let phones = store.load()
        #expect(phones.count == 1)
        #expect(phones.first?.tokenHash == PhoneToken.hash("tok1"))
        #expect(phones.first?.name == "iPhone")
        #expect(remote.lastPairedName == "iPhone")
        #expect(remote.pairedCount == 1)
        #expect(remote.connectedCount == 1)
        #expect(recorder.statusChanges > changesBefore)
    }

    @Test func helloAfterPairing() {
        paired()
        send(#"{"type":"hello","token":"tok1"}"#, from: 2)
        #expect(transport.messages(to: 2) == [.welcome, status()])
        #expect(transport.authenticated == [1, 2])
        #expect(remote.connectedCount == 2)
    }

    @Test func expiredPairing() {
        remote.setPairing(true)
        recorder.now += PairingCode.lifetime + 1
        pair("1234")
        #expect(transport.messages(to: 1) == [.pairFailed(PhoneRemote.openPairingMessage)])
    }

    @Test func elevenPairingsKeepTen() {
        remote.setPairing(true)
        for session in 1...11 {
            recorder.now += 1
            pair(remote.pairing!.code, from: session, name: "Phone \(session)")
        }
        let phones = store.load()
        #expect(phones.count == 10)
        #expect(phones.first?.name == "Phone 2")
        #expect(phones.last?.name == "Phone 11")
    }

    @Test func commandsWhileActive() {
        paired()
        send(#"{"type":"command","command":"down"}"#)
        #expect(recorder.dispatched.map(\.0) == [.down])
        #expect(recorder.dispatched.map(\.1) == [false])
    }

    @Test func commandsWhileInactive() {
        paired()
        recorder.isActive = false
        send(#"{"type":"command","command":"home"}"#)
        #expect(recorder.dispatched.map(\.0) == [.home])
        #expect(recorder.dispatched.map(\.1) == [true])

        send(#"{"type":"command","command":"up"}"#)
        send(#"{"type":"command","command":"playPause"}"#)
        #expect(recorder.posted == [.key(126), .media(16)])

        recorder.canPost = false
        send(#"{"type":"command","command":"up"}"#)
        #expect(recorder.posted.count == 2)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    /// M7h L3: the phone goes through `ExternalRouter`; volume and power commands still post nothing to other apps.
    @Test func volumeAndPowerCommandsDoNothingInOtherApps() {
        paired()
        recorder.isActive = false
        for command in ["volumeUp", "volumeDown", "mute", "power", "powerMenu"] {
            send(#"{"type":"command","command":"\#(command)"}"#)
        }
        #expect(recorder.posted.isEmpty)
        #expect(recorder.dispatched.isEmpty)
        #expect(transport.messages(to: 1).isEmpty)

        // Without Accessibility the phone hears about it, as before (not for Power, which is ignored: step 12).
        recorder.canPost = false
        send(#"{"type":"command","command":"power"}"#)
        #expect(transport.messages(to: 1).isEmpty)
        send(#"{"type":"command","command":"mute"}"#)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    /// M7h step 12 (step 4 security low): a paired phone's raw `power` / `powerMenu` never reach MMTVL's screens
    /// (no power menu, no TV off), with MMTVL in front or not.
    @Test func powerCommandsFromThePhoneAreIgnored() {
        paired()
        for isActive in [true, false] {
            recorder.isActive = isActive
            recorder.repairs = true
            send(#"{"type":"command","command":"power"}"#)
            send(#"{"type":"command","command":"powerMenu"}"#)
        }
        #expect(recorder.dispatched.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(recorder.repairCalls == 0)
        #expect(transport.messages(to: 1).isEmpty)
        // Other commands still go through.
        recorder.isActive = true
        send(#"{"type":"command","command":"select"}"#)
        #expect(recorder.dispatched.map(\.0) == [.select])
    }

    /// M7c L3: MMTVL's window shows but it isn't active; the command goes to MMTVL, not out as a key.
    @Test func commandsRepairTheForeground() {
        paired()
        recorder.isActive = false
        recorder.repairs = true
        send(#"{"type":"command","command":"down"}"#)
        #expect(recorder.dispatched.map(\.0) == [.down])
        #expect(recorder.dispatched.map(\.1) == [false])
        #expect(recorder.posted.isEmpty)
        #expect(recorder.repairCalls == 1)

        recorder.isActive = true
        send(#"{"type":"command","command":"up"}"#)
        #expect(recorder.repairCalls == 1)
    }

    @Test func textDiffs() {
        paired()
        send(#"{"type":"text","value":"s"}"#)
        send(#"{"type":"text","value":"st"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "s"), TextEdit(deletions: 0, insertion: "t")])
        send(#"{"type":"textBegin"}"#)
        send(#"{"type":"text","value":"x"}"#)
        #expect(recorder.edits.last == TextEdit(deletions: 0, insertion: "x"))
    }

    @Test func textNeedsSomewhereToGo() {
        paired()
        recorder.acceptsText = false
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits.isEmpty)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.nothingToTypeMessage))

        recorder.acceptsText = true
        send(#"{"type":"text","value":"ab"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "b")])

        recorder.isActive = false
        recorder.canPost = false
        send(#"{"type":"text","value":"abc"}"#)
        #expect(recorder.edits.count == 1)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    @Test func overlongTextIsIgnored() {
        paired()
        let long = String(repeating: "a", count: 1001)
        send(#"{"type":"text","value":"\#(long)"}"#)
        #expect(recorder.edits.isEmpty)
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "a")])
    }

    /// M7m L19, L20: while the screen saver shows, a command, text or Return only ends it: nothing is dispatched,
    /// posted or typed, and the text typed meanwhile goes in with the next edit.
    @Test func inputWhileTheScreenSaverShowsOnlyEndsIt() {
        paired()
        recorder.isActive = false
        recorder.screenSaverShowing = true
        send(#"{"type":"command","command":"down"}"#)
        send(#"{"type":"command","command":"home"}"#)
        send(#"{"type":"text","value":"a"}"#)
        send(#"{"type":"submit"}"#)
        #expect(recorder.screenSaverInputs == [.init("phone down", .down), .init("phone home", .home),
                                               .init("phone text", nil), .init("phone return", nil)])
        #expect(recorder.dispatched.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(recorder.edits.isEmpty)
        #expect(recorder.returns == 0)
        #expect(recorder.repairCalls == 0)
        recorder.screenSaverShowing = false
        send(#"{"type":"text","value":"ab"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "ab")])
    }

    @Test func submitPostsReturnAndResets() {
        paired()
        send(#"{"type":"text","value":"cats"}"#)
        send(#"{"type":"submit"}"#)
        #expect(recorder.returns == 1)
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits.last == TextEdit(deletions: 0, insertion: "a"))
    }

    @Test func volumeFeedback() {
        paired()
        recorder.volumeResult = .level(0.5, muted: false)
        send(#"{"type":"volume","action":"up"}"#)
        recorder.volumeResult = .sentKeys
        send(#"{"type":"volume","action":"down"}"#)
        recorder.volumeResult = .unavailable("Volume can't be changed here")
        send(#"{"type":"volume","action":"mute"}"#)
        #expect(recorder.volumeActions == [.up, .down, .mute])
        #expect(transport.messages(to: 1) == [
            .volume(level: 0.5, muted: false),
            .volume(level: nil, muted: nil),
            .toast("Volume can't be changed here"),
        ])
    }

    @Test func forgetAll() {
        paired()
        send(#"{"type":"textBegin"}"#, from: 2)   // unauthenticated
        remote.forgetAll()
        #expect(store.load().isEmpty)
        #expect(remote.pairedCount == 0)
        #expect(transport.messages(to: 1) == [.authFailed])
        #expect(transport.closed == [1])
        #expect(transport.messages(to: 2).isEmpty)
        #expect(remote.connectedCount == 0)
    }

    @Test func frontAppChangedOnlyReachesAuthenticatedSessions() {
        paired()
        send(#"{"type":"textBegin"}"#, from: 2)
        recorder.isActive = false
        remote.frontAppChanged()
        #expect(transport.messages(to: 1) == [status()])
        #expect(transport.messages(to: 2).isEmpty)
    }

    @Test func sessionClosedDecrementsConnected() {
        paired()
        #expect(remote.connectedCount == 1)
        remote.sessionClosed(1)
        #expect(remote.connectedCount == 0)
    }

    @Test func endingPairing() {
        paired()
        #expect(remote.lastPairedName == "iPhone")
        remote.setPairing(true)
        // Already pairing: unchanged, with the code renewed by the pairing (pre-release lows (e)).
        #expect(remote.pairing?.code == "5678")
        remote.setPairing(false)
        #expect(remote.pairing == nil)
        #expect(remote.lastPairedName == nil)
    }

    // MARK: Trackpad (M7b L13)

    @Test func pointerActionsNeedAuthentication() {
        send(#"{"type":"pointer","dx":3,"dy":4}"#)
        #expect(recorder.pointerActions.isEmpty)
        paired()
        send(#"{"type":"pointer","dx":3,"dy":4}"#)
        send(#"{"type":"click","button":"right"}"#)
        send(#"{"type":"scroll","dx":0,"dy":-12.5}"#)
        #expect(recorder.pointerActions == [.move(dx: 3, dy: 4), .click(.right), .scroll(dx: 0, dy: -12.5)])
        #expect(recorder.pointerInsets == [0, 0, 0])
        #expect(transport.sent.isEmpty)
    }

    @Test func pointerWithoutAccessibilityToastsEveryFiveSeconds() {
        paired()
        recorder.canPost = false
        send(#"{"type":"pointer","dx":1,"dy":1}"#)
        send(#"{"type":"pointer","dx":1,"dy":1}"#)
        recorder.now += 4
        send(#"{"type":"scroll","dx":1,"dy":1}"#)
        #expect(transport.sent.count == 1)
        recorder.now += 1
        send(#"{"type":"click","button":"left"}"#)
        #expect(transport.sent.count == 2)
        #expect(recorder.pointerActions.isEmpty)
    }

    // MARK: Pairing brute force (security, pre-release review, high)

    /// 20,000 guesses cycling 0000…9999 (twice) over one socket, with random codes: never paired. The code is off
    /// from the cap on (re-review L1), and the pairing still expires after its lifetime. Spaced a second apart, so
    /// every guess is checked.
    @Test func twentyThousandGuessesNeverPair() {
        recorder.randomCodes = true
        remote.setPairing(true)
        for attempt in 0..<20_000 {
            recorder.now += 1.01
            pair(String(format: "%04d", attempt % 10_000))
        }
        let sent = transport.messages(to: 1)
        let locked = ServerMessage.pairFailed(PhoneRemote.codeLockedMessage, codeLocked: true)
        #expect(!sent.contains { if case .paired = $0 { true } else { false } })
        #expect(store.load().isEmpty)
        #expect(sent.firstIndex(of: locked) == PairingCode.maxTotalFailures - 1)
        // Expired, not ended by the wrong codes.
        #expect(remote.pairing == nil)
        #expect(remote.pairingEnded)
        #expect(sent.last == .pairFailed(PhoneRemote.openPairingMessage))
    }

    /// The same, all at once: after the first, guesses aren't checked (too fast) but count, so the code turns off at
    /// the cap; the pairing and its QR secret stay (re-review L1).
    @Test func rapidGuessesCountWithoutBeingChecked() throws {
        recorder.randomCodes = true
        remote.setPairing(true)
        for attempt in 0..<20_000 {
            pair(String(format: "%04d", attempt % 10_000))
        }
        let sent = transport.messages(to: 1)
        #expect(!sent.contains { if case .paired = $0 { true } else { false } })
        #expect(store.load().isEmpty)
        #expect(sent[1] == .pairFailed(PhoneRemote.tooFastMessage))
        #expect(sent[PairingCode.maxTotalFailures - 1] == .pairFailed(PhoneRemote.codeLockedMessage, codeLocked: true))
        #expect(!remote.pairingEnded)
        let secret = try #require(remote.pairing?.secret)
        recorder.now += 1
        pair(secret, from: 1)
        #expect(transport.messages(to: 1).last == status())
        #expect(store.load().count == 1)
    }

    /// Re-review L1: a LAN peer's 10 quick wrong codes (1 checked, 9 throttled) turn the typed code off but don't end
    /// pairing: a correct 4-digit code is refused, a wrong secret changes nothing (and, security lows L-5, isn't
    /// counted), and the QR code's secret still pairs.
    @Test func wrongCodesFromAPeerDontEndThePairing() throws {
        transport.hosts = [1: "10.0.0.66", 2: "10.0.0.7"]
        remote.setPairing(true)
        let changesBefore = recorder.statusChanges
        for _ in 0..<PairingCode.maxTotalFailures {
            pair("0000", from: 1)
        }
        let locked = ServerMessage.pairFailed(PhoneRemote.codeLockedMessage, codeLocked: true)
        #expect(transport.messages(to: 1).last == locked)
        #expect(remote.pairing?.isCodeLocked == true)
        #expect(!remote.pairingEnded)
        // One for the rotation at 5, one for the lock at 10.
        #expect(recorder.statusChanges == changesBefore + 2)

        let code = try #require(remote.pairing?.code)
        let secret = try #require(remote.pairing?.secret)
        pair(code, from: 2)
        #expect(transport.messages(to: 2) == [locked])
        recorder.now += 1
        pair(String(repeating: "f", count: 32), from: 1)
        #expect(transport.messages(to: 1).last == locked)
        #expect(remote.pairing?.secret == secret)
        #expect(recorder.statusChanges == changesBefore + 2)

        recorder.now += 1
        pair(secret, from: 2)
        #expect(transport.messages(to: 2).suffix(2) == [.paired(token: "tok1"), status()])
        #expect(store.load().count == 1)
        #expect(transport.authenticated == [2])
    }

    /// The throttle is per address: a right code too soon after a wrong one fails unchecked; a second later it pairs.
    @Test func throttleIsPerAddress() {
        transport.hosts = [1: "10.0.0.7", 2: "10.0.0.7", 3: "10.0.0.8"]
        remote.setPairing(true)
        pair("0000", from: 1)
        pair("1234", from: 2)
        #expect(transport.messages(to: 2) == [.pairFailed(PhoneRemote.tooFastMessage)])
        pair("1234", from: 3)
        #expect(transport.messages(to: 3).first == .paired(token: "tok1"))
        // Pre-release lows (e): session 3's pairing renewed the code.
        #expect(remote.pairing?.code == "5678")
        recorder.now += 1
        pair("1234", from: 2)
        #expect(transport.messages(to: 2).last == .pairFailed("Wrong code"))
        recorder.now += 1
        pair("5678", from: 2)
        #expect(transport.messages(to: 2).last == status())
    }

    /// Pre-release lows (e): a successful pairing renews both the code and the QR code's secret (same expiry), so a
    /// photographed QR code or a seen code is single-use; the next phone pairs with the fresh ones.
    @Test func pairingRenewsTheCodeAndTheSecret() throws {
        transport.hosts = [1: "10.0.0.7", 2: "10.0.0.8", 3: "10.0.0.9"]
        remote.setPairing(true)
        let first = try #require(remote.pairing)
        pair(first.secret, from: 1)
        #expect(transport.messages(to: 1).first == .paired(token: "tok1"))
        let renewed = try #require(remote.pairing)
        #expect(renewed.secret != first.secret)
        #expect(renewed.secret.count == 32)
        #expect(renewed.code == "5678")
        #expect(renewed.expires == first.expires)
        #expect(remote.lastPairedName == "iPhone")

        recorder.now += 2
        pair(first.secret, from: 2)
        #expect(transport.messages(to: 2) == [.pairFailed("Wrong code")])
        recorder.now += 2
        pair(first.code, from: 2)
        #expect(transport.messages(to: 2).last == .pairFailed("Wrong code"))
        #expect(store.load().count == 1)

        recorder.now += 2
        pair(renewed.secret, from: 3, name: "Pixel")
        #expect(transport.messages(to: 3).first == .paired(token: "tok2"))
        #expect(store.load().map(\.name) == ["iPhone", "Pixel"])
        #expect(remote.pairing?.secret != renewed.secret)
        #expect(remote.pairing?.code == "9012")
    }

    /// Pre-release lows (e): the throttle is for typed codes only. A QR scan right after a wrong code from the same
    /// address pairs; a wrong secret is checked, never answered "Too fast", and (security lows L-5) isn't a wrong code.
    @Test func qrScanRightAfterAWrongCodeStillPairs() throws {
        transport.hosts = [1: "10.0.0.7", 2: "10.0.0.7"]
        remote.setPairing(true)
        pair("0000", from: 1)
        pair(String(repeating: "0", count: 32), from: 1)
        #expect(transport.messages(to: 1) == [.pairFailed("Wrong code"), .pairFailed("Wrong code")])
        #expect(remote.pairing?.totalFailures == 1)
        let secret = try #require(remote.pairing?.secret)
        pair(secret, from: 2)
        #expect(transport.messages(to: 2) == [.paired(token: "tok1"), status()])
        // A typed code right after is still throttled.
        pair(remote.pairing!.code, from: 1)
        #expect(transport.messages(to: 1).last == .pairFailed(PhoneRemote.tooFastMessage))
    }

    /// Pre-release lows (e): 20,000 wrong secrets as fast as they come, over 4,000 sockets of 5 each (security lows
    /// L-5: a 6th on one socket closes it), are each checked; none pairs, they never lock or change the typed code
    /// (L-5), and the real secret and the typed code still pair.
    @Test func twentyThousandWrongSecretsNeverPair() throws {
        remote.setPairing(true)
        let secret = try #require(remote.pairing?.secret)
        let code = try #require(remote.pairing?.code)
        var generator = SeededGenerator(seed: 7)
        for attempt in 0..<20_000 {
            let guess = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
                .joined()
            guard guess != secret else { continue }
            pair(guess, from: 100 + attempt / PhoneRemote.maxSecretAttempts)
        }
        #expect(!transport.sent.contains { if case .paired = $0.1 { true } else { false } })
        #expect(!transport.sent.contains { $0.1 == .pairFailed(PhoneRemote.tooFastMessage) })
        #expect(transport.sent.allSatisfy { $0.1 == .pairFailed("Wrong code") })
        #expect(transport.sent.count == 20_000)
        #expect(transport.closed.isEmpty)
        #expect(store.load().isEmpty)
        #expect(remote.pairing?.isCodeLocked == false)
        #expect(remote.pairing?.totalFailures == 0)
        #expect(remote.pairing?.code == code)
        pair(secret, from: 2)
        #expect(transport.messages(to: 2).first == .paired(token: "tok1"))
        recorder.now += 1
        pair(try #require(remote.pairing?.code), from: 3)
        #expect(transport.messages(to: 3).first == .paired(token: "tok2"))
    }

    /// Security lows L-5: 1,000 wrong secrets (and garbage) on one socket at once: 5 are checked, the 6th closes the
    /// socket unchecked, and none locks, rotates or counts against the typed code, which still pairs. A socket trying
    /// a secret every 2.5 s is never closed.
    @Test func wrongSecretsOnOneSocketCloseItWithoutLockingTheCode() throws {
        remote.setPairing(true)
        let code = try #require(remote.pairing?.code)
        let changesBefore = recorder.statusChanges
        for attempt in 0..<1_000 {
            pair(attempt.isMultiple(of: 2) ? String(repeating: "e", count: 32) : "not-a-code-\(attempt)", from: 1)
        }
        #expect(transport.messages(to: 1) == Array(repeating: .pairFailed("Wrong code"), count: PhoneRemote.maxSecretAttempts))
        #expect(transport.closed.first == 1)
        #expect(Set(transport.closed) == [1])
        #expect(remote.pairing?.code == code)
        #expect(remote.pairing?.failures == 0)
        #expect(remote.pairing?.totalFailures == 0)
        #expect(remote.pairing?.isCodeLocked == false)
        #expect(recorder.statusChanges == changesBefore)

        transport.closed = []
        for _ in 0..<20 {
            recorder.now += 2.5
            pair(String(repeating: "e", count: 32), from: 3)
        }
        #expect(transport.closed.isEmpty)
        #expect(transport.messages(to: 3).count == 20)

        pair(code, from: 2)
        #expect(transport.messages(to: 2).first == .paired(token: "tok1"))
    }

    /// The QR code's secret pairs; once the pairing expires it doesn't, and Pair a Phone opened again starts fresh.
    @Test func secretPairsAndReopeningRestarts() throws {
        remote.setPairing(true)
        let secret = try #require(remote.pairing?.secret)
        pair(secret)
        #expect(transport.messages(to: 1).first == .paired(token: "tok1"))

        remote.setPairing(false)
        remote.setPairing(true)
        let second = try #require(remote.pairing?.secret)
        recorder.now += PairingCode.lifetime
        pair(second, from: 2)
        #expect(transport.messages(to: 2).last == .pairFailed(PhoneRemote.openPairingMessage))
        #expect(remote.pairingEnded)
        #expect(remote.pairing == nil)
        remote.setPairing(false)
        #expect(!remote.pairingEnded)
        remote.setPairing(true)
        #expect(remote.pairing != nil)
        recorder.now += 1
        pair(remote.pairing!.code, from: 2)
        #expect(transport.messages(to: 2).contains(.paired(token: "tok2")))
    }

    // MARK: Kiosk lock (security, pre-release review, medium)

    /// Another app in front that the kiosk guard doesn't allow, with the lock in force: the phone's clicks, moves,
    /// scrolls, text, Return and keys post nothing; Home still goes home.
    @Test func blockedFrontAppGetsNothingFromThePhone() {
        paired()
        recorder.isActive = false
        recorder.gate = .blocked(bundleID: "com.example.other")
        send(#"{"type":"click","button":"left"}"#)
        send(#"{"type":"pointer","dx":0,"dy":-500}"#)
        send(#"{"type":"scroll","dx":0,"dy":5}"#)
        send(#"{"type":"text","value":"secret"}"#)
        send(#"{"type":"submit"}"#)
        send(#"{"type":"command","command":"select"}"#)
        send(#"{"type":"command","command":"playPause"}"#)
        #expect(recorder.pointerActions.isEmpty)
        #expect(recorder.edits.isEmpty)
        #expect(recorder.returns == 0)
        #expect(recorder.posted.isEmpty)
        #expect(transport.messages(to: 1).contains(.toast(PhoneRemote.blockedAppMessage)))
        // The pointer's toast is rate-limited: one for the three pointer messages, plus text, Return and two keys.
        #expect(transport.messages(to: 1).count(where: { $0 == .toast(PhoneRemote.blockedAppMessage) }) == 5)

        send(#"{"type":"command","command":"home"}"#)
        #expect(recorder.dispatched.map(\.0) == [.home])

        // An allowed app: everything goes through again, the pointer with the lock's edge inset.
        recorder.gate = .allowed
        recorder.edgeInset = PointerMath.remoteEdgeInset(isLockEffective: true)
        send(#"{"type":"click","button":"left"}"#)
        send(#"{"type":"text","value":"secretx"}"#)
        #expect(recorder.pointerActions == [.click(.left)])
        #expect(recorder.pointerInsets == [PointerMath.kioskEdgeInset])
        #expect(recorder.edits.count == 1)
    }

    /// With the lock in force, a phone move toward y = 0 (the menu bar) stops at the inset.
    @Test func lockedMoveTowardTheTopClampsToTheInset() throws {
        paired()
        recorder.edgeInset = PointerMath.remoteEdgeInset(isLockEffective: true)
        send(#"{"type":"pointer","dx":0,"dy":-1000}"#)
        let inset = try #require(recorder.pointerInsets.first)
        #expect(inset == 6)
        guard case .move(let dx, let dy) = recorder.pointerActions.first else {
            Issue.record("Expected a move")
            return
        }
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let move = try #require(PhonePointer.moveTarget(dx: dx, dy: dy, current: CGPoint(x: 960, y: 40),
                                                        displays: [screen], edgeInset: inset))
        #expect(move.point.y == 6)
        #expect(move.point.x == 960)
        let unlocked = try #require(PhonePointer.moveTarget(dx: dx, dy: dy, current: CGPoint(x: 960, y: 40),
                                                            displays: [screen], edgeInset: 0))
        #expect(unlocked.point.y < 6)
    }
}
