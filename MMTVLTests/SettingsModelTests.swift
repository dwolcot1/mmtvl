import Foundation
import Testing
@testable import MMTVL

struct SettingsModelTests {
    // MARK: Root page

    @Test func initialFocusIsFirstRow() {
        let (model, _) = makeSettingsModel()
        #expect(model.page == .root)
        #expect(model.focusedRowID == "homeScreen")
    }

    /// M7g L6: the root lists the categories, each opening its page.
    @Test func rootListsCategories() {
        let (model, _) = makeSettingsModel()
        let expected: [(String, SettingsPage)] = [
            ("homeScreen", .homeScreen), ("liveTV", .liveTV), ("plex", .plex), ("youtube", .youtube),
            ("casting", .casting), ("audioTV", .audioTV), ("remoteInput", .remoteInput), ("restrictions", .restrictions),
            ("system", .system), ("about", .about), ("licenses", .licenses),   // MR step 4
        ]
        #expect(model.actionRowIDs == expected.map(\.0))
        for (id, page) in expected {
            #expect(model.row(id: id)?.action == .push(page))
        }
    }

    @Test func upDownMovesAndClamps() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteInput)
        model.press(.up)
        #expect(model.focusedRowID == "globalInput")
        model.press(.down, .down, .down, .down, .down, .down)   // M7h: + Siri Remote (Receiver & TV moved to Audio & TV)
        #expect(model.focusedRowID == "phoneRemote")
        model.press(.down)
        #expect(model.focusedRowID == "phoneRemote")
    }

    @Test func togglingAppliesSettings() {
        let (model, recorder) = makeSettingsModel()
        model.open(.remoteInput)
        model.press(.down, .select)
        #expect(recorder.appliedSettings.count == 1)
        #expect(recorder.appliedSettings.first?.controllersEnabled == false)
        #expect(!model.settings.controllersEnabled)
        #expect(model.row(id: "controllers")?.value == "Off")
    }

    @Test func accessibilityRowRequestsAccess() {
        let (model, recorder) = makeSettingsModel(trusted: false)
        model.open(.system)
        #expect(model.row(id: "accessibility")?.value == "Not Allowed")
        model.press(.select)
        #expect(recorder.accessibilityRequests == 1)
    }

    @Test func approveLoginItemRowOnlyWhenWaitingForApproval() {
        let (plain, _) = makeSettingsModel(loginStatus: .requiresApproval)
        plain.open(.system)
        #expect(plain.row(id: "approveLoginItem") == nil)

        var settings = AppSettings()
        settings.launchAtLogin = true
        let (waiting, recorder) = makeSettingsModel(loginStatus: .requiresApproval, settings: settings)
        waiting.open(.system)
        #expect(waiting.row(id: "approveLoginItem") != nil)
        waiting.activate(rowID: "approveLoginItem")
        #expect(recorder.loginItemsOpened == 1)

        let (windowed, _) = makeSettingsModel(kiosk: false, loginStatus: .requiresApproval, settings: settings)
        windowed.open(.system)
        #expect(windowed.row(id: "approveLoginItem") == nil)
    }

    @Test func windowedModeMarksKioskOnlyRows() {
        let (model, _) = makeSettingsModel(kiosk: false)
        model.open(.system)
        #expect(model.row(id: "launchAtLogin")?.detail == "Applies in kiosk mode only")
        model.perform(.pop)
        model.open(.remoteInput)
        #expect(model.row(id: "globalInput")?.detail == "Applies in kiosk mode only")
    }

    @Test func globalInputNeedsAccessibilityDetail() {
        let (model, _) = makeSettingsModel(trusted: false)
        model.open(.remoteInput)
        #expect(model.row(id: "globalInput")?.detail == "Needs Accessibility access")
    }

    @Test func pushAndPopRestoresFocus() {
        let (model, _) = makeSettingsModel()
        model.focus(rowID: "homeScreen")
        let pushed = model.handle(.select)
        #expect(pushed)
        #expect(model.page == .homeScreen)
        let popped = model.handle(.back)
        #expect(popped)
        #expect(model.page == .root)
        #expect(model.focusedRowID == "homeScreen")
        let leftRoot = model.handle(.back)
        #expect(!leftRoot)
    }

    @Test func refreshStatusRereadsAccessibility() {
        let (model, recorder) = makeSettingsModel(trusted: false)
        model.open(.system)
        recorder.trusted = true
        model.refreshStatus()
        #expect(model.row(id: "accessibility")?.value == "Allowed")
    }

    @Test func homeIsNotHandled() {
        let (model, _) = makeSettingsModel()
        let handled = model.handle(.home)
        #expect(!handled)
    }

    /// M7g review fixes: no detail or footer repeats its row's description.
    @Test func copyDoesntRepeatDescriptions() {
        let (model, recorder) = makeSettingsModel()
        model.open(.liveTV)
        recorder.iptv = IPTVSettingsStatus(hasPlaylist: true, playlistHost: "example.com", channelCount: 5)
        model.refreshStatus()
        #expect(model.row(id: "iptv.teams") != nil)
        #expect(model.row(id: "iptv.teams")?.detail == nil)

        model.reset()
        model.open(.homeScreen)
        model.perform(.push(.tile(id: "youtube")))
        #expect(model.row(id: "tile.remove")?.detail == nil)
        #expect(model.row(id: "tile.remove")?.description == "Removes the tile. Built-in tiles can be added back from Add Tile.")

        model.reset()
        model.open(.plex)
        #expect(model.row(id: "plex.signIn") != nil)
        #expect(model.sections.allSatisfy { $0.footer == nil })

        model.reset()
        model.open(.restrictions)
        let kioskLock = model.row(id: "kioskLock")?.description
        #expect(kioskLock == "⌘Tab, Force Quit and other apps can't take over the TV, and ⌘Q asks for the PIN when one is set. Exit to Desktop is the way out.")

        // M15 step 8: Software Update and Automatic Updates.
        for page in [SettingsPage.softwareUpdate, .automaticUpdates] {
            model.reset()
            model.open(page)
            for row in model.sections.flatMap(\.rows) where row.description != nil {
                #expect(row.detail != row.description)
            }
            #expect(model.sections.allSatisfy { section in
                section.footer == nil || !section.rows.contains { $0.description == section.footer }
            })
        }
    }

    @Test func systemActions() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        model.activate(rowID: "relaunch")
        model.activate(rowID: "exit")
        #expect(recorder.relaunches == 1)
        #expect(recorder.exits == 1)
    }

    /// M15 step 1: Restart Mac mini sits between Relaunch and Exit to Desktop, and opens its confirm page.
    @Test func systemHasRestartRow() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        let ids = model.sections.first { $0.id == "mmtvl" }?.rows.map(\.id)
        #expect(ids == ["relaunch", "restartMac", "exit"])
        let row = model.row(id: "restartMac")
        #expect(row?.title == "Restart Mac mini")
        #expect(row?.showsDisclosure == true)
        #expect(row?.action == .push(.confirmRestartMac))
        #expect(row?.description == "Restarts the Mac mini. Asks first.")
        model.activate(rowID: "restartMac")
        #expect(model.page == .confirmRestartMac)
        #expect(model.title(for: .confirmRestartMac) == "Restart Mac mini?")
        #expect(model.actionRowIDs == ["confirm.cancel", "confirm.restartMac"])
        #expect(model.focusedRowID == "confirm.cancel")
        #expect(model.row(id: "confirm.restartMac")?.title == "Restart Mac mini")
        #expect(model.sections.first?.footer == "Other apps are asked to quit first. With Launch at Login on, MMTVL opens again after the restart.")
        #expect(recorder.restarts == 0)
    }

    @Test func restartConfirmCancelPops() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        model.activate(rowID: "restartMac")
        model.press(.select)
        #expect(model.page == .system)
        #expect(model.focusedRowID == "restartMac")
        #expect(recorder.restarts == 0)
    }

    @Test func restartConfirmRestarts() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        model.activate(rowID: "restartMac")
        model.press(.down, .select)
        #expect(recorder.restarts == 1)
        #expect(model.page == .system)
        #expect(model.focusedRowID == "restartMac")
    }

    // MARK: Software Update (M15 step 8)

    private static let update = AvailableUpdate(version: "1.5.0", build: "60")

    /// A model on Settings → System → Software Update with this status.
    private func onSoftwareUpdate(_ status: UpdateStatus, settings: AppSettings = AppSettings())
        -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(settings: settings)
        recorder.updateStatus = status
        model.refreshStatus()
        model.open(.system)
        model.activate(rowID: "softwareUpdate")
        return (model, recorder)
    }

    /// *Design*: the System row's value follows the status, in a Software section above MMTVL's.
    @Test func softwareUpdateRowOnSystem() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        #expect(model.sections.map(\.id) == ["permissions", "startup", "appearance", "software", "mmtvl"])
        let row = model.row(id: "softwareUpdate")
        #expect(row?.title == "Software Update")
        #expect(row?.showsDisclosure == true)
        #expect(row?.action == .push(.softwareUpdate))
        #expect(row?.description == "Checks GitHub for new versions of MMTVL and installs them.")
        let cases: [(UpdateStatus, String?)] = [
            (.upToDate(lastChecked: Date()), "Up to Date"),
            (.available(Self.update), "1.5.0 Available"),
            (.downloading(Self.update, fraction: 0.3), "Downloading"),
            (.ready(Self.update), "Ready to Install"),
            (.off(.developmentBuild), "Off"),
            (.off(.windowed), "Off"),
        ]
        for (status, value) in cases {
            recorder.updateStatus = status
            model.refreshStatus(.updates)
            #expect(model.row(id: "softwareUpdate")?.value == value)
        }
    }

    /// The user's values for the states *Design* left out (2026-11-23).
    @Test func softwareUpdateRowCheckingFailedIdle() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        let cases: [(UpdateStatus, String?)] = [
            (.checking, "Checking…"),
            (.failed(.checkFailed), "Couldn't Check"),
            (.failed(.installFailed), "Couldn't Install"),
            (.idle(lastChecked: nil), nil),
            (.idle(lastChecked: Date()), nil),
        ]
        for (status, value) in cases {
            recorder.updateStatus = status
            model.refreshStatus(.updates)
            #expect(model.row(id: "softwareUpdate")?.value == value)
        }
    }

    /// The root's System description names software updates.
    @Test func systemDescriptionNamesSoftwareUpdates() {
        let (model, _) = makeSettingsModel()
        #expect(model.row(id: "system")?.description == "Accessibility access, starting at login, glass, software updates, relaunching MMTVL, restarting the Mac and leaving to the desktop.")
    }

    @Test func softwareUpdatePageUpToDate() {
        let checked = Date(timeIntervalSinceReferenceDate: 100_000)
        let (model, recorder) = makeSettingsModel()
        model.now = { checked + 2 * 3600 }
        recorder.updateStatus = .upToDate(lastChecked: checked)
        recorder.lastUpdateCheck = checked
        model.refreshStatus()
        model.open(.system)
        model.activate(rowID: "softwareUpdate")
        #expect(model.page == .softwareUpdate)
        #expect(model.title(for: .softwareUpdate) == "Software Update")
        #expect(model.sections.map(\.id) == ["update", "automatic"])
        #expect(model.sections[0].title == nil)
        #expect(model.sections[0].rows.map(\.id) == ["update.installed", "update.status", "update.checkNow"])
        let installed = model.row(id: "update.installed")
        #expect(installed?.title == "Installed")
        #expect(installed?.value == "1.1.0 Build 7")
        #expect(installed?.action == nil)
        let status = model.row(id: "update.status")
        #expect(status?.title == "Up to Date")
        #expect(status?.detail == "Checked 2 hours ago")
        #expect(status?.action == nil)
        #expect(model.row(id: "update.checkNow")?.title == "Check Now")
        #expect(model.row(id: "update.checkNow")?.action == .checkForUpdates)
        #expect(model.focusedRowID == "update.checkNow")

        #expect(model.sections[1].title == "Automatic")
        #expect(model.sections[1].rows.map(\.id) == ["update.checks", "update.mode"])
        let checks = model.row(id: "update.checks")
        #expect(checks?.title == "Check for Updates")
        #expect(checks?.value == "On")
        #expect(checks?.action == .toggle(.updateChecks))
        #expect(checks?.description == "Checks github.com once a day and shows a notice on the home screen when there's a new version. Check Now works either way.")
        let mode = model.row(id: "update.mode")
        #expect(mode?.title == "Automatic Updates")
        #expect(mode?.value == "Off")
        #expect(mode?.action == .push(.automaticUpdates))
        #expect(mode?.isDimmed == false)
        #expect(mode?.detail == nil)
        #expect(model.sections.last?.footer == "Updates come from github.com/dwolcot1/mmtvl. Each one is checked for MMTVL's signatures before it's installed.")

        // The last check, relative to the clock.
        model.now = { checked + 5 * 60 }
        #expect(model.row(id: "update.status")?.detail == "Checked 5 minutes ago")
    }

    @Test func softwareUpdatePageAvailableOffersInstall() {
        let (model, _) = onSoftwareUpdate(.available(Self.update))
        #expect(model.sections[0].rows.map(\.id) == ["update.installed", "update.status", "update.install", "update.checkNow"])
        let install = model.row(id: "update.install")
        #expect(install?.title == "Install MMTVL 1.5.0")
        #expect(install?.detail == "MMTVL quits and opens again in about half a minute.")
        #expect(install?.action == .installUpdate)
        #expect(model.focusedRowID == "update.install")
    }

    @Test func softwareUpdatePageDownloadingShowsPercent() {
        let (model, recorder) = onSoftwareUpdate(.downloading(Self.update, fraction: 0.45))
        #expect(model.sections[0].rows.map(\.id) == ["update.installed", "update.status", "update.install"])
        let install = model.row(id: "update.install")
        #expect(install?.title == "Install MMTVL 1.5.0")
        #expect(install?.value == "45 %")
        #expect(install?.action == nil)
        // An automatic download Sparkle doesn't report progress for.
        recorder.updateStatus = .downloading(Self.update, fraction: nil)
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.install")?.value == "Downloading…")
        recorder.updateStatus = .installing(Self.update)
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.install")?.value == "Installing…")
        #expect(model.row(id: "update.install")?.action == nil)
        #expect(model.row(id: "update.checkNow") == nil)
    }

    @Test func softwareUpdatePageReadyInstallNow() {
        var settings = AppSettings()
        settings.automaticUpdates = .whenIdle
        let (model, recorder) = onSoftwareUpdate(.ready(Self.update), settings: settings)
        #expect(model.sections[0].rows.map(\.id) == ["update.installed", "update.status", "update.install"])
        let install = model.row(id: "update.install")
        #expect(install?.title == "Install MMTVL 1.5.0 Now")
        #expect(install?.detail == "Downloaded. Installs on its own When Idle, or the next time MMTVL quits.")
        #expect(install?.action == .installUpdate)
        model.activate(rowID: "update.mode")
        model.activate(rowID: "automatic.atNight")
        #expect(model.row(id: "update.install")?.detail == "Downloaded. Installs on its own At Night, or the next time MMTVL quits.")
        #expect(recorder.updateInstalls == 0)
    }

    /// QA minor: staged, then Automatic Updates switched to Off.
    @Test func softwareUpdatePageReadyWithModeOff() {
        let (model, _) = onSoftwareUpdate(.ready(Self.update))
        #expect(model.settings.automaticUpdates == .off)
        let install = model.row(id: "update.install")
        #expect(install?.title == "Install MMTVL 1.5.0 Now")
        #expect(install?.detail == "Downloaded. Installs the next time MMTVL quits.")
        #expect(install?.action == .installUpdate)
    }

    @Test func softwareUpdatePageOff() {
        let (model, recorder) = onSoftwareUpdate(.off(.developmentBuild))
        #expect(model.sections[0].rows.map(\.id) == ["update.installed", "update.status"])
        #expect(model.row(id: "update.status")?.title == "Updates Are Off")
        #expect(model.row(id: "update.status")?.detail == "Development builds don't update.")
        recorder.updateStatus = .off(.windowed)
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.status")?.detail == "MMTVL is in a window.")
        #expect(model.row(id: "update.checkNow") == nil)
    }

    /// Checking dims Check Now; a failed check says why and offers it again.
    @Test func softwareUpdatePageCheckingAndFailed() {
        let (model, recorder) = onSoftwareUpdate(.checking)
        #expect(model.row(id: "update.status")?.title == "Checking…")
        #expect(model.row(id: "update.checkNow")?.isDimmed == true)
        #expect(model.row(id: "update.checkNow")?.action == nil)
        recorder.updateStatus = .failed(.checkFailed)
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.status")?.title == "Couldn't Check")
        #expect(model.row(id: "update.status")?.detail == "Check your network connection and try again.")
        #expect(model.row(id: "update.checkNow")?.action == .checkForUpdates)
        recorder.updateStatus = .idle(lastChecked: nil)
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.status")?.title == "Not Checked Yet")
    }

    /// N1: a test feed shows its host right after Installed; the real feed shows nothing.
    @Test func softwareUpdatePageShowsTestFeed() {
        let (model, recorder) = onSoftwareUpdate(.upToDate(lastChecked: Date()))
        #expect(model.row(id: "update.testFeed") == nil)
        recorder.updateTestFeedHost = "feed.example"
        model.refreshStatus(.updates)
        #expect(model.sections[0].rows.map(\.id).prefix(2) == ["update.installed", "update.testFeed"])
        let row = model.row(id: "update.testFeed")
        #expect(row?.title == "Test Feed")
        #expect(row?.value == "feed.example")
        #expect(row?.action == nil)
        recorder.updateTestFeedHost = nil
        model.refreshStatus(.updates)
        #expect(model.row(id: "update.testFeed") == nil)
    }

    @Test func checkNowCallsEnvironment() {
        let (model, recorder) = onSoftwareUpdate(.upToDate(lastChecked: Date()))
        let checkNow = model.row(id: "update.checkNow")
        #expect(checkNow?.description == "Asks GitHub now whether there's a newer MMTVL.")
        #expect(checkNow?.isDimmed == false)
        #expect(model.row(id: "update.status")?.title == "Up to Date")
        model.activate(rowID: "update.checkNow")
        #expect(recorder.updateChecks == 1)
        #expect(model.page == .softwareUpdate)
        // The page re-read the status the press changed.
        #expect(model.row(id: "update.status")?.title == "Checking…")
        #expect(model.row(id: "update.checkNow")?.isDimmed == true)
        #expect(model.row(id: "update.checkNow")?.action == nil)
        #expect(model.row(id: "update.checkNow")?.description == "Asks GitHub now whether there's a newer MMTVL.")
    }

    @Test func installCallsEnvironment() {
        let (model, recorder) = onSoftwareUpdate(.available(Self.update))
        model.activate(rowID: "update.install")
        #expect(recorder.updateInstalls == 1)
        #expect(model.page == .softwareUpdate)
    }

    @Test func checksToggleSavesUpdateChecks() {
        let (model, recorder) = onSoftwareUpdate(.idle(lastChecked: nil))
        model.activate(rowID: "update.checks")
        #expect(recorder.appliedSettings.last?.updateChecks == false)
        #expect(!model.settings.updateChecks)
        #expect(model.row(id: "update.checks")?.value == "Off")
        model.activate(rowID: "update.checks")
        #expect(recorder.appliedSettings.last?.updateChecks == true)
        #expect(recorder.appliedSettings.count == 2)
    }

    @Test func automaticUpdatesChoiceSetsAndPops() {
        let (model, recorder) = onSoftwareUpdate(.idle(lastChecked: nil))
        model.activate(rowID: "update.mode")
        #expect(model.page == .automaticUpdates)
        #expect(model.title(for: .automaticUpdates) == "Automatic Updates")
        #expect(model.actionRowIDs == ["automatic.off", "automatic.whenIdle", "automatic.atNight"])
        #expect(model.row(id: "automatic.off")?.value == "Selected")
        #expect(model.row(id: "automatic.whenIdle")?.value == nil)
        #expect(model.row(id: "automatic.off")?.description == "Shows a notice when there's an update. You install it here.")
        #expect(model.row(id: "automatic.whenIdle")?.description == "Downloads updates and installs them when Power has turned the TV off, or while the screen saver is on.")
        #expect(model.row(id: "automatic.atNight")?.description == "Downloads updates and installs them at about 4 a.m. when nothing is playing.")
        #expect(model.sections.first?.footer == "MMTVL relaunches to install an update.")

        model.activate(rowID: "automatic.whenIdle")
        #expect(recorder.appliedSettings.count == 1)
        #expect(recorder.appliedSettings.last?.automaticUpdates == .whenIdle)
        #expect(model.settings.automaticUpdates == .whenIdle)
        #expect(model.page == .softwareUpdate)
        #expect(model.focusedRowID == "update.mode")
        #expect(model.row(id: "update.mode")?.value == "When Idle")

        // The same choice again saves nothing.
        model.activate(rowID: "update.mode")
        model.activate(rowID: "automatic.whenIdle")
        #expect(recorder.appliedSettings.count == 1)
        #expect(model.page == .softwareUpdate)
    }

    @Test func automaticUpdatesDimmedWhenChecksOff() {
        var settings = AppSettings()
        settings.updateChecks = false
        let (model, _) = onSoftwareUpdate(.idle(lastChecked: nil), settings: settings)
        let mode = model.row(id: "update.mode")
        #expect(mode?.isDimmed == true)
        #expect(mode?.detail == "Needs Check for Updates")
        #expect(mode?.action == nil)
        #expect(mode?.showsDisclosure == false)
        model.activate(rowID: "update.mode")
        #expect(model.page == .softwareUpdate)
        model.activate(rowID: "update.checks")
        #expect(model.row(id: "update.mode")?.isDimmed == false)
        #expect(model.row(id: "update.mode")?.action == .push(.automaticUpdates))
    }

    /// The status follows the updater only while Settings shows (`refreshStatus(_:)`'s guard).
    @Test func updateStatusRefreshOnlyWhileShowing() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        model.isShowing = { false }
        recorder.updateStatus = .available(Self.update)
        model.refreshStatus(.updates)
        #expect(model.row(id: "softwareUpdate")?.value == nil)
        model.isShowing = { true }
        model.refreshStatus(.updates)
        #expect(model.row(id: "softwareUpdate")?.value == "1.5.0 Available")
    }

    /// M7l step 2 (L3): System → Glass shows the step, its page lists the five, and a choice saves at once.
    @Test func glassRowChoosesTheGlassStyle() {
        let (model, recorder) = makeSettingsModel()
        model.open(.system)
        let row = model.row(id: "glass")
        #expect(row?.value == "Clear")
        #expect(row?.action == .push(.glassStyle))
        #expect(row?.description == "How see-through MMTVL's glass panels are.")
        model.activate(rowID: "glass")
        #expect(model.page == .glassStyle)
        #expect(model.title(for: .glassStyle) == "Glass")
        #expect(model.actionRowIDs == GlassStyle.allCases.map { "glass.\($0.rawValue)" })
        #expect(model.row(id: "glass.frosted")?.title == "Frosted")
        #expect(model.row(id: "glass.clear")?.value == "Selected")
        #expect(model.row(id: "glass.frosted")?.value == nil)
        #expect(model.sections.first?.footer == "Changes every glass panel in MMTVL. Reduce Transparency in macOS's Accessibility settings always uses Solid.")

        model.activate(rowID: "glass.frosted")
        #expect(recorder.appliedSettings.count == 1)
        #expect(recorder.appliedSettings.last?.glassStyle == .frosted)
        #expect(model.settings.glassStyle == .frosted)
        #expect(model.page == .system)
        #expect(model.row(id: "glass")?.value == "Frosted")

        // The same step again saves nothing.
        model.activate(rowID: "glass")
        model.activate(rowID: "glass.frosted")
        #expect(recorder.appliedSettings.count == 1)
    }
}

