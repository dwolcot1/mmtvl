import CoreGraphics
import Foundation
import Observation
import os

/// Everything PhoneRemote does to the outside world. The app wires the real thing; tests pass fakes.
struct PhoneRemoteEnvironment {
    /// NSApp.isActive.
    var isLauncherActive: () -> Bool
    /// InputRouter.dispatchFromRemote(_:isGlobal:) (keeps a command while MMTVL is brought forward).
    var dispatch: (RemoteCommand, Bool) -> Void
    /// SyntheticInput.canPost.
    var canPostEvents: () -> Bool
    /// SyntheticInput.postKey / postMediaKey.
    var postExternal: (ExternalKey) -> Void
    /// deleteBackward + type.
    var typeEdit: (TextEdit) -> Void
    /// SyntheticInput.postKey(kVK_Return).
    var postReturn: () -> Void
    /// router.screen == .youtube.
    var launcherAcceptsText: () -> Bool
    /// frontmostApplication?.localizedName ?? "Mac".
    var frontAppName: () -> String
    /// VolumeController.perform: calls back with the feedback (at once, or after the receiver's reply, D44).
    var volume: (VolumeAction, @escaping (VolumeFeedback) -> Void) -> Void
    var now: () -> Date
    /// PairingCode.random.
    var makeCode: () -> String
    /// PhoneToken.make.
    var makeToken: () -> String
    /// M7b: PhonePointer.perform (trackpad), with the edge inset (`pointerEdgeInset`).
    var pointer: (PointerAction, CGFloat) -> Void
    /// M7c L3: MMTVL's window shows but MMTVL isn't active (nothing else in front): brings it forward
    /// and returns true, so the command goes to MMTVL instead of out as a synthetic key.
    var repairForeground: () -> Bool = { false }
    /// M7m L19, L20: `AppRouter.endScreenSaverIfShowing(by:)`: true when the screen saver showed and this input (a
    /// command, text or Return; the first argument names it for the log) ended it, so it's swallowed. M15 step 6b: the
    /// second is the command (nil for text and Return).
    var endsScreenSaver: (String, RemoteCommand?) -> Bool = { _, _ in false }
    /// Security (pre-release review, medium): `KioskGuard.pointerGate` for the app in front, like the Siri Remote's
    /// trackpad: while the kiosk lock is in force, the phone's pointer, text, Return and keys act only in an app the
    /// guard allows.
    var inputGate: () -> KioskGuard.PointerGate = { .allowed }
    /// `PointerMath.remoteEdgeInset(isLockEffective:)`: the pointer stays off the screen edges while the lock is in force.
    var pointerEdgeInset: () -> CGFloat = { 0 }
}

/// The phone remote coordinator (D24): auth, pairing, command routing, text, volume and status pushes.
@Observable
final class PhoneRemote {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")
    static let maxPhones = 10
    static let maxTextLength = 1000
    static let maxNameLength = 40

    static let openPairingMessage = "Open Settings → Phone Remote → Pair a Phone on the TV"
    static let accessibilityMessage = "Allow Accessibility for MMTVL on the Mac to control other apps"
    static let nothingToTypeMessage = "Nothing to type into here"
    static let blockedAppMessage = "The phone can't control this app. Press Home"
    /// Re-review L1: the typed code is off after `PairingCode.maxTotalFailures` wrong codes; the QR code still pairs.
    static let codeLockedMessage = "Too many wrong codes. Scan the QR code on the TV with the phone's camera"
    static let tooFastMessage = "Too fast. Wait a second and try again"
    /// Security (pre-release review, high): one checked pairing attempt per address per second; quicker ones count
    /// as wrong codes without being checked. Pre-release lows (e): only typed 4-digit codes; the QR code's secret is
    /// always checked at once. Security lows L-5: a wrong secret (any attempt that isn't 4 digits) isn't a wrong code.
    static let pairAttemptInterval: TimeInterval = 1
    /// Security lows L-5: attempts that aren't 4-digit codes (the QR code's secret, or garbage) per session in
    /// `secretAttemptWindow`; one more closes the session, unchecked.
    static let maxSecretAttempts = 5
    static let secretAttemptWindow: TimeInterval = 10

    /// Pairing started/rotated/ended, a phone paired, a session opened/closed or authenticated, forget-all.
    @ObservationIgnored var onStatusChange: (() -> Void)?

