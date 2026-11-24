import Observation
import SwiftUI
import os

/// M7 L2: bumped on every home arrow that moved focus and on Select; the focused tile reacts (parallax nudge, press).
struct FocusMotion: Equatable {
    var direction: RemoteCommand?
    var generation = 0
}

/// The current launcher screen. Receives every `RemoteCommand` from `InputRouter`
/// and dispatches it to the active screen.
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case home
        case accessibilityOnboarding
        case settings
        case youtube
        case liveTV
        case pin(PINPurpose)
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppRouter")

    private(set) var screen: Screen = .home {
        didSet {
            guard screen != oldValue else { return }
            // M7m L5: the tile menu belongs to the home screen; any other screen (a cast, Live TV, a PIN) closes it.
            if screen != .home {
                tileMenu = nil
                endMoving(reason: "the screen changed")
            }
            // M7m (QA step 6, finding 4): a new screen counts as activity, so a click that opens one through the
            // dim (mouse, phone trackpad, Siri trackpad mode) doesn't leave it dimmed.
            feedIdleActivity(reason: "(the screen changed)")
            updateLivePreview()
            updateStillness()
        }
    }
    /// All tiles in stored order, hidden ones included.
    private(set) var items: [LaunchItem]
    /// The tiles shown on the home screen; `focus` and `activate(_:)` index into these.
    private(set) var visibleItems: [LaunchItem]
    /// Kept while another screen is shown, so Back restores the previous focus position.
    private(set) var focus: LauncherFocusModel {
        didSet {
            guard focus.index != oldValue.index else { return }
            // M7c L25: a failed preview tries again when Live TV gets focus.
            if liveTV.previewFailed, isLiveTVFocused { liveTV.stopPreview() }
            updateLivePreview()
        }
    }
    private(set) var shakeTriggers: [LaunchItem.ID: Int] = [:]
    /// L2. Hover moves don't bump it.
    private(set) var focusMotion = FocusMotion()
    /// M7 L12: nil = the tiles have focus; else the focused card of the focused tile's shelf.
    private(set) var shelfIndex: Int? {
        didSet { if shelfIndex != oldValue { updateLivePreview() } }
    }
    /// M7c L14: the carousel's page while the tiles have focus (auto-advances); 0 when the focused tile changes.
    private(set) var carouselPage = 0
    /// The tile `carouselPage` belongs to.
    @ObservationIgnored private var carouselTileID: LaunchItem.ID?
    @ObservationIgnored private var carouselTask: Task<Void, Never>?
    /// Injectable (tests advance by hand with `advanceCarousel()`).
    @ObservationIgnored var carouselInterval: Duration = Theme.carouselInterval
    /// M7c L28: "Version 1.1.0 Build 2" under the home clock; nil = hidden. Set live by AppDelegate.
    var homeVersionLabel: String?
    /// M7f L8: the lowest Siri Remote battery percent beside the home clock; nil = hidden. Set by AppDelegate.
    var remoteBatteryLevel: Int?
    /// M7f L8: AppDelegate reads the battery again (the home screen appeared or its minute ticked).
    @ObservationIgnored var onRefreshRemoteBattery: (() -> Void)?
    /// M7l L4: `settings.json` `glassStyle`, set live by AppDelegate; the root view puts it in the environment.
    var glassStyle = GlassStyle.clear
    /// M7c L15: `settings.json` `homeLivePreview`, set live by AppDelegate.
    @ObservationIgnored var livePreviewEnabled = true {
        didSet { if livePreviewEnabled != oldValue { updateLivePreview() } }
    }
    /// L16: MMTVL is the active app (AppDelegate, from didBecomeActive/didResignActive).
    @ObservationIgnored var isAppActive = true {
        didSet {
            guard isAppActive != oldValue else { return }
            // M7m L20: back in front with the screen saver asked for but no `didstop` (it never started, or macOS
            // didn't say): awake, as after the screen saver.
            if isAppActive, idlePhase == .screenSaver, !isScreenSaverRunning {
                feedIdleActivity(reason: "(back in front)")
            }
            updateLivePreview()
            updateStillness()
            updateIdleTicks()
            if isAppActive {
                homeEntryGeneration += 1
            } else if isLeavingHome {
                // L23: the launched app took the screen; the home UI is back for the return.
                finishLeavingHome(animated: false)
            }
        }
    }
    /// M7c L22, L23: the home UI animates away before Live TV or Plex opens. Commands wait (Home cancels).
    private(set) var isLeavingHome = false
    /// Bumped when the home screen comes back (MMTVL active again); the dock slides up.
    private(set) var homeEntryGeneration = 0
    /// Injectable: 0 (no animation) by default and in tests; AppDelegate sets `Theme.homeExitDuration`.
    @ObservationIgnored var homeExitDelay: Duration = .zero
    /// M7c L23: how long the home UI stays away for an app that doesn't take the screen (tests shorten it).
    @ObservationIgnored var homeExitAppFallback: Duration = Theme.homeExitAppFallback
    /// M7h L16: a launch that restarts its app first (Plex after a hot-plug); the home exit's fallback starts only
    /// once it has opened the new process, so the home UI doesn't bounce back meanwhile.
    @ObservationIgnored private var restartingLaunch: Task<Void, Never>?
    @ObservationIgnored private(set) var homeExitTask: Task<Void, Never>?
    /// Injectable; tests use zero.
    @ObservationIgnored var previewDelay: Duration = Theme.previewDelay
    @ObservationIgnored var previewIdleTimeout: Duration = Theme.previewIdleTimeout
    /// L16: no input for `previewIdleTimeout`, or the displays slept.
    @ObservationIgnored private(set) var isIdle = false
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledPreviewID: Channel.ID?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    /// M7m L18 (D51): the idle dimmer. `idlePhase` mirrors its phase for the views (the dim in `LauncherRootView`).
    @ObservationIgnored private var stillIdle = StillScreenIdle(dimAfter: Theme.stillScreenDimAfter,
                                                                saverAfterDim: Theme.screenSaverAfterDim)
    private(set) var idlePhase: StillScreenIdle.Phase = .awake
    /// M15 step 6b: a remote command reached MMTVL (`handle`) since the last Power-off (`notePowerOff`), so someone is
    /// using it: no idle install. Power and volume don't count (Power-on clears "off" anyway; a volume press in the
    /// dark isn't someone watching). False at launch.
    @ObservationIgnored private(set) var inputSincePowerOff = false
    /// Injectable clock for the dimmer (tests advance it and call `idleTick()`).
    @ObservationIgnored var idleNow: () -> ContinuousClock.Instant = { ContinuousClock.now }
    /// M7m L20: the dimmer asks for the screen saver (AppDelegate: `ScreenSaver.start()`).
    @ObservationIgnored var startScreenSaver: () -> Void = {}
    /// M7m L20: a press ends the running screen saver (AppDelegate: `ScreenSaver.end()`).
    @ObservationIgnored var endScreenSaver: () -> Void = {}
    /// M7m L20: macOS's screen saver runs (`screenSaverDidStart`/`Stop`), whoever started it.
    @ObservationIgnored private(set) var isScreenSaverRunning = false
    /// M7m L20 (security medium): a screen saver engine really runs (AppDelegate: `ScreenSaver.isEngineRunning`), so a
    /// `didstart` without a `didstop` can't swallow every press for good.
    @ObservationIgnored var isScreenSaverEngineRunning: () -> Bool = { false }
    /// M7m L19 (QA step 7, major 1): a press already ended this screen saver, so its stop opens no grace window.
    @ObservationIgnored private var screenSaverEndedByPress = false
    /// M7m pre-build review (security medium): a real engine was seen running during this screen saver (at `didstart`,
    /// an idle tick or a press). Only then does its end open a grace window, so forged `didstart`s can't swallow presses.
    @ObservationIgnored private var screenSaverEngineSeen = false
    /// The engine may not be listed yet when `didstart` arrives, and the idle tick doesn't run while the screen saver
    /// shows (MMTVL inactive): look again after each of these waits (successive: 0.5 s, then 2 s after `didstart`).
    @ObservationIgnored var screenSaverEngineRecheckWaits: [Duration] = [.milliseconds(500), .milliseconds(1500)]
    /// Cancelled by `didstop` and the next `didstart`; readable so tests await it.
    @ObservationIgnored private(set) var screenSaverEngineRecheckTask: Task<Void, Never>?
    /// M7m pre-build review (QA minor): a press only woke the screen; a held key's repeats are swallowed too, until the
    /// next fresh press.
    @ObservationIgnored private var swallowsRepeatsAfterWake = false
    /// When a screen saver no press ended stopped (macOS ended it on a touch); the next press within
    /// `screenSaverWakeGrace` is the waking one and is swallowed.
    @ObservationIgnored private var screenSaverStoppedAt: ContinuousClock.Instant?
    @ObservationIgnored var screenSaverWakeGrace: Duration = Theme.screenSaverWakeGrace
    /// M7m L20 (QA step 7, major 2): the displays sleep (`screensDidSleep` until `screensDidWake`); the dimmer waits.
    @ObservationIgnored private(set) var areDisplaysAsleep = false
    /// Runs `idleTick()` every second while MMTVL is active.
    @ObservationIgnored private var idleTickTask: Task<Void, Never>?
    private static let idleTickInterval: Duration = .seconds(1)
    private static let idleLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Idle")
    /// D20: read at init, on going home and after PIN flows, not on every render.
    private var hasPINCache = false
    /// The PIN screen's model while `screen` is `.pin`.
    private(set) var pinEntry: PINEntryModel?
    /// M7h L15: the power menu, over whatever screen shows (YouTube and Live TV included); it takes every command
    /// while open (Home closes it and goes home).
    private(set) var powerMenu: PowerMenu? {
        didSet { if (powerMenu == nil) != (oldValue == nil) { updateStillness() } }
    }
    /// Relaunch and Restart show a lock: a PIN was set when the menu opened.
    private(set) var powerMenuShowsPINLock = false
    /// M7m L5, L6 (D50): the focused home tile's menu (Menu on a tile); it takes every command while open (Home closes
    /// it and goes home).
    private(set) var tileMenu: TileMenu? {
        didSet { if (tileMenu == nil) != (oldValue == nil) { updateStillness() } }
    }
    /// M7m L8: the home tile being moved (the tile menu's Move): arrows move it, focus stays on it; Select, Back and
    /// Menu end it, Home ends it and goes home, and so does any change of screen. Step 11 draws it lifted.
    private(set) var movingTileID: String?
    /// The edit rows show a lock: a PIN was set when the menu opened.
    private(set) var tileMenuShowsPINLock = false
    /// M7m L7: the tile menu's Quit or Restart while it waits for the app to quit (tests await it).
    @ObservationIgnored private(set) var tileMenuTask: Task<Void, Never>?
    /// M7m L11: a short message over any app (AppDelegate's default: `OverlayToast`; tests record it).
    @ObservationIgnored var showToast: (_ text: String, _ symbol: String) -> Void = {
        OverlayToast.shared.show($0, symbol: $1)
    }
    private static let homeLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Home")

    @ObservationIgnored let launcher: AppLauncher
    /// M7 L3: custom tile pictures.
    let tileArt: TileArtStore
    let settings: SettingsModel
    @ObservationIgnored let youtube: any YouTubeHosting
    @ObservationIgnored let liveTV: any LiveTVHosting
    @ObservationIgnored let topShelf: any TopShelfProviding
    /// M7 step 12: card images fetched with headers (Plex).
    @ObservationIgnored let shelfImages = ShelfImageLoader()
    @ObservationIgnored private let pinStore: PINStore
    /// Kept across PIN screens, so cancelling doesn't reset the lockout (L10).
    @ObservationIgnored private var pinLockout = PINLockout()
    /// Where cancelling the PIN screen returns: .home or .settings.
    @ObservationIgnored private var screenBeforePIN: Screen = .home
    /// L8: hover only moves focus after the pointer moved since the last consumed command.
    /// Not private so tests can set nil, which makes the pointer count as moved (M7m step 10 QA).
    @ObservationIgnored var pointerLocationAtLastCommand: NSPoint?
    /// L21: scroll distance not yet turned into a row move, and when it last changed.
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0
    @ObservationIgnored private var lastScrollAt: Date?
    /// Injectable clock (tests).
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var onExitToDesktop: (() -> Void)?
    /// M7c L9: quits MMTVL for real (after the PIN, if one is set).
    @ObservationIgnored var onQuit: (() -> Void)?
    @ObservationIgnored var onRequestAccessibility: (() -> Void)?
    /// M7h L14: Power's short press (`PowerController.powerButton`).
    @ObservationIgnored var onPowerButton: (() -> Void)?
    /// M7h L15: a power menu item ran (Relaunch and Restart after the PIN, when one is set). Never `.cancel`.
    @ObservationIgnored var onPowerAction: ((PowerMenuAction) -> Void)?
    /// The power menu closed, and why (U1: Cancel hands the screen back; M7h re-review: Exit to Desktop).
    @ObservationIgnored var onPowerMenuClose: ((PowerMenuCloseReason) -> Void)?

    init(items: [LaunchItem], launcher: AppLauncher, settings: SettingsModel, youtube: any YouTubeHosting,
         liveTV: any LiveTVHosting, pinStore: PINStore, tileArt: TileArtStore,
         topShelf: any TopShelfProviding = NoTopShelf()) {
        self.items = items
        self.launcher = launcher
        self.settings = settings
        self.youtube = youtube
        self.liveTV = liveTV
        self.pinStore = pinStore
        self.tileArt = tileArt
        self.topShelf = topShelf
        let visibleItems = items.visible
        self.visibleItems = visibleItems
        focus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        hasPINCache = pinStore.load() != nil
        // M7 L18: a web app whose window never showed shakes its tile.
        launcher.onLaunchFailed = { [weak self] id in self?.shakeTriggers[id, default: 0] += 1 }
        // M7h step 13e: status changes refresh Settings only while it shows.
        settings.isShowing = { [weak self] in self?.screen == .settings }
        syncCarousel()
        updateStillness()
        updateIdleTicks()
        observeLiveTVVideo()
    }

    /// Replaces the tiles (Settings edits), keeping focus on the same tile where possible.
    func setItems(_ newItems: [LaunchItem]) {
        let oldIndex = focus.index
        let focusedID = oldIndex.map { visibleItems[$0].id }

        items = newItems
        visibleItems = newItems.visible
        var newFocus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        if let focusedID, let index = visibleItems.firstIndex(where: { $0.id == focusedID }) {
            newFocus.focus(index: index)
        } else if let oldIndex, !visibleItems.isEmpty {
            newFocus.focus(index: min(oldIndex, visibleItems.count - 1))
        }
        focus = newFocus
        // M7m L8: a moving tile that's no longer on the home screen ends move mode.
        if let movingTileID, !visibleItems.contains(where: { $0.id == movingTileID }) {
            endMoving(reason: "the tile left the home screen")
        }
        shelfContentChanged()
    }

    /// M7c L32: `settings.json` `homeStartTile`, set live by AppDelegate.
    @ObservationIgnored var startTileID = "plex"

    /// M7c L32: Home (any remote, the keyboard, the phone, from any screen or app) shows the home screen on the
    /// start tile; so does Back when it reaches the home screen (user request 2026-10-10).
    func goHomeToStartTile() {
        goHome()
        withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
    }

    /// M7c L32: at launch and on Home, the home screen opens on `id` (else the first tile), out of the top shelf, so
    /// the dock row shows with the next row peeking.
    func focusStartTile(id: String) {
        var newFocus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        if let index = visibleItems.firstIndex(where: { $0.id == id }) {
            newFocus.focus(index: index)
        }
        focus = newFocus
        shelfIndex = nil
        // L8: a pointer resting where the home screen appears mustn't take the focus; only a real move does.
        pointerLocationAtLastCommand = NSEvent.mouseLocation
        topShelf.refresh(focusing: focusedItem)
        shelfContentChanged()
    }

    // MARK: Top shelf (M7 D28, L12)

    /// The focused tile, if any.
    var focusedItem: LaunchItem? {
        focus.index.flatMap { visibleItems.indices.contains($0) ? visibleItems[$0] : nil }
    }

    /// The focused tile's shelf. PIN-protected tiles only get a banner.
    var shelfContent: ShelfContent {
        guard let item = focusedItem else { return .banner }
        if item.isPINProtected && hasPINCache { return .banner }
        return topShelf.content(for: item)
    }

    /// Call when the shelf's content may have changed: clamps the card focus, or returns to the tile.
    func shelfContentChanged() {
        defer { updateLivePreview() }
        syncCarousel()
        guard let index = shelfIndex else { return }
        let count = shelfContent.cards.count
        shelfIndex = count == 0 ? nil : min(index, count - 1)
    }

    // MARK: Live TV preview (M7c L15, L16, D37)

    /// The channel the home screen should preview now, or nil.
    /// M7c L25: it preloads with any tile focused while the Live TV tile is on the home screen.
    var wantedPreviewChannelID: Channel.ID? {
        // M7m L18: dimmed counts as idle.
        guard screen == .home, livePreviewEnabled, isAppActive, !isIdle, idlePhase == .awake,
              let liveItem = visibleItems.first(where: { $0.kind == .internalDestination(.iptv) }),
              !(liveItem.isPINProtected && hasPINCache)
        else { return nil }
        guard isLiveTVFocused else {
            // Another tile: whatever plays keeps playing (no reconnect), else the default channel.
            return liveTV.previewChannelID ?? liveTV.defaultPreviewChannelID
        }
        // M7c L21: the focused page (or card); Down/Back keep the page, so its channel keeps playing.
        let content = shelfContent
        if let index = shelfIndex ?? (content.isCarousel ? carouselPage : nil) {
            let cards = content.cards
            if cards.indices.contains(index), case .playChannel(let id) = cards[index].action { return id }
        }
        return liveTV.defaultPreviewChannelID
    }

    private var isLiveTVFocused: Bool {
        focusedItem?.kind == .internalDestination(.iptv)
    }

    /// Whether the preview's video shows through the backdrop (the Live TV tile focused and its preview playing).
    var revealsLivePreview: Bool {
        screen == .home && isLiveTVFocused && liveTV.isPreviewPlaying
    }

    /// M7c L25: the preview's video is drawn only while the Live TV tile has focus (other tiles' art and crossfades
    /// never show it).
    var showsLivePreviewVideo: Bool {
        screen == .home && isLiveTVFocused
    }

    /// Starts (after `previewDelay`), switches or stops the preview. Called on every focus, shelf, screen,
    /// setting and activity change.
    func updateLivePreview() {
        // Live TV owns the player while it's open (an adopted preview keeps playing).
        if screen == .liveTV {
            cancelScheduledPreview()
            return
        }
        guard let wanted = wantedPreviewChannelID else {
            cancelScheduledPreview()
            if liveTV.previewChannelID != nil || liveTV.previewFailed { liveTV.stopPreview() }
            return
        }
        if idleTask == nil { restartIdleTimer() }
        if wanted == liveTV.previewChannelID || liveTV.previewFailed {
            cancelScheduledPreview()
            return
        }
        guard scheduledPreviewID != wanted else { return }
        cancelScheduledPreview()
        guard previewDelay > .zero else {
            liveTV.startPreview(channelID: wanted)
            return
        }
        scheduledPreviewID = wanted
        let delay = previewDelay
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, scheduledPreviewID == wanted else { return }
            scheduledPreviewID = nil
            if wantedPreviewChannelID == wanted { liveTV.startPreview(channelID: wanted) }
        }
    }

    /// M7f L5: the playlist was re-fetched (`IPTVLibrary.onLineupChange`). A preview whose channel left it stops, and
    /// the default channel (else the first favorite) takes over; the Live TV pages reload around it.
    func playlistDidChange() {
        liveTV.playlistDidChange()
        if screen == .home { topShelf.refresh(focusing: focusedItem) }
        updateLivePreview()
    }

    private func cancelScheduledPreview() {
        previewTask?.cancel()
        previewTask = nil
        scheduledPreviewID = nil
    }

    /// L16: any remote command (`InputRouter.onCommandDispatched`, called before `handle`). M7m L19: while dimmed,
    /// `handle` wakes the dimmer (and swallows the command), so it isn't fed here.
    func noteActivity() {
        if idlePhase == .awake { stillIdle.activity(at: idleNow()) }
        restartIdleTimer()
        if isIdle {
            isIdle = false
            updateLivePreview()
        }
    }

    /// L16: the displays or the system went to sleep. The next command restarts the preview. M7m L20: the dimmer
    /// waits until they wake (no screen saver started with the displays off).
    func screensDidSleep() {
        areDisplaysAsleep = true
        stopPreviewUntilInput()
    }

    /// M7m L20 (QA step 7, major 2): the displays woke; the dimmer's wait starts over (the preview still waits for a
    /// command, L16).
    func screensDidWake() {
        guard areDisplaysAsleep else { return }
        areDisplaysAsleep = false
        feedIdleActivity(reason: "(the displays woke)")
    }

    private func stopPreviewUntilInput() {
        idleTask?.cancel()
        idleTask = nil
        isIdle = true
        updateLivePreview()
    }

    /// M15 L16 (amends D45): Power-off, before the TV is told to turn off. Live TV (Multiview too) stops without
    /// keeping a preview, YouTube pauses, and the home preview waits for the next command (as after the displays
    /// sleep). AppDelegate then goes home (`goHomeFromAnywhere`): `goHome` leaves Live TV again, which keeps nothing
    /// (its players are stopped), and `updateLivePreview` starts no preview while `isIdle`.
    func stopPlaybackForPowerOff() {
        switch screen {
        case .liveTV: liveTV.leave(keepingPreview: false)
        case .youtube: youtube.pause()
        default: break
        }
        stopPreviewUntilInput()
    }

    /// M15 step 6b: MMTVL's Power-off started (`PowerController.onPowerOff`): input counts from now on. Not for the
    /// receiver turning off by itself.
    func notePowerOff() {
        inputSincePowerOff = false
    }

    /// M15 step 6b (QA major): a command reached MMTVL, also one only a wake or the screen saver took (`handle`,
    /// `endScreenSaverIfShowing`); Power and volume don't count.
    func noteInputSincePowerOff(_ command: RemoteCommand) {
        if Self.countsAsInputSincePowerOff(command) { inputSincePowerOff = true }
    }

    /// M15 step 6b: whether `command` counts as someone using MMTVL after a Power-off. Pure.
    static func countsAsInputSincePowerOff(_ command: RemoteCommand) -> Bool {
        switch command {
        case .power, .volumeUp, .volumeDown, .mute:
            false
        case .up, .down, .left, .right, .select, .back, .home, .playPause, .fastForward, .rewind, .menu, .channelUp,
             .channelDown, .powerMenu:
            true
        }
    }

    /// M7c L26: no stream while the screen saver runs. M7m L20: from now on a press only ends it.
    func screenSaverDidStart() {
        isScreenSaverRunning = true
        screenSaverEndedByPress = false
        screenSaverEngineSeen = false
        screenSaverStoppedAt = nil
        screenSaverEngineRecheckTask?.cancel()
        screenSaverEngineRecheckTask = nil
        noteScreenSaverEngine()
        if !screenSaverEngineSeen { scheduleScreenSaverEngineRecheck() }
        stopPreviewUntilInput()
    }

    private func scheduleScreenSaverEngineRecheck() {
        let waits = screenSaverEngineRecheckWaits
        screenSaverEngineRecheckTask = Task { [weak self] in
            for wait in waits {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                noteScreenSaverEngine()
                if screenSaverEngineSeen { return }
            }
        }
    }

    /// Records that this screen saver's engine really runs (pre-build review, security medium). Returns whether it does.
    @discardableResult
    private func noteScreenSaverEngine() -> Bool {
        let running = isScreenSaverEngineRunning()
        if running, isScreenSaverRunning { screenSaverEngineSeen = true }
        return running
    }

    /// M7c L26: counts as activity, so the preview can start again. M7m L20: wakes the dimmer. L19 (QA step 7,
    /// major 1): unless a press ended it, the next press within `screenSaverWakeGrace` is swallowed too: macOS ends
    /// the screen saver on the Siri Remote's touch, before its press reaches MMTVL.
    func screenSaverDidStop() {
        // A second report of the same stop (it was found gone first, or reported twice) opens no new window, nor a
        // session whose engine was never seen (forged `didstart`s, pre-build review).
        if isScreenSaverRunning {
            screenSaverStoppedAt = screenSaverEndedByPress || !screenSaverEngineSeen ? nil : idleNow()
        }
        isScreenSaverRunning = false
        screenSaverEndedByPress = false
        screenSaverEngineSeen = false
        screenSaverEngineRecheckTask?.cancel()
        screenSaverEngineRecheckTask = nil
        stillIdle.screenSaverStopped(at: idleNow())
        syncIdlePhase(reason: "(the screen saver stopped)")
        noteActivity()
        updateStillness()
    }

    /// M7m L19, L20: the screen saver shows: macOS said it started, or the dimmer asked for it and MMTVL went to the
    /// background (it took the screen); either way only while an engine really runs (security medium).
    var isScreenSaverShowing: Bool {
        (isScreenSaverRunning || (idlePhase == .screenSaver && !isAppActive)) && isScreenSaverEngineRunning()
    }

    /// QA step 7, major 1: a screen saver no press ended stopped less than `screenSaverWakeGrace` ago.
    private var isInScreenSaverWakeGrace: Bool {
        guard let screenSaverStoppedAt else { return false }
        return idleNow() - screenSaverStoppedAt < screenSaverWakeGrace
    }

    /// M7m L19, L20: the one check for input that arrives while the screen saver shows, from any source (`handle`,
    /// `ExternalRouter` for the Siri Remote and the phone, phone text): it ends the screen saver and wakes the dimmer,
    /// and the caller swallows the input (it never reaches the app in front). Also the first press within the grace
    /// window after a screen saver no press ended (it wakes, without ending anything). False otherwise.
    @discardableResult
    /// `command`: the remote command (M15 step 6b: it counts as input since Power-off when swallowed here); nil for
    /// phone text and Return.
    func endScreenSaverIfShowing(by reason: String, command: RemoteCommand? = nil) -> Bool {
        // QA step 7 (minor): the engine is gone but `didstop` hasn't come yet, and no press ended it (macOS did, on a
        // touch): stopped now, so this press opens the grace window and is swallowed once.
        // Pre-build review (security medium): only for a session whose engine was seen.
        let engineRunning = noteScreenSaverEngine()
        if isScreenSaverRunning, screenSaverEngineSeen, !screenSaverEndedByPress, !engineRunning {
            Self.idleLogger.info("The screen saver ended before its didstop")
            screenSaverDidStop()
        }
        if isScreenSaverShowing {
            if let command { noteInputSincePowerOff(command) }
            swallowsRepeatsAfterWake = true
            wakeFromIdle(by: reason)
            return true
        }
        guard isInScreenSaverWakeGrace else {
            screenSaverStoppedAt = nil
            return false
        }
        screenSaverStoppedAt = nil
        if let command { noteInputSincePowerOff(command) }
        swallowsRepeatsAfterWake = true
        feedIdleActivity(reason: "by \(reason)")
        noteActivity()
        Self.idleLogger.info("Swallowed \(reason, privacy: .public) just after the screen saver")
        return true
    }

    private func restartIdleTimer() {
        idleTask?.cancel()
        let timeout = previewIdleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            idleTask = nil
            isIdle = true
            updateLivePreview()
        }
    }

    // MARK: Still screens (M7m L17–L19, D51)

    /// L17: nothing on screen moves, so it can burn in: the home screen (its dock and clock stay put, preview or
    /// not), Settings, the PIN screen, the power menu, and Live TV while it shows no moving video. Never YouTube, and
    /// never while MMTVL isn't in front.
    var isStillScreen: Bool {
        guard isAppActive else { return false }
        if powerMenu != nil || tileMenu != nil { return true }
        switch screen {
        case .home, .settings, .pin, .accessibilityOnboarding: return true
        case .liveTV: return !liveTV.isShowingVideo
        case .youtube: return false
        }
    }

    /// Feeds the screen's stillness to the dimmer; a screen that starts moving wakes it.
    func updateStillness() {
        // M7m L20: going to the background for the screen saver isn't the screen starting to move; `didstop` (or a
        // press) wakes it.
        if !isAppActive, isScreenSaverRunning || idlePhase == .screenSaver { return }
        stillIdle.stillnessChanged(isStillScreen, at: idleNow())
        syncIdlePhase(reason: nil)
    }

    /// One step of the dimmer (every second while MMTVL is active; tests call it with their clock).
    func idleTick() {
        if isScreenSaverRunning { noteScreenSaverEngine() }
        updateStillness()
        // QA step 7, major 2: nothing advances while the displays sleep (no screen saver started on a dark screen).
        guard !areDisplaysAsleep, stillIdle.tick(at: idleNow()) else { return }
        syncIdlePhase(reason: nil)
        switch idlePhase {
        case .dimmed:
            Self.idleLogger.info("Dimmed (\(self.stillScreenName, privacy: .public))")
        case .screenSaver:
            Self.idleLogger.info("Asking for the screen saver (\(self.stillScreenName, privacy: .public))")
            startScreenSaver()
        case .awake:
            break
        }
    }

    /// M7m L19 (QA step 6, findings 1–3, 5): input that wakes the dimmer and counts as activity, also when it
    /// doesn't come through `handle`: the Siri Remote's Power and Power Menu (`PowerMenuPresenter`), the scroll
    /// wheel, phone text into Live TV, a button Remote Buttons learns. Restarts the home preview's idle timer too.
    func wakeFromIdle(by reason: String) {
        // M7m L20: every waking press ends a showing screen saver (`ScreenSaver.end()` ignores repeats); its stop then
        // opens no grace window.
        if isScreenSaverShowing {
            screenSaverEndedByPress = true
            endScreenSaver()
        }
        feedIdleActivity(reason: "by \(reason)")
        noteActivity()
    }

    /// The dimmer only: activity now, waking it from either phase.
    private func feedIdleActivity(reason: String) {
        stillIdle.activity(at: idleNow())
        syncIdlePhase(reason: reason)
    }

    private func syncIdlePhase(reason: String?) {
        let phase = stillIdle.phase
        guard phase != idlePhase else { return }
        let wasDimmed = idlePhase != .awake
        idlePhase = phase
        if wasDimmed && phase == .awake {
            Self.idleLogger.info("Woke \(reason ?? "(the screen is moving)", privacy: .public)")
        }
        updateLivePreview()
    }

    private func updateIdleTicks() {
        guard isAppActive else {
            idleTickTask?.cancel()
            idleTickTask = nil
            return
        }
        guard idleTickTask == nil else { return }
        idleTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.idleTickInterval)
                guard !Task.isCancelled, let self else { return }
                idleTick()
            }
        }
    }

    /// L17: Live TV's video starting or stopping changes the stillness at once (the tick would catch it within 1 s).
    private func observeLiveTVVideo() {
        withObservationTracking {
            _ = liveTV.isShowingVideo
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStillness()
                self?.observeLiveTVVideo()
            }
        }
    }

    /// For the log: which still screen dimmed.
    private var stillScreenName: String {
        if powerMenu != nil { return "power menu" }
        if tileMenu != nil { return "tile menu" }
        switch screen {
        case .home: return "home"
        case .accessibilityOnboarding: return "onboarding"
        case .settings: return "Settings"
        case .youtube: return "YouTube"
        case .liveTV: return "Live TV"
        case .pin: return "PIN"
        }
    }

    // MARK: Leaving home (M7c L22, L23)

    /// Animates the home UI away, then runs `open`. With `untilInactive` (an app launch) the UI stays away until
    /// MMTVL resigns active, or comes back after `Theme.homeExitAppFallback`.
    private func leaveHome(untilInactive: Bool = false, _ open: @escaping () -> Void) {
        guard homeExitDelay > .zero else {
            open()
            return
        }
        homeExitTask?.cancel()
        withAnimation(Theme.homeExitAnimation) { isLeavingHome = true }
        let delay = homeExitDelay
        homeExitTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, isLeavingHome else { return }
            open()
            guard untilInactive else {
                finishLeavingHome(animated: false)
                return
            }
            if let launch = restartingLaunch {
                restartingLaunch = nil
                await launch.value
                guard !Task.isCancelled, isLeavingHome else { return }
            }
            try? await Task.sleep(for: homeExitAppFallback)
            guard !Task.isCancelled, isLeavingHome else { return }
            finishLeavingHome(animated: true)
        }
    }

    private func finishLeavingHome(animated: Bool) {
        homeExitTask?.cancel()
        homeExitTask = nil
        if animated {
            withAnimation(Theme.homeReturnAnimation) { isLeavingHome = false }
        } else {
            isLeavingHome = false
        }
    }

    /// The Live TV page's channel when it isn't the first page (the first is what Live TV opens by itself).
    private var livePageChannelID: Channel.ID? {
        let content = shelfContent
        guard content.isCarousel, carouselPage > 0, content.cards.indices.contains(carouselPage),
              case .playChannel(let id) = content.cards[carouselPage].action
        else { return nil }
        return id
    }

    // MARK: Carousel (M7c L14)

    /// Resets the page when the focused tile changed, clamps it, and runs the auto-advance timer only while a carousel
    /// shows on the home screen.
    private func syncCarousel() {
        let content = shelfContent
        if focusedItem?.id != carouselTileID {
            carouselTileID = focusedItem?.id
            carouselPage = 0
            carouselTask?.cancel()
            carouselTask = nil
        }
        let count = content.cards.count
        if carouselPage >= count { carouselPage = max(count - 1, 0) }
        if screen == .home && content.autoAdvances && count > 1 {
            if carouselTask == nil { restartCarouselTimer() }
        } else {
            carouselTask?.cancel()
            carouselTask = nil
        }
    }

    /// Auto-advance starts over from the current page.
    private func restartCarouselTimer() {
        carouselTask?.cancel()
        let interval = carouselInterval
        carouselTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.advanceCarousel()
            }
        }
    }

    /// One auto-advance step (wraps). Not while the carousel itself has focus.
    func advanceCarousel() {
        let content = shelfContent
        guard screen == .home, content.autoAdvances, shelfIndex == nil, !content.cards.isEmpty else { return }
        withAnimation(Theme.carouselCrossfade) { carouselPage = (carouselPage + 1) % content.cards.count }
    }

    /// Mouse hover over a card (with the pointer-moved rule, M1 L8).
    func hoverShelfCard(_ index: Int) {
        guard idlePhase == .awake, screen == .home, movingTileID == nil, pointerMovedSinceLastCommand,
              shelfContent.cards.indices.contains(index) else { return }
        shelfIndex = index
    }

    /// Select on a card, or a click.
    func activateShelfCard(_ index: Int) {
        let cards = shelfContent.cards
        guard screen == .home, cards.indices.contains(index) else { return }
        // M7m L8: a click on a card while a tile moves only ends move mode, like a click on a tile.
        if movingTileID != nil {
            endMoving(reason: "click")
            return
        }
        shelfIndex = nil
        switch cards[index].action {
        case .playChannel(let id):
            leaveHome { [weak self] in self?.openLiveTV(channelID: id) }
        case .openTile(let id):
            guard let tileIndex = visibleItems.firstIndex(where: { $0.id == id }) else { return }
            let item = visibleItems[tileIndex]
            // The PIN screen comes first, without the animation.
            guard !(item.isPINProtected && hasPIN) else {
                activate(tileIndex)
                return
            }
            // M7c L23: a Plex page fades to its art, then the tile opens (an app keeps the UI away until it's up).
            let isApp = switch item.kind {
            case .application, .url, .defaultBrowser: true
            case .internalDestination, .system: false
            }
            leaveHome(untilInactive: isApp) { [weak self] in self?.activate(tileIndex) }
        }
    }

    private func routeShelf(_ command: RemoteCommand, index: Int) -> Bool {
        let content = shelfContent
        switch command {
        case .left where content.isCarousel, .right where content.isCarousel:
            // M7c L14: pages wrap around.
            let count = content.cards.count
            let new = (index + (command == .left ? -1 : 1) + count) % count
            withAnimation(Theme.carouselCrossfade) {
                shelfIndex = new
                carouselPage = new
            }
            bumpFocusMotion(command)
            return true
        case .left, .right:
            let count = content.cards.count
            let new = min(max(index + (command == .left ? -1 : 1), 0), count - 1)
            if new != index {
                shelfIndex = new
                bumpFocusMotion(command)
            }
            return true
        case .down, .back, .home:
            shelfIndex = nil
            bumpFocusMotion(.down)
            // M7c L14: auto-advance resumes from this page.
            if content.autoAdvances { restartCarouselTimer() }
            return true
        case .select:
            bumpFocusMotion(.select)
            activateShelfCard(index)
            return true
        case .up:
            return true
        case .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown,
             .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return false
        }
    }

    /// Returns true if the command was consumed. `isRepeat`: a held key's or button's auto-repeat (M7g: Settings
    /// changes page only on a fresh Left or Right).
    func handle(_ command: RemoteCommand, isRepeat: Bool = false) -> Bool {
        // M15 step 6b: every command that reaches MMTVL passes here, also the ones a wake swallows.
        noteInputSincePowerOff(command)
        // M7m pre-build review (QA minor): a held key that woke the screen keeps doing nothing until a fresh press.
        if isRepeat, swallowsRepeatsAfterWake { return true }
        if !isRepeat { swallowsRepeatsAfterWake = false }
        // M7m L19: a press while dimmed only wakes the screen; Power and Power Menu wake it and still act. L20: the
        // same while the screen saver shows (a global binding while MMTVL is behind it; it's ended) and for the first
        // press just after a screen saver no press ended (QA step 7, major 1).
        let swallowedForScreenSaver = endScreenSaverIfShowing(by: "\(command)", command: command)
        if swallowedForScreenSaver || idlePhase != .awake {
            if !swallowedForScreenSaver { wakeFromIdle(by: "\(command)") }
            swallowsRepeatsAfterWake = true
            guard command == .power || command == .powerMenu else { return true }
        }
        // M7h D45: Power and Power Menu work on every screen; a held key's repeats do nothing (security S3: a held
        // Power key would turn things off, then on again).
        if command == .power {
            if !isRepeat { pressPower() }
            return true
        }
        if powerMenu != nil {
            guard command == .home else {
                routePowerMenu(command)
                return true
            }
            closePowerMenu(reason: .home)
        } else if command == .powerMenu {
            if !isRepeat { openPowerMenu() }
            return true
        }
        if tileMenu != nil {
            guard command == .home else {
                // A held Menu key's repeats don't close the menu it just opened.
                if !(command == .menu && isRepeat) { routeTileMenu(command) }
                return true
            }
            closeTileMenu(reason: "closed (Home)")
        }
        if command == .home { launcher.homePressed() }
        if isLeavingHome {
            // L22: commands wait for the animation; Home cancels it and stays home.
            if command == .home {
                finishLeavingHome(animated: true)
                withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
            }
            return true
        }
        let consumed = route(command, isRepeat: isRepeat)
        // M7c L32: every screen's Home lands on the home screen; then on the start tile.
        if command == .home && screen == .home {
            withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
        }
        if consumed {
            pointerLocationAtLastCommand = NSEvent.mouseLocation
        }
        return consumed
    }

    private func route(_ command: RemoteCommand, isRepeat: Bool) -> Bool {
        switch screen {
        case .home:
            shelfContentChanged()
            if let movingTileID { return routeMoving(command, id: movingTileID, isRepeat: isRepeat) }
            if let shelfIndex { return routeShelf(command, index: shelfIndex) }
            switch command {
            case .up where focus.position.row == 0 && !shelfContent.cards.isEmpty:
                // L12: Up from the first row enters the shelf; a carousel on its current page (M7c L14).
                shelfIndex = shelfContent.isCarousel ? carouselPage : 0
                bumpFocusMotion(.up)
                return true
            case .up, .down, .left, .right:
                var moved = false
                withAnimation(Theme.focusAnimation) { moved = focus.move(command) }
                if moved {
                    bumpFocusMotion(command)
                    topShelf.refresh(focusing: focusedItem)
                    syncCarousel()
                }
                return true
            case .select:
                if let index = focus.index {
                    bumpFocusMotion(.select)
                    activate(index)
                }
                return true
            case .back:
                // M7c L32: Back on the tiles goes to the start tile, like Home.
                withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
                return true
            case .home:
                return true
            case .menu:
                // M7m L5: the focused tile's menu (the Siri Remote's held centre, the phone's Menu, Tab, Y).
                guard let index = focus.index else { return false }
                if !isRepeat { openTileMenu(index) }
                return true
            case .playPause, .fastForward, .rewind, .channelUp, .channelDown,
                 .volumeUp, .volumeDown, .mute, .power, .powerMenu:
                return false
            }

        case .accessibilityOnboarding:
            switch command {
            case .select:
                onRequestAccessibility?()
                return true
            case .back, .home:
                goHomeToStartTile()
                return true
            case .up, .down, .left, .right, .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown,
                 .volumeUp, .volumeDown, .mute, .power, .powerMenu:
                return false
            }

        case .settings:
            if command == .home {
                goHome()
                return true
            }
            if settings.handle(command, isRepeat: isRepeat) { return true }
            if command == .back {
                // Back on the root page; M7c L32: on the start tile.
                goHomeToStartTile()
                return true
            }
            return false

        case .youtube:
            // L2: Home always leaves; everything else goes to leanback.
            if command == .home {
                goHome()
            } else {
                youtube.send(command)
            }
            return true

        case .liveTV:
            if command == .home {
                goHome()
                return true
            }
            switch liveTV.handle(command) {
            case .handled:
                break
            case .leave:
                // M7c L32: Back out of Live TV lands on the start tile, like Home.
                goHomeToStartTile()
            case .openSettings:
                // Live TV isn't set up: Select opens Settings (PIN-guarded like the tile).
                liveTV.leave()
                if hasPIN {
                    requestPIN(.openSettings)
                } else {
                    openSettings()
                }
            }
            return true

        case .pin:
            if command == .home {
                goHome()
            } else if let result = pinEntry?.handle(command) {
                finishPIN(result)
            }
            return true
        }
    }

    // MARK: Power (M7h L14, L15)

    /// Power's short press: closes the menu, then turns things off or on (`onPowerButton`).
    func pressPower() {
        // M7m L19: every Power source wakes the dimmer (a bound key's already did in `handle`; this is a no-op then).
        wakeFromIdle(by: "power")
        closePowerMenu()
        onPowerButton?()
    }

    /// Over the current screen, on its first item. Already open: stays as it is.
    func openPowerMenu() {
        // M7m L19: as for Power; the menu never opens under the dim.
        wakeFromIdle(by: "powerMenu")
        guard powerMenu == nil else { return }
        powerMenuShowsPINLock = hasPIN
        powerMenu = PowerMenu()
        Self.logger.info("Power menu opened")
    }

    /// `reason` goes to `onPowerMenuClose`.
    func closePowerMenu(reason: PowerMenuCloseReason = .other) {
        guard powerMenu != nil else { return }
        powerMenu = nil
        Self.logger.info("Power menu closed (\(String(describing: reason), privacy: .public))")
        onPowerMenuClose?(reason)
    }

    /// A click on a row.
    func choosePowerMenuItem(_ index: Int) {
        guard var menu = powerMenu else { return }
        let outcome = menu.choose(index: index)
        powerMenu = menu
        perform(outcome)
    }

    /// Hover over a row.
    func hoverPowerMenuItem(_ index: Int) {
        // M7m pre-build review (QA minor): nothing moves under the dim.
        guard idlePhase == .awake, pointerMovedSinceLastCommand, var menu = powerMenu else { return }
        menu.focus(index: index)
        powerMenu = menu
    }

    /// Every source's commands while the menu is open, a paired phone's included (U3, accepted 2026-11-06: the phone
    /// can't open the menu, but may move through and choose in one that's open; Relaunch and Restart still need the PIN).
    private func routePowerMenu(_ command: RemoteCommand) {
        guard var menu = powerMenu else { return }
        let outcome = menu.handle(command)
        powerMenu = menu
        perform(outcome)
    }

    private func perform(_ outcome: PowerMenu.Outcome) {
        switch outcome {
        case .none:
            break
        case .close:
            closePowerMenu(reason: .cancelled)
        case .choose(let action):
            // Closed first (the PIN screen must not sit under it), told after: `onPowerMenuClose` sees the PIN screen
            // Relaunch and Restart may have opened.
            powerMenu = nil
            runPowerAction(action)
            Self.logger.info("Power menu closed (\(action.rawValue, privacy: .public))")
            onPowerMenuClose?(.other)
        }
    }

    /// D20: Relaunch and Restart ask for the PIN when one is set; cancelling it returns to the screen the PIN screen
    /// replaced (Settings, else home: like Quit, it can't sit over Live TV or YouTube) and the menu stays closed.
    private func runPowerAction(_ action: PowerMenuAction) {
        guard action != .cancel else { return }
        guard action.needsPIN, hasPIN else {
            onPowerAction?(action)
            return
        }
        if screen != .home && screen != .settings { goHome() }
        requestPIN(action == .relaunch ? .relaunch : .restartMac)
    }

    // MARK: Tile menu (M7m L5–L11, D50)

    /// Over the home screen, on its first item, for the tile at `index` (into `visibleItems`).
    func openTileMenu(_ index: Int) {
        guard screen == .home, tileMenu == nil, visibleItems.indices.contains(index) else { return }
        let item = visibleItems[index]
        // The tile's own title as the home screen shows it (the default browser's name).
        var shown = item
        shown.title = launcher.title(for: item)
        tileMenuShowsPINLock = hasPIN
        let menu = TileMenu.make(for: shown, isStartTile: item.id == startTileID, isRunning: launcher.isRunning(item),
                                 youTubeOpened: youtube.hasOpened, ownBundleID: Bundle.main.bundleIdentifier,
                                 bundleID: launcher.bundleID(for: item))
        tileMenu = menu
        let actions = menu.items.map(\.action.rawValue).joined(separator: ", ")
        Self.homeLogger.info("Tile menu: \(item.id, privacy: .public) opened (\(actions, privacy: .public))")
    }

    func closeTileMenu(reason: String = "closed") {
        guard let menu = tileMenu else { return }
        tileMenu = nil
        Self.homeLogger.info("Tile menu: \(menu.tileID, privacy: .public) \(reason, privacy: .public)")
    }

    /// A click on a row.
    func chooseTileMenuItem(_ index: Int) {
        guard var menu = tileMenu else { return }
        let outcome = menu.choose(index: index)
        tileMenu = menu
        performTileMenu(outcome)
    }

    /// Hover over a row.
    func hoverTileMenuItem(_ index: Int) {
        // M7m pre-build review (QA minor): nothing moves under the dim.
        guard idlePhase == .awake, pointerMovedSinceLastCommand, var menu = tileMenu else { return }
        menu.focus(index: index)
        tileMenu = menu
    }

    /// Every source's commands while the menu is open (a paired phone's too: its Menu button opens it).
    private func routeTileMenu(_ command: RemoteCommand) {
        guard var menu = tileMenu else { return }
        let outcome = menu.handle(command)
        tileMenu = menu
        performTileMenu(outcome)
    }

    /// Closed first (a PIN screen must not sit under it). L9, D20: with a PIN set, the edits ask first.
    private func performTileMenu(_ outcome: TileMenu.Outcome) {
        switch outcome {
        case .none:
            break
        case .close:
            closeTileMenu()
        case .choose(let action):
            guard let id = tileMenu?.tileID else { return }
            tileMenu = nil
            Self.homeLogger.info("Tile menu: \(id, privacy: .public) \(action.rawValue, privacy: .public)")
            if action.needsPIN && hasPIN {
                requestPIN(.tileAction(id: id, action: action))
            } else {
                runTileAction(action, id: id)
            }
        }
    }

    /// Runs a tile menu item (after the PIN, when it asked). Edits go through Settings, so its tile list and
    /// `launch-items.json` stay in step (`settings.perform` → `applyItems` → `setItems`).
    private func runTileAction(_ action: TileMenuAction, id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch action {
        case .move:
            startMoving(id)
        case .quit:
            tileMenuTask = Task { [launcher] in await launcher.quit(item) }
        case .restart:
            // L7: quit, then open it as Select would (a protected tile asks for the PIN then).
            tileMenuTask = Task { [weak self, launcher] in
                await launcher.quit(item)
                self?.activateTile(id: id, after: .restart)
            }
        case .reloadYouTube:
            youtube.reload()
            activateTile(id: id, after: .reloadYouTube)
        case .hide:
            guard item.isVisible else { return }
            settings.perform(.toggleTileVisible(id: id))
            // L11: where to get it back.
            showToast("Hidden · Settings → Home Screen shows it again", "eye.slash")
        case .startHere:
            settings.perform(.setStartTile(id: id))
        case .toggleFullScreen:
            settings.perform(.toggleTileFullScreen(id: id))
        case .toggleRequiresPIN:
            settings.perform(.toggleTileRequiresPIN(id: id))
        case .tileSettings:
            openSettings(atTile: id)
        }
    }

    /// Restart and Reload: Select on the tile, if it's still on the home screen and nothing else took over meanwhile
    /// (a restart waits up to 6 s for the app to quit).
    private func activateTile(id: String, after action: TileMenuAction) {
        let skipped: String? = if !isAppActive {
            "MMTVL isn't in front"
        } else if screen != .home {
            "not on the home screen"
        } else if isLeavingHome {
            "another tile is opening"
        } else if tileMenu != nil || powerMenu != nil {
            "a menu is open"
        } else if movingTileID != nil {
            "a tile is being moved"
        } else {
            nil
        }
        guard skipped == nil, let index = visibleItems.firstIndex(where: { $0.id == id }) else {
            let why = skipped ?? "the tile isn't on the home screen"
            Self.homeLogger.info(
                "Tile menu: \(id, privacy: .public) \(action.rawValue, privacy: .public): not reopened (\(why, privacy: .public))")
            return
        }
        activate(index)
    }

    // MARK: Move mode (M7m L8)

    /// The tile menu's Move (after the PIN, when one is set): focus on the tile, out of the top shelf.
    private func startMoving(_ id: String) {
        guard screen == .home, let index = visibleItems.firstIndex(where: { $0.id == id }) else {
            Self.homeLogger.info("Move: \(id, privacy: .public) not started (not on the home screen)")
            return
        }
        shelfIndex = nil
        withAnimation(Theme.focusAnimation) { _ = focus.focus(index: index) }
        movingTileID = id
        Self.homeLogger.info("Move: \(id, privacy: .public) started")
    }

    private func endMoving(reason: String) {
        guard let id = movingTileID else { return }
        movingTileID = nil
        Self.homeLogger.info("Move: \(id, privacy: .public) ended (\(reason, privacy: .public))")
    }

    /// Commands while a tile moves. Each arrow saves at once (`settings.moveTile` → `applyItems` → `setItems`, which
    /// keeps focus on the tile). Up never enters the top shelf.
    private func routeMoving(_ command: RemoteCommand, id: String, isRepeat: Bool) -> Bool {
        switch command {
        case .up, .down, .left, .right:
            guard let current = visibleItems.firstIndex(where: { $0.id == id }) else {
                endMoving(reason: "the tile left the home screen")
                return true
            }
            let target = Self.moveTarget(command, from: current, count: visibleItems.count, perRow: Theme.tilesPerRow)
            guard target != current else { return true }
            withAnimation(Theme.focusAnimation) { settings.moveTile(id: id, toVisibleIndex: target) }
            Self.homeLogger.debug("Move: \(id, privacy: .public) to \(target)")
            return true
        case .select, .back, .menu, .home:
            // A held key's repeats (the Select that chose Move, a held Menu) don't end it; Home always does.
            if isRepeat && command != .home { return true }
            endMoving(reason: "\(command)")
            return true
        case .playPause, .fastForward, .rewind, .channelUp, .channelDown,
             .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return false
        }
    }

    /// L8: the neighbouring visible place. Left/Right ±1 and Down ±`perRow`, clamped to the tiles; Up from the first
    /// row and Down from the last stay put.
    static func moveTarget(_ command: RemoteCommand, from index: Int, count: Int, perRow: Int) -> Int {
        guard count > 0 else { return index }
        let last = count - 1
        switch command {
        case .left:
            return max(index - 1, 0)
        case .right:
            return min(index + 1, last)
        case .up:
            return index - perRow >= 0 ? index - perRow : index
        case .down:
            return index / perRow < last / perRow ? min(index + perRow, last) : index
        default:
            return index
        }
    }

    private func bumpFocusMotion(_ direction: RemoteCommand) {
        focusMotion = FocusMotion(direction: direction, generation: focusMotion.generation + 1)
    }

    /// Shows the home screen, keeping the focus position. Leaving YouTube pauses it (L3); leaving Live TV stops it (M4 L7).
    func goHome() {
        if isLeavingHome { finishLeavingHome(animated: false) }
        closePowerMenu()
        closeTileMenu(reason: "closed (home)")
        endMoving(reason: "home")
        if screen == .youtube {
            youtube.pause()
        }
        if screen == .liveTV {
            // M7c L25: the channel keeps playing as the preview; `updateLivePreview` below stops it if unwanted.
            liveTV.leave(keepingPreview: livePreviewEnabled)
        }
        closePINEntry()
        if screen == .settings { settings.screenDidClose() }
        screen = .home
        hasPINCache = hasPIN
        tileArt.reloadIfChanged()
        topShelf.refresh(focusing: focusedItem)
        shelfContentChanged()
        updateLivePreview()
    }

    var hasPIN: Bool { pinStore.load() != nil }

    /// Shows the PIN screen; cancelling returns to the current screen (home or Settings).
    func requestPIN(_ purpose: PINPurpose) {
        screenBeforePIN = screen == .settings ? .settings : .home
        pinEntry = PINEntryModel(purpose: purpose, storedPIN: pinStore.load(), lockout: pinLockout)
        screen = .pin(purpose)
    }

    /// M7c L9: ⌘Q or the Dock's Quit while the kiosk lock is on: the PIN first, if one is set.
    func requestQuit() {
        if case .pin(.quit) = screen { return }
        if hasPIN {
            // The PIN screen can't sit over Live TV or YouTube (they'd keep playing); cancelling returns home.
            if screen != .home && screen != .settings { goHome() }
            requestPIN(.quit)
        } else {
            onQuit?()
        }
    }

    /// Mouse click on the PIN screen's keypad.
    func pinEnter(row: Int, column: Int) {
        guard let result = pinEntry?.enter(row: row, column: column) else { return }
        finishPIN(result)
    }

    private func finishPIN(_ result: PINEntryModel.Result) {
        guard let purpose = pinEntry?.purpose else { return }
        closePINEntry()
        defer { hasPINCache = hasPIN }
        switch result {
        case .cancelled:
            returnFromPIN()
        case .verified:
            switch purpose {
            case .openSettings:
                openSettings()
            case .openTile(let id):
                screen = .home
                if let item = visibleItems.first(where: { $0.id == id }) { open(item) }
            case .exitToDesktop:
                screen = .home
                onExitToDesktop?()
            case .quit:
                returnFromPIN()
                onQuit?()
            case .relaunch:
                returnFromPIN()
                onPowerAction?(.relaunch)
            case .restartMac:
                returnFromPIN()
                onPowerAction?(.restartMac)
            case .tileAction(let id, let action):
                // M7m L9: Tile Settings… opens Settings without asking again.
                screen = .home
                runTileAction(action, id: id)
            case .setNew, .change, .turnOff:
                returnFromPIN()
            }
        case .newPIN(let pin):
            do {
                try pinStore.save(pin)
            } catch {
                Self.logger.error("Failed to save the PIN: \(error.localizedDescription, privacy: .public)")
            }
            returnToSettings()
        case .removed:
            do {
                try pinStore.remove()
            } catch {
                Self.logger.error("Failed to remove the PIN: \(error.localizedDescription, privacy: .public)")
            }
            returnToSettings()
        }
    }

    /// Back to the screen the PIN screen covered. Settings: through `returnToSettings()`, which re-reads every status
    /// (M7h step 13e: part refreshes while the PIN screen showed were dropped, as Settings wasn't showing).
    private func returnFromPIN() {
        if screenBeforePIN == .settings {
            returnToSettings()
        } else {
            screen = screenBeforePIN
        }
    }

    /// Back to the same Settings page (not `openSettings()`, which resets the page stack).
    private func returnToSettings() {
        screen = .settings
        settings.refreshStatus()
    }

    /// Keeps the lockout for the next PIN screen.
    private func closePINEntry() {
        if let pinEntry { pinLockout = pinEntry.lockout }
        pinEntry = nil
    }

    func openYouTube() {
        youtube.open()
        screen = .youtube
    }

    /// M7b L4: a YouTube cast takes over the TV from any screen. No PIN, even for a protected YouTube tile
    /// (user choice). nil query = keep the page (leanback already paired).
    func castYouTube(query: String?) {
        if screen != .youtube { goHome() }
        if let query {
            youtube.launch(query: query)
        } else {
            youtube.open()
        }
        screen = .youtube
    }

    /// nil = the last channel or Multiview; else that channel full screen (a top shelf card, M7 L13).
    func openLiveTV(channelID: Channel.ID? = nil) {
        liveTV.open(channelID: channelID)
        screen = .liveTV
    }

    func showAccessibilityOnboarding() {
        screen = .accessibilityOnboarding
    }

    func openSettings() {
        settings.reset()
        screen = .settings
    }

    /// M7m L10: Settings on the tile's page (the tile menu's Tile Settings…, after its PIN).
    func openSettings(atTile id: String) {
        settings.openTile(id)
        screen = .settings
    }

    private var pointerMovedSinceLastCommand: Bool {
        NSEvent.mouseLocation != pointerLocationAtLastCommand
    }

    func hover(_ index: Int) {
        // M7m L8: focus stays on a moving tile. Pre-build review (QA minor): nothing moves under the dim.
        guard idlePhase == .awake, screen == .home, movingTileID == nil, pointerMovedSinceLastCommand else { return }
        shelfIndex = nil
        var moved = false
        withAnimation(Theme.focusAnimation) { moved = focus.focus(index: index) }
        if moved {
            topShelf.refresh(focusing: focusedItem)
            syncCarousel()
        }
    }

    /// L21: the mouse wheel moves home focus one row per `Theme.homeScrollStep` points (trackpad) or per line (wheel).
    /// Positive deltas (content moves down) move focus up. Other screens ignore it.
    func scrollWheel(deltaY: CGFloat, precise: Bool) {
        guard screen == .home, deltaY != 0 else { return }
        // M7m L19 (QA step 6, finding 2): a wheel event while dimmed only wakes; otherwise it's activity.
        guard idlePhase == .awake else {
            wakeFromIdle(by: "the scroll wheel")
            scrollAccumulator = 0
            lastScrollAt = now()
            return
        }
        noteActivity()
        let time = now()
        if let lastScrollAt, time.timeIntervalSince(lastScrollAt) > 0.3 { scrollAccumulator = 0 }
        lastScrollAt = time
        // A direction change starts over.
        if scrollAccumulator != 0 && (scrollAccumulator > 0) != (deltaY > 0) { scrollAccumulator = 0 }
        scrollAccumulator += deltaY
        let step = precise ? Theme.homeScrollStep : 1
        while abs(scrollAccumulator) >= step {
            let up = scrollAccumulator > 0
            scrollAccumulator -= up ? step : -step
            _ = handle(up ? .up : .down)
        }
    }

    /// M7m pre-build review (QA minor): a click on the dim (it takes clicks only while dimmed) only wakes the screen.
    func clickOnIdleDim() {
        guard idlePhase != .awake else { return }
        wakeFromIdle(by: "click")
    }

    /// `page`: the page of the column the row is in; only the current page's rows take focus.
    func hoverSettingsRow(_ id: String, on page: SettingsPage) {
        guard idlePhase == .awake, screen == .settings, pointerMovedSinceLastCommand else { return }
        settings.focus(rowID: id, on: page)
    }

    /// `index` is into `visibleItems`.
    func activate(_ index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        // M7m L8: a click on a tile while one moves ends move mode, like Select, and opens nothing.
        if movingTileID != nil {
            endMoving(reason: "click")
            return
        }
        focus.focus(index: index)
        let item = visibleItems[index]

        if item.isPINProtected && hasPIN {
            if item.isSettingsTile {
                requestPIN(.openSettings)
            } else if item.isExitToDesktop {
                requestPIN(.exitToDesktop)
            } else {
                requestPIN(.openTile(id: item.id))
            }
            return
        }
        open(item)
    }

    /// Opens a tile without asking for the PIN (already checked or not needed).
    private func open(_ item: LaunchItem) {
        switch item.kind {
        case .application, .url, .defaultBrowser:
            guard launcher.isInstalled(item) else {
                // L6: not-installed tiles only shake.
                shakeTriggers[item.id, default: 0] += 1
                return
            }
            // M7h L16: a restart (up to ~6 s) holds the home exit until the new process has opened.
            let restarts = launcher.willRestart(item)
            let launch = { [weak self] in
                let task = Task {
                    do {
                        try await self?.launcher.launch(item)
                    } catch {
                        Self.logger.error("Failed to launch \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        self?.shakeTriggers[item.id, default: 0] += 1
                    }
                }
                if restarts, self?.isLeavingHome == true { self?.restartingLaunch = task }
            }
            // M7c L23: the Plex tile (its carousel showing) fades to its art first; the UI stays away until the app
            // takes the screen.
            if !isLeavingHome && item.id == focusedItem?.id && shelfContent.isCarousel {
                leaveHome(untilInactive: true) { launch() }
            } else {
                launch()
            }
        case .internalDestination(.settings):
            openSettings()
        case .internalDestination(.youtube):
            openYouTube()
        case .internalDestination(.iptv):
            // M7c L21: a page other than the first keeps playing after Down; Select opens that channel.
            // L22: after the home UI animates away (the preview's video stays put).
            let channelID = livePageChannelID
            leaveHome { [weak self] in self?.openLiveTV(channelID: channelID) }
        case .system(.exitToDesktop):
            onExitToDesktop?()
        }
    }
}