struct SettingsHomeScreenTests {
    private func modelOnHomeScreen(items: [LaunchItem] = LaunchItem.defaults) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: items)
        model.perform(.push(.homeScreen))
        return (model, recorder)
    }

    @Test func listsEveryTileIncludingHidden() {
        let items = LaunchItem.defaults.settingHidden(true, id: "iptv")
        let (model, _) = modelOnHomeScreen(items: items)
        let tileRows = model.sections.first { $0.id == "tiles" }!.rows
        #expect(tileRows.map(\.id) == items.map { "tile.\($0.id)" })
        let iptv = model.row(id: "tile.iptv")!
        #expect(iptv.value == "Hidden")
        #expect(iptv.isDimmed)
    }

    @Test func fullScreenRowOnlyForApps() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        #expect(model.row(id: "tile.fullScreen") != nil)
        model.perform(.pop)
        model.perform(.push(.tile(id: "youtube")))
        #expect(model.row(id: "tile.fullScreen") == nil)
    }

    @Test func toggleVisibleAppliesItems() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.visible")
        #expect(recorder.appliedItems.last?.first { $0.id == "youtube" }?.isVisible == false)
        #expect(model.row(id: "tile.visible")?.value == "Off")
    }

    @Test func toggleFullScreenAppliesItems() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "prime")))
        model.activate(rowID: "tile.fullScreen")
        #expect(recorder.appliedItems.last?.first { $0.id == "prime" }?.wantsFullScreen == false)
    }

    @Test func moveModeReordersAndEnds() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        model.activate(rowID: "tile.move")
        #expect(model.page == .homeScreen)
        #expect(model.movingTileID == "plex")
        #expect(model.focusedRowID == "tile.plex")
        #expect(model.row(id: "tile.plex")?.isLifted == true)

        model.press(.down)
        #expect(model.items.map(\.id).prefix(2) == ["youtube", "plex"])
        #expect(recorder.appliedItems.last?.map(\.id) == model.items.map(\.id))
        #expect(model.focusedRowID == "tile.plex")

        model.press(.select)
        #expect(model.movingTileID == nil)
    }

    @Test func backEndsMoveModeWithoutLeavingPage() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        model.perform(.startMove(id: "plex"))
        let handled = model.handle(.back)
        #expect(handled)
        #expect(model.movingTileID == nil)
        #expect(model.page == .homeScreen)
    }

    @Test func removeFocusesNeighbor() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.remove")
        #expect(model.page == .homeScreen)
        #expect(!model.items.contains { $0.id == "youtube" })
        #expect(model.focusedRowID == "tile.iptv")
    }

    @Test func restoreDefaultsConfirms() {
        let items = LaunchItem.defaults.removingItem(id: "plex")
        let (model, recorder) = modelOnHomeScreen(items: items)
        model.perform(.push(.confirmRestoreDefaults))
        #expect(model.focusedRowID == "confirm.cancel")
        model.activate(rowID: "confirm.restore")
        #expect(model.items == LaunchItem.defaults)
        #expect(recorder.appliedItems.last == LaunchItem.defaults)
        #expect(model.page == .homeScreen)
    }

    /// M7m L8: the home screen's move mode saves each step through Settings, without touching its pages.
    @Test func moveTileFromHomeSavesTheNewOrder() {
        let items = LaunchItem.defaults.settingHidden(true, id: "youtube")
        let (model, recorder) = makeSettingsModel(items: items)
        // Plex to the second visible place: after Live TV, Prime Video next; the hidden YouTube stays after Plex's old
        // place.
        model.moveTile(id: "plex", toVisibleIndex: 1)
        #expect(model.items.map(\.id) == ["youtube", "iptv", "plex", "prime", "browser", "settings", "exit"])
        #expect(recorder.appliedItems.last == model.items)
        #expect(model.page == .root)
        #expect(model.movingTileID == nil)
        // No change: nothing saved.
        model.moveTile(id: "plex", toVisibleIndex: 1)
        model.moveTile(id: "youtube", toVisibleIndex: 0)
        #expect(recorder.appliedItems.count == 1)
        // Settings' Home Screen page lists the new order.
        model.perform(.push(.homeScreen))
        let tileRows = model.sections.first { $0.id == "tiles" }!.rows
        #expect(tileRows.map(\.id) == model.items.map { "tile.\($0.id)" })
    }

    @Test func settingsTileCanOnlyMove() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "settings")))
        // Start Here (M7c L32), Tile Art (M7 L25) and Move; never hide or remove.
        #expect(model.actionRowIDs == ["tile.start", "tile.art", "tile.move"])
        model.perform(.toggleTileVisible(id: "settings"))
        model.perform(.removeTile(id: "settings"))
        #expect(recorder.appliedItems.isEmpty)
        #expect(model.items == LaunchItem.defaults)
    }

    @Test func cancelRestorePops() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.confirmRestoreDefaults))
        model.press(.select)
        #expect(model.page == .homeScreen)
        #expect(recorder.appliedItems.isEmpty)
    }
}