    private(set) var pairing: PairingCode?
    /// Pairing expired (`PairingCode.lifetime`; found by the next attempt); cleared when Pair a Phone opens or closes.
    /// Re-review L1: wrong codes never end pairing, they only turn the typed code off (`PairingCode.isCodeLocked`).
    private(set) var pairingEnded = false
    /// Name of the last phone paired during the current pairing; cleared when pairing starts or ends.
    private(set) var lastPairedName: String?
    private(set) var phones: [PairedPhone]
    private var sessions: [RemoteSessionID: Session] = [:]
    /// When each address (else session) last had a pairing attempt checked; cleared when pairing starts or ends.
    @ObservationIgnored private var lastPairAttempt: [String: Date] = [:]

    var pairedCount: Int { phones.count }
    /// Authenticated sessions.
    var connectedCount: Int { sessions.values.count { $0.phoneID != nil } }

    @ObservationIgnored private let transport: RemoteTransport
    @ObservationIgnored private let store: PairedPhoneStore
    @ObservationIgnored private let environment: PhoneRemoteEnvironment

    private struct Session {
        /// nil = unauthenticated.
        var phoneID: String?
        var lastText = ""
        /// M7b L13: when this session last got the Accessibility toast for pointer messages.
        var lastAccessToast: Date?
        /// When this session last got the blocked-app toast for pointer messages.
        var lastBlockedToast: Date?
        /// Security lows L-5: when this session's last attempts that weren't 4-digit codes came (`maxSecretAttempts`).
        var secretAttempts: [Date] = []
    }

    /// L13: pointer messages arrive ~60 times a second; the toast repeats at most this often.
    static let pointerToastInterval: TimeInterval = 5

    init(transport: RemoteTransport, store: PairedPhoneStore, environment: PhoneRemoteEnvironment) {
        self.transport = transport
        self.store = store
        self.environment = environment
        phones = store.load()
    }

    // MARK: From RemoteServer

    func receive(_ data: Data, from session: RemoteSessionID) {
        guard let message = ClientMessage.decode(data) else { return }
        var state = sessions[session] ?? Session()
        var closes = false
        defer {
            sessions[session] = state
            // Security lows L-5: after the state is stored, so the transport's close (which ends the session's state
            // through `sessionClosed`) has the last word.
            if closes { transport.close(session) }
        }

        switch message {
        case .hello(let token):
            hello(token, state: &state, session: session)
        case .pair(let code, let name):
            closes = pair(code, name: name, state: &state, session: session)
        case .command(let command):
            guard state.phoneID != nil else { return }
            // M7h step 12 (step 4 security low): the phone has no Power button; a raw `power` or `powerMenu` never
            // turns the TV off, opens the power menu or reaches MMTVL's screens.
            guard command != .power, command != .powerMenu else {
                Self.logger.info("Ignored a phone \(command.rawValue, privacy: .public) command")
                return
            }
            route(command, session: session)
        case .textBegin:
            guard state.phoneID != nil else { return }
            state.lastText = ""
        case .text(let value):
            guard state.phoneID != nil, value.count <= Self.maxTextLength else { return }
            // M7m L20: text while the screen saver shows only ends it; `lastText` stays, so the next edit types it all.
            guard !environment.endsScreenSaver("phone text", nil) else { return }
            let edit = TextEdit.between(state.lastText, value)
            state.lastText = value
            guard !edit.isEmpty, canType(session: session) else { return }
            environment.typeEdit(edit)
        case .submit:
            guard state.phoneID != nil else { return }
            guard !environment.endsScreenSaver("phone return", nil) else { return }
            state.lastText = ""
            guard canType(session: session) else { return }
            environment.postReturn()
        case .volume(let action):
            guard state.phoneID != nil else { return }
            environment.volume(action) { [transport] feedback in
                switch feedback {
                case .level(let level, let muted): transport.send(.volume(level: level, muted: muted), to: session)
                case .sentKeys: transport.send(.volume(level: nil, muted: nil), to: session)
                case .unavailable(let message): transport.send(.toast(message), to: session)
                }
            }
        case .pointer(let action):
            guard state.phoneID != nil else { return }
            guard environment.canPostEvents() else {
                let now = environment.now()
                if state.lastAccessToast.map({ now.timeIntervalSince($0) >= Self.pointerToastInterval }) ?? true {
                    state.lastAccessToast = now
                    transport.send(.toast(Self.accessibilityMessage), to: session)
                }
                return
            }
            // Security: like the Siri Remote's trackpad, only in an app the kiosk guard allows, off the screen edges.
            guard case .allowed = environment.inputGate() else {
                let now = environment.now()
                if state.lastBlockedToast.map({ now.timeIntervalSince($0) >= Self.pointerToastInterval }) ?? true {
                    state.lastBlockedToast = now
                    Self.logger.info("Ignored the phone's trackpad: the app in front isn't allowed")
                    transport.send(.toast(Self.blockedAppMessage), to: session)
                }
                return
            }
            environment.pointer(action, environment.pointerEdgeInset())
        }
    }

