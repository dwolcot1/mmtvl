import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import Network
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppDelegate")
    private static let phoneLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")
    private static let inputLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Input")
    /// M7f L1: display sleep and wake and screen changes (notice level, kept in the log store).
    private static let displayLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Display")
    private static let receiverLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")
    private static let tvLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "TV")
    private static let powerLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Power")

    private let launcher = AppLauncher()
    private var youtube: YouTubeController?
    private var iptvLibrary: IPTVLibrary?
    private var plex: PlexAccount?
    private var liveTV: LiveTVModel?
    private var settings = AppSettings()
    private var settingsFile: JSONConfigFile<AppSettings>?
    private var bindingsFile: JSONConfigFile<StoredBindings>?
    private var accessibilityWaitTask: Task<Void, Never>?
    /// M7f L5 (D40): the playlist and guide check every 15 minutes.
    private var iptvRefreshTask: Task<Void, Never>?
    /// M7f L13: the Teams group's 5-minute tick (network channels follow the programme on now).
    private var teamsRefreshTask: Task<Void, Never>?
    /// M7f L8: reads the Siri Remote battery every 5 minutes.
    private var remoteBatteryTask: Task<Void, Never>?
    private var inputRouter: InputRouter?
    private var router: AppRouter?
    private var windowController: KioskWindowController?
    private var eventTap: GlobalEventTap?
    private var controllers: ControllerInput?
    /// M7h D43: the Siri Remote, read directly.
    private var siriRemote: SiriRemoteInput?
    private var wakeObserver: NSObjectProtocol?
    private var displayObservers: [NSObjectProtocol] = []
    /// M7h L16 (D45): HDMI hot-plugs mark Plex HTPC to restart on its next open.
    private let hotplugMonitor = DisplayHotplugMonitor()
    private var remoteServer: RemoteServer?
    private var phoneRemote: PhoneRemote?
    private var volume: VolumeController?
    private var receiver: ReceiverController?
    /// M7h L18: the TV over the network (Power, step 12; Settings, step 11).
    private var tv: TVController?
    /// M7h step 9 (reopened): the TV over HDMI-CEC, through the DisplayPort tunnel (`tvBrand` `cec`).
    private var cec: HDMICEC?
    /// M7h step 9c: the one DisplayPort tunnel (one serial queue for every frame) the TV and the receiver share.
    private let cecLink = CECTunnel()
    /// M7h step 9c: the receiver over HDMI-CEC (`receiverConnection` `cec`).
    private var cecReceiver: CECAudioSystem?
    /// M7h L14, L15 (D45): the power button and the power menu's actions.
    private var power: PowerController?
    /// M15 step 6b: the set-up receiver's power (serial, network or HDMI-CEC), fed by both receivers' changes.
    private let receiverPowerWatch = ReceiverPowerWatch()
    /// M7h L15, U1: Power and Power Menu from any app; Cancel hands the screen back.
    private var powerMenuPresenter: PowerMenuPresenter?
    /// M15: Sparkle updates (off in Debug and `-windowed`, L4).
    private var updater: SoftwareUpdater?
    /// Step 11: `scheduleSettingsRefresh` coalesces.
    private var settingsRefreshScheduled = false
    /// Step 13e: what the scheduled refresh re-reads.
    private var settingsRefreshParts: SettingsModel.StatusParts = []
    private var settingsRefreshReadsBattery = false
    private var appActivationObserver: NSObjectProtocol?
    private var castReceiver: CastReceiver?
    /// M7b D31: the phone trackpad.
    private let phonePointer = PhonePointer()
    /// M7b D32: Android screen mirroring through Reflector.
    private var reflector: ReflectorMonitor?
    /// M7b L15: the last AirPlay probe; refreshed when Settings → Casting opens.
    private var airPlayState: AirPlayReceiverState = .unknown
    /// M7c L9: set by the PIN-checked quit, Relaunch and a logout/shutdown; otherwise the kiosk lock cancels a quit.
    private var allowsTermination = false
    /// M15 L14 (security L-b): the updater's own permission for Sparkle's quit, set and taken back only by it, so its
    /// 60-s revoke never undoes `allowsTermination` (a logout, ⌘Q with the PIN, Relaunch).
    private var updateQuitAllowed = false
    /// M7c L8b: takes the screen back from apps MMTVL didn't open.
    private let kioskGuard = KioskGuard()
    private var powerOffObserver: NSObjectProtocol?
    /// M7c L16: the displays or the system went to sleep; the Live TV preview stops.
    private var screensSleepObservers: [NSObjectProtocol] = []
    /// M7m L20: macOS's screen saver, started after the dim and ended on a press.
    private let screenSaver = ScreenSaver()
    /// M7m L24: in kiosk mode the Mac never idle-sleeps, so a TV turned off by its own remote, its button or its
    /// standby timer doesn't let it sleep. Held from launch, never released (process exit releases it). Sleep Mac mini
    /// still sleeps, and the displays still sleep.
    private let noIdleSleep = SleepAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                                             name: "MMTVL: TV may be off", category: "Power")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }

        let directory = LaunchItemStore.defaultDirectory
        let settingsFile = JSONConfigFile(url: directory.appending(path: AppSettings.fileName), defaultValue: AppSettings())
        self.settingsFile = settingsFile
        settings = settingsFile.load()
        if settings.castDeviceID == nil {
            // M7b L3: the DIAL device uuid, made once.
            settings.castDeviceID = UUID().uuidString.lowercased()
            do {
                try settingsFile.save(settings)
            } catch {
                Self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
            }
        }
        let bindingsFile = JSONConfigFile(url: directory.appending(path: KeyBindings.fileName),
                                          defaultValue: StoredBindings(KeyBindings.defaultBindings))
        self.bindingsFile = bindingsFile
        let stored = StoredBindings.load(from: bindingsFile)   // M7h: a file with skipped entries is copied to .bak
        for _ in 0..<stored.skippedCount {
            Self.inputLogger.notice("Skipped an unreadable binding")
        }
        let bindings = restoreSiriRemoteBindings(migrateBindings(KeyBindings(stored.bindings)))
        let inputRouter = InputRouter(bindings: bindings)
        let kiosk = !AppEnvironment.windowedMode
        if kiosk, noIdleSleep.hold(true) {
            // M7m L24. A failed hold is logged by `SleepAssertion`.
            Self.powerLogger.notice("Power: the Mac won't idle-sleep while MMTVL runs")
        }

        let store = LaunchItemStore()
        let storedItems = store.load()
        let items = storedItems.ensuringSettingsTile()
        if items != storedItems {
            do {
                try store.save(items)
            } catch {
                Self.logger.error("Failed to save launch items: \(error.localizedDescription, privacy: .public)")
            }
        }
        let iptvLibrary = makeIPTVLibrary(directory: directory)
        iptvLibrary.usePlaylistGuide = settings.usePlaylistGuide
        // M7j L14: before the first refresh.
        iptvLibrary.antenna.isEnabled = settings.antennaEnabled
        iptvLibrary.antennaGuideEnabled = settings.antennaGuide
        // M7m L29: the matcher's index for these options is built off the main actor before its first use.
        iptvLibrary.teamMatchOptions = settings.teamMatchOptions
        TeamMatcher.Index.prepareBundled(settings.teamMatchOptions)
        self.iptvLibrary = iptvLibrary
        let plex = PlexAccount(network: .live,
                               configFile: JSONConfigFile(url: directory.appending(path: PlexConfig.fileName),
                                                          defaultValue: PlexConfig()),
                               tokens: .keychain)
        self.plex = plex
        let settingsModel = SettingsModel(settings: settings, items: items, environment: makeSettingsEnvironment(kiosk: kiosk),
                                          bindings: bindings)
        let youtube = YouTubeController(userAgent: YouTubeConfig.userAgent(override: settings.youtubeUserAgent),
                                        castEnabled: settings.youtubeCastEnabled)
        self.youtube = youtube
        let liveTV = LiveTVModel(player: MPVPlayerController(), makePlayer: { MPVPlayerController() }, library: iptvLibrary)
        liveTV.channelUpMovesUpList = settings.channelUpMovesUpList
        self.liveTV = liveTV
        #if DEBUG
        muteLiveTVForDebugIfAsked(liveTV)
        #endif
        var liveShelf = LiveShelfSource.library(iptvLibrary)
        liveShelf.defaultChannel = { [weak liveTV] in liveTV?.defaultPreviewChannelID }
        // M7c L24.
        liveTV.prefetchLogos = { ChannelLogoCache.shared.prefetch($0) }
        liveTV.prefetchStreams = { StreamResolver.shared.prefetch($0) }
        // M7c L30: the loopback relay mpv loads Live TV through.
        HLSRelay.shared.start()
        // M7c L31: a channel highlighted in the guide starts loading before Select.
        liveTV.warmStream = { url in
            Task { HLSRelay.shared.prefetch(await StreamResolver.shared.resolve(url)) }
        }
        ChannelLogoCache.shared.pruneDisk()
        let topShelf = TopShelfModel(live: liveShelf, plex: plex)
        let router = AppRouter(items: items, launcher: launcher, settings: settingsModel, youtube: youtube,
                               liveTV: liveTV, pinStore: .keychain, tileArt: TileArtStore(), topShelf: topShelf)
        topShelf.onChange = { [weak router] in router?.shelfContentChanged() }
        let windowController = KioskWindowController(
            rootView: LauncherRootView(router: router, youtube: youtube, liveTV: liveTV),
            hidesCursor: settings.cursorAutoHide
        )
        self.inputRouter = inputRouter
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        router.onQuit = { [weak self] in
            self?.allowsTermination = true
            // Not from inside applicationShouldTerminate.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        router.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show(reason: "appQuit") }
        launcher.onOpened = { [weak self] in self?.kioskGuard.opened(bundleIDs: $0) }
        // Leanback's own exit (Back at its top level); it may fire several times, going home is idempotent.
        // M7c L32: on the start tile, like Home.
        youtube.onExit = { [weak router] in
            if router?.screen == .youtube { router?.goHomeToStartTile() }
        }
        // M7h step 13e: status changes refresh only their part, and only while Settings shows.
        iptvLibrary.onStatusChange = { [weak router] in router?.settings.refreshStatus(.iptv) }
        iptvLibrary.onLineupChange = { [weak router] in router?.playlistDidChange() }
        // M7j L18: a channel scan stops MMTVL's own antenna streams first.
        iptvLibrary.stopAntennaStreams = { [weak liveTV] in liveTV?.stopAntennaStreams() }
        plex.onChange = { [weak router] in
            router?.settings.refreshStatus(.plex)
            router?.shelfContentChanged()
        }
        // M7b L21: Home on MMTVL also ends a mirroring session.
        inputRouter.handler = { [weak self, weak router] command, isRepeat in
            if command == .home {
                self?.endMirroringIfNeeded()
                self?.kioskGuard.homePressed()
                // M7h re-review medium: Home in MMTVL after Exit to Desktop ends the exit (the lock comes back).
                self?.windowController?.endExitToDesktop()
            }
            return router?.handle(command, isRepeat: isRepeat) ?? false
        }
        inputRouter.onScrollWheel = { [weak router] deltaY, precise in router?.scrollWheel(deltaY: deltaY, precise: precise) }
        // M7m L19: a button Remote Buttons learns wakes the idle dimmer.
        inputRouter.onTriggerCaptured = { [weak router] in router?.wakeFromIdle(by: "a learnt button") }
        inputRouter.onGlobalCommand = { [weak self] command in self?.handleGlobal(command) }
        // Reads the current setting, which Settings can change live.
        inputRouter.onCommandDispatched = { [weak self] in
            if self?.hidesCursor == true { NSCursor.setHiddenUntilMouseMoves(true) }
            self?.router?.noteActivity()
        }
        router.startTileID = settings.homeStartTile
        router.focusStartTile(id: router.startTileID)
        router.livePreviewEnabled = settings.homeLivePreview
        router.glassStyle = settings.glassStyle
        OverlayToast.shared.glassStyle = settings.glassStyle
        router.homeVersionLabel = settings.showVersionOnHome ? AppVersion.current.label : nil
        router.homeExitDelay = Theme.homeExitDuration
        router.isAppActive = NSApp.isActive
        setUpScreenSaver(router: router)
        observeScreensSleep()
        observeScreenParameters()
        observeDisplayHotplugs()
        inputRouter.start()

        // L2: global input is off in -windowed mode, so the dev Mac keeps its Home key.
        if kiosk && settings.globalInputEnabled {
            startGlobalInput(showOnboarding: true)
        }
        if settings.controllersEnabled {
            startControllers()
        }
        setUpSiriRemote(inputRouter: inputRouter)
        setUpReceiver()
        setUpTV()
        setUpVolume()
        setUpPower()
        if kiosk {
            LoginItem.apply(enabled: settings.launchAtLogin)
            observeWake()
            observeDisplayWake()
            observePowerOff()
        }
        updateKioskLock()
        setUpPhoneRemote(inputRouter: inputRouter, router: router)
        setUpCasting()

        windowController.show(reason: "launch")
        setUpReflector()

        // M4 L4/L5: channels are fetched at every launch; the guide only when stale. M7j L4: the antenna's tuners
        // are searched for at the same time.
        if iptvLibrary.canHaveLiveSource {
            Task { await iptvLibrary.refreshAtLaunch() }
        }
        startIPTVRefreshTimer()
        startRemoteBatteryPolling()
        setUpUpdater(kiosk: kiosk)
        #if DEBUG
        showToastDemo()
        showSettingsDemo()
        showPowerMenuDemo()
        #endif
    }

    #if DEBUG
    /// M7j step 5 (Debug builds only): `-liveTVMuted YES` starts every Live TV player muted (the pool's players made
    /// later too, `LiveTVModel.configure`), and the app volume route can't unmute them (`setUpVolume`): playback
    /// checks on the dev Mac make no sound.
    static var liveTVMutedForDebug: Bool { UserDefaults.standard.bool(forKey: "liveTVMuted") }

    private func muteLiveTVForDebugIfAsked(_ liveTV: LiveTVModel) {
        guard Self.liveTVMutedForDebug else { return }
        liveTV.setAppVolume(0, muted: true)
        Logger(subsystem: "dev.mmtvl.launcher", category: "MPV").notice("Live TV muted (Debug)")
    }
    #endif

    #if DEBUG
    /// M7h step 6 (Debug builds only): `-toastDemo "Trackpad On"` (optional `-toastDemoSymbol <SF Symbol>`) shows
    /// the toast 5 s after launch, time to bring another app forward and check it stays in front.
    private func showToastDemo() {
        guard let text = UserDefaults.standard.string(forKey: "toastDemo"), !text.isEmpty else { return }
        let symbol = UserDefaults.standard.string(forKey: "toastDemoSymbol") ?? "cursorarrow.motionlines"
        Task {
            try? await Task.sleep(for: .seconds(5))
            OverlayToast.shared.show(text, symbol: symbol)
        }
    }
    #endif

    #if DEBUG
    /// M7h step 11 (Debug builds only): `-settingsDemo "audioTV/receiver"` opens Settings on those pages 2 s after
    /// launch (no PIN), and `-settingsDemoFocus <row id>` focuses a row: screenshots of Settings without a remote.
    private func showSettingsDemo() {
        guard let path = UserDefaults.standard.string(forKey: "settingsDemo"), !path.isEmpty else { return }
        let focus = UserDefaults.standard.string(forKey: "settingsDemoFocus")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let router = self?.router else { return }
            router.openSettings()
            for name in path.split(separator: "/") {
                guard let page = Self.demoPage(String(name)) else { continue }
                // The row that opens it stays selected in the parent column.
                let settings = router.settings
                if let row = settings.sections.flatMap(\.rows).first(where: { $0.action == .push(page) }) {
                    settings.focus(rowID: row.id)
                }
                settings.perform(.push(page))
            }
            if let focus { router.settings.focus(rowID: focus) }
        }
    }

    /// M7h step 12 (Debug builds only): `-powerMenuDemo settings|liveTV|youtube|home` opens that screen 2 s after
    /// launch, then sends `-powerMenuDemoCommands "powerMenu,down,pause,back"` (command names, one a second; `pause`
    /// waits 5 s) through `AppRouter.handle`, as a bound key would: screenshots of the menu without a remote or an
    /// unlocked screen. In this mode the power button and the menu's items only log; nothing sleeps or restarts.
    private func showPowerMenuDemo() {
        guard let screen = UserDefaults.standard.string(forKey: "powerMenuDemo"), !screen.isEmpty, let router else { return }
        let steps = (UserDefaults.standard.string(forKey: "powerMenuDemoCommands") ?? "powerMenu")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        router.onPowerButton = { PowerController.logger.notice("Power demo: the power button (not run)") }
        router.onPowerAction = { PowerController.logger.notice("Power demo: \($0.rawValue, privacy: .public) (not run)") }
        Task { [weak router] in
            try? await Task.sleep(for: .seconds(2))
            guard let router else { return }
            switch screen {
            case "settings": router.openSettings()
            case "liveTV": router.openLiveTV()
            case "youtube": router.openYouTube()
            default: break
            }
            for step in steps {
                try? await Task.sleep(for: .seconds(step == "pause" ? 5 : 1))
                guard let command = RemoteCommand(rawValue: step) else { continue }
                PowerController.logger.notice("Power demo: \(command.rawValue, privacy: .public)")
                _ = router.handle(command)
            }
        }
    }

    private static func demoPage(_ name: String) -> SettingsPage? {
        switch name {
        case "remoteInput": .remoteInput
        case "remoteButtons": .remoteButtons
        case "siriRemote": .siriRemote
        case "audioTV": .audioTV
        case "receiver": .receiver
        case "tv": .tv
        case "receiverBrand": .receiverBrand
        case "receiverPort": .receiverPort
        case "receiverMaxVolume": .receiverMaxVolume
        case "tvBrand": .tvBrand
        case "receiverConnection": .receiverConnection
        case "receiverAddress": .addressEntry(.receiver)
        case "tvAddress": .addressEntry(.tv)
        case "system": .system
        case "glassStyle": .glassStyle
        // M15 step 8: `-settingsDemo "system/softwareUpdate"`, with `-updatePreview <state>`.
        case "softwareUpdate": .softwareUpdate
        case "automaticUpdates": .automaticUpdates
        // M7j step 9: `-settingsDemo "liveTV/antenna/antennaChannels"`.
        case "liveTV": .liveTV
        case "antenna": .antenna
        case "antennaChannels": .antennaChannels
        default: nil
        }
    }
    #endif

    /// M15: the updater, after the battery polling. Release builds in kiosk mode run Sparkle (L4); Debug builds
    /// and `-windowed` are off, with no request; `-updatePreview <state>` (Debug, L13) runs a fake in that state.
    private func setUpUpdater(kiosk: Bool) {
        var mode = settings.automaticUpdates
        var made: SoftwareUpdater?
        #if DEBUG
        if let preview = UpdatePreview.requested {
            made = SoftwareUpdater(engine: FakeUpdaterEngine(preview: preview), feed: .current, hooks: updaterHooks())
            // A staged update is held only in the automatic modes.
            if preview == .ready && mode == .off { mode = .whenIdle }
        }
        #endif
        if made == nil {
            if let reason = SoftwareUpdater.offReason(debugBuild: SoftwareUpdater.isDebugBuild, windowed: !kiosk) {
                made = SoftwareUpdater(off: reason)
            } else {
                made = SoftwareUpdater(engine: SparkleEngine(), feed: .current, hooks: updaterHooks())
            }
        }
        guard let updater = made else { return }
        self.updater = updater
        // Step 8: Settings' Software Update rows and the home notice follow the status.
        updater.onStatusChange = { [weak self, weak updater] _ in
            guard let router = self?.router else { return }
            router.settings.refreshStatus(.updates)
            router.homeUpdateLabel = updater?.homeLabel
        }
        updater.start(checks: settings.updateChecks, mode: mode)
        router?.homeUpdateLabel = updater.homeLabel
    }

    private func updaterHooks() -> SoftwareUpdater.Hooks {
        SoftwareUpdater.Hooks(
            allowQuit: { [weak self] in self?.updateQuitAllowed = true },
            revokeQuit: { [weak self] in self?.updateQuitAllowed = false },
            snapshot: { [weak self] in self?.updateIdleSnapshot() ?? SoftwareUpdater.notIdle },
            writeMarker: { Self.writeUpdateRelaunchMarker() },
            deleteMarker: { UpdateRelaunchMarker.delete(from: LaunchItemStore.defaultDirectory) },
            showToast: { OverlayToast.shared.show($0, symbol: "arrow.down.circle") }
        )
    }

    /// M15: what the idle loop sees (the one place that builds it; step 6b: the receiver and input since Power-off).
    private func updateIdleSnapshot() -> UpdateIdleSnapshot {
        let screen = router?.screen
        return UpdateIdleSnapshot(
            mmtvlFrontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
            exitedToDesktop: windowController?.isExitedToDesktop == true,
            mirroring: reflector?.isMirroring == true,
            poweredOffByMMTVL: power?.poweredOffByMMTVL == true,
            screenSaverOurs: screenSaver.isRunning && screenSaver.startedByMMTVL,
            stillPhase: router?.idlePhase ?? .awake,
            videoPlaying: screen == .youtube || (screen == .liveTV && liveTV?.isShowingVideo == true),
            receiverOn: receiverPowerWatch.isOn,
            inputSincePowerOff: router?.inputSincePowerOff == true,
            hour: Calendar.current.component(.hour, from: Date())
        )
    }

    /// M15 L8: before an idle install's block, with the TV off.
    private static func writeUpdateRelaunchMarker() {
        do {
            try UpdateRelaunchMarker(poweredOff: true, written: Date()).write(to: LaunchItemStore.defaultDirectory)
        } catch {
            // The domain and code only: the error's text names the file's path.
            let error = error as NSError
            powerLogger.error("Power: couldn't save the update relaunch marker: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
    }

    /// Settings → System → Relaunch MMTVL and the power menu's Relaunch (L15): a staged update installs (Sparkle
    /// relaunches MMTVL after it); otherwise `AppRelauncher` with the kiosk lock's quit guard lifted.
    private func relaunch() {
        if updater?.installStagedForRelaunch() == true { return }
        AppRelauncher.relaunch(allowTermination: { [weak self] in self?.allowsTermination = true })
    }

    /// M7f L8: at launch, every 5 minutes, and when the home screen appears (`AppRouter.onRefreshRemoteBattery`).
    private func startRemoteBatteryPolling() {
        router?.onRefreshRemoteBattery = { [weak self] in self?.refreshRemoteBattery() }
        refreshRemoteBattery()
        remoteBatteryTask?.cancel()
        remoteBatteryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { return }
                self?.refreshRemoteBattery()
            }
        }
    }

    private func refreshRemoteBattery() {
        let level = RemoteBattery.current()
        if router?.remoteBatteryLevel != level { router?.remoteBatteryLevel = level }
    }

    /// M7f L5 (D40): every 15 minutes the playlist (10 min staleness), then the guides (12 h), in windowed mode too.
    /// M7j: also the antenna's lineup and, when due (L10), the antenna guide (`refreshIfStale`).
    /// A source pasted later is picked up by the next tick.
    private func startIPTVRefreshTimer() {
        iptvRefreshTask?.cancel()
        iptvRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(IPTVLibrary.autoRefreshInterval))
                guard !Task.isCancelled, let library = self?.iptvLibrary else { return }
                if library.canHaveLiveSource { await library.refreshIfStale() }
            }
        }
        teamsRefreshTask?.cancel()
        teamsRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(IPTVLibrary.teamsRefreshInterval))
                guard !Task.isCancelled, let library = self?.iptvLibrary else { return }
                if !library.preferences.teams.isEmpty { await library.updateTeams() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        iptvRefreshTask?.cancel()
        teamsRefreshTask?.cancel()
        remoteBatteryTask?.cancel()
        updater?.cancelIdleLoop()
        siriRemote?.stop()   // closes the seized interfaces
        receiver?.stop()
    }

    /// M7 L7: an older `key-bindings.json` gets the defaults of the new commands once (only triggers not bound yet).
    /// M7h: revision 3 adds the Siri Remote and drops global plain letter/digit bindings (L2, L9).
    private func migrateBindings(_ bindings: KeyBindings) -> KeyBindings {
        let revision = settings.keyBindingsRevision
        guard revision < KeyBindings.currentRevision else { return bindings }
        let migration = bindings.migrated(fromRevision: revision)
        let migrated = migration.bindings
        for removed in migration.removedGlobal {
            Self.inputLogger.notice("Removed global binding \(TriggerName.describe(removed.trigger), privacy: .public)")
        }
        do {
            try bindingsFile?.save(StoredBindings(migrated.bindings))
            settings.keyBindingsRevision = KeyBindings.currentRevision
            try settingsFile?.save(settings)
            Self.logger.info("Key bindings updated from revision \(revision, privacy: .public) to \(KeyBindings.currentRevision, privacy: .public)")
        } catch {
            Self.logger.error("Failed to save key bindings: \(error.localizedDescription, privacy: .public)")
        }
        return migrated
    }

    /// M7h: bindings without any Siri Remote trigger (an older build rewrote the file after a rollback, keeping
    /// revision 3) get the Siri Remote defaults again. Someone who removed every Siri Remote binding gets them back too.
    private func restoreSiriRemoteBindings(_ bindings: KeyBindings) -> KeyBindings {
        guard !bindings.hasSiriRemoteBindings else { return bindings }
        let restored = bindings.addingSiriRemoteDefaults()
        Self.inputLogger.notice("No Siri Remote buttons; added the defaults")
        do {
            try bindingsFile?.save(StoredBindings(restored.bindings))
        } catch {
            Self.logger.error("Failed to save key bindings: \(error.localizedDescription, privacy: .public)")
        }
        return restored
    }

    /// M7h D43, L3: the Siri Remote, in kiosk and -windowed mode alike. Commands for other apps go through the
    /// same `ExternalRouter` as the phone's; trackpad mode's pointer goes through the phone's `PhonePointer` (L7).
    private func setUpSiriRemote(inputRouter: InputRouter) {
        let siriRemote = SiriRemoteInput(inputRouter: inputRouter, externalRouter: makeExternalRouter(inputRouter: inputRouter),
                                         pointer: { [weak self] action in
                                             guard let self else { return }
                                             // Security: off the screen edges while the kiosk lock is in force.
                                             phonePointer.perform(action, edgeInset: PointerMath.remoteEdgeInset(
                                                 isLockEffective: isLockEffective))
                                         },
                                         pointerGate: { [weak self] in
                                             // Security M1: only in an app the kiosk guard allows, suspended or not.
                                             self?.remoteInputGate() ?? .allowed
                                         },
                                         revealPointer: { [weak self] in
                                             // Step 13e (c): moves don't show an obscured pointer while a finger
                                             // is down; after a lift (or trackpad mode on) this one does.
                                             guard let self else { return }
                                             NSCursor.setHiddenUntilMouseMoves(false)
                                             phonePointer.reveal(edgeInset: PointerMath.remoteEdgeInset(
                                                 isLockEffective: isLockEffective))
                                         })
        // D44, L8: volume to the chosen route (the receiver first), with the toast.
        siriRemote.onVolume = { [weak self] action in self?.performVolume(action) }
        // L7: the pointer stays visible while trackpad mode is on; step 13e (c) QA: with auto-hide on and MMTVL in
        // front, it hides again when the mode ends (the double-press isn't a dispatched command).
        siriRemote.onTrackpadModeChange = { [weak self] isOn in
            guard let self else { return }
            windowController?.hidesCursor = hidesCursor
            if let hidden = CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: isOn, setting: settings.cursorAutoHide,
                                                                  isAppActive: NSApp.isActive) {
                NSCursor.setHiddenUntilMouseMoves(hidden)
            }
        }
        // Step 11 (QA major): Settings → Siri Remote → Status, and the battery, follow the remote coming and going.
        siriRemote.onConnectionChange = { [weak self] in
            self?.scheduleSettingsRefresh(.siriRemote, readingBattery: true)
        }
        siriRemote.swipesEnabled = settings.siriRemoteSwipes
        self.siriRemote = siriRemote
        if settings.siriRemoteEnabled { siriRemote.start() }
    }

    /// Step 11 (QA major): one Settings refresh on the next main-actor turn for any number of link or remote
    /// changes before it (never inside IOKit's or the transport's callbacks). Step 13e (build 25's Live TV skip):
    /// only `parts`, and only while Settings shows; opening Settings (or coming back to it) re-reads everything.
    private func scheduleSettingsRefresh(_ parts: SettingsModel.StatusParts, readingBattery: Bool = false) {
        if readingBattery { settingsRefreshReadsBattery = true }
        settingsRefreshParts.formUnion(parts)
        guard !settingsRefreshScheduled else { return }
        settingsRefreshScheduled = true
        Task { [weak self] in
            guard let self else { return }
            settingsRefreshScheduled = false
            let parts = settingsRefreshParts
            settingsRefreshParts = []
            if settingsRefreshReadsBattery {
                settingsRefreshReadsBattery = false
                refreshRemoteBattery()
            }
            // Off screen, `refreshStatus(_:)` does nothing.
            router?.settings.refreshStatus(parts)
        }
    }

    /// M7h D44, L11, L17: the receiver, in kiosk and -windowed mode alike. No port or connection is opened while
    /// `receiverBrand` is `none`, or over the network without a usable `receiverHost`.
    private func setUpReceiver() {
        let receiver = ReceiverController(makeTransport: ReceiverController.systemTransport)
        self.receiver = receiver
        // Step 11: Settings → Audio & TV → Receiver → Status follows it (QA major: the link too).
        receiver.onStatusChange = { [weak self] in self?.scheduleSettingsRefresh(.receiver) }
        receiver.onLinkChange = { [weak self] in self?.scheduleSettingsRefresh(.receiver) }
        // M15 step 6b: the receiver's own power lines (no query of its own).
        receiver.onPowerChange = { [weak self] in self?.updateReceiverPower() }
        // Step 9c: the receiver over HDMI-CEC, on the tunnel the TV uses.
        let cecReceiver = CECAudioSystem(link: cecLink)
        cecReceiver.onStatusChange = { [weak self] in
            self?.scheduleSettingsRefresh(.cec)
            // M15 step 6b: the power status the CEC path already reads.
            self?.updateReceiverPower()
        }
        self.cecReceiver = cecReceiver
        configureReceiver()
    }

    /// M15 step 6b: the power of the receiver that is set up (HDMI-CEC, else serial or network; `unknown` without one).
    private func updateReceiverPower() {
        let power: ReceiverPower = if settings.receiverConnection == .cec {
            cecReceiver?.isEnabled == true ? ReceiverPower(cec: cecReceiver?.power) : .unknown
        } else {
            receiver?.power ?? .unknown
        }
        receiverPowerWatch.update(power)
    }

    /// From `settings.json`, at launch and (step 11) whenever Settings changes a receiver setting.
    private func configureReceiver() {
        guard let receiver else { return }
        // Step 9c: over HDMI-CEC, the serial and network receiver is off (no port or connection); its brand isn't used.
        let overCEC = settings.receiverConnection == .cec
        if cecReceiver?.isEnabled == true || overCEC { cecReceiver?.configure(enabled: overCEC) }
        if overCEC {
            if receiver.brand != .none { receiver.configure(brand: .none, link: .serial(path: nil)) }
            Self.receiverLogger.notice("Receiver: HDMI-CEC")
            return
        }
        guard settings.receiverBrand != .none else {
            if receiver.brand != .none { receiver.configure(brand: .none, link: .serial(path: nil)) }
            Self.receiverLogger.notice("Receiver: not set up")
            return
        }
        switch settings.receiverConnection {
        case .serial:
            receiver.configure(brand: settings.receiverBrand, serialPort: settings.receiverSerialPort)
        case .cec:
            break
        case .network:
            guard let host = settings.receiverHost.flatMap(LANAddress.normalized) else {
                receiver.configure(brand: .none, link: .serial(path: nil))
                Self.receiverLogger.notice("Receiver: \(self.settings.receiverBrand.rawValue, privacy: .public) over the network, no address set")
                return
            }
            // A name ("receiver.lan") is allowed; the transport checks that it resolved to a LAN address.
            guard LANAddress.isAllowedReceiverHost(host) else {
                receiver.configure(brand: .none, link: .serial(path: nil))
                // Never the value itself: a pasted URL could carry credentials.
                Self.receiverLogger.notice("Receiver: receiverHost (\(host.count, privacy: .public) characters) isn't a LAN address or host name; not connecting")
                return
            }
            receiver.configure(brand: settings.receiverBrand,
                               link: .network(host: host, port: settings.validatedReceiverNetworkPort))
        }
    }

    /// M7h L18: the TV, from `tvBrand`, `tvHost` and `tvMAC`. Nothing is sent to it here.
    private func setUpTV() {
        tv = TVController()
        let cec = HDMICEC(link: cecLink)
        // Settings → Audio & TV → TV → Status follows it.
        cec.onAvailabilityChange = { [weak self] in self?.scheduleSettingsRefresh(.cec) }
        self.cec = cec
        configureTV()
    }

    /// From `settings.json`, at launch and (step 11) whenever Settings changes a TV setting. Sends nothing.
    private func configureTV() {
        guard let tv else { return }
        tv.configure(brand: settings.tvBrand, host: settings.tvHost, mac: settings.tvMAC)
        cec?.configure(brand: settings.tvBrand)
        guard settings.tvBrand != .none else {
            Self.tvLogger.notice("TV: not set up")
            return
        }
        if settings.tvBrand == .cec, let cec {
            // Read-only: the tunnel's state is logged (category CEC); nothing is sent.
            Self.tvLogger.notice("TV: HDMI-CEC")
            Task { await cec.refreshAvailability() }
            return
        }
        guard let host = tv.host else {
            Self.tvLogger.notice("TV: \(self.settings.tvBrand.rawValue, privacy: .public), no usable address set")
            return
        }
        // The host only, never the MAC.
        Self.tvLogger.notice("TV: \(self.settings.tvBrand.rawValue, privacy: .public) at \(host, privacy: .public), \(tv.mac == nil ? "no MAC (can't turn on)" : "MAC set", privacy: .public)")
    }

    /// `cursorAutoHide`, except while the Siri Remote's trackpad mode is on (M7h L7).
    private var hidesCursor: Bool {
        CursorAutoHide.hides(setting: settings.cursorAutoHide, isTrackpadMode: siriRemote?.isTrackpadMode == true)
    }

    /// M7h L3: MMTVL in front (or brought forward, M7c L3) → MMTVL; Home → global Home; else a synthetic key.
    private func makeExternalRouter(inputRouter: InputRouter) -> ExternalRouter {
        ExternalRouter(
            isLauncherInFront: { [weak self] in NSApp.isActive || (self?.repairForeground() ?? false) },
            dispatch: { [weak inputRouter] command, isGlobal, isRepeat in
                inputRouter?.dispatchFromRemote(command, isGlobal: isGlobal, isRepeat: isRepeat)
            },
            canPostEvents: { SyntheticInput.canPost },
            postExternal: Self.postExternal,
            // M7m L19, L20: a press while the screen saver shows only ends it.
            endsScreenSaver: { [weak self] in
                self?.router?.endScreenSaverIfShowing(by: "Siri Remote \($0.rawValue)", command: $0) ?? false
            }
        )
    }

    /// A key or media key for the app in front (L5).
    private static func postExternal(_ key: ExternalKey) {
        switch key {
        case .key(let code): SyntheticInput.postKey(code)
        case .media(let media): SyntheticInput.postMediaKey(media)
        }
    }

    /// The volume routes (D25, D44) for the phone, the Siri Remote and the volume keys (L3a). After `setUpReceiver`:
    /// a set-up receiver is asked for its volume once, so it's ready (answering) before the first press.
    private func setUpVolume() {
        let volume = VolumeController(
            mode: { [weak self] in self?.settings.volumeMode ?? .auto },
            isLauncherActive: { NSApp.isActive },
            applyAppVolume: { [weak self] volume in
                var liveVolume = (level: volume.level, muted: volume.muted)
                #if DEBUG
                // M7j step 5: with `-liveTVMuted YES` no volume button unmutes Live TV.
                if Self.liveTVMutedForDebug { liveVolume = (0, true) }
                #endif
                self?.liveTV?.setAppVolume(liveVolume.level, muted: liveVolume.muted)
                self?.youtube?.setVolume(volume.level, muted: volume.muted)
            },
            receiver: receiver,
            maxDB: { [weak self] in self?.settings.validatedReceiverMaxDB ?? AppSettings().receiverMaxDB },
            cecReceiver: cecReceiver,
            tv: VolumeTVSelector(network: tv, cec: cec),
            tvVolumeEnabled: { [weak self] in self?.settings.tvVolumeEnabled ?? AppSettings().tvVolumeEnabled },
            // Build 25 security L2: "set up" follows the settings, not the controller (brand `none` without a host).
            receiverConfigured: { [weak self] in self?.settings.receiverIsSetUp ?? false }
        )
        self.volume = volume
        // QA minor 2: each time the receiver's transport comes up, it's asked once, so it's ready before a press.
        // M15 step 6b (user, 2026-11-24): and once for its power, after the volume query.
        receiver?.onLinkUp = { [weak volume, weak receiver] in
            volume?.receiverLinkUp()
            receiver?.queryPowerOnLinkUp()
        }
        volume.probeReceiverIfNeeded()
    }

    /// M7h D45, L14, L15: the Siri Remote's Power (short press and held), a key bound to Power or Power Menu, and the
    /// power menu's items. After `setUpReceiver` and `setUpTV`. The phone can't (PhoneRemote ignores both commands).
    private func setUpPower() {
        // Step 9c: a receiver over HDMI-CEC gets its own power frames only with a TV that isn't on HDMI-CEC.
        let powerReceiver = PowerReceiverSelector(receiver: receiver, cec: cecReceiver,
                                                  tvUsesCEC: { [weak self] in self?.cec?.isConfigured == true })
        let power = PowerController(tv: PowerTVSelector(network: tv, cec: cec), receiver: powerReceiver, effects: .system(relaunch: { [weak self] in
            self?.relaunch()
        }))
        power.onToast = { OverlayToast.shared.show($0, symbol: "power") }
        // L16 and the user decision of 2026-11-06: Plex is marked (frontmost or not), then MMTVL's home screen comes
        // forward like a global Home (Exit to Desktop ends, as with Home).
        power.onPowerOn = PowerController.powerOnHandler(launcher: launcher, goHome: { [weak self] in
            self?.goHomeFromAnywhere(reason: "powerOn")
        })
        // M15 L16: Power-off stops MMTVL's own playback and goes home before the TV is told to turn off (both the
        // short press and the power menu's Turn Off TV & Receiver run `runOff`).
        power.onPowerOff = { [weak self] in
            // M15 step 6b: the receiver's "off" that follows is this Power-off's; input from now on counts.
            self?.receiverPowerWatch.noteOwnPowerOff()
            self?.router?.notePowerOff()
            self?.router?.stopPlaybackForPowerOff()
            self?.goHomeFromAnywhere(reason: "powerOff")
            PowerController.logger.notice("Power: stopped playback, home")
        }
        // M15 step 6b (D45 amended): the receiver turned off without MMTVL's Power (the TV's own remote, the receiver
        // following over HDMI-CEC; or the receiver's remote): the same first half, nothing sent, Power unchanged.
        let receiverTurnedOff = ReceiverPowerWatch.turnedOffHandler(
            stopPlayback: { [weak self] in self?.router?.stopPlaybackForPowerOff() },
            goHome: { [weak self] in self?.goHomeFromAnywhere(reason: "receiverOff") }
        )
        // On the next main-actor turn, never inside the transport's or the CEC check's callback (like
        // `scheduleSettingsRefresh`).
        receiverPowerWatch.onTurnedOff = { Task { receiverTurnedOff() } }
        self.power = power
        // M15 L8: an update installed during Power-off left "the TV is off" behind; read once, deleted.
        if UpdateRelaunchMarker.take(from: LaunchItemStore.defaultDirectory, now: Date()) != nil {
            power.restorePoweredOff()
            PowerController.logger.notice("Power: still off after an update")
        }
        guard let router else { return }
        router.onPowerButton = { [weak power] in power?.powerButton() }
        router.onPowerAction = { [weak self] action in self?.performPowerAction(action) }
        // From any app: Power Menu brings MMTVL forward first (D35), so the menu shows over the app in front and the
        // remote's commands reach it; Cancel hands the screen back to that app (U1).
        powerMenuPresenter = PowerMenuPresenter(
            router: router,
            isLauncherActive: { NSApp.isActive },
            frontApp: PowerMenuPresenter.systemFrontApp,
            // QA minor: not a Home, so it doesn't end Exit to Desktop (the lock stays off and Cancel goes back).
            bringForward: { [weak self] in self?.windowController?.show(reason: KioskWindowController.powerMenuReason) },
            returnToApp: PowerMenuPresenter.systemReturn(to:),
            // Security (re-review medium): only an app the kiosk guard allows while the lock is in force.
            mayReturn: { [weak self] app in
                guard let self else { return false }
                return PowerMenuPresenter.mayReturn(to: app, isLockInForce: isLockEffective, kioskGuard: kioskGuard)
            },
            // After Exit to Desktop: hides MMTVL again, or ends the exit (re-review medium).
            desktopExit: windowController
        )
        siriRemote?.onPower = { [weak self] command in self?.powerMenuPresenter?.handle(command) }
    }

    /// L15: an item of the power menu (Relaunch and Restart after the PIN, when one is set).
    private func performPowerAction(_ action: PowerMenuAction) {
        guard let power else { return }
        switch action {
        case .turnOff: power.turnOff()
        case .sleepMac: power.sleepMac()
        case .relaunch: power.relaunch()
        case .restartMac: power.restartMac()
        case .cancel: break
        }
    }

    /// The Siri Remote's volume buttons and the volume keys the event tap takes (L3a), with the L8 toast.
    private func performVolume(_ action: VolumeAction) {
        guard let volume else { return }
        volume.perform(action) { [weak self] outcome in
            // Step 13b: the live Show Volume setting, read at each press.
            let enabled = self?.settings.volumeToast ?? AppSettings().volumeToast
            guard let message = VolumeToast.message(for: outcome, enabled: enabled) else { return }
            OverlayToast.shared.show(message.text, symbol: message.symbol)
        }
    }

    /// Security M1 (Siri Remote), pre-release review medium (phone): while the kiosk lock is in force, remote pointer
    /// input, text and keys act only in an app the kiosk guard allows, suspended or not.
    private func remoteInputGate() -> KioskGuard.PointerGate {
        let front = NSWorkspace.shared.frontmostApplication
        return kioskGuard.pointerGate(isLockInForce: isLockEffective, frontBundleID: front?.bundleIdentifier,
                                      isSelf: front?.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }

    /// M5: the phone remote server and its coordinator (D24); volume through `setUpVolume`'s controller.
    private func setUpPhoneRemote(inputRouter: InputRouter, router: AppRouter) {
        let server = RemoteServer()
        let phoneRemote = PhoneRemote(transport: server, store: .keychain, environment: PhoneRemoteEnvironment(
            isLauncherActive: { NSApp.isActive },
            dispatch: { [weak inputRouter] command, isGlobal in inputRouter?.dispatchFromRemote(command, isGlobal: isGlobal) },
            canPostEvents: { SyntheticInput.canPost },
            postExternal: Self.postExternal,
            // M7f L11: in Live TV, phone text types into its search (no synthetic events); YouTube gets keys.
            typeEdit: { [weak self, weak router] edit in
                if router?.screen == .liveTV, NSApp.isActive {
                    // M7m L19 (QA step 6, finding 3): typing is activity and wakes the dimmer; the text still goes in.
                    router?.wakeFromIdle(by: "phone text")
                    self?.liveTV?.typeText(edit)
                    return
                }
                SyntheticInput.deleteBackward(edit.deletions)
                SyntheticInput.type(edit.insertion)
            },
            postReturn: { [weak self, weak router] in
                if router?.screen == .liveTV, NSApp.isActive {
                    router?.wakeFromIdle(by: "phone text")
                    self?.liveTV?.submitText()
                    return
                }
                SyntheticInput.postKey(CGKeyCode(kVK_Return))
            },
            launcherAcceptsText: { [weak router] in router?.screen == .youtube || router?.screen == .liveTV },
            frontAppName: { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac" },
            volume: { [weak self] action, done in
                guard let volume = self?.volume else { return done(.unavailable(VolumeController.unavailableMessage)) }
                volume.perform(action) { done($0.feedback) }
            },
            now: { Date() },
            makeCode: { PairingCode.random() },
            makeToken: { PhoneToken.make() },
            pointer: { [weak self] action, edgeInset in self?.phonePointer.perform(action, edgeInset: edgeInset) },
            repairForeground: { [weak self] in self?.repairForeground() ?? false },
            // M7m L19, L20: phone input while the screen saver shows only ends it.
            endsScreenSaver: { [weak router] in router?.endScreenSaverIfShowing(by: $0, command: $1) ?? false },
            // Security (pre-release review, medium): the Siri Remote's kiosk gate and edge inset.
            inputGate: { [weak self] in self?.remoteInputGate() ?? .allowed },
            pointerEdgeInset: { [weak self] in PointerMath.remoteEdgeInset(isLockEffective: self?.isLockEffective ?? false) }
        ))
        server.onMessage = { [weak phoneRemote] id, data in phoneRemote?.receive(data, from: id) }
        server.onSessionClosed = { [weak phoneRemote] id in phoneRemote?.sessionClosed(id) }
        server.onStateChange = { [weak router] in router?.settings.refreshStatus(.phoneRemote) }
        phoneRemote.onStatusChange = { [weak router] in router?.settings.refreshStatus(.phoneRemote) }
        remoteServer = server
        self.phoneRemote = phoneRemote
        if settings.phoneRemoteEnabled { startPhoneRemote() }
        observeAppActivation()
    }

    /// M7c L3: the window shows but MMTVL isn't active and nothing else is in front (after a launched app quit).
    private func repairForeground() -> Bool {
        guard !AppEnvironment.windowedMode, !NSApp.isActive,
              let windowController, windowController.window.isVisible
        else { return false }
        let front = NSWorkspace.shared.frontmostApplication
        guard front == nil || front?.bundleIdentifier == "com.apple.finder"
                || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return false }
        // M7h: one repair at a time; commands meanwhile wait in `InputRouter` (the latest one is delivered).
        if inputRouter?.isRepairingForeground == true { return true }
        inputRouter?.foregroundRepairStarted()
        Task { [weak self] in
            let succeeded = await windowController.bringForward(reason: "repair")
            self?.inputRouter?.foregroundRepairFinished(succeeded: succeeded)
        }
        return true
    }

    /// M7b D30: the YouTube DIAL receiver, in kiosk and -windowed mode alike.
    private func setUpCasting() {
        let bridge = CastBridge(
            isAppReady: { [weak self] in self?.youtube?.isDIALReady ?? false },
            forward: { [weak self] request in await self?.youtube?.handleDIAL(request) },
            launch: { [weak self] query in self?.castToTV(query: query) },
            didConnect: { [weak self] in self?.castToTV(query: nil) }
        )
        let receiver = CastReceiver(deviceID: settings.castDeviceID ?? UUID().uuidString.lowercased(),
                                    friendlyName: "MMTVL", bridge: bridge)
        receiver.onStateChange = { [weak self] in self?.router?.settings.refreshStatus(.casting) }
        castReceiver = receiver
        if settings.youtubeCastEnabled { receiver.start() }
    }

    /// M7b L4: a cast takes over the TV from any screen or app, without the PIN.
    private func castToTV(query: String?) {
        endMirroringIfNeeded()
        launcher.homePressed()
        router?.castYouTube(query: query)
        windowController?.show(reason: "cast")
    }

    /// M7b D32, L18–L22: keep Reflector running hidden and follow its mirroring sessions.
    private func setUpReflector() {
        let reflector = ReflectorMonitor(autoStart: settings.reflectorAutoStart)
        reflector.onSessionBegan = { [weak self] in
            // L20: leave Live TV/YouTube like Home (no PIN), then bring the mirrored screen forward.
            guard let self else { return }
            launcher.homePressed()
            router?.goHome()
            NSRunningApplication.runningApplications(withBundleIdentifier: ReflectorMonitor.bundleID).first?.activate()
        }
        reflector.onSessionEnded = { [weak self] in
            // L22: back to the home screen unless the user switched to another app on purpose. M7h QA Q1: not while
            // the power menu is open (opening it hid the mirrored window, which looks like the session ending).
            let front = NSWorkspace.shared.frontmostApplication
            guard ReflectorMonitor.showsHomeAfterSession(
                frontBundleID: front?.bundleIdentifier,
                frontIsSelf: front?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                hasFrontApp: front != nil,
                isPowerMenuOpen: self?.router?.powerMenu != nil)
            else { return }
            self?.router?.goHome()
            self?.windowController?.show(reason: "mirroringEnded")
        }
        reflector.onStatusChange = { [weak self] in self?.router?.settings.refreshStatus(.casting) }
        self.reflector = reflector
        reflector.start()
    }

    /// L21: Home or a YouTube cast during mirroring ends it first.
    private func endMirroringIfNeeded() {
        guard let reflector, reflector.isMirroring else { return }
        reflector.endMirroring()
    }

    private func startPhoneRemote() {
        let port = settings.validatedPhoneRemotePort
        guard let httpPort = NWEndpoint.Port(rawValue: UInt16(port)),
              let socketPort = NWEndpoint.Port(rawValue: UInt16(port + 1))
        else { return }
        Self.phoneLogger.info("Phone remote on port \(port)")
        remoteServer?.start(httpPort: httpPort, socketPort: socketPort)
    }

    private func stopPhoneRemote() {
        remoteServer?.stop()
        phoneRemote?.reset()
        Self.phoneLogger.info("Phone remote stopped")
    }

    /// L16: the phone shows which app is in front.
    private func observeAppActivation() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let isRegular = app?.activationPolicy == .regular
            let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                self?.phoneRemote?.frontAppChanged()
                self?.guardActivation(bundleID: bundleID, isRegular: isRegular, isSelf: isSelf)
            }
        }
    }

    /// M7c L8b: an app MMTVL didn't open came forward; take the screen back like Home.
    private func guardActivation(bundleID: String?, isRegular: Bool, isSelf: Bool) {
        kioskGuard.isEnabled = isLockEffective
        guard kioskGuard.appDidActivate(bundleID: bundleID, isRegular: isRegular, isSelf: isSelf) == .takeBack else { return }
        launcher.homePressed()
        router?.goHome()
        windowController?.show(reason: "guard")
    }

    /// What Settings → Phone Remote shows.
    private func phoneRemoteSettingsStatus() -> PhoneRemoteSettingsStatus {
        var status = PhoneRemoteSettingsStatus()
        switch remoteServer?.state ?? .stopped {
        case .stopped: break
        case .starting: status.problem = "Starting…"
        case .running: status.isRunning = true
        case .failed(let message): status.problem = message
        }
        if let ip = LocalAddress.primaryIPv4() {
            status.address = "http://\(ip):\(settings.validatedPhoneRemotePort)"
        }
        if let phoneRemote {
            status.pairingCode = phoneRemote.pairing?.code
            // Security (pre-release review, high): the QR code carries the 128-bit secret, not the typed code.
            if let address = status.address, let secret = phoneRemote.pairing?.secret {
                status.pairingURL = "\(address)/#pair=\(secret)"
            }
            status.pairingEnded = phoneRemote.pairingEnded
            status.pairingCodeLocked = phoneRemote.pairing?.isCodeLocked ?? false
            status.lastPairedName = phoneRemote.lastPairedName
            status.pairedCount = phoneRemote.pairedCount
            status.connectedCount = phoneRemote.connectedCount
        }
        status.canControlOtherApps = SyntheticInput.canPost
        return status
    }

    /// What Settings → Casting shows (M7b L14, L16).
    private func castingSettingsStatus() -> CastingSettingsStatus {
        var status = CastingSettingsStatus()
        if settings.youtubeCastEnabled {
            status.youtube = switch castReceiver?.state ?? .off {
            case .off: .off
            case .starting: .starting
            case .ready: .ready
            case .failed(let message): .failed(message)
            }
        }
        status.airPlay = airPlayState
        if let reflector, reflector.isInstalled {
            status.reflector = reflector.isMirroring ? .mirroring : reflector.isRunning ? .ready : .notRunning
        }
        let plexHTPC = "tv.plex.htpc"
        if !NSRunningApplication.runningApplications(withBundleIdentifier: plexHTPC).isEmpty {
            status.plexHTPC = .running
        } else if NSWorkspace.shared.urlForApplication(withBundleIdentifier: plexHTPC) != nil {
            status.plexHTPC = .notRunning
        }
        return status
    }

    private func refreshCasting() {
        Task {
            airPlayState = await AirPlayReceiverProbe.check()
            router?.settings.refreshStatus(.casting)
        }
    }

    /// What Settings → Plex shows (L15). Never tokens.
    private func plexSettingsStatus() -> PlexSettingsStatus {
        guard let plex else { return PlexSettingsStatus() }
        var status = PlexSettingsStatus()
        status.isSignedIn = plex.isSignedIn
        status.linkCode = plex.linkCode
        status.linkURL = plex.linkCode.map(PlexAPI.linkURL(code:))
        status.serverName = plex.serverName
        status.servers = plex.servers.map { server in
            PlexSettingsStatus.Server(id: server.clientIdentifier, name: server.name,
                                      detail: server.owned == false ? "Shared with you" : "Yours")
        }
        status.statusLine = plex.statusLine
        status.itemCount = plex.continueWatching.count
        status.hasNoServer = plex.status == .noServer && plex.servers.isEmpty
        status.needsServerChoice = plex.status == .noServer && plex.servers.count > 1
        return status
    }

    private func makeIPTVLibrary(directory: URL) -> IPTVLibrary {
        var epgStore: EPGStore?
        do {
            epgStore = try EPGStore.open(at: EPGStore.defaultURL)
        } catch {
            Self.logger.error("Guide storage unavailable: \(error.localizedDescription, privacy: .public)")
        }
        return IPTVLibrary(
            sources: .keychain,
            store: epgStore,
            network: .live,
            stateFile: JSONConfigFile(url: directory.appending(path: IPTVState.fileName), defaultValue: IPTVState()),
            overridesFile: JSONConfigFile(url: directory.appending(path: IPTVState.overridesFileName), defaultValue: [String: String]()),
            preferencesFile: JSONConfigFile(url: directory.appending(path: ChannelPreferences.fileName),
                                            defaultValue: ChannelPreferences()),
            // M7j: the live discovery and tuner HTTP; turned on from `settings.json` before the first refresh. L18: the
            // only place `livePost` is passed in (the channel scan's `lineup.post`); everywhere else posts nothing.
            antenna: AntennaSource(http: HDHomeRunHTTP(post: HDHomeRunHTTP.livePost))
        )
    }

    /// What Settings → Live TV shows. Times are time-only; hosts only (L2).
    private func iptvSettingsStatus() -> IPTVSettingsStatus {
        guard let library = iptvLibrary else { return IPTVSettingsStatus() }
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

        var status = IPTVSettingsStatus()
        status.hasPlaylist = library.hasPlaylist
        status.playlistHost = library.playlistHost
        status.channelCount = library.playlistChannels.count
        switch library.playlistStatus {
        case .idle: status.playlistLine = ""
        case .loading: status.playlistLine = "Loading…"
        case .loaded(let date): status.playlistLine = "Updated \(time(date))"
        case .failed(let message): status.playlistLine = "Failed: \(message)"
        }

        // M6b: one line per guide. Labels may show a guide's file name, never its query (L2).
        // M7f L4: then the pasted guides kept while the playlist's guide is used.
        let inUse = Set(library.guideSources.map(\.id))
        let unused = library.customGuideSources.filter { !inUse.contains($0.id) }.map { source in
            IPTVSettingsStatus.GuideSourceStatus(id: source.id, label: source.label, line: "Not in use (kept)",
                                                 isFromPlaylist: false, isInUse: false)
        }
        status.playlistNamesGuide = library.playlistNamesGuide
        status.guideSources = library.guideSources.map { source in
            let info = library.guideSourceInfo[source.id] ?? IPTVLibrary.GuideSourceInfo()
            func summary(_ updated: String) -> String {
                "\(info.programmeCount.formatted()) programmes · \(info.matchedChannels) channels · Updated \(updated)"
            }
            let line = switch info.status {
            case .loading: "Loading…"
            case .failed(let message): "Failed: \(message)"
            case .loaded(let date): summary(time(date))
            case .idle: library.state.guideImports[source.id]
                .map { summary($0.formatted(date: .abbreviated, time: .shortened)) } ?? "Not loaded yet"
            }
            return IPTVSettingsStatus.GuideSourceStatus(id: source.id, label: source.label, line: line,
                                                        isFromPlaylist: source.isFromPlaylist)
        } + unused
        status.customGuideCount = library.customGuideCount
        status.matchedChannelCount = library.matchedChannelCount

        // M6b L5: groups and hidden channels, in playlist order.
        let hiddenGroups = Set(library.preferences.hiddenGroups)
        let counts = Dictionary(grouping: library.channels, by: \.group).mapValues(\.count)
        status.groups = ChannelList.groups(of: library.channels).map { name in
            IPTVSettingsStatus.GroupStatus(name: name, channelCount: counts[name] ?? 0, isHidden: hiddenGroups.contains(name))
        }
        let hiddenChannels = Set(library.preferences.hiddenChannels)
        status.hiddenChannels = library.channels.filter { hiddenChannels.contains($0.id) }.map { channel in
            IPTVSettingsStatus.HiddenChannelStatus(id: channel.id, number: channel.number, name: channel.name, group: channel.group,
                                                   guideNumber: channel.guideNumber)
        }
        status.teams = library.preferences.teams
        library.fillAntennaSettings(&status)
        return status
    }

    /// L2: reads the clipboard on Select. Returns an error message, or nil after starting the save + refresh.
    private func pasteIPTVURL(_ kind: IPTVURLKind) -> String? {
        let text = NSPasteboard.general.string(forType: .string)
        switch ClipboardURL.parse(text) {
        case .failure(let problem):
            return ClipboardURL.message(for: problem)
        case .success(let url):
            Self.logger.info("Pasted a \(kind == .playlist ? "playlist" : "guide", privacy: .public) URL for \(url.host() ?? "?", privacy: .public)")
            guard let library = iptvLibrary else { return nil }
            switch kind {
            case .playlist:
                Task { await library.setPlaylistURL(url) }
            case .guide:
                switch library.guideAddProblem(url) {
                case .duplicate: return "That guide is already added"
                case .full: return "Up to \(IPTVLibrary.maxGuideSources) guides; remove one first"
                case nil: Task { await library.addGuideURL(url) }
                }
            }
            return nil
        }
    }

    /// A global binding fired while another app is frontmost.
    private func handleGlobal(_ command: RemoteCommand) {
        // M7h D45: a key bound to Power or Power Menu with Work in Other Apps.
        if powerMenuPresenter?.handleGlobal(command) == true { return }
        // Only Home is global by default; ignore others for now.
        guard command == .home else { return }
        goHomeFromAnywhere(reason: "home")
    }

    /// A global Home press, and (M7h user decision 2026-11-06) a power-on: the start tile, MMTVL in front. Like any
    /// show but the power menu's, it ends Exit to Desktop (the kiosk lock comes back).
    private func goHomeFromAnywhere(reason: String) {
        // M7b L21: Home during mirroring ends it.
        endMirroringIfNeeded()
        // D18: the other app keeps running. An app still starting won't take the screen back when it's up.
        kioskGuard.homePressed()
        launcher.homePressed()
        router?.goHomeToStartTile()
        windowController?.show(reason: reason)
    }

    /// L9: system wake (not display-only wake) returns to the launcher home screen,
    /// after a delay for the HDMI/AVR re-handshake.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        }
    }

    /// M7f L1: display wake only logs (no foreground repair, no Home; D18's go-home stays for system wake).
    private func observeDisplayWake() {
        displayObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Self.displayLogger.notice("Displays woke")
            // M7m L20: the idle dimmer's wait starts over.
            MainActor.assumeIsolated { self?.router?.screensDidWake() }
        })
    }

    /// M7f L1: logs screen changes; `KioskWindowController` still does the refit.
    private func observeScreenParameters() {
        displayObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let screens = NSScreen.screens
                let size = screens.first?.frame.size ?? .zero
                Self.displayLogger.notice("Screen parameters changed: \(screens.count) screens, main \(Int(size.width))×\(Int(size.height))")
            }
        })
    }

    /// M7h L16 (D45): each display added or removed marks Plex HTPC (if it runs and isn't in front) to restart on
    /// its next open.
    private func observeDisplayHotplugs() {
        hotplugMonitor.onEvent = { [launcher, weak self] _ in
            launcher.noteDisplayChange(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            // Step 9 (reopened): the DisplayPort proxies vanish while HPD is low; the tunnel opens them again.
            self?.cec?.noteDisplayChange()
            // Step 9c: a receiver over HDMI-CEC is asked again once the tunnel is back.
            self?.cecReceiver?.noteDisplayChange()
        }
        hotplugMonitor.start()
    }

    private func systemDidWake() {
        // M7m L20: after a system sleep (`willSleep` set the displays asleep), in case no display wake follows.
        router?.screensDidWake()
        Task {
            try? await Task.sleep(for: .seconds(2))
            router?.goHome()
            windowController?.show(reason: "wake")
            eventTap?.ensureEnabled()
            if settings.phoneRemoteEnabled, case .failed = remoteServer?.state {
                startPhoneRemote()
            }
            castReceiver?.restart()
            reflector?.systemDidWake()
            // M7f L5 (D40): the network may need a moment; a failure is logged and the next tick retries.
            // M7j L4: the antenna's tuners are searched for again.
            if let library = iptvLibrary, library.canHaveLiveSource { await library.refreshAfterWake() }
        }
    }

    /// M7c L6: the lock applies in kiosk mode with `kioskLock` on and the event tap running (Home must work).
    /// Exit to Desktop turns it off until the next show (`KioskWindowController.isExitedToDesktop`).
    private var lockConfigured: Bool {
        !AppEnvironment.windowedMode && settings.kioskLock && settings.globalInputEnabled && eventTap?.isRunning == true
    }

    private var isLockEffective: Bool {
        lockConfigured && windowController?.isExitedToDesktop != true
    }

    private func updateKioskLock() {
        windowController?.lockOptions = lockConfigured
    }

    /// M7c L16: display sleep and system sleep stop the Live TV preview.
    private func observeScreensSleep() {
        let center = NSWorkspace.shared.notificationCenter
        screensSleepObservers = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if name == NSWorkspace.screensDidSleepNotification { Self.displayLogger.notice("Displays slept") }
                MainActor.assumeIsolated { self?.router?.screensDidSleep() }
            }
        }
        // M7c L26: the screen saver stops the Live TV preview; its end counts as activity. M7m L20: `ScreenSaver`
        // follows it too; its `onStop` tells the router (`setUpScreenSaver`). Delivered at once (security medium):
        // AppKit holds distributed notifications back while MMTVL isn't active, which is when the screen saver shows.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenSaverDidStartNotification(_:)),
                                name: Notification.Name("com.apple.screensaver.didstart"), object: nil,
                                suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(screenSaverDidStopNotification(_:)),
                                name: Notification.Name("com.apple.screensaver.didstop"), object: nil,
                                suspensionBehavior: .deliverImmediately)
    }

    @objc private func screenSaverDidStartNotification(_ notification: Notification) {
        screenSaver.didStart()
        router?.screenSaverDidStart()
    }

    @objc private func screenSaverDidStopNotification(_ notification: Notification) {
        screenSaver.didStop()
    }

    /// M7m L20 (D51): the dimmer starts macOS's screen saver after `Theme.screenSaverAfterDim`; a press ends it. When
    /// it stops (`didstop`, or `end()` terminated it) the router wakes, and MMTVL comes back in front if it had
    /// started the screen saver (D35).
    private func setUpScreenSaver(router: AppRouter) {
        router.startScreenSaver = { [weak self] in self?.screenSaver.start() }
        router.endScreenSaver = { [weak self] in self?.screenSaver.end() }
        router.isScreenSaverEngineRunning = { [weak self] in self?.screenSaver.isEngineRunning ?? false }
        screenSaver.onStop = { [weak self] wasOurs in
            self?.router?.screenSaverDidStop()
            if wasOurs { self?.returnAfterScreenSaver() }
        }
    }

    /// MMTVL was in front when it started the screen saver: if it isn't again a moment after the screen saver ended,
    /// and nothing else took the screen (only the screen saver, Finder or nothing), it's brought forward.
    private func returnAfterScreenSaver() {
        Task { [weak self] in
            try? await Task.sleep(for: Theme.screenSaverEndCheckDelay)
            guard let self, !NSApp.isActive, let windowController, windowController.window.isVisible,
                  !windowController.isExitedToDesktop else { return }
            let front = NSWorkspace.shared.frontmostApplication
            guard front == nil || front?.bundleIdentifier == ScreenSaver.bundleID
                    || front?.bundleIdentifier == "com.apple.finder"
                    || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            else { return }
            windowController.show(reason: "screenSaverEnded")
        }
    }

    /// L9: a logout, restart or shutdown may always quit MMTVL.
    private func observePowerOff() {
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.allowsTermination = true }
        }
    }

    /// L9: a quit goes through without the PIN when it's allowed (logout, ⌘Q with the PIN, Relaunch), when the updater
    /// allowed it for an install (M15 L14, its own flag, security L-b), or without the kiosk lock. Pure.
    nonisolated static func quitSkipsPIN(allowsTermination: Bool, updateQuitAllowed: Bool, lockEffective: Bool) -> Bool {
        allowsTermination || updateQuitAllowed || !lockEffective
    }

    /// L9: ⌘Q and the Dock's Quit ask for the PIN while the kiosk lock is on.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.quitSkipsPIN(allowsTermination: allowsTermination, updateQuitAllowed: updateQuitAllowed,
                                 lockEffective: isLockEffective), let router else { return .terminateNow }
        Self.logger.info("Quit needs the PIN (kiosk lock)")
        router.requestQuit()
        if case .pin(.quit) = router.screen {
            windowController?.show(reason: "quit")
        }
        return .terminateCancel
    }

    /// Applies a Settings change live (L3) and saves `settings.json`.
    private func applySettings(_ new: AppSettings) {
        let old = settings
        settings = new
        do {
            try settingsFile?.save(new)
        } catch {
            Self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }

        // L8: kiosk-only settings are saved but not applied in -windowed mode.
        let kiosk = !AppEnvironment.windowedMode
        if kiosk && new.globalInputEnabled != old.globalInputEnabled {
            if new.globalInputEnabled {
                startGlobalInput(showOnboarding: false)
            } else {
                eventTap?.stop()
            }
        }
        if new.controllersEnabled != old.controllersEnabled {
            if new.controllersEnabled {
                startControllers()
            } else {
                controllers?.stop()
                controllers = nil
            }
        }
        // M7h step 11: receiver and TV changes apply at once.
        if new.receiverBrand != old.receiverBrand || new.receiverConnection != old.receiverConnection
            || new.receiverSerialPort != old.receiverSerialPort || new.receiverHost != old.receiverHost
            || new.receiverNetworkPort != old.receiverNetworkPort {
            configureReceiver()
        }
        if new.tvBrand != old.tvBrand || new.tvHost != old.tvHost || new.tvMAC != old.tvMAC {
            configureTV()
        }
        // Step 9c: the TV is asked whether it answers once TV volume is turned on, or its settings change.
        if new.tvVolumeEnabled != old.tvVolumeEnabled || new.tvBrand != old.tvBrand || new.tvHost != old.tvHost {
            volume?.tvSettingsChanged()
        }
        siriRemote?.swipesEnabled = new.siriRemoteSwipes
        if new.siriRemoteEnabled != old.siriRemoteEnabled {
            if new.siriRemoteEnabled {
                siriRemote?.start()
            } else {
                siriRemote?.stop()
            }
        }
        windowController?.hidesCursor = hidesCursor
        liveTV?.channelUpMovesUpList = new.channelUpMovesUpList
        if new.phoneRemoteEnabled != old.phoneRemoteEnabled {
            if new.phoneRemoteEnabled {
                startPhoneRemote()
            } else {
                stopPhoneRemote()
            }
        }
        if new.youtubeCastEnabled != old.youtubeCastEnabled {
            if new.youtubeCastEnabled {
                castReceiver?.start()
            } else {
                castReceiver?.stop()
            }
        }
        reflector?.autoStart = new.reflectorAutoStart
        router?.startTileID = new.homeStartTile
        router?.livePreviewEnabled = new.homeLivePreview
        router?.glassStyle = new.glassStyle
        OverlayToast.shared.glassStyle = new.glassStyle
        router?.homeVersionLabel = new.showVersionOnHome ? AppVersion.current.label : nil
        if new.usePlaylistGuide != old.usePlaylistGuide, let iptvLibrary {
            Task { await iptvLibrary.applyUsePlaylistGuide(new.usePlaylistGuide) }
        }
        if new.teamMatchOptions != old.teamMatchOptions, let iptvLibrary {
            Task { await iptvLibrary.applyTeamMatchOptions(new.teamMatchOptions) }
        }
        if new.antennaEnabled != old.antennaEnabled, let iptvLibrary {
            Task { await iptvLibrary.applyAntennaEnabled(new.antennaEnabled) }
        }
        if new.antennaGuide != old.antennaGuide, let iptvLibrary {
            Task { await iptvLibrary.applyAntennaGuide(new.antennaGuide) }
        }
        if new.updateChecks != old.updateChecks || new.automaticUpdates != old.automaticUpdates {
            updater?.apply(checks: new.updateChecks, mode: new.automaticUpdates)
        }
        updateKioskLock()
        if kiosk && new.launchAtLogin != old.launchAtLogin {
            LoginItem.apply(enabled: new.launchAtLogin)
        }
    }

    /// M7: a Remote Buttons edit applies at once everywhere (`InputRouter.bindings` is read on every event).
    private func applyBindings(_ bindings: KeyBindings) {
        inputRouter?.bindings = bindings
        do {
            try bindingsFile?.save(StoredBindings(bindings.bindings))
        } catch {
            Self.logger.error("Failed to save key bindings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies a tile edit from Settings and saves `launch-items.json`.
    private func applyItems(_ items: [LaunchItem]) {
        router?.setItems(items)
        do {
            try LaunchItemStore().save(items)
        } catch {
            Self.logger.error("Failed to save launch items: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startControllers() {
        guard let inputRouter, controllers == nil else { return }
        let controllers = ControllerInput(inputRouter: inputRouter, monitorInBackground: !AppEnvironment.windowedMode)
        controllers.start()
        self.controllers = controllers
    }

    /// Starts the event tap; when it can't be created, optionally shows the onboarding (L14) and waits for the grant.
    private func startGlobalInput(showOnboarding: Bool) {
        guard let inputRouter else { return }
        let eventTap = self.eventTap ?? GlobalEventTap(inputRouter: inputRouter)
        eventTap.lockActive = { [weak self] in self?.isLockEffective ?? false }
        // M7h L3a: the volume keys, from any app, while they go to the receiver.
        eventTap.volumeKeysConsumed = { [weak self] in self?.volume?.consumesVolumeKeys() ?? false }
        eventTap.onVolume = { [weak self] action in self?.performVolume(action) }
        self.eventTap = eventTap
        if eventTap.start() {
            updateKioskLock()
            return
        }
        if showOnboarding {
            router?.showAccessibilityOnboarding()
        }
        startAccessibilityWait()
    }

    private func requestAccessibility() {
        kioskGuard.openedSystemSettings()
        AccessibilityPermission.request()
        // Harmless when granted; prompts if PostEvent is ever separate from Accessibility (M5).
        SyntheticInput.requestAccess()
        startAccessibilityWait()
    }

    /// Idempotent. L7: keeps polling even after "Not now", so a later grant still activates the tap.
    /// Also runs in -windowed mode, so granting from Settings brings MMTVL back; the tap starts in kiosk mode only.
    private func startAccessibilityWait() {
        guard accessibilityWaitTask == nil, !AccessibilityPermission.isTrusted else { return }
        accessibilityWaitTask = Task { [weak self] in
            await AccessibilityPermission.waitUntilTrusted()
            guard let self, AccessibilityPermission.isTrusted else { return }
            accessibilityWaitTask = nil
            if !AppEnvironment.windowedMode && settings.globalInputEnabled {
                if let eventTap {
                    eventTap.start()
                } else {
                    startGlobalInput(showOnboarding: false)
                }
                updateKioskLock()
            }
            if router?.screen == .accessibilityOnboarding { router?.goHome() }
            router?.settings.refreshStatusIfShowing()
            // Come back from System Settings.
            windowController?.show(reason: "accessibilityGranted")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // L10: e.g. back from granting Accessibility or approving the login item in System Settings (step 13e: only
        // while Settings shows; opening it re-reads everything).
        router?.settings.refreshStatusIfShowing()
        router?.isAppActive = true
        // M7m L20 (QA minor): a later screen saver stop isn't one MMTVL must come back from.
        screenSaver.appDidBecomeActive()
        windowController?.appDidBecomeActive()
    }

    /// M7c L16: an app launched or Exit to Desktop stops the Live TV preview.
    func applicationDidResignActive(_ notification: Notification) {
        router?.isAppActive = false
        windowController?.appDidResignActive()
    }

    private func makeSettingsEnvironment(kiosk: Bool) -> SettingsEnvironment {
        SettingsEnvironment(
            isKiosk: kiosk,
            version: .current,
            applySettings: { [weak self] in self?.applySettings($0) },
            applyItems: { [weak self] in self?.applyItems($0) },
            isAccessibilityTrusted: { AccessibilityPermission.isTrusted },
            requestAccessibility: { [weak self] in self?.requestAccessibility() },
            loginItemStatus: { LoginItem.status },
            openLoginItemsSettings: { [weak self] in
                self?.kioskGuard.openedSystemSettings()
                LoginItem.openSystemSettings()
            },
            scanInstalledApps: {
                await InstalledApps.scanInBackground(excludingBundleIDs: [Bundle.main.bundleIdentifier ?? ""])
            },
            relaunch: { [weak self] in self?.relaunch() },
            restartMac: { [weak self] in self?.power?.restartMac() },
            // M15 step 8: before `setUpUpdater` nothing is known yet; Settings re-reads it when it opens.
            updateStatus: { [weak self] in self?.updater?.status ?? .idle(lastChecked: nil) },
            lastUpdateCheck: { [weak self] in self?.updater?.lastUpdateCheckDate },
            updateTestFeedHost: { [weak self] in
                guard let updater = self?.updater, updater.isTestFeed else { return nil }
                return updater.feedHost
            },
            checkForUpdates: { [weak self] in self?.updater?.checkNow() },
            installUpdate: { [weak self] in self?.updater?.install() },
            exitToDesktop: { [weak self] in
                self?.router?.goHome()
                self?.windowController?.exitToDesktop()
            },
            tileTitle: { [launcher] in launcher.title(for: $0) },
            isInstalled: { [launcher] in launcher.isInstalled($0) },
            hasPIN: { PINStore.keychain.load() != nil },
            startPINFlow: { [weak self] in self?.router?.requestPIN($0) },
            reloadYouTube: { [weak self] in self?.youtube?.reload() },
            clearYouTubeData: { [weak self] in
                Task { await self?.youtube?.clearData() }
            },
            iptvStatus: { [weak self] in self?.iptvSettingsStatus() ?? IPTVSettingsStatus() },
            pasteIPTVURL: { [weak self] in self?.pasteIPTVURL($0) },
            moveGuideSource: { [weak self] id, step in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.moveGuideSource(id, by: step) }
            },
            removeGuideSource: { [weak self] id in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.removeGuideSource(id) }
            },
            setIPTVGroupHidden: { [weak self] name, hidden in self?.iptvLibrary?.setGroupHidden(name, hidden) },
            unhideIPTVChannel: { [weak self] id in self?.iptvLibrary?.setChannelHidden(id, false) },
            setTeamPicked: { [weak self] id, picked in self?.iptvLibrary?.setTeamPicked(id, picked) },
            refreshIPTV: { [weak self] in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.refreshAll() }
            },
            removeIPTVSource: { [weak self] in
                guard let library = self?.iptvLibrary else { return }
                self?.liveTV?.leave()
                Task { await library.removeSource() }
            },
            findAntennaTuners: { [weak self] in
                guard let library = self?.iptvLibrary else { return .noneFound }
                let found = await library.discoverAntenna()
                return library.antenna.findOutcome(found: found)
            },
            setChannelHidden: { [weak self] id, hidden in self?.iptvLibrary?.setChannelHidden(id, hidden) },
            startAntennaScan: { [weak self] in self?.iptvLibrary?.startAntennaScan() },
            stopAntennaScan: { [weak self] in self?.iptvLibrary?.stopAntennaScan() },
            antennaPageVisible: { [weak self] visible in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.antennaPageVisible(visible) }
            },
            phoneRemoteStatus: { [weak self] in self?.phoneRemoteSettingsStatus() ?? PhoneRemoteSettingsStatus() },
            setPhonePairing: { [weak self] in self?.phoneRemote?.setPairing($0) },
            forgetAllPhones: { [weak self] in self?.phoneRemote?.forgetAll() },
            applyBindings: { [weak self] in self?.applyBindings($0) },
            setButtonLearning: { [weak self] handler in self?.inputRouter?.captureHandler = handler },
            tileArtFileName: { [weak self] in self?.router?.tileArt.customFileName(for: $0) },
            plexStatus: { [weak self] in self?.plexSettingsStatus() ?? PlexSettingsStatus() },
            setPlexLinking: { [weak self] in self?.plex?.setLinking($0) },
            choosePlexServer: { [weak self] id in
                guard let plex = self?.plex else { return }
                Task { await plex.chooseServer(id: id) }
            },
            signOutOfPlex: { [weak self] in self?.plex?.signOut() },
            refreshPlex: { [weak self] in self?.plex?.startRefresh(maxAge: .seconds(120)) },
            webAppInfo: { [launcher] in launcher.webAppInfo(for: $0) },
            pasteURL: { ClipboardURL.parse(NSPasteboard.general.string(forType: .string)) },
            findPictures: {
                await Task.detached { PictureFinder.find(in: PictureFinder.defaultFolders) }.value
            },
            setTilePicture: { [weak self] id, url in
                do {
                    try self?.router?.tileArt.setPicture(from: url, for: id)
                    return nil
                } catch {
                    Self.logger.error("Can't copy tile art: \(error.localizedDescription, privacy: .public)")
                    return "Couldn't copy that picture"
                }
            },
            removeTilePicture: { [weak self] in self?.router?.tileArt.removePicture(for: $0) },
            castingStatus: { [weak self] in self?.castingSettingsStatus() ?? CastingSettingsStatus() },
            refreshCasting: { [weak self] in self?.refreshCasting() },
            openAirPlaySettings: { [weak self] in
                self?.kioskGuard.openedSystemSettings()
                if let url = URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            },
            siriRemoteStatus: { [weak self] in
                guard let self, let siriRemote else { return SiriRemoteSettingsStatus() }
                return SiriRemoteSettingsStatus(isConnected: siriRemote.isConnected,
                                                batteryLevel: router?.remoteBatteryLevel,
                                                isTouchAvailable: siriRemote.isTouchAvailable)
            },
            receiverStatus: { [weak self] in
                guard let receiver = self?.receiver else { return ReceiverSettingsStatus() }
                return ReceiverSettingsStatus(state: receiver.state, isConnected: receiver.isConnected,
                                              isAnswering: receiver.isAnswering, lastError: receiver.lastConnectError)
            },
            serialPorts: { SerialPort.available() },
            testReceiver: { [weak self] in await self?.testReceiver() ?? ReceiverTestOutcome(error: "No answer") },
            findReceiverOnPort: { [weak self] path in await self?.receiver?.find(onPort: path) },
            findReceiversOnNetwork: { port in await ReceiverDiscovery().find(portOverride: port) },
            testTV: { [weak self] in
                guard let tv = self?.tv, tv.isConfigured else { return nil }
                return await tv.test()
            },
            findTVs: { [weak self] in await self?.tv?.find() ?? [] },
            cecAvailability: { [weak self] in self?.cec?.availability },
            refreshCEC: { [weak self] in
                guard let cec = self?.cec else { return }
                Task { [weak self] in
                    await cec.refreshAvailability()
                    self?.router?.settings.refreshStatus(.cec)
                }
            },
            testCEC: { [weak self] in await self?.cec?.powerStatus() },
            cecReceiverStatus: { [weak self] in
                guard let cecReceiver = self?.cecReceiver else { return CECReceiverSettingsStatus() }
                return CECReceiverSettingsStatus(availability: cecReceiver.availability, power: cecReceiver.power,
                                                 name: cecReceiver.name, isAnswering: cecReceiver.isAnswering)
            },
            testCECReceiver: { [weak self] in await self?.cecReceiver?.test() ?? CECReceiverTest() },
            showToast: { text in OverlayToast.shared.show(text, symbol: "cursorarrow.motionlines") }
        )
    }

    /// Settings → Audio & TV → Receiver → Test Connection (L12): read-only queries, or why nothing answered.
    private func testReceiver() async -> ReceiverTestOutcome {
        guard settings.receiverBrand != .none else { return ReceiverTestOutcome(error: "Choose the receiver's brand first") }
        if settings.receiverConnection == .network, settings.receiverHost == nil {
            return ReceiverTestOutcome(error: "Set the receiver's address first")
        }
        guard let receiver, receiver.brand != .none else {
            return ReceiverTestOutcome(error: "Not a LAN address or name")
        }
        let replies = await receiver.test()
        return ReceiverTestOutcome(replies: replies, error: replies.isEmpty ? receiver.lastConnectError : nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show(reason: "reopen")
        return true
    }
}

/// M7h L7: whether remote input hides the pointer.
nonisolated enum CursorAutoHide {
    static func hides(setting: Bool, isTrackpadMode: Bool) -> Bool {
        setting && !isTrackpadMode
    }

    /// Step 13e (c) QA: what trackpad mode turning on or off does to the pointer (`setHiddenUntilMouseMoves`). On:
    /// shown (false). Off: hidden again (true) with `cursorAutoHide` on and MMTVL active, as a remote press would;
    /// else unchanged (nil).
    static func hiddenUntilMouseMoves(trackpadModeOn: Bool, setting: Bool, isAppActive: Bool) -> Bool? {
        if trackpadModeOn { return false }
        return setting && isAppActive ? true : nil
    }
}