struct SettingsAddTileTests {
    private let plex = InstalledApp(bundleID: "tv.plex.htpc", name: "Plex HTPC", url: URL(filePath: "/Applications/Plex HTPC.app"))
    private let new = InstalledApp(bundleID: "com.example.new", name: "New", url: URL(filePath: "/Applications/New.app"))

    private func modelOnAddTile(apps: [InstalledApp]) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: LaunchItem.defaults.removingItem(id: "youtube"))
        recorder.installedApps = apps
        model.perform(.push(.homeScreen))
        model.perform(.push(.addTile))
        return (model, recorder)
    }

    @Test func showsLoadingThenApps() async {
        let (model, _) = modelOnAddTile(apps: [plex, new])
        #expect(model.row(id: "apps.loading") != nil)
        await model.loadInstalledApps()
        #expect(model.row(id: "apps.loading") == nil)
        #expect(model.row(id: "add.app.tv.plex.htpc") == nil)
        #expect(model.row(id: "add.app.com.example.new") != nil)
        #expect(model.row(id: "add.default.youtube") != nil)
    }

    @Test func addingAppInsertsBeforeExit() async {
        let (model, recorder) = modelOnAddTile(apps: [new])
        await model.loadInstalledApps()
        model.activate(rowID: "add.app.com.example.new")
        let ids = model.items.map(\.id)
        #expect(ids.suffix(2) == ["app.com.example.new", "exit"])
        #expect(model.items.first { $0.id == "app.com.example.new" }?.kind == .application(bundleID: "com.example.new"))
        #expect(recorder.appliedItems.last == model.items)
        #expect(model.page == .homeScreen)
        #expect(model.focusedRowID == "tile.app.com.example.new")
    }

    @Test func addingDefaultTileInsertsBeforeExit() async {
        let (model, _) = modelOnAddTile(apps: [])
        await model.loadInstalledApps()
        model.activate(rowID: "add.default.youtube")
        #expect(model.items.map(\.id).suffix(2) == ["youtube", "exit"])
    }

    @Test func noAppsLeftShowsInfoRow() async {
        let (model, _) = modelOnAddTile(apps: [plex])
        await model.loadInstalledApps()
        #expect(model.row(id: "apps.none") != nil)
        #expect(!model.actionRowIDs.contains("apps.none"))
    }
}

struct SettingsPINTests {
    private func rowIDs(_ model: SettingsModel) -> [String] {
        model.sections.flatMap(\.rows).map(\.id)
    }

    @Test func rootOffersSetPINWithoutPIN() {
        let (model, recorder) = makeSettingsModel()
        model.open(.restrictions)
        #expect(rowIDs(model).contains("pin.set"))
        #expect(!rowIDs(model).contains("pin.change"))
        model.perform(model.row(id: "pin.set")!.action!)
        #expect(recorder.pinFlows == [.setNew])
    }

    @Test func rootOffersChangeAndTurnOffWithPIN() {
        let (model, recorder) = makeSettingsModel(hasPIN: true)
        model.open(.restrictions)
        #expect(!rowIDs(model).contains("pin.set"))
        model.perform(model.row(id: "pin.change")!.action!)
        model.perform(model.row(id: "pin.off")!.action!)
        #expect(recorder.pinFlows == [.change, .turnOff])
    }

    @Test func refreshStatusRereadsPIN() {
        let (model, recorder) = makeSettingsModel()
        model.open(.restrictions)
        recorder.hasPIN = true
        model.refreshStatus()
        #expect(model.hasPIN)
        #expect(rowIDs(model).contains("pin.change"))
    }

    @Test func requirePINRowOnlyForOrdinaryTiles() {
        let (model, _) = makeSettingsModel()
        model.perform(.push(.tile(id: "plex")))
        #expect(rowIDs(model).contains("tile.requiresPIN"))
        model.perform(.pop)
        model.perform(.push(.tile(id: "settings")))
        #expect(!rowIDs(model).contains("tile.requiresPIN"))
        model.perform(.pop)
        model.perform(.push(.tile(id: "exit")))
        #expect(!rowIDs(model).contains("tile.requiresPIN"))
        #expect(model.sections.first?.footer == "Exit to Desktop always asks for the PIN when one is set.")
    }

    @Test func toggleRequiresPINAppliesItems() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.tile(id: "plex")))
        model.perform(.toggleTileRequiresPIN(id: "plex"))
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.requiresPIN == true)
        model.perform(.toggleTileRequiresPIN(id: "plex"))
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.requiresPIN == nil)
        model.perform(.toggleTileRequiresPIN(id: "exit"))
        #expect(recorder.appliedItems.count == 2)
    }

    @Test func requirePINDetailDependsOnPIN() {
        let (without, _) = makeSettingsModel()
        without.perform(.push(.tile(id: "plex")))
        #expect(without.row(id: "tile.requiresPIN")?.detail == "Set a PIN in Settings first")
        let (with, _) = makeSettingsModel(hasPIN: true)
        with.perform(.push(.tile(id: "plex")))
        #expect(with.row(id: "tile.requiresPIN")?.detail == nil)
    }
}

struct SettingsYouTubeTests {
    @Test func rootHasYouTubeRows() {
        let (model, recorder) = makeSettingsModel()
        model.open(.youtube)
        #expect(model.row(id: "youtube.clear") != nil)
        model.perform(model.row(id: "youtube.reload")!.action!)
        #expect(recorder.youtubeReloads == 1)
    }

    @Test func clearConfirmFocusesCancelFirst() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.confirmClearYouTube))
        #expect(model.focusedRowID == "confirm.cancel")
        model.press(.select)
        #expect(model.page == .root)
        #expect(recorder.youtubeClears == 0)
    }

    @Test func clearConfirmClearsAndPops() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.confirmClearYouTube))
        model.press(.down, .select)
        #expect(recorder.youtubeClears == 1)
        #expect(model.page == .root)
    }
}

struct SettingsLiveTVTests {
    private static let status = IPTVSettingsStatus(
        hasPlaylist: true, playlistHost: "iptv.example", channelCount: 118, playlistLine: "Updated 10:42 PM",
        guideSources: [
            .init(id: "g1", label: "guide-source.online · guide-source_US2.xml.gz", line: "1,234 programmes · 50 channels · Updated 10:43 PM",
                  isFromPlaylist: false),
            .init(id: "g2", label: "guide-source.online · guide-source_FANDUEL1.xml.gz", line: "Loading…", isFromPlaylist: false),
        ],
        customGuideCount: 2, matchedChannelCount: 3)

