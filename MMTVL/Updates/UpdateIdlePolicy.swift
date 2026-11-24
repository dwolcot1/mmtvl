/// What `SoftwareUpdater`'s idle loop sees each tick (M15), built by `AppDelegate`.
nonisolated struct UpdateIdleSnapshot: Equatable, Sendable {
    /// The frontmost app's bundle id is MMTVL's.
    var mmtvlFrontmost: Bool
    var exitedToDesktop: Bool
    /// `ReflectorMonitor.isMirroring`.
    var mirroring: Bool
    var poweredOffByMMTVL: Bool
    /// The screen saver is running and MMTVL started it.
    var screenSaverOurs: Bool
    var stillPhase: StillScreenIdle.Phase
    /// YouTube is open, or Live TV is showing video.
    var videoPlaying: Bool
    /// M15 step 6b: the receiver reports on (`ReceiverPowerWatch.isOn`; unknown isn't on), so the TV likely is too.
    var receiverOn: Bool
    /// M15 step 6b: a remote command reached MMTVL since the last Power-off (`AppRouter.inputSincePowerOff`).
    var inputSincePowerOff: Bool
    /// The local hour, 0…23.
    var hour: Int
}

/// When a staged update may be installed (M15 L7). Pure.
nonisolated enum UpdateIdlePolicy {
    /// "About 4 a.m." (L7).
    static let nightHours = 3..<5

    static func mayInstall(_ mode: AutomaticUpdates, _ s: UpdateIdleSnapshot) -> Bool {
        guard mode != .off, !s.exitedToDesktop, !s.mirroring else { return false }
        // Step 6b: the TV turned back on with its own remote shows as the receiver on, or as someone pressing buttons.
        let tvOff = s.poweredOffByMMTVL && s.mmtvlFrontmost && !s.videoPlaying && !s.receiverOn && !s.inputSincePowerOff
        switch mode {
        case .off: return false
        case .whenIdle: return tvOff || s.screenSaverOurs
        case .atNight:
            guard nightHours.contains(s.hour) else { return false }
            return tvOff || s.screenSaverOurs || (s.mmtvlFrontmost && s.stillPhase != .awake && !s.videoPlaying)
        }
    }
}