    func sessionClosed(_ session: RemoteSessionID) {
        guard let state = sessions.removeValue(forKey: session) else { return }
        if state.phoneID != nil { onStatusChange?() }
    }

    // MARK: From Settings (L3)

    func setPairing(_ active: Bool) {
        if active {
            guard pairing == nil else { return }
            pairing = PairingCode(code: environment.makeCode(), expires: environment.now() + PairingCode.lifetime)
            lastPairedName = nil
            pairingEnded = false
            lastPairAttempt = [:]
            Self.logger.info("Pairing started")
        } else {
            guard pairing != nil || lastPairedName != nil || pairingEnded else { return }
            pairing = nil
            lastPairedName = nil
            pairingEnded = false
            lastPairAttempt = [:]
            Self.logger.info("Pairing ended")
        }
        onStatusChange?()
    }

    /// Clears the paired phones and closes every authenticated session, so their pages show pairing.
    func forgetAll() {
        phones = []
        save()
        for (id, state) in sessions where state.phoneID != nil {
            sessions[id] = nil
            transport.send(.authFailed, to: id)
            transport.close(id)
        }
        Self.logger.info("Forgot all phones")
        onStatusChange?()
    }

    /// App activation changed: push .status to every authenticated session (L16).
    func frontAppChanged() {
        for (id, state) in sessions where state.phoneID != nil {
            sendStatus(to: id)
        }
    }

    /// Server stopped: drop all session state.
    func reset() {
        sessions = [:]
        onStatusChange?()
    }

    // MARK: Private

    private func hello(_ token: String, state: inout Session, session: RemoteSessionID) {
        let hash = PhoneToken.hash(token)
        guard let phone = phones.first(where: { $0.tokenHash == hash }) else {
            state.phoneID = nil
            transport.send(.authFailed, to: session)
            return
        }
        state.phoneID = phone.id
        transport.sessionAuthenticated(session)
        Self.logger.info("Phone \"\(phone.name, privacy: .public)\" connected")
        transport.send(.welcome, to: session)
        sendStatus(to: session)
        sessions[session] = state
        onStatusChange?()
    }

    /// Whether the session must be closed (security lows L-5: too many attempts that aren't 4-digit codes).
    @discardableResult
    private func pair(_ code: String, name: String, state: inout Session, session: RemoteSessionID) -> Bool {
        guard var pairing else {
            transport.send(.pairFailed(Self.openPairingMessage), to: session)
            return false
        }
        // Security (pre-release review, high): one checked code per address (an IPv6 /64, `PeerAddress`) per second;
        // a quicker one is a failure without looking at the code. Pre-release lows (e): only 4-digit codes; the QR
        // code's 128-bit secret needs no throttle, so a scan right after a wrong code from the same phone still pairs.
        let now = environment.now()
        let key = transport.peerHost(of: session) ?? "session \(session)"
        let isCode = PairingCode.isCodeAttempt(code)
        let isTooSoon = isCode
            && (lastPairAttempt[key].map { now.timeIntervalSince($0) < Self.pairAttemptInterval } ?? false)
        let result: PairingCode.Check
        if !isCode {
            // Security lows L-5: compared with the secret only, never counted as a wrong code; more than
            // `maxSecretAttempts` in `secretAttemptWindow` on one session closes it, unchecked.
            state.secretAttempts.removeAll { now.timeIntervalSince($0) >= Self.secretAttemptWindow || $0 > now }
            guard state.secretAttempts.count < Self.maxSecretAttempts else {
                Self.logger.info("Closed a phone connection: too many pairing attempts")
                return true
            }
            state.secretAttempts.append(now)
            result = pairing.checkSecret(code, now: now)
        } else if isTooSoon {
            result = pairing.fail(now: now, makeCode: environment.makeCode)
        } else {
            lastPairAttempt[key] = now
            result = pairing.check(code, now: now, makeCode: environment.makeCode)
        }
        switch result {
        case .expired:
            // Pair a Phone must be opened again; the page says so.
            self.pairing = nil
            pairingEnded = true
            Self.logger.info("Pairing expired")
            transport.send(.pairFailed(Self.openPairingMessage), to: session)
            onStatusChange?()
        case .rejected where !isCode && pairing.isCodeLocked:
            // Security lows L-5: a wrong secret once the typed code is off: the page keeps saying to scan the QR code.
            transport.send(.pairFailed(Self.codeLockedMessage, codeLocked: true), to: session)
        case .rejected:
            self.pairing = pairing
            transport.send(.pairFailed(isTooSoon ? Self.tooFastMessage : "Wrong code"), to: session)
        case .rotated(let fresh):
            self.pairing = fresh
            Self.logger.info("Pairing code rotated after \(PairingCode.maxFailures) wrong codes")
            transport.send(.pairFailed("Wrong code. A new code is on the TV"), to: session)
            onStatusChange?()
        case .codeLocked:
            // Re-review L1: only the typed code stops working; the QR code's secret pairs until the pairing expires,
            // so wrong codes from another device can't end the user's pairing. Pair a Phone says to scan the QR code.
            let wasLocked = self.pairing?.isCodeLocked ?? false
            self.pairing = pairing
            transport.send(.pairFailed(Self.codeLockedMessage, codeLocked: true), to: session)
            if !wasLocked {
                Self.logger.notice("Pairing code turned off after \(PairingCode.maxTotalFailures) wrong codes; the QR code still pairs")
                onStatusChange?()
            }
        case .accepted:
            let token = environment.makeToken()
            let phone = PairedPhone(id: UUID().uuidString, name: Self.cleanName(name),
                                    tokenHash: PhoneToken.hash(token), pairedAt: environment.now())
            phones.append(phone)
            if phones.count > Self.maxPhones {
                phones.removeFirst(phones.count - Self.maxPhones)
            }
            save()
            state.phoneID = phone.id
            transport.sessionAuthenticated(session)
            lastPairedName = phone.name
            // Pre-release lows (e): the QR code and the code shown when this phone paired no longer pair; Pair a
            // Phone shows fresh ones (`onStatusChange` below).
            pairing.renew(makeCode: environment.makeCode)
            self.pairing = pairing
            Self.logger.info("Paired \"\(phone.name, privacy: .public)\" (\(self.phones.count) phones)")
            transport.send(.paired(token: token), to: session)
            sendStatus(to: session)
            sessions[session] = state
            onStatusChange?()
        }
        return false
    }