    @Test func rootRowShowsSetupState() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "liveTV")?.value == "Not Set Up")
        recorder.iptv = Self.status
        model.refreshStatus()
        #expect(model.row(id: "liveTV")?.value == "118 Channels")
        model.perform(model.row(id: "liveTV")!.action!)
        #expect(model.page == .liveTV)
    }

    /// M7c L15.
    @Test func previewOnHomeTogglesTheSetting() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        let row = model.row(id: "iptv.homePreview")
        #expect(row?.value == "On")
        #expect(row?.detail == nil)
        #expect(row?.description == "Loads the channel, muted, while the Home screen shows; you see it when Live TV is focused.")
        model.activate(rowID: "iptv.homePreview")
        #expect(recorder.appliedSettings.last?.homeLivePreview == false)
        #expect(model.row(id: "iptv.homePreview")?.value == "Off")
    }

    /// M7c L28.
    @Test func aboutShowsTheVersionAndBuild() {
        let (model, recorder) = makeSettingsModel()
        model.open(.about)
        #expect(model.row(id: "about.version")?.value == "1.1.0")
        #expect(model.row(id: "about.build")?.value == "7")
        #expect(model.row(id: "about.version")?.action == nil)
        #expect(model.row(id: "about.showOnHome")?.value == "On")
        model.activate(rowID: "about.showOnHome")
        #expect(recorder.appliedSettings.last?.showVersionOnHome == false)
        #expect(model.row(id: "about.showOnHome")?.value == "Off")
    }

    /// M7c L32.
    @Test func startHereChoosesTheStartTile() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.homeScreen))
        #expect(model.row(id: SettingsModel.tileRowID("plex"))?.detail?.hasSuffix(" · Start tile") == true)
        model.perform(.push(.tile(id: "iptv")))
        #expect(model.row(id: "tile.start")?.value == "Off")
        model.activate(rowID: "tile.start")
        #expect(recorder.appliedSettings.last?.homeStartTile == "iptv")
        #expect(model.row(id: "tile.start")?.value == "On")
        model.perform(.push(.tile(id: "exit")))
        #expect(model.row(id: "tile.start") == nil)
    }

    @Test func aHiddenStartTileFallsBackToTheFirstTile() {
        var settings = AppSettings()
        settings.homeStartTile = "youtube"
        let items = LaunchItem.defaults.settingHidden(true, id: "youtube")
        let (model, recorder) = makeSettingsModel(settings: settings, items: items)
        #expect(model.startTileID == "plex")
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.start")
        #expect(recorder.appliedSettings.isEmpty)
    }

    /// M7j: with the antenna off, the Antenna row stays, so it can be turned back on.
    @Test func pageWithoutPlaylistOnlyPastes() {
        let (model, recorder) = makeSettingsModel(settings: Self.antennaOff)
        model.perform(.push(.liveTV))
        #expect(model.actionRowIDs == ["iptv.playlist.paste", "iptv.antenna"])
        #expect(model.row(id: "iptv.playlist.paste")?.title == "Paste Playlist URL")
        #expect(model.row(id: "iptv.guide.add") == nil)
        model.press(.select)
        #expect(recorder.pastes == [.playlist])
    }

    @Test func pasteErrorShowsUntilNavigation() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.liveTV))
        let defaultDetail = model.row(id: "iptv.playlist.paste")?.detail
        #expect(defaultDetail == "Copy the M3U address on this Mac or your iPhone first")

        recorder.pasteResult = "The clipboard doesn't hold a web address."
        model.press(.select)
        #expect(model.row(id: "iptv.playlist.paste")?.detail == "The clipboard doesn't hold a web address.")

        model.press(.back)
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.playlist.paste")?.detail == defaultDetail)

        // A successful paste clears it too.
        model.press(.select)
        recorder.pasteResult = nil
        model.press(.select)
        #expect(model.row(id: "iptv.playlist.paste")?.detail == defaultDetail)
    }

    /// M7f L4: Guide Source shows only when the playlist names a guide and one is pasted.
    @Test func guideSourceRowOnlyWithAChoice() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guideSource") == nil)

        recorder.iptv.playlistNamesGuide = true
        model.refreshStatus()
        let row = model.row(id: "iptv.guideSource")
        #expect(row?.value == "Pasted Guides")
        #expect(row?.detail == nil)
        #expect(row?.description
            == "Use the guide the playlist names, or your pasted guides. Your pasted guides are kept either way.")
        model.activate(rowID: "iptv.guideSource")
        #expect(recorder.appliedSettings.last?.usePlaylistGuide == true)
        #expect(model.row(id: "iptv.guideSource")?.value == "Playlist")

        recorder.iptv.customGuideCount = 0
        model.refreshStatus()
        #expect(model.row(id: "iptv.guideSource") == nil)
    }

    /// M7f L4: a pasted guide kept while the playlist's is used.
    @Test func unusedPastedGuideIsOffAndKeepsItsPage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.playlistNamesGuide = true
        recorder.iptv.customGuideCount = 1
        recorder.iptv.guideSources = [
            .init(id: "p", label: "provider.example · guide.xml", line: "Loading…", isFromPlaylist: true),
            .init(id: "g1", label: "guide-source.online · guide-source_US2.xml.gz", line: "Not in use (kept)",
                  isFromPlaylist: false, isInUse: false),
        ]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guide.p")?.value == "From Playlist")
        let unused = model.row(id: "iptv.guide.g1")
        #expect(unused?.value == "Off")
        #expect(unused?.isDimmed == true)
        #expect(unused?.detail == "Not in use (kept)")
        #expect(unused?.action == .push(.guideSource(id: "g1")))
        model.perform(.push(.guideSource(id: "g1")))
        #expect(model.row(id: "guideSource.remove") != nil)
    }

    @Test func pageWithPlaylistAndTwoGuides() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.channelCount = 5
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.actionRowIDs == ["iptv.playlist.paste", "iptv.guide.g1", "iptv.guide.g2", "iptv.guide.add",
                                          "iptv.antenna", "iptv.groups", "iptv.hiddenChannels", "iptv.teams", "iptv.homePreview", "iptv.refresh",
                                          "iptv.remove"])
        let info = model.row(id: "iptv.playlist.info")
        #expect(info?.title == "iptv.example")
        #expect(info?.value == "5 Channels")
        #expect(info?.detail == "Updated 10:42 PM")
        #expect(model.row(id: "iptv.playlist.paste")?.title == "Replace with Clipboard URL")
        let first = model.row(id: "iptv.guide.g1")
        #expect(first?.title == "guide-source.online · guide-source_US2.xml.gz")
        #expect(first?.value == "1")
        #expect(first?.detail == "1,234 programmes · 50 channels · Updated 10:43 PM")
        #expect(first?.action == .push(.guideSource(id: "g1")))
        #expect(model.row(id: "iptv.guide.g2")?.value == "2")
        #expect(model.row(id: "iptv.guide.g2")?.detail == "Loading…")
        let footer = model.sections.first { $0.id == "guides" }?.footer
        #expect(footer?.hasPrefix("Guide data for 3 of 5 channels.") == true)

        model.press(.down, .down, .down, .select)
        #expect(recorder.pastes == [.guide])
        model.press(.down, .down, .down, .down, .down, .down, .select)   // past Antenna (M7j), Groups, Hidden Channels, Teams (M7f L13)
        #expect(recorder.iptvRefreshes == 1)
    }

    @Test func playlistGuideIsAnInfoRow() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.guideSources = [.init(id: "p", label: "guide.example", line: "Not loaded yet", isFromPlaylist: true)]
        recorder.iptv.customGuideCount = 0
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.actionRowIDs == ["iptv.playlist.paste", "iptv.guide.add", "iptv.antenna", "iptv.groups", "iptv.hiddenChannels", "iptv.teams",
                                          "iptv.homePreview", "iptv.refresh", "iptv.remove"])
        #expect(model.row(id: "iptv.guide.p")?.value == "From Playlist")
        #expect(model.row(id: "iptv.guide.p")?.action == nil)
    }

    @Test func noGuideExplainsHowToAddOne() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.guideSources = []
        recorder.iptv.customGuideCount = 0
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guide.none")?.title == "No guide")
        #expect(model.row(id: "iptv.guide.none")?.detail == "Copy an XMLTV guide address, then add it below")
    }

    @Test func noAddRowAtTheLimit() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.customGuideCount = IPTVLibrary.maxGuideSources
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guide.add") == nil)
    }

    @Test func guidePasteErrorShowsOnTheGuideRowOnly() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        let playlistDetail = model.row(id: "iptv.playlist.paste")?.detail
        recorder.pasteResult = "That guide is already added"
        model.perform(.pasteIPTVURL(.guide))
        #expect(model.row(id: "iptv.guide.add")?.detail == "That guide is already added")
        #expect(model.row(id: "iptv.playlist.paste")?.detail == playlistDetail)

        model.perform(.pasteIPTVURL(.playlist))
        #expect(model.row(id: "iptv.playlist.paste")?.detail == "That guide is already added")
        #expect(model.row(id: "iptv.guide.add")?.detail == "Copy an XMLTV address on this Mac or your iPhone first")
    }

    @Test func channelsSection() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.groups = [.init(name: "Live Channels", channelCount: 97, isHidden: false),
                                .init(name: "NHL Games", channelCount: 8, isHidden: false)]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.groups")?.value == "All Shown")
        #expect(model.row(id: "iptv.hiddenChannels")?.value == "None")

        recorder.iptv.groups[1].isHidden = true
        recorder.iptv.hiddenChannels = [.init(id: "id:a", number: 3, name: "A", group: "Live Channels"),
                                        .init(id: "id:b", number: 9, name: "B", group: "Live Channels")]
        model.refreshStatus()
        #expect(model.row(id: "iptv.groups")?.value == "1 Hidden")
        #expect(model.row(id: "iptv.hiddenChannels")?.value == "2")
    }

    @Test func groupsPage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.groups = [.init(name: "Live Channels", channelCount: 97, isHidden: false),
                                .init(name: "NHL Games", channelCount: 8, isHidden: true)]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.iptvGroups))
        #expect(model.pageTitle == "Groups")
        #expect(model.actionRowIDs == ["group.Live Channels", "group.NHL Games"])
        let nhl = model.row(id: "group.NHL Games")
        #expect(nhl?.value == "Hidden")
        #expect(nhl?.detail == "8 channels")
        #expect(nhl?.isDimmed == true)
        model.press(.select)
        model.press(.down, .select)
        #expect(recorder.groupHides == [GroupHide(name: "Live Channels", hidden: true), GroupHide(name: "NHL Games", hidden: false)])
    }

    /// M7f L13.
    @Test func teamsPages() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.teams")?.value == "None")
        recorder.iptv.teams = ["nba.lal", "nhl.la", "nba.mia"]
        model.refreshStatus()
        #expect(model.row(id: "iptv.teams")?.value == "3 Teams")
        #expect(SettingsModel.teamCountLabel(1) == "1 Team")

        model.perform(.push(.iptvTeams))
        #expect(model.pageTitle == "My Teams")
        #expect(model.actionRowIDs == ["league.nfl", "league.nba", "league.nhl", "league.mlb",
                                          "league.ncaaf", "league.ncaam", "league.ncaaw", "league.ncaabase",
                                          "teams.matchInitials", "teams.matchNicknames"])
        #expect(model.sections.map(\.title) == ["Pro", "College", "Matching"])
        #expect(model.row(id: "league.nba")?.value == "2 On")
        #expect(model.row(id: "league.nfl")?.value == nil)

        model.press(.down, .select)
        #expect(model.page == .iptvLeague(.nba))
        #expect(model.pageTitle == "NBA")
        #expect(model.actionRowIDs.count == 30)
        #expect(model.row(id: "team.nba.lal")?.value == "On")
        #expect(model.row(id: "team.nba.atl")?.value == nil)
        // The first team (Atlanta Hawks) is added; the Lakers removed.
        model.press(.select)
        model.perform(.toggleTeam(id: "nba.lal"))
        #expect(recorder.teamPicks == [TeamPick(id: "nba.atl", picked: true), TeamPick(id: "nba.lal", picked: false)])
    }

    /// M7m L29: My Teams → Matching, both Off by default; Select saves the switch and flips its row.
    @Test func myTeamsMatchingSwitches() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.iptvTeams))
        let matching = model.sections.first { $0.id == "matching" }
        #expect(matching?.title == "Matching")
        #expect(matching?.rows.map(\.id) == ["teams.matchInitials", "teams.matchNicknames"])
        #expect(matching?.footer == "Spelled-out names, such as Louisiana-Monroe or Brigham Young, always count.")
        let initials = model.row(id: "teams.matchInitials")
        #expect(initials?.title == "Match Initials")
        #expect(initials?.value == "Off")
        #expect(initials?.description
            == "Games named with initials, such as ULM or BYU, count for your teams. Some initials are also pro teams' (BUF, MIA), so other games may show.")
        let nicknames = model.row(id: "teams.matchNicknames")
        #expect(nicknames?.title == "Match Nicknames Alone")
        #expect(nicknames?.value == "Off")
        #expect(nicknames?.description
            == "A game that names only a nickname, such as \"The Cougars meet the Bearcats\", counts for your teams with that nickname, narrowed by the school or conference when the guide names one.")

        model.activate(rowID: "teams.matchInitials")
        #expect(recorder.appliedSettings.last?.teamMatchInitials == true)
        #expect(recorder.appliedSettings.last?.teamMatchNicknames == false)
        #expect(model.row(id: "teams.matchInitials")?.value == "On")
        #expect(model.row(id: "teams.matchNicknames")?.value == "Off")
        model.activate(rowID: "teams.matchNicknames")
        #expect(recorder.appliedSettings.last?.teamMatchOptions == TeamMatchOptions(initials: true, nicknames: true))
        #expect(model.row(id: "teams.matchNicknames")?.value == "On")
        model.activate(rowID: "teams.matchInitials")
        #expect(recorder.appliedSettings.last?.teamMatchOptions == TeamMatchOptions(nicknames: true))
        #expect(model.row(id: "teams.matchInitials")?.value == "Off")
    }

    /// M7l L13: College leagues push conferences, then the conference's teams.
    @Test func collegeTeamsPages() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.teams")?.description == "Your teams' live and upcoming games, pro and college, in the guide's My Teams group.")
        #expect(model.row(id: "iptv.teams")?.title == "My Teams")
        model.perform(.push(.iptvTeams))
        #expect(model.sections.first { $0.title == "College" }?.footer
                == "The guide's My Teams group shows your teams' live games, the channels showing them now, and their games in the next 3 days.")
        #expect(model.sections.first { $0.title == "College" }?.rows.map(\.id)
            == ["league.ncaaf", "league.ncaam", "league.ncaaw", "league.ncaabase"])
        #expect(model.row(id: "league.ncaaf")?.title == "College Football")

        model.perform(.push(.iptvLeague(.ncaaf)))
        #expect(model.pageTitle == "College Football")
        let conferences = TeamCatalog.conferences(in: .ncaaf)
        #expect(model.actionRowIDs == conferences.map { "conference.ncaaf.\($0)" })
        #expect(model.row(id: "conference.ncaaf.ACC")?.value == nil)
        // FBS conferences come before FCS ones.
        #expect(!TeamCatalog.isFCS(conferences[0]))
        #expect(TeamCatalog.isFCS(conferences[conferences.count - 1]))

        model.perform(.push(.iptvConference(.ncaaf, "ACC")))
        #expect(model.pageTitle == "ACC")
        let acc = TeamCatalog.teams(in: .ncaaf, conference: "ACC")
        #expect(!acc.isEmpty)
        #expect(model.actionRowIDs == acc.map { "team.\($0.id)" })
        let first = acc[0]
        #expect(first.id.hasPrefix("ncaaf."))
        #expect(model.row(id: "team.\(first.id)")?.value == nil)
        model.press(.select)
        #expect(recorder.teamPicks == [TeamPick(id: first.id, picked: true)])

        // The library now has it: the team, its conference and its league show it.
        recorder.iptv.teams = [first.id]
        model.refreshStatus()
        #expect(model.row(id: "team.\(first.id)")?.value == "On")
        #expect(model.sections(for: .iptvLeague(.ncaaf)).flatMap(\.rows)
            .first { $0.id == "conference.ncaaf.ACC" }?.value == "1 On")
        #expect(model.sections(for: .iptvTeams).flatMap(\.rows).first { $0.id == "league.ncaaf" }?.value == "1 On")
        #expect(model.sections(for: .iptvTeams).flatMap(\.rows).first { $0.id == "league.ncaam" }?.value == nil)
        // Selecting it again removes it.
        model.press(.select)
        #expect(recorder.teamPicks.last == TeamPick(id: first.id, picked: false))
    }

    // MARK: Antenna (M7j L14)

    private static let antennaOff: AppSettings = {
        var settings = AppSettings()
        settings.antennaEnabled = false
        return settings
    }()

    /// A tuner whose DeviceID ("SECRETID") and base URL (`http://10.0.0.9`) the app knows; Settings gets neither.
    private static func antennaStatus(hasPlaylist: Bool = false) -> IPTVSettingsStatus {
        let device = HDHomeRunDevice(id: "SECRETID", name: "HDHomeRun FLEX 4K", model: "HDFX-4K", tunerCount: 2,
                                     baseURL: URL(string: "http://10.0.0.9")!,
                                     lineupURL: URL(string: "http://10.0.0.9/lineup.json")!)
        var status = hasPlaylist ? Self.status : IPTVSettingsStatus()
        status.antennaEnabled = true
        status.antennaTuners = [.init(name: device.name, model: device.model, tunerCount: device.tunerCount,
                                      channelCount: 3)]
        status.antennaChannels = [
            .init(id: "antenna:2.1", displayNumber: "2.1", name: "WSB-HD", isHD: true, signalQuality: 100),
            .init(id: "antenna:2.2", displayNumber: "2.2", name: "ME-TV", signalQuality: 87),
            .init(id: "antenna:5.1", displayNumber: "5.1", name: "WAGA-HD", isHD: true),
        ]
        status.antennaGuideLine = "Updated Nov 15, 9:12 AM · 1,234 programmes · 2 of 3 channels"
        return status
    }

    private func onAntennaPage(_ status: IPTVSettingsStatus = Self.antennaStatus(),
                               settings: AppSettings = AppSettings()) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(settings: settings)
        recorder.iptv = status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.antenna))
        return (model, recorder)
    }

    @Test func liveTVPageHasAnAntennaRow() {
        // Without a playlist: a tuner found sets Live TV up, and the Channels section shows with the Antenna row.
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.antennaStatus()
        model.refreshStatus()
        #expect(model.row(id: "liveTV")?.value == "3 Channels")
        model.perform(.push(.liveTV))
        #expect(model.sections.first { $0.id == "channels" }?.rows.map(\.id)
            == ["iptv.antenna", "iptv.groups", "iptv.hiddenChannels", "iptv.teams"])
        let row = model.row(id: "iptv.antenna")
        #expect(row?.title == "Antenna")
        #expect(row?.value == "1 Tuner · 3 Channels")
        #expect(row?.description == "Channels from an HDHomeRun tuner on your network.")
        #expect(row?.action == .push(.antenna))
        #expect(row?.showsDisclosure == true)

        // Searching, then nothing found (the antenna on, no playlist: the Channels section still shows).
        recorder.iptv = IPTVSettingsStatus()
        recorder.iptv.antennaEnabled = true
        recorder.iptv.antennaSearching = true
        model.refreshStatus()
        #expect(model.sections(for: .root).flatMap(\.rows).first { $0.id == "liveTV" }?.value == "Not Set Up")
        #expect(model.row(id: "iptv.antenna")?.value == "Searching…")
        #expect(model.row(id: "iptv.groups") != nil)
        // No tuner yet: the Channels section only (no guides, preview or Refresh Now).
        #expect(model.sections.map(\.id) == ["playlist", "channels"])
        recorder.iptv.antennaSearching = false
        model.refreshStatus()
        #expect(model.row(id: "iptv.antenna")?.value == "No Tuner Found")

        // With a playlist: the row leads the Channels section; the root counts both sources.
        let (withPlaylist, playlistRecorder) = makeSettingsModel()
        playlistRecorder.iptv = Self.antennaStatus(hasPlaylist: true)
        withPlaylist.refreshStatus()
        #expect(withPlaylist.row(id: "liveTV")?.value == "121 Channels")
        withPlaylist.perform(.push(.liveTV))
        #expect(withPlaylist.sections.first { $0.id == "channels" }?.rows.map(\.id)
            == ["iptv.antenna", "iptv.groups", "iptv.hiddenChannels", "iptv.teams"])
        #expect(withPlaylist.row(id: "iptv.antenna")?.value == "1 Tuner · 3 Channels")
        #expect(withPlaylist.sections.map(\.id) == ["playlist", "guides", "channels", "homePreview", "manage"])
    }

    /// L11, L13: a tuner alone gets the guides (antenna channels match the pasted ones with Guide from SiliconDust
    /// off), the preview switch (the preview holds a tuner) and Refresh Now; only Remove is the playlist's.
    @Test func antennaOnlyPageHasGuidesPreviewAndRefresh() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.antennaStatus()
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.sections.map(\.id) == ["playlist", "guides", "channels", "homePreview", "manage"])
        #expect(model.actionRowIDs == ["iptv.playlist.paste", "iptv.guide.add", "iptv.antenna", "iptv.groups",
                                          "iptv.hiddenChannels", "iptv.teams", "iptv.homePreview", "iptv.refresh"])
        #expect(model.row(id: "iptv.remove") == nil)
        #expect(model.row(id: "iptv.playlist.info") == nil)
        #expect(model.row(id: "iptv.guideSource") == nil)
        #expect(model.row(id: "iptv.guide.none")?.title == "No guide")
        // The count is the playlist's, so it's left out.
        #expect(model.sections.first { $0.id == "guides" }?.footer == "A channel uses the first guide in this list that has it.")
        #expect(model.row(id: "iptv.refresh")?.description == "Reads the tuner's channels and downloads the guides again now.")
        model.activate(rowID: "iptv.refresh")
        #expect(recorder.iptvRefreshes == 1)
        model.activate(rowID: "iptv.homePreview")
        #expect(recorder.appliedSettings.last?.homeLivePreview == false)

        // A pasted guide with a tuner alone: its row and page as with a playlist.
        recorder.iptv.guideSources = [.init(id: "g1", label: "guide-source.online · guide-source_US2.xml.gz",
                                            line: "Loading…", isFromPlaylist: false)]
        recorder.iptv.customGuideCount = 1
        model.refreshStatus()
        #expect(model.row(id: "iptv.guide.g1")?.action == .push(.guideSource(id: "g1")))
    }

    @Test func antennaPageShowsTunersAndGuide() {
        var status = Self.antennaStatus()
        status.antennaLeftOut = 2
        let (model, _) = onAntennaPage(status)
        #expect(model.pageTitle == "Antenna")
        #expect(model.sections.map(\.title) == ["Antenna", "Tuners", "Guide", "Channels"])
        #expect(model.actionRowIDs == ["antenna.enabled", "antenna.find", "antenna.scan", "antenna.guide",
                                          "antenna.channels"])

        let use = model.row(id: "antenna.enabled")
        #expect(use?.title == "Use Antenna")
        #expect(use?.value == "On")
        #expect(use?.description == "Finds HDHomeRun tuners on your network and adds their channels to Live TV's Antenna group.")
        let tuner = model.row(id: "antenna.tuner.0")
        #expect(tuner?.title == "HDHomeRun FLEX 4K")
        #expect(tuner?.value == "2 tuners")
        #expect(tuner?.detail == "HDFX-4K · 3 channels")
        #expect(tuner?.action == nil)
        let find = model.row(id: "antenna.find")
        #expect(find?.title == "Find Tuners")
        #expect(find?.detail == nil)
        #expect(find?.description == "Looks for HDHomeRun tuners on your network again.")
        let guide = model.row(id: "antenna.guide")
        #expect(guide?.title == "Guide from SiliconDust")
        #expect(guide?.value == "On")
        #expect(guide?.description == "Downloads 2 days of listings from SiliconDust (api.hdhomerun.com) about once a day, signed in with your tuner. Off: antenna channels use your pasted guides.")
        let guideStatus = model.row(id: "antenna.guide.status")
        #expect(guideStatus?.detail == "Updated Nov 15, 9:12 AM · 1,234 programmes · 2 of 3 channels")
        #expect(guideStatus?.action == nil)
        let channels = model.row(id: "antenna.channels")
        #expect(channels?.value == "3 Shown")
        #expect(channels?.description == "Show or hide each antenna channel.")
        #expect(model.sections.last?.footer == "Channels come from the tuner's lineup. After moving the antenna, Scan for Channels finds them again. 2 protected channels can't play and are left out.")

        // The lineup can't be read: the tuner row says so (the last channels are kept).
        var failing = Self.antennaStatus()
        failing.antennaLineupLine = AntennaSource.unreachableMessage
        let (failed, _) = onAntennaPage(failing)
        #expect(failed.row(id: "antenna.tuner.0")?.detail == "HDFX-4K · The antenna tuner isn't answering")
        #expect(failed.sections.last?.footer == "Channels come from the tuner's lineup. After moving the antenna, Scan for Channels finds them again.")

        // L15: no DeviceID or address anywhere on the Antenna pages, or on Live TV's.
        for page in [SettingsPage.liveTV, .antenna, .antennaChannels, .root] {
            for row in model.sections(for: page).flatMap(\.rows) {
                for text in [row.id, row.title, row.value, row.detail, row.description].compactMap({ $0 }) {
                    #expect(!text.contains("SECRETID"))
                    #expect(!text.contains("10.0.0.9"))
                }
            }
            for footer in model.sections(for: page).compactMap(\.footer) {
                #expect(!footer.contains("SECRETID"))
                #expect(!footer.contains("10.0.0.9"))
            }
        }
    }

    @Test func findTunersSaysWhatItFound() async {
        let (model, recorder) = onAntennaPage()
        recorder.antennaFindResult = .found(1)
        model.activate(rowID: "antenna.find")
        #expect(model.row(id: "antenna.find")?.detail == "Searching…")
        #expect(model.isProbeRunning(.findAntennaTuners))
        await model.probeTasks[.findAntennaTuners]?.value
        #expect(recorder.antennaFinds == 1)
        #expect(model.row(id: "antenna.find")?.detail == "Found 1 tuner")

        recorder.antennaFindResult = .noneFound
        model.activate(rowID: "antenna.find")
        #expect(model.row(id: "antenna.find")?.detail == "Searching…")
        await model.probeTasks[.findAntennaTuners]?.value
        #expect(recorder.antennaFinds == 2)
        #expect(model.row(id: "antenna.find")?.detail == "No HDHomeRun found on this network")
        #expect(SettingsModel.antennaFindLine(.found(2)) == "Found 2 tuners")
        // QA 4: a known tuner kept after an empty search that didn't answer either.
        recorder.antennaFindResult = .noneAnswered
        model.activate(rowID: "antenna.find")
        await model.probeTasks[.findAntennaTuners]?.value
        #expect(model.row(id: "antenna.find")?.detail == "No HDHomeRun answered")

        // A fresh visit starts without the old result.
        model.press(.back)
        model.perform(.push(.antenna))
        #expect(model.row(id: "antenna.find")?.detail == nil)

        // No tuner known: the row says what the automatic search is doing, then that none was found.
        var none = IPTVSettingsStatus()
        none.antennaEnabled = true
        none.antennaSearching = true
        let (empty, emptyRecorder) = onAntennaPage(none)
        #expect(empty.row(id: "antenna.tuner.0") == nil)
        #expect(empty.row(id: "antenna.find")?.detail == "Searching…")
        emptyRecorder.iptv.antennaSearching = false
        empty.refreshStatus()
        #expect(empty.row(id: "antenna.find")?.detail == "No HDHomeRun found on this network")
    }

    /// QA 2: one channel is "1 Channel", on the root row and the Antenna row.
    @Test func oneChannelIsSingular() {
        var status = Self.antennaStatus()
        status.antennaTuners[0].channelCount = 1
        status.antennaChannels = [status.antennaChannels[0]]
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = status
        model.refreshStatus()
        #expect(model.row(id: "liveTV")?.value == "1 Channel")
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.antenna")?.value == "1 Tuner · 1 Channel")
        model.perform(.push(.antenna))
        #expect(model.row(id: "antenna.tuner.0")?.detail == "HDFX-4K · 1 channel")
    }

    /// QA 6: one protected channel left out.
    @Test func oneLeftOutChannelIsSingular() {
        var status = Self.antennaStatus()
        status.antennaLeftOut = 1
        let (model, _) = onAntennaPage(status)
        #expect(model.sections.last?.footer == "Channels come from the tuner's lineup. After moving the antenna, Scan for Channels finds them again. 1 protected channel can't play and is left out.")
    }

    /// QA 3: with the Antenna group hidden, each channel keeps its own Shown/Hidden and the footer says why none show.
    @Test func hiddenAntennaGroupSaysSoOnTheChannelsPage() {
        var status = Self.antennaStatus()
        status.antennaChannels[1].isHidden = true
        let (model, recorder) = onAntennaPage(status)
        model.perform(.push(.antennaChannels))
        #expect(model.sections.first?.footer == nil)
        recorder.iptv.groups = [.init(name: "Antenna", channelCount: 3, isHidden: true)]
        model.refreshStatus()
        #expect(model.sections.first?.footer
            == "The Antenna group is hidden in Live TV → Groups, so none of these channels show.")
        #expect(model.row(id: "antennaChannel.antenna:2.1")?.value == "Shown")
        #expect(model.row(id: "antennaChannel.antenna:2.2")?.value == "Hidden")
        #expect(model.row(id: "antennaChannel.antenna:2.1")?.isDimmed == false)
        // Another group hidden: no footer.
        recorder.iptv.groups = [.init(name: "Antenna", channelCount: 3, isHidden: false),
                                .init(name: "NHL Games", channelCount: 8, isHidden: true)]
        model.refreshStatus()
        #expect(model.sections.first?.footer == nil)
    }

    /// QA 5: the descriptions hold for a tuner without a playlist too.
    @Test func liveTVDescriptionsCoverTheAntenna() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "liveTV")?.description
            == "The playlist, antenna and guides, channel groups, hidden channels, teams and the Home screen preview.")
        recorder.iptv = Self.antennaStatus()
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.groups")?.description == "Which groups show in the guide.")
    }

    @Test func useAntennaTogglesTheSetting() {
        let (model, recorder) = onAntennaPage()
        model.activate(rowID: "antenna.enabled")
        #expect(recorder.appliedSettings.last?.antennaEnabled == false)
        #expect(model.row(id: "antenna.enabled")?.value == "Off")
        #expect(model.row(id: "antenna.find") == nil)
        model.activate(rowID: "antenna.enabled")
        #expect(recorder.appliedSettings.last?.antennaEnabled == true)
        #expect(model.row(id: "antenna.enabled")?.value == "On")
        #expect(model.row(id: "antenna.find") != nil)
        #expect(recorder.appliedSettings.allSatisfy { $0.antennaGuide })
    }

    @Test func guideToggleAppliesTheSetting() {
        let (model, recorder) = onAntennaPage()
        model.activate(rowID: "antenna.guide")
        #expect(recorder.appliedSettings.last?.antennaGuide == false)
        #expect(recorder.appliedSettings.last?.antennaEnabled == true)
        #expect(model.row(id: "antenna.guide")?.value == "Off")
        #expect(model.row(id: "antenna.guide.status")?.detail == "Off")
        model.activate(rowID: "antenna.guide")
        #expect(recorder.appliedSettings.last?.antennaGuide == true)
        #expect(model.row(id: "antenna.guide.status")?.detail == "Updated Nov 15, 9:12 AM · 1,234 programmes · 2 of 3 channels")
    }

    @Test func antennaChannelsPageTogglesHiding() {
        let (model, recorder) = onAntennaPage()
        model.activate(rowID: "antenna.channels")
        #expect(model.page == .antennaChannels)
        #expect(model.pageTitle == "Channels")
        #expect(model.actionRowIDs == ["antennaChannel.antenna:2.1", "antennaChannel.antenna:2.2",
                                          "antennaChannel.antenna:5.1"])
        let first = model.row(id: "antennaChannel.antenna:2.1")
        #expect(first?.title == "2.1  WSB-HD")
        #expect(first?.value == "Shown")
        #expect(first?.detail == "HD · Signal 100 %")
        #expect(first?.isDimmed == false)
        #expect(model.row(id: "antennaChannel.antenna:2.2")?.detail == "Signal 87 %")
        #expect(model.row(id: "antennaChannel.antenna:5.1")?.detail == "HD")

        model.press(.down, .select)
        #expect(recorder.channelHides == [ChannelHide(id: "antenna:2.2", hidden: true)])
        // The library hid it.
        recorder.iptv.antennaChannels[1].isHidden = true
        model.refreshStatus()
        let hidden = model.row(id: "antennaChannel.antenna:2.2")
        #expect(hidden?.value == "Hidden")
        #expect(hidden?.isDimmed == true)
        #expect(model.sections(for: .antenna).flatMap(\.rows).first { $0.id == "antenna.channels" }?.value == "1 Hidden")
        model.press(.select)
        #expect(recorder.channelHides.last == ChannelHide(id: "antenna:2.2", hidden: false))

        // No channels: only an info row.
        recorder.iptv.antennaChannels = []
        model.refreshStatus()
        #expect(model.actionRowIDs.isEmpty)
        #expect(model.row(id: "antennaChannel.none")?.title == "No antenna channels")
    }

    @Test func antennaOffShowsOffAndHidesTheTunerRows() {
        var status = Self.antennaStatus()
        status.antennaEnabled = false
        status.antennaTuners = []
        status.antennaChannels = []
        let (model, _) = onAntennaPage(status, settings: Self.antennaOff)
        #expect(model.sections.map(\.id) == ["antenna"])
        #expect(model.actionRowIDs == ["antenna.enabled"])
        #expect(model.row(id: "antenna.enabled")?.value == "Off")
        #expect(model.row(id: "antenna.tuner.0") == nil)
        #expect(model.sections(for: .liveTV).flatMap(\.rows).first { $0.id == "iptv.antenna" }?.value == "Off")
        // Even with a tuner still in the status (the library hasn't caught up), the setting decides.
        let (lagging, _) = onAntennaPage(Self.antennaStatus(), settings: Self.antennaOff)
        #expect(lagging.row(id: "antenna.tuner.0") == nil)
        #expect(lagging.sections(for: .liveTV).flatMap(\.rows).first { $0.id == "iptv.antenna" }?.value == "Off")
    }

    @Test func hiddenChannelsPage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.hiddenChannels = [.init(id: "id:a", number: 3, name: "A", group: "Live Channels")]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.iptvHiddenChannels))
        #expect(model.row(id: "hidden.id:a")?.title == "3  A")
        #expect(model.row(id: "hidden.id:a")?.value == "Show")
        #expect(model.row(id: "hidden.id:a")?.detail == "Live Channels")
        // M7j: an antenna channel shows its GuideNumber, not its position.
        recorder.iptv.hiddenChannels = [.init(id: "id:a", number: 3, name: "A", group: "Live Channels"),
                                        .init(id: "antenna:5.1", number: 412, name: "WAGA-HD", group: "Antenna",
                                              guideNumber: "5.1")]
        model.refreshStatus()
        #expect(model.row(id: "hidden.antenna:5.1")?.title == "5.1  WAGA-HD")
        #expect(model.row(id: "hidden.antenna:5.1")?.detail == "Antenna")
        #expect(model.row(id: "hidden.id:a")?.title == "3  A")
        recorder.iptv.hiddenChannels = []
        model.press(.select)
        #expect(recorder.unhiddenChannels == ["id:a"])
        // Empty: only the info row.
        #expect(model.actionRowIDs.isEmpty)
        #expect(model.sections.flatMap(\.rows).map(\.id) == ["hidden.none"])
    }

    @Test func guidePage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.guideSource(id: "g1")))
        #expect(model.pageTitle == "guide-source.online · guide-source_US2.xml.gz")
        #expect(model.row(id: "guideSource.status")?.detail == "1,234 programmes · 50 channels · Updated 10:43 PM")
        #expect(model.actionRowIDs == ["guideSource.moveDown", "guideSource.remove"])
        model.press(.select)
        #expect(recorder.guideMoves == [GuideMove(id: "g1", step: 1)])
        #expect(model.page == .guideSource(id: "g1"))

        model.perform(.push(.guideSource(id: "g2")))
        #expect(model.actionRowIDs == ["guideSource.moveUp", "guideSource.remove"])
        model.press(.down, .select)
        #expect(recorder.guideRemovals == ["g2"])
        #expect(model.page == .guideSource(id: "g1"))

        // An id no longer listed shows nothing.
        model.perform(.push(.guideSource(id: "gone")))
        #expect(model.sections.isEmpty)
        #expect(model.pageTitle == "Guide")
    }

    // MARK: M7j L18: the channel scan

    @Test func scanRowOpensTheConfirmPage() {
        let (model, recorder) = onAntennaPage()
        let row = model.row(id: "antenna.scan")
        #expect(row?.title == "Scan for Channels")
        #expect(row?.value == nil)
        #expect(row?.detail == nil)
        #expect(row?.isDimmed == false)
        #expect(row?.showsDisclosure == true)
        #expect(row?.description == "Has the tuner look for channels again, for a few minutes.")
        #expect(model.sections.first { $0.id == "antennaTuners" }?.rows.map(\.id)
            == ["antenna.tuner.0", "antenna.find", "antenna.scan"])

        model.activate(rowID: "antenna.scan")
        #expect(model.page == .confirmAntennaScan)
        #expect(model.pageTitle == "Scan for Channels?")
        #expect(model.actionRowIDs == ["confirm.cancel", "confirm.scan"])
        #expect(model.focusedRowID == "confirm.cancel")
        #expect(model.row(id: "confirm.scan")?.title == "Scan")
        #expect(model.sections.first?.footer == "The tuner looks for channels for a few minutes. Antenna channels can't play meanwhile, here or on other devices. Channels it doesn't find are removed from the tuner's lineup.")
        // Cancel goes back without a scan.
        model.press(.select)
        #expect(model.page == .antenna)
        #expect(recorder.antennaScanStarts == 0)

        // No tuner: no Scan row.
        var none = IPTVSettingsStatus()
        none.antennaEnabled = true
        let (empty, _) = onAntennaPage(none)
        #expect(empty.row(id: "antenna.scan") == nil)
    }

    @Test func confirmPageScanStartsAndPops() {
        let (model, recorder) = onAntennaPage()
        model.activate(rowID: "antenna.scan")
        model.press(.down, .select)
        #expect(recorder.antennaScanStarts == 1)
        #expect(model.page == .antenna)
        #expect(model.focusedRowID == "antenna.scan")
    }

    @Test func scanningRowShowsProgressAndStops() {
        var status = Self.antennaStatus()
        status.antennaScan = .running(progress: 45, found: 120)
        let (model, recorder) = onAntennaPage(status)
        let row = model.row(id: "antenna.scan")
        #expect(row?.title == "Stop Scan")
        #expect(row?.value == "45 %")
        #expect(row?.detail == "Scanning… 120 found")
        #expect(row?.action == .stopAntennaScan)
        #expect(row?.showsDisclosure == false)
        // Select stops it at once, with no confirm page.
        model.activate(rowID: "antenna.scan")
        #expect(recorder.antennaScanStops == 1)
        #expect(model.page == .antenna)
        // The scan read the lineup again: the row is idle once more.
        recorder.iptv.antennaScan = .stopped
        model.refreshStatus()
        #expect(model.row(id: "antenna.scan")?.title == "Scan for Channels")
        #expect(model.row(id: "antenna.scan")?.detail == "Scan stopped")
    }

    @Test func cantScanRowIsDimmed() {
        var status = Self.antennaStatus()
        status.antennaCanScan = false
        let (model, _) = onAntennaPage(status)
        let row = model.row(id: "antenna.scan")
        #expect(row?.isDimmed == true)
        #expect(row?.detail == "The tuner can't scan now")
        #expect(row?.title == "Scan for Channels")
        // Security L2: an info row; Select on it does nothing.
        #expect(row?.action == nil)
        #expect(row?.showsDisclosure == false)
        #expect(!model.actionRowIDs.contains("antenna.scan"))
        model.activate(rowID: "antenna.scan")
        #expect(model.page == .antenna)
        // "Can't scan" wins over the last scan's line.
        #expect(SettingsModel.antennaScanLine(.finished(found: 5, added: 1, removed: 0), canScan: false)
            == "The tuner can't scan now")
    }

    @Test func finishedScanSaysWhatChanged() {
        var status = Self.antennaStatus()
        status.antennaScan = .finished(found: 185, added: 3, removed: 2)
        let (model, _) = onAntennaPage(status)
        #expect(model.row(id: "antenna.scan")?.detail == "Found 185 channels: 3 new, 2 gone")
        #expect(model.row(id: "antenna.scan")?.isDimmed == false)
        #expect(SettingsModel.antennaScanLine(.finished(found: 1, added: 1, removed: 0), canScan: true)
            == "Found 1 channel: 1 new, 0 gone")
        #expect(SettingsModel.antennaScanLine(.finished(found: 1_234, added: 0, removed: 0), canScan: true)
            == "Found 1,234 channels: 0 new, 0 gone")
        #expect(SettingsModel.antennaScanLine(.stopped, canScan: true) == "Scan stopped")
        #expect(SettingsModel.antennaScanLine(.failed, canScan: true) == "Scan failed")
        #expect(SettingsModel.antennaScanLine(nil, canScan: true) == nil)
    }

    /// The scan is polled fast exactly while the Antenna page is on top (and Settings open).
    @Test func antennaPageVisibilityFollowsTheTopPage() {
        let (model, recorder) = onAntennaPage()
        #expect(recorder.antennaPageVisibility == [true])
        model.activate(rowID: "antenna.scan")
        #expect(recorder.antennaPageVisibility == [true, false])
        model.press(.back)
        #expect(recorder.antennaPageVisibility == [true, false, true])
        model.activate(rowID: "antenna.channels")
        model.press(.back)
        #expect(recorder.antennaPageVisibility == [true, false, true, false, true])
        model.screenDidClose()
        #expect(recorder.antennaPageVisibility.last == false)
        model.reset()
        #expect(recorder.antennaPageVisibility.count == 6)
    }

    @Test func removeConfirmFocusesCancelFirst() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(model.row(id: "iptv.remove")!.action!)
        #expect(model.page == .confirmRemoveIPTV)
        #expect(model.focusedRowID == "confirm.cancel")
        model.press(.select)
        #expect(model.page == .liveTV)
        #expect(recorder.iptvRemovals == 0)

        model.perform(.push(.confirmRemoveIPTV))
        model.press(.down, .select)
        #expect(recorder.iptvRemovals == 1)
        #expect(model.page == .liveTV)
    }
    // MARK: Channel Up/Down and Menu (M7 L5, L22)

    @Test func channelUpDownPageByEightRows() {
        let (model, _) = makeSettingsModel()
        #expect(model.handle(.channelDown))
        let ids = model.focusableRowIDs
        #expect(model.focusedRowID == ids[8])
        #expect(model.handle(.channelUp))
        #expect(model.focusedRowID == ids[0])
        model.press(.channelDown, .channelDown, .channelDown, .channelDown, .channelDown)
        #expect(model.focusedRowID == ids.last)
    }

    @Test func menuIsNotHandled() {
        let (model, _) = makeSettingsModel()
        #expect(!model.handle(.menu))
    }

    @Test func channelUpRowTogglesTheDirection() {
        let (model, recorder) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.row(id: "channelUp")?.value == "Up the List")
        #expect(model.row(id: "channelUp")?.detail == nil)
        #expect(model.row(id: "channelUp")?.description?.hasPrefix("Changes channel in Live TV.") == true)
        model.activate(rowID: "channelUp")
        #expect(recorder.appliedSettings.last?.channelUpMovesUpList == false)
        #expect(model.row(id: "channelUp")?.value == "Higher Number")
    }

    /// M7c L6.
    @Test func keepOtherAppsOutRowTogglesTheLock() {
        let (model, recorder) = makeSettingsModel()
        model.open(.restrictions)
        #expect(model.row(id: "kioskLock")?.value == "On")
        #expect(model.row(id: "kioskLock")?.action == .toggle(.kioskLock))
        model.activate(rowID: "kioskLock")
        #expect(recorder.appliedSettings.last?.kioskLock == false)
        #expect(model.row(id: "kioskLock")?.value == "Off")
    }
}

