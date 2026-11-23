import Carbon.HIToolbox
import Testing
@testable import MMTVL

/// M7h step 11: Remote & Input → Siri Remote, and the Remote Buttons items from step 3.
struct SettingsSiriRemoteTests {
    /// Step 13c: Receiver & TV moved to Audio & TV, so Remote Buttons follows the Siri Remote.
    @Test func remoteInputListsSiriRemoteAfterGameControllers() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteInput)
        let ids = model.actionRowIDs
        #expect(ids == ["globalInput", "controllers", "siriRemote", "remoteButtons", "channelUp", "cursorAutoHide",
                        "phoneRemote"])
        #expect(model.row(id: "siriRemote")?.action == .push(.siriRemote))
        #expect(model.row(id: "siriRemote")?.showsDisclosure == true)
        #expect(model.row(id: "receiver") == nil)
        #expect(!model.sections.flatMap(\.rows).contains { $0.action == .push(.receiver) })
    }

    @Test func siriRemoteValueForEachState() {
        let (model, recorder) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.row(id: "siriRemote")?.value == "Not Connected")
        recorder.siriRemote = SiriRemoteSettingsStatus(isConnected: true, batteryLevel: 78, isTouchAvailable: true)
        model.refreshStatus()
        #expect(model.row(id: "siriRemote")?.value == "Connected · 78 %")
        recorder.siriRemote.batteryLevel = nil
        model.refreshStatus()
        #expect(model.row(id: "siriRemote")?.value == "Connected")

        var off = AppSettings()
        off.siriRemoteEnabled = false
        let (offModel, offRecorder) = makeSettingsModel(settings: off)
        offRecorder.siriRemote.isConnected = true
        offModel.refreshStatus()
        offModel.open(.remoteInput)
        #expect(offModel.row(id: "siriRemote")?.value == "Off")
    }

    @Test func pageRowsWithoutARemote() {
        let (model, recorder) = makeSettingsModel()
        recorder.siriRemote.isTouchAvailable = true
        model.refreshStatus()
        model.open(.siriRemote)
        #expect(model.pageTitle == "Siri Remote")
        #expect(model.row(id: "siri.enabled")?.value == "On")
        #expect(model.row(id: "siri.enabled")?.action == .toggle(.siriRemoteEnabled))
        #expect(model.row(id: "siri.enabled")?.description
            == "Read the Siri Remote directly. Double-press Siri for trackpad mode.")
        #expect(model.row(id: "siri.status")?.value == "Not Connected")
        #expect(model.row(id: "siri.status")?.detail == nil)
        let footer = model.sections.first?.footer ?? ""
        #expect(footer.hasPrefix("How it works: TV goes Home."))
        #expect(footer.contains("Double-press Siri for trackpad mode"))
        #expect(footer.contains("holding Power opens the power menu, even if those buttons are changed"))
    }

    @Test func pageRowsWhenConnected() {
        let (model, recorder) = makeSettingsModel()
        recorder.siriRemote = SiriRemoteSettingsStatus(isConnected: true, batteryLevel: 78, isTouchAvailable: true)
        model.refreshStatus()
        model.open(.siriRemote)
        #expect(model.row(id: "siri.status")?.value == "Connected · 78 %")
        #expect(model.row(id: "siri.status")?.detail == "Touch available")
        recorder.siriRemote.isTouchAvailable = false
        model.refreshStatus()
        #expect(model.row(id: "siri.status")?.detail == "Touch not available")
    }

    @Test func turningItOffSavesAndHidesStatus() {
        let (model, recorder) = makeSettingsModel()
        model.open(.siriRemote)
        model.activate(rowID: "siri.enabled")
        #expect(recorder.appliedSettings.last?.siriRemoteEnabled == false)
        #expect(model.row(id: "siri.enabled")?.value == "Off")
        #expect(model.row(id: "siri.status") == nil)
    }

    /// Step 13e: Swipes, off by default, saved at once; "How it works" mentions it.
    @Test func swipesRowIsOffByDefaultAndToggles() {
        let (model, recorder) = makeSettingsModel()
        model.open(.siriRemote)
        #expect(model.actionRowIDs.prefix(2) == ["siri.enabled", "siri.swipes"])
        let row = model.row(id: "siri.swipes")
        #expect(row?.title == "Swipes")
        #expect(row?.value == "Off")
        #expect(row?.action == .toggle(.siriRemoteSwipes))
        #expect(row?.description == "Swipe on the remote's touch surface to move around, like an Apple TV. "
            + "Off: only the clickpad's clicks move.")
        let footer = model.sections.first?.footer ?? ""
        #expect(footer.contains("Press the clickpad's edges to move (or swipe, with Swipes on)"))
        model.activate(rowID: "siri.swipes")
        #expect(recorder.appliedSettings.last?.siriRemoteSwipes == true)
        #expect(model.row(id: "siri.swipes")?.value == "On")
        // Not offered while the remote isn't used.
        model.activate(rowID: "siri.enabled")
        #expect(model.row(id: "siri.swipes") == nil)
    }

    /// Step 13e (build 25's Live TV skip): a receiver, CEC or Siri Remote change re-reads only its own status, never
    /// the PIN (Keychain) or the login item.
    @Test func partRefreshReadsOnlyThatStatus() {
        let (model, recorder) = makeSettingsModel()
        model.open(.siriRemote)
        let pinReads = recorder.pinReads
        let loginReads = recorder.loginItemReads
        recorder.receiver.isConnected = true
        recorder.cec = .ready
        recorder.siriRemote.isConnected = true
        recorder.hasPIN = true

        model.refreshStatus(.receiver)
        #expect(model.receiver.isConnected)
        #expect(model.cec == nil)
        #expect(!model.siriRemote.isConnected)

        model.refreshStatus(.cec)
        #expect(model.cec == .ready)
        #expect(!model.siriRemote.isConnected)

        model.refreshStatus(.siriRemote)
        #expect(model.siriRemote.isConnected)

        #expect(!model.hasPIN)
        #expect(recorder.pinReads == pinReads)
        #expect(recorder.loginItemReads == loginReads)
        // The full refresh still reads everything.
        model.refreshStatus()
        #expect(model.hasPIN)
        #expect(recorder.pinReads == pinReads + 1)
        #expect(recorder.loginItemReads == loginReads + 1)
    }

    /// Step 13e (QA minor): off screen, no status change (receiver, CEC, Siri Remote, phone remote, Live TV, Plex,
    /// casting, becoming active) reads anything, so never the PIN (Keychain) or the login item (SMAppService). While
    /// Settings shows, each part reads its own status, still without the PIN or the login item.
    @Test func offScreenRefreshesReadNothing() {
        let (model, recorder) = makeSettingsModel()
        var showing = false
        model.isShowing = { showing }
        let pinReads = recorder.pinReads
        let loginReads = recorder.loginItemReads
        recorder.hasPIN = true
        recorder.receiver.isConnected = true
        recorder.phoneRemote.isRunning = true
        recorder.iptv.hasPlaylist = true
        recorder.plex.isSignedIn = true
        recorder.casting.plexHTPC = .running
        let parts: [SettingsModel.StatusParts] = [.receiver, .cec, .siriRemote, .phoneRemote, .iptv, .plex, .casting]
        for part in parts { model.refreshStatus(part) }
        model.refreshStatusIfShowing()
        #expect(recorder.pinReads == pinReads)
        #expect(recorder.loginItemReads == loginReads)
        #expect(!model.hasPIN)
        #expect(!model.receiver.isConnected)
        #expect(!model.phoneRemote.isRunning)
        #expect(!model.iptv.hasPlaylist)
        #expect(!model.plex.isSignedIn)
        #expect(model.casting.plexHTPC != .running)

        showing = true
        model.refreshStatus([.receiver, .phoneRemote, .iptv, .plex, .casting])
        #expect(model.receiver.isConnected)
        #expect(model.phoneRemote.isRunning)
        #expect(model.iptv.hasPlaylist)
        #expect(model.plex.isSignedIn)
        #expect(model.casting.plexHTPC == .running)
        #expect(recorder.pinReads == pinReads)
        #expect(recorder.loginItemReads == loginReads)
        model.refreshStatusIfShowing()
        #expect(model.hasPIN)
        #expect(recorder.pinReads == pinReads + 1)
        #expect(recorder.loginItemReads == loginReads + 1)
    }

    #if DEBUG
    /// Step 6: Debug builds show the toast from the Status row.
    @Test func statusShowsTheToastInDebugBuilds() {
        let (model, recorder) = makeSettingsModel()
        model.open(.siriRemote)
        #expect(model.row(id: "siri.status")?.action == .showToastDemo)
        model.activate(rowID: "siri.status")
        #expect(recorder.toasts == ["Trackpad On"])
    }
    #endif

    // MARK: Remote Buttons (step 3 (a)–(c))

    private static let letterA = InputBinding.Trigger.key(keyCode: UInt16(kVK_ANSI_A), modifiers: [])

    /// (a) L9: a plain letter can't work in other apps, and the row says why instead of a dead toggle.
    @Test func letterHomeButtonSaysWhyItStaysInMMTVL() {
        let bindings = KeyBindings.defaults.adding(Self.letterA, for: .home)
        let (model, recorder) = makeSettingsModel(bindings: bindings)
        model.open(.remoteButtons)
        model.perform(.push(.remoteBinding(.home, Self.letterA)))
        let row = model.row(id: "binding.global")
        #expect(row?.value == "Off")
        #expect(row?.detail == "Letter and number keys only work in MMTVL")
        #expect(row?.action == nil)
        #expect(!model.actionRowIDs.contains("binding.global"))
        #expect(recorder.appliedBindings.isEmpty)
    }

    /// (b) L2: Siri Remote buttons always work in other apps: no row.
    @Test func siriRemoteHomeButtonHasNoWorksInOtherAppsRow() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteButtons)
        model.perform(.push(.remoteBinding(.home, .siriRemote(button: .tv))))
        #expect(model.row(id: "binding.global") == nil)
        // A keyboard Home still has its toggle.
        model.perform(.pop)
        model.perform(.push(.remoteBinding(.home, .key(keyCode: UInt16(kVK_Home), modifiers: []))))
        #expect(model.row(id: "binding.global")?.action == .toggleBindingGlobal(.key(keyCode: UInt16(kVK_Home), modifiers: [])))
    }

    /// (c) The new commands have rows; M7h U2 (2026-11-06): Power Menu has one again (no buttons by default), and
    /// the footer says the long press opens it too.
    @Test func remoteButtonsListsThePowerCommands() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteButtons)
        #expect(model.row(id: "command.powerMenu")?.value == "None")
        for command in [RemoteCommand.volumeUp, .volumeDown, .mute, .power, .powerMenu] {
            #expect(model.row(id: "command.\(command.rawValue)") != nil, "\(command)")
        }
        #expect(model.row(id: "command.power")?.value == "Siri Remote Power")
        #expect(model.sections.first?.footer?.contains("Holding the Siri Remote's Power button also opens the power menu") == true)
    }
}
