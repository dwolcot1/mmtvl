import Testing
@testable import MMTVL

/// Settings → Casting (M7b L14).
struct SettingsCastingTests {
    @Test func rootRowPushesCastingAndRefreshes() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "casting")?.action == .push(.casting))
        let ids = model.actionRowIDs
        #expect(ids.firstIndex(of: "casting") == ids.firstIndex(of: "youtube")! + 1)
        model.perform(.push(.casting))
        #expect(model.page == .casting)
        #expect(model.pageTitle == "Casting")
        #expect(recorder.castingRefreshes == 1)
        #expect(model.sections.map(\.id) == ["cast.youtube", "cast.airplay", "cast.android", "cast.plex"])
    }

    @Test func youtubeRowFollowsTheReceiver() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.casting))
        let cases: [(CastingSettingsStatus.YouTube, String?)] = [
            (.ready, "Phones on this network list \"MMTVL\""),
            (.starting, "Starting…"),
            (.failed("Port 1900 is in use"), "Port 1900 is in use"),
            (.off, nil),
        ]
        for (state, detail) in cases {
            recorder.casting.youtube = state
            model.refreshStatus()
            #expect(model.row(id: "cast.youtube.enabled")?.value == "On")
            #expect(model.row(id: "cast.youtube.enabled")?.detail == detail)
        }
    }

    @Test func togglingYouTubeOffAppliesIt() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.casting))
        #expect(model.row(id: "cast.youtube.enabled")?.action == .toggle(.youtubeCastEnabled))
        model.perform(.toggle(.youtubeCastEnabled))
        #expect(recorder.appliedSettings.last?.youtubeCastEnabled == false)
        #expect(model.row(id: "cast.youtube.enabled")?.value == "Off")
        #expect(model.row(id: "cast.youtube.enabled")?.detail == nil)
    }

    @Test func airPlayRow() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.casting))
        #expect(model.row(id: "cast.airplay.receiver")?.value == "Unknown")
        recorder.casting.airPlay = .on
        model.refreshStatus()
        #expect(model.row(id: "cast.airplay.receiver")?.value == "On")
        recorder.casting.airPlay = .off
        model.refreshStatus()
        #expect(model.row(id: "cast.airplay.receiver")?.value == "Off")
        #expect(model.row(id: "cast.airplay.receiver")?.action == .openAirPlaySettings)
        model.perform(.openAirPlaySettings)
        #expect(recorder.airPlaySettingsOpened == 1)
    }

    @Test func plexRowIsInfoOnly() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.casting))
        #expect(model.row(id: "cast.plex.htpc")?.value == "Not Installed")
        #expect(model.row(id: "cast.plex.htpc")?.action == nil)
        recorder.casting.plexHTPC = .notRunning
        model.refreshStatus()
        #expect(model.row(id: "cast.plex.htpc")?.value == "Not Running")
        recorder.casting.plexHTPC = .running
        model.refreshStatus()
        #expect(model.row(id: "cast.plex.htpc")?.value == "Running")
        #expect(!model.actionRowIDs.contains("cast.plex.htpc"))
    }

    // MARK: Android (step 8)

    @Test func androidRowsFollowReflector() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.casting))
        #expect(model.row(id: "cast.android.reflector")?.value == "Not Installed")
        #expect(model.row(id: "cast.android.reflector")?.detail == "Install Reflector 4 from airsquirrels.com")
        #expect(model.row(id: "cast.android.reflector")?.action == nil)
        #expect(model.row(id: "cast.android.autostart") == nil)

        let cases: [(CastingSettingsStatus.Reflector, String)] = [
            (.notRunning, "Not Running"), (.ready, "Ready"), (.mirroring, "Mirroring"),
        ]
        for (state, value) in cases {
            recorder.casting.reflector = state
            model.refreshStatus()
            #expect(model.row(id: "cast.android.reflector")?.value == value)
            #expect(model.row(id: "cast.android.reflector")?.detail == nil)
            #expect(model.row(id: "cast.android.autostart")?.value == "On")
        }
    }

    @Test func autostartToggleApplies() {
        let (model, recorder) = makeSettingsModel()
        recorder.casting.reflector = .ready
        model.refreshStatus()
        model.perform(.push(.casting))
        #expect(model.row(id: "cast.android.autostart")?.action == .toggle(.reflectorAutoStart))
        model.perform(.toggle(.reflectorAutoStart))
        #expect(recorder.appliedSettings.last?.reflectorAutoStart == false)
        #expect(model.row(id: "cast.android.autostart")?.value == "Off")
    }
}