/// A web app tile's start page (M7 L23).
/// M7g: the column track, Left/Right, the description band and the mouse on columns.
struct SettingsColumnsTests {
    @Test func columnsRoles() {
        let (model, _) = makeSettingsModel()
        #expect(model.columns.map(\.role) == [.current, .empty])
        #expect(model.columns.map(\.page) == [.root, nil])
        #expect(model.columns.map(\.id) == [0, 1])

        model.open(.remoteInput)
        #expect(model.columns.map(\.role) == [.parent, .current, .empty])
        model.open(.remoteButtons)
        #expect(model.columns.map(\.role) == [.hidden, .parent, .current, .empty])
        #expect(model.columns.map(\.page) == [.root, .remoteInput, .remoteButtons, nil])
        #expect(model.columns.map(\.id) == [0, 1, 2, 3])
    }

    @Test func rightOpensDisclosureRow() {
        let (model, _) = makeSettingsModel()
        #expect(model.handle(.right))
        #expect(model.page == .homeScreen)
        model.reset()
        model.open(.remoteInput)
        model.focus(rowID: "remoteButtons")
        #expect(model.handle(.right))
        #expect(model.page == .remoteButtons)
    }

    @Test func rightIgnoresToggle() {
        let (model, recorder) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.focusedRowID == "globalInput")
        #expect(model.handle(.right))
        #expect(model.page == .remoteInput)
        #expect(recorder.appliedSettings.isEmpty)
        // Other actions don't run: Relaunch and Exit to Desktop stay put.
        model.reset()
        model.open(.system)
        model.focus(rowID: "relaunch")
        #expect(model.handle(.right))
        model.focus(rowID: "exit")
        #expect(model.handle(.right))
        #expect(model.page == .system)
        #expect(recorder.relaunches == 0)
        #expect(recorder.exits == 0)
        // On a page of info rows only (Add Tile while apps load, every default tile already there), focus is on
        // the first info row, and Right and Select do nothing.
        model.reset()
        model.open(.addTile)
        #expect(model.row(id: "apps.loading")?.action == nil)
        #expect(model.actionRowIDs.isEmpty)
        #expect(model.focusedRowID == model.focusableRowIDs.first)
        #expect(model.handle(.right))
        #expect(model.handle(.select))
        #expect(model.page == .addTile)
    }

    // MARK: Info rows take focus (Settings → Device on the Roku felt stuck; same change on the Mac)

    /// About: Version and Build (info rows) above Show Version on Home.
    @Test func upDownReachesInfoRows() {
        let (model, recorder) = makeSettingsModel()
        model.open(.about)
        #expect(model.focusableRowIDs == ["about.version", "about.build", "about.showOnHome"])
        #expect(model.actionRowIDs == ["about.showOnHome"])
        // Opening the page lands on the first action row, as before.
        #expect(model.focusedRowID == "about.showOnHome")
        model.press(.up)
        #expect(model.focusedRowID == "about.build")
        model.press(.up, .up)
        #expect(model.focusedRowID == "about.version")
        // Select and Right on an info row do nothing.
        model.press(.select, .right)
        #expect(model.page == .about)
        #expect(recorder.appliedSettings.isEmpty)
        model.press(.down)
        #expect(model.focusedRowID == "about.build")
        model.press(.down, .down)
        #expect(model.focusedRowID == "about.showOnHome")
        // Channel Up/Down page over info rows too, clamped.
        model.press(.channelUp)
        #expect(model.focusedRowID == "about.version")
        model.press(.channelDown)
        #expect(model.focusedRowID == "about.showOnHome")
    }

    @Test func hoverFocusesAnInfoRow() {
        let (model, _) = makeSettingsModel()
        model.open(.about)
        model.focus(rowID: "about.build")
        #expect(model.focusedRowID == "about.build")
        // A row of another page still doesn't take focus.
        model.focus(rowID: "about.version", on: .root)
        #expect(model.focusedRowID == "about.build")
    }

    @Test func openingAPageLandsOnItsFirstActionRow() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = IPTVSettingsStatus(hasPlaylist: true, playlistHost: "iptv.example", channelCount: 5)
        model.refreshStatus()
        model.open(.liveTV)
        #expect(model.focusableRowIDs.first == "iptv.playlist.info")
        #expect(model.focusedRowID == "iptv.playlist.paste")
        model.press(.up)
        #expect(model.focusedRowID == "iptv.playlist.info")
        // Back and in again: the page opens on its first action row, not the info row it was left on.
        model.press(.back)
        model.open(.liveTV)
        #expect(model.focusedRowID == "iptv.playlist.paste")
    }

    @Test func infoRowBandText() {
        let (model, _) = makeSettingsModel()
        model.open(.about)
        #expect(model.bandText == "Shows the version and build under the clock, for testing builds.")
        model.press(.up)
        #expect(model.row(id: "about.build")?.description == nil)
        #expect(model.bandText == "Information only: nothing to change here.")
        #expect(SettingsModel.infoRowBandText == "Information only: nothing to change here.")
    }

    /// The parent column marks the row that opened the page, resolved over action rows only.
    @Test func parentSelectionIgnoresInfoRows() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = IPTVSettingsStatus(hasPlaylist: true, playlistHost: "iptv.example", channelCount: 5)
        model.refreshStatus()
        model.open(.liveTV)
        model.press(.up)
        #expect(model.focusedRowID == "iptv.playlist.info")
        model.perform(.push(.confirmRemoveIPTV))
        #expect(model.parentSelectionRowID == "iptv.playlist.paste")
        model.press(.back)
        model.focus(rowID: "iptv.remove")
        model.press(.select)
        #expect(model.page == .confirmRemoveIPTV)
        #expect(model.parentSelectionRowID == "iptv.remove")
    }

    @Test func leftPopsExceptRootAndLearn() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.handle(.left))
        #expect(model.page == .root)

        model.open(.remoteInput)
        model.open(.remoteButtons)
        #expect(model.handle(.left))
        #expect(model.page == .remoteInput)
        #expect(model.handle(.left))
        #expect(model.page == .root)
        #expect(model.handle(.left))
        #expect(model.page == .root)

        model.open(.remoteInput)
        model.open(.remoteButtons)
        model.activate(rowID: "command.home")
        model.activate(rowID: "learn")
        #expect(model.page == .learnButton(.home))
        #expect(model.handle(.left))
        #expect(model.page == .learnButton(.home))
        #expect(recorder.learningCalls == [true])
        // Back still cancels learning.
        #expect(model.handle(.back))
        #expect(model.page == .remoteCommand(.home))
        #expect(recorder.learningCalls == [true, false])

        // Left ends pairing like Back does.
        model.reset()
        recorder.phoneRemote.isRunning = true
        model.refreshStatus()
        model.open(.phoneRemote)
        model.open(.pairPhone)
        #expect(recorder.pairingCalls == [true])
        #expect(model.handle(.left))
        #expect(model.page == .phoneRemote)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func leftAndRightInertInMoveMode() {
        let (model, _) = makeSettingsModel()
        model.open(.homeScreen)
        model.perform(.push(.tile(id: "youtube")))
        model.perform(.startMove(id: "youtube"))
        let items = model.items
        #expect(model.handle(.right))
        #expect(model.handle(.left))
        #expect(model.page == .homeScreen)
        #expect(model.movingTileID == "youtube")
        #expect(model.items == items)
    }

    @Test func parentSelectionIsOpeningRow() {
        let (model, _) = makeSettingsModel()
        #expect(model.parentSelectionRowID == nil)
        // The first row, never moved to: the parent's focus resolves to it.
        model.press(.select)
        #expect(model.parentSelectionRowID == "homeScreen")
        model.press(.back, .down, .down, .select)
        #expect(model.page == .plex)
        #expect(model.parentSelectionRowID == "plex")
        model.press(.back)
        model.focus(rowID: "remoteInput")
        model.press(.select)
        model.focus(rowID: "remoteButtons")
        model.press(.right)
        #expect(model.parentSelectionRowID == "remoteButtons")
        model.press(.left)
        #expect(model.parentSelectionRowID == "remoteInput")
    }

    @Test func parentColumnActivates() {
        let (model, _) = makeSettingsModel()
        model.press(.down)
        model.open(.liveTV)
        #expect(model.page == .liveTV)
        model.activateParentColumn()
        #expect(model.page == .root)
        #expect(model.focusedRowID == "liveTV")
        model.activateParentColumn()
        #expect(model.page == .root)
    }

    /// The parent column builds the sections of a page that isn't on top.
    @Test func sectionsForOtherPagesHaveNoSideEffects() {
        let (model, recorder) = makeSettingsModel()
        let plexRefreshes = recorder.plexRefreshes
        let castingRefreshes = recorder.castingRefreshes
        model.focus(rowID: "plex")
        _ = model.columns
        _ = model.sections(for: .plex)
        model.focus(rowID: "casting")
        _ = model.columns
        _ = model.sections(for: .casting)
        #expect(recorder.plexRefreshes == plexRefreshes)
        #expect(recorder.castingRefreshes == castingRefreshes)
        #expect(recorder.plexLinkingCalls.isEmpty)
        #expect(recorder.pairingCalls.isEmpty)
        #expect(model.page == .root)
    }

    /// M7g L3.
    @Test func bandTextPrefersModeHint() {
        let (model, _) = makeSettingsModel()
        #expect(model.bandText == model.row(id: "homeScreen")?.description)
        #expect(model.bandText != nil)

        model.open(.homeScreen)
        model.perform(.push(.tile(id: "youtube")))
        model.perform(.startMove(id: "youtube"))
        #expect(model.page == .homeScreen)
        #expect(model.bandText == "Up/Down: move · Select or Back: done")
        #expect(model.handle(.back))
        #expect(model.bandText == nil)

        model.reset()
        model.open(.remoteInput)
        model.activate(rowID: "remoteButtons")
        model.activate(rowID: "command.home")
        model.activate(rowID: "learn")
        #expect(model.bandText == "Waiting for a button…")
        model.screenDidClose()

        model.reset()
        model.open(.system)
        model.focus(rowID: "relaunch")
        #expect(model.bandText == "Quits and reopens MMTVL. Picks up changes made by hand to its settings files.")
    }

    // MARK: Held Left/Right (M7g review fixes)

    /// Only a fresh Left or Right changes page; a held key's or button's repeats are swallowed (still handled).
    @Test func repeatedRightAndLeftDontChangePage() {
        let (model, _) = makeSettingsModel()
        #expect(model.handle(.right, isRepeat: true))
        #expect(model.page == .root)
        #expect(model.handle(.right))
        #expect(model.page == .homeScreen)
        #expect(model.handle(.left, isRepeat: true))
        #expect(model.page == .homeScreen)
        #expect(model.handle(.left))
        #expect(model.page == .root)
        // Up and Down still repeat.
        #expect(model.handle(.down, isRepeat: true))
        #expect(model.focusedRowID == "liveTV")
    }

    /// A key just learned for Left auto-repeats on the confirm page: it mustn't leave it.
    @Test func repeatedLeftStaysOnConfirmLearn() {
        let (model, recorder) = makeSettingsModel()
        model.open(.remoteButtons)
        model.activate(rowID: "command.left")
        model.activate(rowID: "learn")
        recorder.learningHandler?(.key(keyCode: 123, modifiers: []))
        guard case .confirmLearn = model.page else {
            Issue.record("Expected the confirm page")
            return
        }
        #expect(model.handle(.left, isRepeat: true))
        guard case .confirmLearn = model.page else {
            Issue.record("A repeated Left left the confirm page")
            return
        }
        #expect(model.handle(.left))
        #expect(model.page == .remoteCommand(.left))
        model.screenDidClose()
    }

    // MARK: Mouse guards (M7g review fixes)

    /// The second click of a double-click on the parent column lands on a row of the page the first click went back
    /// to: it's ignored for the system's double-click interval.
    @Test func rowClickRightAfterAColumnClickIsIgnored() {
        let (model, _) = makeSettingsModel()
        var clock = Date(timeIntervalSinceReferenceDate: 1000)
        model.now = { clock }
        model.doubleClickInterval = { 0.5 }
        model.open(.remoteInput)
        model.focus(rowID: "remoteButtons")
        model.open(.remoteButtons)
        model.activateParentColumn()
        #expect(model.page == .remoteInput)
        clock += 0.3
        model.activate(rowID: "remoteButtons", on: .remoteInput)
        #expect(model.page == .remoteInput)
        clock += 0.3
        model.activate(rowID: "remoteButtons", on: .remoteInput)
        #expect(model.page == .remoteButtons)

        // Back to the root the same way, where a row would push.
        model.activateParentColumn()
        model.activateParentColumn()
        #expect(model.page == .root)
        clock += 0.1
        model.activate(rowID: "about", on: .root)
        #expect(model.page == .root)
        clock += 0.5
        model.activate(rowID: "about", on: .root)
        #expect(model.page == .about)
    }

    /// Only the current page's rows react, not a page fading out after a pop or a replace, or the parent.
    @Test func rowsOfOtherPagesIgnoreThePointer() {
        let (model, recorder) = makeSettingsModel()
        model.focus(rowID: "system")
        model.open(.system)
        model.activateParentColumn()
        #expect(model.page == .root)
        model.doubleClickInterval = { 0 }
        // The popped System page, still fading out.
        model.activate(rowID: "exit", on: .system)
        model.focus(rowID: "relaunch", on: .system)
        #expect(recorder.exits == 0)
        #expect(model.page == .root)
        #expect(model.focusedRowID == "system")
        // The current page's rows do react.
        model.focus(rowID: "liveTV", on: .root)
        #expect(model.focusedRowID == "liveTV")
        model.activate(rowID: "liveTV", on: .root)
        #expect(model.page == .liveTV)
    }
}

