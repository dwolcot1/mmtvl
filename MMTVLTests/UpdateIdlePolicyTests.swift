import Testing
@testable import MMTVL

/// M15 L7: When Idle installs after Power-off (MMTVL in front) or during MMTVL's own screen saver; At Night only
/// 03:00–05:00, also on a dimmed still screen with nothing playing; never while mirroring or after Exit to Desktop.
struct UpdateIdlePolicyTests {
    /// Awake, MMTVL in front, nothing playing, at noon: no mode installs.
    private func snapshot(mmtvlFrontmost: Bool = true, exitedToDesktop: Bool = false, mirroring: Bool = false,
                          poweredOffByMMTVL: Bool = false, screenSaverOurs: Bool = false,
                          stillPhase: StillScreenIdle.Phase = .awake, videoPlaying: Bool = false,
                          hour: Int = 12) -> UpdateIdleSnapshot {
        UpdateIdleSnapshot(mmtvlFrontmost: mmtvlFrontmost, exitedToDesktop: exitedToDesktop, mirroring: mirroring,
                           poweredOffByMMTVL: poweredOffByMMTVL, screenSaverOurs: screenSaverOurs,
                           stillPhase: stillPhase, videoPlaying: videoPlaying, hour: hour)
    }

    @Test func offNeverInstalls() {
        let idle = [
            snapshot(poweredOffByMMTVL: true),
            snapshot(screenSaverOurs: true),
            snapshot(stillPhase: .dimmed, hour: 4),
            snapshot(poweredOffByMMTVL: true, screenSaverOurs: true, stillPhase: .screenSaver, hour: 4),
        ]
        for s in idle {
            #expect(!UpdateIdlePolicy.mayInstall(.off, s))
        }
        #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, snapshot()))
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot()))
    }

    @Test func whenIdleAfterPowerOff() {
        for hour in [0, 4, 12, 23] {
            #expect(UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(poweredOffByMMTVL: true, hour: hour)))
        }
    }

    @Test func whenIdleNotWhenOtherAppFront() {
        #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(mmtvlFrontmost: false, poweredOffByMMTVL: true)))
        // A dimmed screen isn't idle enough for When Idle, whatever is in front.
        #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(stillPhase: .dimmed)))
    }

    @Test func whenIdleDuringOurScreenSaver() {
        #expect(UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(screenSaverOurs: true, stillPhase: .screenSaver)))
        #expect(UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(mmtvlFrontmost: false, screenSaverOurs: true)))
    }

    @Test func whenIdleNotForOthersScreenSaver() {
        // macOS's own saver (not started by MMTVL) over another app.
        #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(mmtvlFrontmost: false, screenSaverOurs: false)))
        #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, snapshot(screenSaverOurs: false, stillPhase: .screenSaver)))
    }

    @Test func notWhileMirroring() {
        let cases = [
            snapshot(mirroring: true, poweredOffByMMTVL: true, hour: 4),
            snapshot(mirroring: true, screenSaverOurs: true, hour: 4),
            snapshot(mirroring: true, stillPhase: .dimmed, hour: 4),
        ]
        for s in cases {
            #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, s))
            #expect(!UpdateIdlePolicy.mayInstall(.atNight, s))
        }
    }

    @Test func notAfterExitToDesktop() {
        let cases = [
            snapshot(exitedToDesktop: true, poweredOffByMMTVL: true, hour: 4),
            snapshot(exitedToDesktop: true, screenSaverOurs: true, hour: 4),
            snapshot(exitedToDesktop: true, stillPhase: .dimmed, hour: 4),
        ]
        for s in cases {
            #expect(!UpdateIdlePolicy.mayInstall(.whenIdle, s))
            #expect(!UpdateIdlePolicy.mayInstall(.atNight, s))
        }
    }

    @Test func atNightOnlyBetween3And5() {
        for hour in 0..<24 {
            let expected = hour == 3 || hour == 4
            #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .dimmed, hour: hour)) == expected,
                    "\(hour)")
            #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(poweredOffByMMTVL: true, hour: hour)) == expected,
                    "\(hour)")
            #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(screenSaverOurs: true, hour: hour)) == expected,
                    "\(hour)")
        }
    }

    @Test func atNightOnDimmedStillScreen() {
        #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .dimmed, hour: 4)))
        #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .screenSaver, hour: 3)))
        // Awake, or another app in front, doesn't count.
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .awake, hour: 4)))
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot(mmtvlFrontmost: false, stillPhase: .dimmed, hour: 4)))
    }

    @Test func atNightNotWhileVideoPlays() {
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .dimmed, videoPlaying: true, hour: 4)))
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot(stillPhase: .awake, videoPlaying: true, hour: 4)))
    }

    @Test func atNightAfterPowerOffEvenAt4() {
        // TV off by Power, MMTVL in front: installs at 4 a.m. even with the screen awake and video reported.
        #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(poweredOffByMMTVL: true, hour: 4)))
        #expect(UpdateIdlePolicy.mayInstall(.atNight, snapshot(poweredOffByMMTVL: true, videoPlaying: true, hour: 4)))
        #expect(!UpdateIdlePolicy.mayInstall(.atNight, snapshot(mmtvlFrontmost: false, poweredOffByMMTVL: true,
                                                                 hour: 4)))
    }
}