/// Lays the active screen out on the 1920×1080 canvas and scales it to the window.
struct LauncherRootView: View {
    let router: AppRouter
    let youtube: YouTubeController
    let liveTV: LiveTVModel

    var body: some View {
        ZStack {
            screenBody
            // M7m L5: over the home screen, under the power menu.
            tileMenuOverlay
            // M7h L15: above every screen, YouTube and Live TV (outside the canvas) included.
            powerMenuOverlay
            // M7m L18: the idle dimmer, above everything (the power menu too); a click on it only wakes (L19).
            idleDim
        }
        // M7l L4: every glass panel and tile rim below, the canvas, Live TV and the power menu alike.
        .environment(\.glassStyle, router.glassStyle)
    }

    /// M7m L18: a still screen darkens after a while without input; any press brings it back (`AppRouter.handle`).
    /// While dimmed it takes clicks, which only wake (pre-build review, QA minor); awake, clicks go through.
    private var idleDim: some View {
        Color.black
            .opacity(router.idlePhase == .awake ? 0 : Theme.idleDimOpacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { router.clickOnIdleDim() }
            .allowsHitTesting(router.idlePhase != .awake)
            .animation(Theme.idleDimAnimation, value: router.idlePhase == .awake)
    }

    /// M7m L5 (step 11): drawn like the power menu, its sibling: the dim over the whole window, the panel on the
    /// scaled canvas, the same fade. A click on the dim does nothing, as with the power menu.
    private var tileMenuOverlay: some View {
        ZStack {
            if let menu = router.tileMenu {
                GeometryReader { geometry in
                    Theme.menuDim
                    TileMenuView(menu: menu, hasPIN: router.tileMenuShowsPINLock,
                                 onHover: router.hoverTileMenuItem, onChoose: router.chooseTileMenuItem)
                        .scaleEffect(Theme.scale(for: geometry.size))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(Theme.menuFadeAnimation, value: router.tileMenu == nil)
    }

    /// Fades in and out by itself; screen changes underneath aren't animated with it (QA Q4).
    private var powerMenuOverlay: some View {
        ZStack {
            if let menu = router.powerMenu {
                GeometryReader { geometry in
                    // The dim covers the whole window, the panel is on the scaled canvas.
                    Theme.menuDim
                    PowerMenuView(menu: menu, hasPIN: router.powerMenuShowsPINLock,
                                  onHover: router.hoverPowerMenuItem, onChoose: router.choosePowerMenuItem)
                        .scaleEffect(Theme.scale(for: geometry.size))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(Theme.menuFadeAnimation, value: router.powerMenu == nil)
    }

    @ViewBuilder
    private var screenBody: some View {
        if router.screen == .youtube {
            // L4: outside the scaled canvas, at the window's real size.
            YouTubeView(controller: youtube)
        } else {
            GeometryReader { geometry in
                ZStack {
                    // M7h step 13h: one video layer for the home preview (M7c L15) and Live TV (M4 L16, M6 L15), at
                    // the same place for both, so a player's view never leaves the window between them.
                    videoLayer(in: geometry.size)
                    if router.screen == .liveTV {
                        // Overlays are scaled inside LiveTVRootView.
                        LiveTVRootView(model: liveTV)
                    } else {
                        content
                            .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
                            .scaleEffect(Theme.scale(for: geometry.size))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .background { screenBackground }
            .ignoresSafeArea()
        }
    }

    /// Black behind Live TV's video (the guide's preview rect, Multiview, setup and loading); else the gradient.
    @ViewBuilder
    private var screenBackground: some View {
        if router.screen == .liveTV {
            Color.black
        } else {
            Theme.backgroundGradient
        }
    }

    private var videoPlacements: [ScreenVideoPlacement] {
        ScreenVideoLayout.placements(screen: router.screen,
                                     liveTVPlacements: liveTV.videoPlacements,
                                     previewPlayer: liveTV.previewChannelID != nil ? liveTV.player : nil,
                                     showsPreview: router.showsLivePreviewVideo,
                                     homeFade: homeFade)
    }

    /// The players' video in window coordinates, outside the scaled canvas. Keyed by player identity, so a view
    /// that moves (home → Live TV, a Multiview window) keeps its GL context.
    private func videoLayer(in size: CGSize) -> some View {
        ForEach(videoPlacements) { placement in
            if let view = (placement.player as? MPVPlayerController)?.videoView {
                let rect = placement.canvasRect.map { CanvasGeometry.windowRect(forCanvasRect: $0, in: size) }
                    ?? CGRect(origin: .zero, size: size)
                MPVVideoRepresentable(view: view)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .transaction { $0.animation = nil }
                    .opacity(placement.opacity)
                    .transaction { if !placement.animatesOpacity { $0.animation = nil } }
                    .animation(Theme.focusAnimation, value: homeFade)
                    .animation(Theme.shelfBackdropCrossfade, value: router.showsLivePreviewVideo)
            }
        }
    }

    /// The backdrop's dim as the home rows scroll (M7c L19); the preview video follows it. Leaving home, the video
    /// comes up to full strength with the exit animation, as Live TV shows it (M7c step 35).
    private var homeFade: Double {
        router.isLeavingHome ? 1 : HomeLayout.heroOpacity(focusedRow: router.focus.position.row)
    }

    @ViewBuilder
    private var content: some View {
        switch router.screen {
        case .home:
            HomeView(
                items: router.visibleItems,
                focus: router.focus,
                launcher: router.launcher,
                tileArt: router.tileArt,
                shakeTriggers: router.shakeTriggers,
                focusMotion: router.focusMotion,
                shelf: router.shelfContent,
                shelfIndex: router.shelfIndex,
                carouselPage: router.carouselPage,
                revealsLivePreview: router.revealsLivePreview,
                isLeaving: router.isLeavingHome,
                versionLabel: router.homeVersionLabel,
                remoteBatteryLevel: router.remoteBatteryLevel,
                movingTileID: router.movingTileID,
                entryGeneration: router.homeEntryGeneration,
                onHoverCard: router.hoverShelfCard,
                onActivateCard: router.activateShelfCard,
                onRefreshShelf: {
                    router.topShelf.refresh(focusing: router.focusedItem)
                    router.onRefreshRemoteBattery?()
                },
                shelfImages: router.shelfImages,
                onHover: router.hover,
                onActivate: router.activate
            )
        case .accessibilityOnboarding:
            AccessibilityOnboardingView(
                onOpenSettings: { router.onRequestAccessibility?() },
                onNotNow: router.goHome
            )
        case .settings:
            SettingsView(
                model: router.settings,
                launcher: router.launcher,
                tileArt: router.tileArt,
                onHoverRow: router.hoverSettingsRow,
                onActivateRow: router.settings.activate(rowID:on:),
                onActivateParent: router.settings.activateParentColumn
            )
        case .youtube, .liveTV:
            // Shown by `body` outside the canvas.
            EmptyView()
        case .pin:
            if let pinEntry = router.pinEntry {
                PINEntryView(model: pinEntry, onEnter: router.pinEnter)
            }
        }
    }
}