struct SettingsWebAppStartPageTests {
    static let meet = LaunchItem(id: "app.meet", title: "Google Meet",
                                 kind: .application(bundleID: "com.brave.Browser.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"))
    static let info = WebAppInfo(appID: "kjg", name: "Google Meet", startURL: URL(string: "https://meet.google.com/landing?lfhs=2"),
                                 browserBundleID: "com.brave.Browser")

    private func onMeetPage() -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: LaunchItem.defaults + [Self.meet])
        recorder.webApps["app.meet"] = Self.info
        model.perform(.push(.homeScreen))
        model.perform(.push(.tile(id: "app.meet")))
        return (model, recorder)
    }

    @Test func onlyWebAppsHaveTheRows() {
        let (model, _) = onMeetPage()
        let ids = model.actionRowIDs
        #expect(ids.firstIndex(of: "tile.startURL") == ids.firstIndex(of: "tile.fullScreen")! + 1)
        #expect(model.row(id: "tile.startURL")?.value == "App's Own")
        #expect(model.row(id: "tile.startURL")?.detail == "Copy a page address on this Mac or your iPhone, then select")
        #expect(model.row(id: "tile.startURL.clear") == nil)

        let (plain, _) = makeSettingsModel()
        plain.perform(.push(.homeScreen))
        plain.perform(.push(.tile(id: "plex")))
        #expect(plain.row(id: "tile.startURL") == nil)
    }

    @Test func pastingAPageOfTheAppsSite() {
        let (model, recorder) = onMeetPage()
        recorder.clipboard = "https://meet.google.com/home?calling=1\n"
        model.activate(rowID: "tile.startURL")
        let saved = recorder.appliedItems.last?.first { $0.id == "app.meet" }
        #expect(saved?.startURL?.absoluteString == "https://meet.google.com/home?calling=1")
        #expect(model.row(id: "tile.startURL")?.value == "meet.google.com/home?calling=1")
        #expect(model.row(id: "tile.startURL.clear") != nil)

        model.activate(rowID: "tile.startURL.clear")
        #expect(recorder.appliedItems.last?.first { $0.id == "app.meet" }?.startURL == nil)
        #expect(model.row(id: "tile.startURL")?.value == "App's Own")
        #expect(model.focusedRowID == "tile.startURL")
    }

    @Test func aPageOnAnotherSiteIsRefused() {
        let (model, recorder) = onMeetPage()
        recorder.clipboard = "https://example.com/meet"
        model.activate(rowID: "tile.startURL")
        #expect(recorder.appliedItems.isEmpty)
        #expect(model.row(id: "tile.startURL")?.detail == "Use a page on meet.google.com")
        recorder.clipboard = nil
        model.activate(rowID: "tile.startURL")
        #expect(model.row(id: "tile.startURL")?.detail == "The clipboard is empty. Copy the URL first.")
        model.press(.back)
        model.perform(.push(.tile(id: "app.meet")))
        #expect(model.row(id: "tile.startURL")?.detail == "Copy a page address on this Mac or your iPhone, then select")
    }

    @Test func longAddressesAreCut() {
        let url = URL(string: "https://meet.google.com/a/very/long/path/that/goes/on/and/on?x=1")!
        let label = SettingsModel.startURLLabel(url)
        #expect(label.count == 48)
        #expect(label.hasSuffix("…"))
    }
}