    /// L5; M7h L3: the shared `ExternalRouter` (volume commands map to no key, so they do nothing here; power commands
    /// never get here).
    /// Security (pre-release review, medium): a key for another app is posted only when the kiosk guard allows that
    /// app (`inputGate`); Home still goes home.
    private func route(_ command: RemoteCommand, session: RemoteSessionID) {
        var blocked = false
        let router = ExternalRouter(
            isLauncherInFront: { [self] in launcherInFront() },
            dispatch: { [environment] command, isGlobal, _ in environment.dispatch(command, isGlobal) },
            canPostEvents: environment.canPostEvents,
            postExternal: { [environment] key in
                guard case .allowed = environment.inputGate() else {
                    blocked = true
                    return
                }
                environment.postExternal(key)
            },
            endsScreenSaver: { [environment] in environment.endsScreenSaver("phone \($0.rawValue)", $0) }
        )
        if router.route(command) == .needsAccessibility {
            transport.send(.toast(Self.accessibilityMessage), to: session)
        } else if blocked {
            Self.logger.info("Ignored a phone \(command.rawValue, privacy: .public): the app in front isn't allowed")
            transport.send(.toast(Self.blockedAppMessage), to: session)
        }
    }

    /// L7: inside MMTVL only the YouTube screen takes text; elsewhere it needs post-event access and (security) an
    /// app the kiosk guard allows.
    private func canType(session: RemoteSessionID) -> Bool {
        if launcherInFront() {
            if !environment.launcherAcceptsText() {
                transport.send(.toast(Self.nothingToTypeMessage), to: session)
                return false
            }
        } else if case .blocked = environment.inputGate() {
            Self.logger.info("Ignored phone text: the app in front isn't allowed")
            transport.send(.toast(Self.blockedAppMessage), to: session)
            return false
        }
        if !environment.canPostEvents() {
            transport.send(.toast(Self.accessibilityMessage), to: session)
            return false
        }
        return true
    }

    /// L3: active, or visible and repaired.
    private func launcherInFront() -> Bool {
        environment.isLauncherActive() || environment.repairForeground()
    }

    private func sendStatus(to session: RemoteSessionID) {
        transport.send(.status(frontApp: environment.frontAppName(), launcherActive: environment.isLauncherActive()), to: session)
    }

    private func save() {
        do {
            try store.save(phones)
        } catch {
            Self.logger.error("Failed to save paired phones: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return trimmed.isEmpty ? "Phone" : trimmed
    }
}
