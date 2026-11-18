import Foundation
import Observation
import os

enum LiveTVOutcome: Equatable { case handled, leave, openSettings }

/// What the router needs; tests use a fake.
protocol LiveTVHosting: AnyObject {
    /// nil = the last channel or Multiview (M4/M6); a channel id plays that channel full screen (M7 L13).
    func open(channelID: Channel.ID?)
    /// M7c L25: `keepingPreview` keeps a single playing channel running as the home preview (muted, no reconnect).
    func leave(keepingPreview: Bool)
    func handle(_ command: RemoteCommand) -> LiveTVOutcome

    // M7c L15 (D37): the home screen's muted preview.
    /// nil = no preview.
    var previewChannelID: Channel.ID? { get }
    var isPreviewPlaying: Bool { get }
    /// The last preview failed; the router doesn't start another until focus comes back (L16).
    var previewFailed: Bool { get }
    /// Multiview's highlighted window if Multiview was left active, else the last channel; M7f L5: either only while
    /// it's in the playlist, else the first favorite.
    var defaultPreviewChannelID: Channel.ID? { get }
    func startPreview(channelID: Channel.ID)
    func stopPreview()
    /// M7f L5: the playlist was re-fetched; a preview whose channel left it stops.
    func playlistDidChange()
    /// M7m L17: Live TV shows moving video (the idle dimmer leaves it alone): the full-screen channel loading or
    /// playing (not paused), the watch guide's preview of the playing channel, or a Multiview window loading or
    /// playing. Observable.
    var isShowingVideo: Bool { get }
}

extension LiveTVHosting {
    func leave() { leave(keepingPreview: false) }
}

/// The Live TV screen: modes, channel zapping, overlays and command handling (M4 L9, L11, L13),
/// and Multiview with its player pool (M6).
@Observable
final class LiveTVModel: LiveTVHosting {
    enum Mode: Equatable { case setupNeeded, loading, player, guide, multiview, unavailable(String) }
    /// The guide watches channels, or picks one for a Multiview window (M6 L11).
    enum GuidePurpose: Equatable { case watch, pick(slot: Int) }
    struct Banner: Equatable {
        var channel: Channel
        var now: Programme?
        var next: Programme?
    }
    /// Where a player's video goes (M6 L15). The view only draws these.
    struct VideoPlacement: Identifiable {
        let player: any LivePlayer
        var id: ObjectIdentifier { ObjectIdentifier(player) }
        /// nil = the whole window.
        var canvasRect: CGRect?
        var isVisible: Bool
    }

    nonisolated static let playbackErrorMessage = "Can't play this channel"
    /// M7j L13: an antenna-only Live TV whose tuner has no channels.
    static let noChannelsMessage = "No channels found"
    static let shortSkip: Double = 10
    static let longSkip: Double = 30

    private(set) var mode: Mode = .loading
    private(set) var currentChannel: Channel?
    private(set) var banner: Banner?
    private(set) var showsTimeshiftBar = false
    /// M7m L12 (D51, burn-in): Multiview's bold outline on the focused window (and the empty and failed windows'
    /// text, L14). True on every command in Multiview and when it opens; false `multiviewHighlightDuration` after.
    private(set) var multiviewHighlightVisible = false
    /// M7m L15: while paused, the timeshift bar, the behind-live badge and Multiview's pause symbol show only while
    /// this is true: on every command (a pause is one), false `pausedOverlayDuration` after.
    private(set) var pausedOverlayVisible = false
    /// "Can't play this channel"
    private(set) var playbackError: String?
    private(set) var guide: GuideModel?
    /// A menu over Live TV (M6 L10); it takes every command but Home while open.
    private(set) var menu: LiveMenu?
    /// M7m L3: the menu a submenu (Layout, Match Guide) was opened from, focus included; Back goes back to it.
    private var menuParent: LiveMenu?
    /// M7m L3: the open menu is a submenu (Back goes back to `menuParent`).
    var isSubmenu: Bool { menu != nil && menuParent != nil }
    /// M7f L12: search over Live TV (the guide, the player or Multiview); it takes every command but Home while open.
    private(set) var search: LiveSearchModel?
    /// M7l L12: Choose Teams over the guide, and its top level's menu; it takes every command but Home while open.
    private(set) var teamPicker: TeamPicker?
    private(set) var teamPickerMenu: LiveMenu?
    /// The full-screen player. Multiview hands it between pool players (M6 L12).
    private(set) var player: any LivePlayer
    private(set) var guidePurpose: GuidePurpose = .watch
    /// Non-nil in `.multiview` and in the picker guide.
    private(set) var multiview: MultiviewModel?
    /// Each Multiview window's player.
    private(set) var tilePlayers: [Channel.ID: any LivePlayer] = [:]
    /// Each failed window's text (M6 L14: after its playlist refresh, "Can't play this channel"; M7j L8, L9: an
    /// antenna window's problem, e.g. "Both antenna tuners are in use" when it was never started).
    private(set) var windowErrors: [Channel.ID: String] = [:]
    /// The windows that show a failure.
    var failedWindows: Set<Channel.ID> { Set(windowErrors.keys) }
    /// M7c L15: the channel the home screen previews on `player` (muted, no sleep assertion); nil = none.
    private(set) var previewChannelID: Channel.ID?
    private(set) var previewFailed = false
    let library: IPTVLibrary
    /// M7 L22 (`settings.json` `channelUpMovesUpList`): Channel Up zaps up the list like the Up arrow;
    /// false = the higher channel number. Channel Down is the opposite. List paging ignores it.
    @ObservationIgnored var channelUpMovesUpList = true
    /// The last async work started by open()/commands; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    /// M7m L3 (QA): the Match Guide options load in flight; a newer open (or leave) cancels it.
    @ObservationIgnored private var matchGuideTask: Task<Void, Never>?
    /// M7f L5: the playlist and guide check of an open that adopted the preview; tests await it. Not cancelled by
    /// leaving (a fetch in flight finishes).
    @ObservationIgnored private(set) var adoptRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    /// 5 s; tests assert state right after a command, never wait for hiding.
    @ObservationIgnored private let overlayDuration: Duration
    /// M7m L16: `Theme.guideIdleReturn` (3 min); tests pass milliseconds.
    @ObservationIgnored private let guideIdleReturn: Duration
    /// M7m L16: restarted by every command, `open` and `openGuide`; cancelled by `leave`. Tests await it.
    @ObservationIgnored private(set) var guideIdleTask: Task<Void, Never>?
    /// M7m L12: `Theme.multiviewHighlightDuration` (5 s), `Theme.pausedOverlayDuration` (15 s); tests pass
    /// milliseconds.
    @ObservationIgnored private let multiviewHighlightDuration: Duration
    @ObservationIgnored private let pausedOverlayDuration: Duration
    /// M7m L12, L15: replaced on each show, cancelled by `leave`. Tests await them.
    @ObservationIgnored private(set) var multiviewHighlightTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pausedOverlayTask: Task<Void, Never>?
    @ObservationIgnored private var refreshedAfterFailure = false
    /// The pool (M6 L2); players[0] is the init player. Never shrinks.
    @ObservationIgnored private var players: [any LivePlayer]
    @ObservationIgnored private let makePlayer: () -> any LivePlayer
    @ObservationIgnored private var refreshedWindows: Set<Channel.ID> = []
    @ObservationIgnored private var appVolume: (level: Int, muted: Bool)?
    @ObservationIgnored private var bannerGeneration = 0
    @ObservationIgnored private var barGeneration = 0
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
    @ObservationIgnored private let antennaLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")
    /// M7c L24: `ChannelLogoCache.prefetch`, set by the app (tests fetch nothing).
    @ObservationIgnored var prefetchLogos: ([URL]) -> Void = { _ in }
    static let logoPrefetchRows = 30
    /// M7c L29: `StreamResolver.prefetch`, set by the app (tests resolve nothing).
    @ObservationIgnored var prefetchStreams: ([URL]) -> Void = { _ in }
    /// M7c L31: resolves a channel and has the relay fetch its playlists and start segments; set by the app.
    @ObservationIgnored var warmStream: (URL) -> Void = { _ in }
    /// M7c L31: how long the guide's highlight must rest on a channel before it's warmed (scrolling past isn't).
    @ObservationIgnored var guideWarmDelay: Duration = .milliseconds(400)
    /// A channel warmed this recently isn't warmed again (Left/Right in its row).
    static let guideRewarmInterval: TimeInterval = 5
    /// Readable so tests await the warm instead of sleeping on the wall clock (M7m pre-build review, a flake).
    @ObservationIgnored private(set) var guideWarmTask: Task<Void, Never>?
    /// M7f L12: the programme query waits this long after the last keystroke; tests use zero.
    @ObservationIgnored var searchDebounce: Duration = .milliseconds(300)
    @ObservationIgnored private var lastWarm: (id: Channel.ID, at: Date)?

    init(player: any LivePlayer, makePlayer: @escaping () -> any LivePlayer, library: IPTVLibrary,
         now: @escaping () -> Date = Date.init, overlayDuration: Duration = .seconds(5),
         guideIdleReturn: Duration = Theme.guideIdleReturn,
         multiviewHighlightDuration: Duration = Theme.multiviewHighlightDuration,
         pausedOverlayDuration: Duration = Theme.pausedOverlayDuration) {
        self.player = player
        self.makePlayer = makePlayer
        self.library = library
        self.now = now
        self.overlayDuration = overlayDuration
        self.guideIdleReturn = guideIdleReturn
        self.multiviewHighlightDuration = multiviewHighlightDuration
        self.pausedOverlayDuration = pausedOverlayDuration
        players = [player]
        configure(player)
    }

    // MARK: - LiveTVHosting

    func open(channelID: Channel.ID? = nil) {
        pendingTask?.cancel()
        restartGuideIdle()
        playbackError = nil
        // M7j L13: a playlist or the antenna turned on (a search for tuners may still be due).
        guard library.canHaveLiveSource else {
            stopPreview()
            mode = .setupNeeded
            return
        }
        // M7c L15: a channel the preview already plays is adopted, before any loading screen.
        if adoptPreview(channelID: channelID) {
            logger.notice("Live TV opened on the home preview's stream (no reconnect)")
            // M7f L5: the playlist too (finished games go away); a re-fetch reaches the guide through the lineup.
            let library = library
            adoptRefreshTask = Task { await library.refreshIfStale() }
            return
        }
        stopPreview()
        // Shown while the playlist is checked (instant when it is fresh).
        mode = .loading
        let library = library
        Task { await library.refreshGuideIfStale() }
        pendingTask = Task {
            // M7j L13: before the antenna's first search, wait for it (an antenna-only Live TV has nothing else);
            // after it, a stale lineup is read in the background and reaches the guide through the lineup.
            if library.antenna.isEnabled && !library.antenna.hasSearched {
                await library.refreshChannelsIfStale()
            } else {
                Task { await library.refreshAntennaIfStale() }
                await library.refreshPlaylistIfStale()
            }
            guard !Task.isCancelled else { return }
            guard !library.channels.isEmpty else {
                if !library.hasPlaylist, case .failed(let message) = library.antenna.status {
                    // M7j L13 (QA, step 4): the search found a tuner but its lineup couldn't be read.
                    mode = .unavailable(message)
                } else if !library.hasLiveSource {
                    // M7j L13: no playlist, and the search found no tuner.
                    mode = .setupNeeded
                } else if case .failed(let message) = library.playlistStatus {
                    mode = .unavailable(message)
                } else if library.hasPlaylist {
                    mode = .unavailable("The playlist has no channels")
                } else {
                    mode = .unavailable(Self.noChannelsMessage)
                }
                return
            }
            // M7 L13: a top shelf card plays its channel full screen, leaving Multiview (kept, inactive).
            if let channelID, let channel = library.channels.first(where: { $0.id == channelID }) {
                if var snapshot = library.state.multiview, snapshot.isActive {
                    snapshot.isActive = false
                    library.rememberMultiview(snapshot)
                }
                play(channel)
                return
            }
            if let snapshot = library.state.multiview, snapshot.isActive {
                let multiview = MultiviewModel(snapshot: snapshot, validIDs: Set(library.channels.map(\.id)))
                if !multiview.isEmpty {
                    startMultiview(multiview, reusing: nil)
                    return
                }
                var inactive = snapshot
                inactive.isActive = false
                library.rememberMultiview(inactive)
            }
            if let id = library.state.lastChannelID, let channel = library.channels.first(where: { $0.id == id }) {
                play(channel)
            } else {
                openGuide()
            }
        }
    }

    // MARK: - Home preview (M7c L15, L16)

    var isPreviewPlaying: Bool {
        previewChannelID != nil && player.state.phase == .playing
    }

    var defaultPreviewChannelID: Channel.ID? {
        let ids = Set(library.channels.map(\.id))
        if let snapshot = library.state.multiview, snapshot.isActive,
           let id = MultiviewModel(snapshot: snapshot, validIDs: ids).focusedChannelID {
            return id
        }
        if let id = library.state.lastChannelID, ids.contains(id) { return id }
        return library.lineup.favorites.first?.id
    }

    func playlistDidChange() {
        guard let id = previewChannelID, !library.channels.contains(where: { $0.id == id }) else { return }
        logger.notice("The preview's channel left the playlist; the preview stops")
        stopPreview()
    }

    /// Muted, without a sleep assertion. The same channel again is a no-op.
    func startPreview(channelID: Channel.ID) {
        guard library.hasLiveSource, let channel = channel(channelID), previewChannelID != channelID else { return }
        // M7j L18 (step 9b QA): no stream is asked of a tuner while it scans; the home screen shows no preview.
        // Step 10 (security N1): only that tuner's channels.
        if case .antenna(let deviceID) = channel.source, library.antenna.isScanning(deviceID: deviceID) { return }
        previewFailed = false
        previewChannelID = channelID
        player.setAudible(false)
        player.setHoldsSleepAssertion(false)
        player.setBufferProfile(.full)
        player.play(channel.streamURL, direct: channel.isDirectStream)
    }

    func stopPreview() {
        previewFailed = false
        endPreview()
    }

    /// M7j L18: before a channel scan (`IPTVLibrary.stopAntennaStreams`). The scan starts from Settings, and opening
    /// Settings leaves Live TV (which releases every player but a kept preview), so the home preview is the only
    /// stream MMTVL can hold then: it stops when its channel is an antenna channel.
    func stopAntennaStreams() {
        guard let id = previewChannelID, channel(id)?.isDirectStream == true else { return }
        antennaLogger.notice("Stopped the home preview for a channel scan")
        stopPreview()
    }

    /// Stops the stream and gives the player its sound and sleep assertion back.
    private func endPreview() {
        guard previewChannelID != nil else { return }
        player.stop()
        restorePreviewPlayer()
    }

    private func restorePreviewPlayer() {
        player.setAudible(true)
        player.setHoldsSleepAssertion(true)
        previewChannelID = nil
    }

    /// The target `open` would play: one channel, or Multiview. Adopts the preview's player when it already plays it.
    private func adoptPreview(channelID: Channel.ID?) -> Bool {
        guard let previewID = previewChannelID, player.state.phase == .loading || player.state.phase == .playing,
              !library.channels.isEmpty
        else { return false }
        let snapshot = library.state.multiview
        if let channelID {
            guard channelID == previewID, let channel = channel(channelID) else { return false }
            if var snapshot, snapshot.isActive {
                snapshot.isActive = false
                library.rememberMultiview(snapshot)
            }
            adopt(channel)
            return true
        }
        if let snapshot, snapshot.isActive {
            let multiview = MultiviewModel(snapshot: snapshot, validIDs: Set(library.channels.map(\.id)))
            if !multiview.isEmpty {
                guard multiview.slot(of: previewID) != nil else { return false }
                restorePreviewPlayer()
                // `applyAudio` mutes every window but the one with sound.
                startMultiview(multiview, reusing: previewID)
                return true
            }
        }
        guard library.state.lastChannelID == previewID, let channel = channel(previewID) else { return false }
        adopt(channel)
        return true
    }

    /// Full screen on the preview's stream: no new `play`, no reconnect.
    private func adopt(_ channel: Channel) {
        restorePreviewPlayer()
        prefetchNeighbors(of: channel)
        currentChannel = channel
        refreshedAfterFailure = false
        library.rememberChannel(channel.id)
        guide = nil
        mode = .player
        showBanner()
    }

    /// Keeps `currentChannel` so the guide can focus it later, and the Multiview snapshot (M6 L13).
    /// M7c L25: `keepingPreview` keeps a single channel that's loading or playing running as the home preview.
    func leave(keepingPreview: Bool) {
        pendingTask?.cancel()
        pendingTask = nil
        matchGuideTask?.cancel()
        matchGuideTask = nil
        guideIdleTask?.cancel()
        guideIdleTask = nil
        multiviewHighlightTask?.cancel()
        multiviewHighlightTask = nil
        multiviewHighlightVisible = false
        pausedOverlayTask?.cancel()
        pausedOverlayTask = nil
        pausedOverlayVisible = false
        let phase = player.state.phase
        let kept = keepingPreview && multiview == nil && playbackError == nil && (phase == .loading || phase == .playing)
            ? currentChannel : nil
        if multiview != nil { saveSnapshot(true) }
        for player in players where kept == nil || player !== self.player { release(player) }
        player.setBufferProfile(.full)
        tilePlayers = [:]
        windowErrors = [:]
        refreshedWindows = []
        multiview = nil
        guidePurpose = .watch
        guide = nil
        menu = nil
        menuParent = nil
        closeSearch()
        closeTeamPicker()
        banner = nil
        showsTimeshiftBar = false
        playbackError = nil
        bannerGeneration += 1
        barGeneration += 1
        if let kept {
            player.setAudible(false)
            player.setHoldsSleepAssertion(false)
            previewFailed = false
            previewChannelID = kept.id
            logger.notice("Left Live TV; the channel keeps playing as the home preview")
        }
    }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        if command == .home { return .leave }
        restartGuideIdle()
        // M7m L15: unconditionally, since mpv reports a pause a moment after `togglePause`; the views read it only
        // while paused.
        showPausedOverlay()
        // M7m L12: every command in Multiview (its menus included), and one that opens it (the picker's Select).
        defer { if mode == .multiview { showMultiviewHighlight() } }
        if teamPicker != nil {
            handleTeamPicker(command)
            return .handled
        }
        if var menu {
            let outcome = menu.handle(command)
            self.menu = menu
            switch outcome {
            case .none:
                break
            case .close:
                // M7m L3: Back from a submenu goes back to its menu; from a menu, closes it.
                self.menu = menuParent
                menuParent = nil
            case .choose(let action):
                self.menu = nil
                switch action {
                case .chooseLayout, .openMatchGuide: menuParent = menu
                default: menuParent = nil
                }
                perform(action)
            }
            return .handled
        }
        if let search {
            switch search.handle(command) {
            case .none: break
            case .close: closeSearch()
            case .choose(let result): choose(result)
            case .toggleTeam(let id):
                // M7l L12: search stays open; the row shows "In My Teams".
                library.setTeamPicked(id, !library.isTeamPicked(id))
                channelsChanged()
            }
            return .handled
        }
        switch mode {
        case .setupNeeded:
            switch command {
            case .select: return .openSettings
            case .back: return .leave
            default: return .handled
            }
        case .unavailable:
            switch command {
            case .select:
                open()
                return .handled
            case .back: return .leave
            default: return .handled
            }
        case .loading:
            return .handled   // M7m L1 (D49): Back stays while loading (a stray press mustn't drop you out); only Home leaves.
        case .player:
            return handlePlayer(command)
        case .guide:
            return handleGuide(command)
        case .multiview:
            return handleMultiview(command)
        }
    }

    /// Phone in-app volume (D25): every pool player, and players created later.
    func setAppVolume(_ level: Int, muted: Bool) {
        appVolume = (level, muted)
        for player in players { player.setVolume(level, muted: muted) }
    }

    /// M6 L15.
    var videoPlacements: [VideoPlacement] {
        switch mode {
        case .player:
            return [VideoPlacement(player: player, canvasRect: nil, isVisible: true)]
        case .guide:
            guard case .pick = guidePurpose, let multiview else {
                return [VideoPlacement(player: player, canvasRect: Theme.guidePreviewRect, isVisible: true)]
            }
            // The window with sound is the preview; the others keep playing, invisible, so their GL contexts survive.
            return multiview.slots.enumerated().compactMap { slot, id in
                guard let id, let player = tilePlayers[id] else { return nil }
                let isPreview = id == multiview.audioChannelID
                return VideoPlacement(player: player,
                                      canvasRect: isPreview ? Theme.guidePreviewRect : multiview.layout.slots[slot],
                                      isVisible: isPreview)
            }
        case .multiview:
            guard let multiview else { return [] }
            return multiview.slots.enumerated().compactMap { slot, id in
                guard let id, let player = tilePlayers[id] else { return nil }
                return VideoPlacement(player: player, canvasRect: multiview.layout.slots[slot], isVisible: true)
            }
        case .setupNeeded, .loading, .unavailable:
            return [VideoPlacement(player: player, canvasRect: nil, isVisible: false)]
        }
    }

    /// The window with sound in the picker guide, else `player`.
    var previewPlayer: any LivePlayer {
        if case .pick = guidePurpose, let id = multiview?.audioChannelID, let player = tilePlayers[id] { return player }
        return player
    }

    /// The guide's "playing" mark: the window with sound in the picker guide, else currentChannel.
    var previewChannel: Channel? {
        if case .pick = guidePurpose { return multiview?.audioChannelID.flatMap(self.channel) }
        return currentChannel
    }

    /// The view calls this when `library.guideRevision` changes.
    func guideDataChanged() {
        guard mode == .guide else { return }
        loadProgrammes()
    }

    /// The view calls this when `library.lineup` changes; the model calls it after favorites/hiding changes too.
    func channelsChanged() {
        guide?.setLineup(library.lineup)
        if mode == .guide { loadProgrammes() }
    }

    /// The playing channel can return to full screen.
    private var isPlaying: Bool {
        currentChannel != nil && player.state.phase != .idle && player.state.phase != .failed
    }

    // MARK: - Player mode

    private func handlePlayer(_ command: RemoteCommand) -> LiveTVOutcome {
        switch command {
        case .up: zap(-1)
        case .down: zap(1)
        case .left: seek(-Self.shortSkip)
        case .right: seek(Self.shortSkip)
        case .rewind: seek(-Self.longSkip)
        case .fastForward: seek(Self.longSkip)
        case .playPause:
            player.togglePause()
            showTimeshiftBar()
        case .select:
            // M7c L11: Select shows the info banner and timeshift bar; a second Select hides them.
            if playbackError != nil, let channel = currentChannel {
                play(channel)
            } else if banner != nil || showsTimeshiftBar {
                hideOverlays()
            } else {
                showBanner()
                showTimeshiftBar()
            }
        case .back:
            // M7c L11: Back hides the overlays, else opens the guide (M7m L2: Back in the guide comes back here).
            if banner != nil || showsTimeshiftBar {
                hideOverlays()
            } else {
                openGuide()
            }
        case .home:
            return .leave
        case .menu:
            // M7 L5: the channel menu of the playing channel (no Move Up/Down: the guide isn't open).
            if let current = currentChannel {
                menuParent = nil
                menu = channelMenu(for: current.id)
            }
        case .channelUp, .channelDown:
            zap(channelStep(command))
        case .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            break   // M7h L3: handled before screens
        }
        return .handled
    }

    /// M7 L22: the zap step for Channel Up/Down.
    private func channelStep(_ command: RemoteCommand) -> Int {
        let up = channelUpMovesUpList ? -1 : 1
        return command == .channelUp ? up : -up
    }

    private func channel(_ id: Channel.ID) -> Channel? {
        library.channels.first { $0.id == id }
    }

    private func play(_ channel: Channel) {
        currentChannel = channel
        playbackError = nil
        refreshedAfterFailure = false
        // M7j L8: no `play` when the device's tuners are all MMTVL's already (a zap on `player` doesn't count).
        if let problem = tunerBudgetProblem(for: channel, excluding: player) {
            player.stop()
            playbackError = problem.message
        } else {
            player.play(channel.streamURL, direct: channel.isDirectStream)
        }
        prefetchNeighbors(of: channel)
        library.rememberChannel(channel.id)
        mode = .player
        guide = nil
        showBanner()
    }

    // MARK: - Guide mode

    private func handleGuide(_ command: RemoteCommand) -> LiveTVOutcome {
        if command == .playPause {
            previewPlayer.togglePause()
            return .handled
        }
        // M7 L5: the picker has no channel menu.
        if command == .menu, case .pick = guidePurpose { return .handled }
        guard var guide else { return .handled }
        let action = guide.handle(command, now: now())
        self.guide = guide
        scheduleGuideWarm()
        switch action {
        case .none:
            break
        case .play(let id):
            if case .pick(let slot) = guidePurpose {
                assignWindow(id, to: slot)
                closePicker()
            } else {
                watch(id)
            }
        case .channelMenu(let id):
            if case .pick(let slot) = guidePurpose {
                assignWindow(id, to: slot)
                closePicker()
            } else {
                menuParent = nil
                menu = channelMenu(for: id)
            }
        case .groupChanged(let group):
            library.rememberGroup(group)
            loadProgrammes()
        case .openSearch:
            openSearch()
        case .openTeamPicker:
            openTeamPicker()
        case .close:
            if case .pick = guidePurpose {
                closePicker()
                break
            }
            // M7m L2 (D49): Back in the watch guide goes back to the channel; with none, the guide stays.
            returnToChannel()
        }
        return .handled
    }

    /// M7c L31: once the highlight rests on a channel for `guideWarmDelay`, its stream is warmed, so Select starts
    /// it at once. Not the channel already playing, nor one already in a Multiview window. M7j L7: never an antenna
    /// channel (warming one would take a tuner).
    private func scheduleGuideWarm() {
        guideWarmTask?.cancel()
        guard mode == .guide, let channel = guide?.focusedChannel, !channel.isDirectStream,
              !(channel.id == currentChannel?.id && isPlaying), tilePlayers[channel.id] == nil
        else { return }
        if let lastWarm, lastWarm.id == channel.id, now().timeIntervalSince(lastWarm.at) < Self.guideRewarmInterval { return }
        let delay = guideWarmDelay
        guideWarmTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.mode == .guide, self.guide?.focusedChannel?.id == channel.id else { return }
            self.lastWarm = (channel.id, self.now())
            self.warmStream(channel.streamURL)
        }
    }

    /// M7m L2 (D49): Back in the watch guide has a channel to go back to: the one playing (even when a playlist
    /// refresh dropped it), or a failed or stopped one that is still in the playlist. The guide's hint follows it (L4).
    var canReturnToChannel: Bool {
        guard let current = currentChannel else { return false }
        return isPlaying || channel(current.id) != nil
    }

    /// M7m L2: full screen on the playing channel without a reconnect; else plays the current channel again
    /// (a failed one retries); with neither, nothing.
    private func returnToChannel() {
        guard canReturnToChannel, let current = currentChannel else { return }
        if isPlaying {
            mode = .player
            guide = nil
            showBanner()
        } else {
            watch(current.id)
        }
    }

    // MARK: - Guide idle return (M7m L16, D51)

    private func restartGuideIdle() {
        guideIdleTask?.cancel()
        let delay = guideIdleReturn
        guideIdleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.returnToVideo()
        }
    }

    /// Something on screen is moving: the full-screen channel (or the watch guide's preview of it), or a Multiview
    /// window (Multiview and the picker guide). Paused counts, as for `isPlaying`.
    private var hasVideo: Bool {
        if multiview != nil {
            return tilePlayers.values.contains { $0.state.phase != .idle && $0.state.phase != .failed }
        }
        return isPlaying
    }

    var isShowingVideo: Bool {
        switch mode {
        case .player:
            return isPlaying && player.state.phase != .paused
        case .guide:
            // The watch guide previews the playing channel (paused too, as in L17); the picker guide the window with
            // sound, alike.
            if case .pick = guidePurpose, multiview != nil {
                let phase = previewPlayer.state.phase
                return phase != .idle && phase != .failed
            }
            return isPlaying
        case .multiview:
            return isMultiviewMoving
        case .setupNeeded, .loading, .unavailable:
            return false
        }
    }

    /// A Multiview window is loading or playing (paused and failed ones are still).
    private var isMultiviewMoving: Bool {
        tilePlayers.values.contains { $0.state.phase == .loading || $0.state.phase == .playing }
    }

    /// After `guideIdleReturn` without input: menus, search and Choose Teams close, the watch guide goes back to the
    /// playing channel without a reconnect, the picker guide back to Multiview. Never starts a play; with nothing
    /// playing it does nothing (the idle dimmer handles still screens).
    private func returnToVideo() {
        guard mode == .player || mode == .guide || mode == .multiview, hasVideo else { return }
        let startMode = mode
        let closed = menu != nil || matchGuideTask != nil || search != nil || teamPicker != nil
        menu = nil
        menuParent = nil
        matchGuideTask?.cancel()
        matchGuideTask = nil
        closeSearch()
        closeTeamPicker()
        if mode == .guide {
            if case .pick = guidePurpose {
                closePicker()
            } else if isPlaying {
                returnToChannel()
            }
        }
        // Only when something changed, not each time the timer runs out while a channel plays full screen.
        if closed || mode != startMode {
            logger.info("No input for a while: back to the video")
        }
    }

    /// The watch guide's Select: full screen on that channel, without reloading the one already playing.
    private func watch(_ id: Channel.ID) {
        guard let channel = library.channels.first(where: { $0.id == id }) else { return }
        if channel.id == currentChannel?.id && isPlaying {
            mode = .player
            guide = nil
            showBanner()
        } else {
            play(channel)
        }
    }

    // MARK: - Search (M7f L12)

    /// Phone text (L11) while Live TV shows a channel, the guide or Multiview: opens search with it typed.
    func typeText(_ edit: TextEdit) {
        guard mode == .player || mode == .guide || mode == .multiview else { return }
        restartGuideIdle()   // M7m L16: typing is input too
        menu = nil
        menuParent = nil
        closeTeamPicker()
        if search == nil { openSearch() }
        search?.apply(edit)
    }

    /// Phone Return: the first result, as if selected.
    func submitText() {
        guard let result = search?.firstResult else { return }
        restartGuideIdle()
        choose(result)
    }

    private func openSearch() {
        guard mode == .player || mode == .guide || mode == .multiview else { return }
        hideOverlays()
        search = LiveSearchModel(library: library, now: now, debounce: searchDebounce)
    }

    /// The screen under search (guide, player, Multiview) comes back as it was.
    private func closeSearch() {
        search?.cancel()
        search = nil
    }

    /// A channel or a programme on now plays; a later programme shows in the guide at its start.
    /// In the Multiview picker the channel goes in the window instead. From Multiview, the windows are left
    /// (the layout is kept, as Watch from a top shelf card does).
    private func choose(_ result: LiveSearchModel.Result) {
        guard let channel = result.channel else { return }
        closeSearch()
        let later: Programme? = if case .programme(_, let programme) = result, programme.start > now() { programme } else { nil }
        if case .pick(let slot) = guidePurpose, mode == .guide {
            if let later {
                focusGuide(on: channel.id, at: later.start)
            } else {
                assignWindow(channel.id, to: slot)
                closePicker()
            }
            return
        }
        if mode == .multiview { leaveMultiviewKeepingLayout() }
        if let later {
            if mode != .guide { openGuide() }
            focusGuide(on: channel.id, at: later.start)
        } else {
            watch(channel.id)
        }
    }

    private func focusGuide(on channelID: Channel.ID, at date: Date) {
        guard var guide else { return }
        guide.focus(channelID: channelID, at: date, now: now())
        self.guide = guide
        loadProgrammes()
        scheduleGuideWarm()
    }

    // MARK: - Choose Teams (M7l L12)

    private func openTeamPicker() {
        guard mode == .guide else { return }
        let picker = TeamPicker()
        teamPicker = picker
        teamPickerMenu = picker.menu(picked: Set(library.preferences.teams))
    }

    /// Closing from level 1 returns to the guide, whose focus stayed on My Teams' Choose Teams row (M7l 8c).
    private func closeTeamPicker() {
        teamPicker = nil
        teamPickerMenu = nil
    }

    /// Select on a league or conference opens it; on a team toggles it (the level is rebuilt, focus kept);
    /// Back and Menu go up a level, and close the picker from level 1.
    private func handleTeamPicker(_ command: RemoteCommand) {
        guard mode == .guide, var picker = teamPicker, var menu = teamPickerMenu else {
            closeTeamPicker()
            return
        }
        switch menu.handle(command) {
        case .none:
            teamPickerMenu = menu
        case .choose(.openTeamLeague(let league)):
            picker.push(.league(league))
            teamPicker = picker
            teamPickerMenu = picker.menu(picked: Set(library.preferences.teams))
        case .choose(.openTeamConference(let league, let conference)):
            picker.push(.conference(league, conference))
            teamPicker = picker
            teamPickerMenu = picker.menu(picked: Set(library.preferences.teams))
        case .choose(.toggleTeam(let id)):
            library.setTeamPicked(id, !library.isTeamPicked(id))
            channelsChanged()
            // Same rows, new values: the focus and the visible rows stay.
            menu.items = picker.menu(picked: Set(library.preferences.teams), focusedIndex: menu.focusedIndex).items
            teamPickerMenu = menu
        case .choose:
            teamPickerMenu = menu
        case .close:
            let left = picker.level
            guard picker.pop() else {
                closeTeamPicker()
                return
            }
            teamPicker = picker
            // Focus on the league or conference just left.
            let parent = picker.menu(picked: Set(library.preferences.teams))
            let index = parent.items.firstIndex { $0.action == left.openAction } ?? 0
            teamPickerMenu = LiveMenu(title: parent.title, items: parent.items, focusedIndex: index)
        }
    }

    /// M7f L12: every window stops and the snapshot stays (inactive), so Live TV can show one channel.
    private func leaveMultiviewKeepingLayout() {
        saveSnapshot(false)
        for tile in tilePlayers.values { release(tile) }
        player.setBufferProfile(.full)
        tilePlayers = [:]
        windowErrors = [:]
        refreshedWindows = []
        multiview = nil
        guidePurpose = .watch
        hideOverlays()
    }

    // MARK: - Menus

    /// M6 L8, M6b L8: the guide's channel menu. Focus on `itemID`, else on the item at `index` (clamped).
    private func channelMenu(for id: Channel.ID, focusing itemID: String? = nil, at index: Int = 0) -> LiveMenu? {
        guard let channel = library.channels.first(where: { $0.id == id }) else { return nil }
        let isShown = library.state.multiview?.slots.contains(id) == true
        let isFavorite = library.isFavorite(id)
        var items: [LiveMenu.Item] = [
            .init(id: "watch", title: "Watch", action: .watch(id)),
            .init(id: "addToMultiview", title: isShown ? "Show in Multiview" : "Add to Multiview", action: .addToMultiview(id)),
            .init(id: "favorite", title: isFavorite ? "Remove from Favorites" : "Add to Favorites", action: .toggleFavorite(id)),
        ]
        // M7l 8b: only the saved favorites below the team channels move, among themselves.
        if guide?.selectedGroup == ChannelLineup.favoritesGroup,
           let position = library.lineup.movableFavorites.firstIndex(where: { $0.id == id }) {
            if position > 0 {
                items.append(.init(id: "moveUp", title: "Move Up", action: .moveFavorite(id, by: -1)))
            }
            if position < library.lineup.movableFavorites.count - 1 {
                items.append(.init(id: "moveDown", title: "Move Down", action: .moveFavorite(id, by: 1)))
            }
        }
        for team in teamSides(shownOn: channel).joined() {
            let picked = library.isTeamPicked(team.id)
            items.append(.init(id: "team.\(team.id)",
                               title: picked ? "Remove \(team.pickTitle) from My Teams" : "Add \(team.pickTitle) to My Teams",
                               action: .toggleTeam(team.id)))
        }
        let guideLabel = library.epgMatches[id].flatMap(library.guideLabel(for:)) ?? "None"
        items.append(.init(id: "matchGuide", title: "Match Guide", value: guideLabel, action: .openMatchGuide(id)))
        items.append(.init(id: "hide", title: "Hide Channel", action: .hideChannel(id)))
        let focused = itemID.flatMap { itemID in items.firstIndex { $0.id == itemID } } ?? index
        return LiveMenu(title: channel.name, items: items, focusedIndex: focused)
    }

    private func perform(_ action: LiveMenuAction) {
        switch action {
        case .watch(let id):
            watch(id)
        case .addToMultiview(let id):
            enterMultiview(adding: id)
        case .fullScreen:
            exitMultiview()
        case .makeMain:
            guard let slot = multiview?.focusedSlot else { return }
            multiview?.makeMain(slot)
            applyAudio()
            saveSnapshot(true)
        case .changeChannel:
            guard let slot = multiview?.focusedSlot else { return }
            openPicker(slot: slot)
        case .retryWindow:
            guard let id = multiview?.focusedChannelID, let channel = channel(id), let tile = tilePlayers[id]
            else { return }
            windowErrors[id] = nil
            refreshedWindows.remove(id)
            playWindow(id, channel, on: tile)
        case .chooseLayout:
            menu = layoutMenu()
            if menu == nil { menuParent = nil }
        case .setLayout(let layout):
            for id in multiview?.setLayout(layout) ?? [] {
                if let player = tilePlayers.removeValue(forKey: id) { release(player) }
                windowErrors[id] = nil
                refreshedWindows.remove(id)
            }
            startWindowsWaitingForATuner()
            applyAudio()
            saveSnapshot(true)
        case .removeWindow:
            guard let slot = multiview?.focusedSlot else { return }
            removeWindow(slot)
        case .toggleFavorite(let id):
            library.setFavorite(id, !library.isFavorite(id))
            channelsChanged()
        case .moveFavorite(let id, let step):
            // The menu stays open, focused on the same item or, if it went, the one now at its place (M6b L8).
            let itemID = step < 0 ? "moveUp" : "moveDown"
            let index = channelMenu(for: id)?.items.firstIndex { $0.id == itemID } ?? 0
            library.moveFavorite(id, by: step)
            channelsChanged()
            menu = channelMenu(for: id, focusing: itemID, at: index)
        case .hideChannel(let id):
            library.setChannelHidden(id, true)
            channelsChanged()
        case .toggleTeam(let teamID):
            library.setTeamPicked(teamID, !library.isTeamPicked(teamID))
            channelsChanged()
        case .openTeamLeague, .openTeamConference:
            // M7l L12: Choose Teams' own; never in these menus.
            break
        case .openMatchGuide(let id):
            // Opens once its options load (M6b L9); nothing shows meanwhile.
            guard let channel = channel(id) else {
                menuParent = nil
                return
            }
            let library = library
            let mode = mode
            // M7m L3 (QA): an older open still loading would open the wrong channel's menu or clear this parent.
            matchGuideTask?.cancel()
            let task = Task {
                let options = await library.guideMatchOptions(for: channel)
                // Cancelled: whatever replaced this task (or leave) owns menuParent now.
                guard !Task.isCancelled else { return }
                // M7: also from the player's channel menu (Menu in the player). M7l: not over Choose Teams or
                // search opened meanwhile, nor in another mode. M7m L3: the channel menu waits in menuParent.
                guard self.mode == mode, mode == .guide || mode == .player, self.menu == nil,
                      self.teamPicker == nil, self.search == nil else {
                    self.menuParent = nil
                    return
                }
                self.menu = self.matchMenu(channel, options)
            }
            matchGuideTask = task
            pendingTask = task
        case .matchGuide(let id, let choice):
            // The guide reloads through guideRevision when the rematch lands.
            guard let channel = channel(id) else { return }
            let library = library
            pendingTask = Task { await library.setGuideMatch(choice, for: channel) }
        }
    }

    /// M7m L31: the most teams the channel menu offers for one side of a game.
    static let menuTeamsPerSide = 3

    /// M7f L13: the teams of a game entry (by its name), else of the programme on now (from the guide or the banner),
    /// matched with the library's options (M7m L29). M7m L31: per side, the first two sides; a game entry, a pro
    /// programme one team each, a college side up to `menuTeamsPerSide` (the nickname fallback, a shared key), picked
    /// teams first, then catalog order.
    private func teamSides(shownOn channel: Channel) -> [[Team]] {
        let index = library.teamMatchIndex
        let sides: [[Team]]
        let game = TeamMatcher.teams(inGame: channel, index: index)
        if !game.isEmpty {
            sides = game.map { [$0] }
        } else {
            let date = now()
            let programme = guide?.programmes[channel.id]?.first { $0.start <= date && date < $0.stop }
                ?? (banner?.channel.id == channel.id ? banner?.now : nil)
            sides = programme.map { TeamMatcher.teamsBySide(in: $0, index: index) } ?? []
        }
        let library = library
        return sides.prefix(2).map { side in
            // Each side is in catalog order; a stable split keeps it within the picked and the others.
            let picked = side.filter { library.isTeamPicked($0.id) }
            let others = side.filter { !library.isTeamPicked($0.id) }
            return Array((picked + others).prefix(Self.menuTeamsPerSide))
        }
    }

    /// M6b L9: Automatic, No Guide, then the current match and the suggestions. Focus on the selected row.
    private func matchMenu(_ channel: Channel, _ options: GuideMatchOptions) -> LiveMenu {
        let id = channel.id
        var items: [LiveMenu.Item] = [
            .init(id: "match.automatic", title: "Automatic", value: options.choice == .automatic ? "Selected" : nil,
                  action: .matchGuide(id, .automatic)),
            .init(id: "match.none", title: "No Guide", value: options.choice == .none ? "Selected" : nil,
                  action: .matchGuide(id, .none)),
        ]
        var focused = options.choice == .none ? 1 : 0
        for candidate in options.candidates {
            var value = candidate.sourceLabel
            if options.choice == .epg(candidate.ref) {
                value += " · Selected"
                focused = items.count
            } else if options.choice == .automatic, candidate.ref == options.current {
                value += " · Automatic"
            }
            items.append(.init(id: "match.\(candidate.ref.sourceID).\(candidate.ref.epgID)", title: candidate.name,
                               value: value, action: .matchGuide(id, .epg(candidate.ref))))
        }
        return LiveMenu(title: "Guide for \(channel.name)", items: items, focusedIndex: focused, isWide: true)
    }

    /// M6 L10, for the highlighted window.
    private func windowMenu() -> LiveMenu? {
        guard let multiview, let id = multiview.focusedChannelID else { return nil }
        let layout = multiview.layout
        var items: [LiveMenu.Item] = [.init(id: "fullScreen", title: "Full Screen", action: .fullScreen)]
        if let main = layout.mainSlot, multiview.focusedSlot != main {
            items.append(.init(id: "makeMain", title: "Make Main", action: .makeMain))
        }
        items.append(.init(id: "changeChannel", title: "Change Channel", action: .changeChannel))
        if failedWindows.contains(id) {
            items.append(.init(id: "retry", title: "Retry", action: .retryWindow))
        }
        items.append(.init(id: "layout", title: "Layout", value: layout.title, action: .chooseLayout))
        items.append(.init(id: "remove", title: "Remove", action: .removeWindow))
        return LiveMenu(title: channel(id)?.name ?? "", items: items)
    }

    private func layoutMenu() -> LiveMenu? {
        guard let current = multiview?.layout else { return nil }
        let layouts = MultiviewLayout.allCases
        return LiveMenu(title: "Layout",
                        items: layouts.map { layout in
                            .init(id: "layout.\(layout.rawValue)", title: layout.title,
                                  value: layout == current ? "Current" : nil, layout: layout, action: .setLayout(layout))
                        },
                        focusedIndex: layouts.firstIndex(of: current) ?? 0)
    }

    // MARK: - Player pool (M6 L2)

    private func configure(_ player: any LivePlayer) {
        player.onFailure = { [weak self, weak player] in
            if let player { self?.playerFailed(player) }
        }
        if let appVolume { player.setVolume(appVolume.level, muted: appVolume.muted) }
    }

    /// An idle pool player, or a new one while the pool has fewer than five.
    private func acquirePlayer() -> (any LivePlayer)? {
        if let idle = players.first(where: { candidate in !tilePlayers.values.contains { $0 === candidate } }) {
            return idle
        }
        guard players.count < MultiviewModel.maxWindows else {
            logger.error("No free player for a Multiview window")
            return nil
        }
        let player = makePlayer()
        configure(player)
        players.append(player)
        return player
    }

    /// Stops it; it stays in the pool.
    private func release(_ player: any LivePlayer) {
        player.stop()
        player.setAudible(true)
    }

    // MARK: - Multiview (M6)

    private func enterMultiview(adding id: Channel.ID) {
        let current = isPlaying ? currentChannel?.id : nil
        let multiview = MultiviewModel.entering(snapshot: library.state.multiview, current: current, adding: id,
                                                validIDs: Set(library.channels.map(\.id)))
        startMultiview(multiview, reusing: current)
    }

    /// The channel playing now keeps its player and buffer (L12); the other windows start on pool players.
    private func startMultiview(_ multiview: MultiviewModel, reusing current: Channel.ID?) {
        guide = nil
        guidePurpose = .watch
        menu = nil
        menuParent = nil
        hideOverlays()
        // M7m L15: a paused channel carried into Multiview keeps its pause symbol for the full time.
        showPausedOverlay()
        playbackError = nil
        tilePlayers = [:]
        windowErrors = [:]
        refreshedWindows = []
        if let current, multiview.slot(of: current) != nil {
            tilePlayers[current] = player
            player.setBufferProfile(.tile)
        } else {
            player.stop()
        }
        for id in multiview.channelIDs where tilePlayers[id] == nil {
            startWindow(id)
        }
        self.multiview = multiview
        mode = .multiview
        applyAudio()
        saveSnapshot(true)
        showWindowChip()
        showMultiviewHighlight()
    }

    /// Plays `id` on a free pool player.
    private func startWindow(_ id: Channel.ID) {
        guard let channel = self.channel(id), let player = acquirePlayer() else { return }
        player.setBufferProfile(.tile)
        tilePlayers[id] = player
        playWindow(id, channel, on: player)
    }

    /// M7j L8: a window over the device's tuner count keeps its (idle) player but isn't played; it shows the busy
    /// message, and its menu's Retry tries again.
    private func playWindow(_ id: Channel.ID, _ channel: Channel, on tile: any LivePlayer) {
        if let problem = tunerBudgetProblem(for: channel, excluding: tile) {
            windowErrors[id] = problem.message
            return
        }
        tile.play(channel.streamURL, direct: channel.isDirectStream)
    }

    // MARK: - Tuner budget (M7j L8)

    /// `.allTunersInUse` when MMTVL's own players already hold every tuner of `channel`'s device, not counting
    /// `excluding` (the player about to load it: a zap replaces its stream). nil for playlist channels and devices
    /// no longer known. M7j L18 (step 9b QA): `.scanning` for a channel whose tuner is in a running channel scan, so
    /// no stream is asked of a tuner mid-scan; another tuner's channels still play (step 10, security N1).
    private func tunerBudgetProblem(for channel: Channel, excluding: any LivePlayer,
                                    logs: Bool = true) -> AntennaProblem? {
        guard case .antenna(let deviceID) = channel.source else { return nil }
        if library.antenna.isScanning(deviceID: deviceID) {
            if logs { antennaLogger.notice("Antenna stream: \(AntennaProblem.scanning.logText, privacy: .public)") }
            return .scanning
        }
        guard let device = library.antenna.devices.first(where: { $0.id == deviceID }) else { return nil }
        let held = antennaStreams(on: deviceID, excluding: excluding)
        guard held >= device.tunerCount else { return nil }
        if logs { antennaLogger.notice("Antenna tuners busy: \(held, privacy: .public) of \(device.tunerCount, privacy: .public) (MMTVL holds \(held, privacy: .public))") }
        return .allTunersInUse(device.tunerCount)
    }

    /// MMTVL's players loading or playing (paused included: the stream stays open) an antenna channel of
    /// `deviceID`: `player` for the full-screen channel or the preview, and the Multiview windows.
    private func antennaStreams(on deviceID: String, excluding: any LivePlayer) -> Int {
        var channelIDs: [ObjectIdentifier: Channel.ID] = [:]
        if let id = previewChannelID ?? currentChannel?.id { channelIDs[ObjectIdentifier(player)] = id }
        for (id, tile) in tilePlayers { channelIDs[ObjectIdentifier(tile)] = id }
        let source = ChannelSource.antenna(deviceID: deviceID)
        return players.count { candidate in
            guard candidate !== excluding else { return false }
            switch candidate.state.phase {
            case .loading, .playing, .paused: break
            case .idle, .failed: return false
            }
            return channelIDs[ObjectIdentifier(candidate)].flatMap(channel)?.source == source
        }
    }

    /// L5: only the window with sound is unmuted.
    private func applyAudio() {
        for (id, player) in tilePlayers {
            player.setAudible(id == multiview?.audioChannelID)
        }
    }

    private var focusedWindowPlayer: (any LivePlayer)? {
        multiview?.focusedChannelID.flatMap { tilePlayers[$0] }
    }

    /// L9.
    private func handleMultiview(_ command: RemoteCommand) -> LiveTVOutcome {
        let onMain = multiview.map { $0.layout.mainSlot == $0.focusedSlot } ?? false
        switch command {
        case .left where onMain, .right where onMain:
            // M7f L6: on the main window, Left/Right rotate the channels through it; players are keyed by channel,
            // so nothing reconnects.
            if multiview?.rotate(by: command == .right ? 1 : -1) == true {
                applyAudio()
                showWindowChip()
                saveSnapshot(true)
            }
        case .down where onMain:
            // M7f L6: Down from the main window highlights the first small window.
            multiview?.focus(1)
            applyAudio()
            showWindowChip()
        case .up, .down, .left, .right:
            if let direction = MultiviewLayout.Direction(command), multiview?.moveFocus(direction) == true {
                applyAudio()
                showWindowChip()
            }
        case .select:
            guard let multiview else { break }
            if multiview.focusedChannelID != nil {
                menuParent = nil
                menu = windowMenu()
            } else {
                openPicker(slot: multiview.focusedSlot)
            }
        case .playPause:
            focusedWindowPlayer?.togglePause()
            showTimeshiftBar()
        case .rewind:
            focusedWindowPlayer?.seek(by: -Self.longSkip)
            showTimeshiftBar()
        case .fastForward:
            focusedWindowPlayer?.seek(by: Self.longSkip)
            showTimeshiftBar()
        case .back:
            exitMultiview()
        case .home:
            return .leave
        case .menu:
            // M7 L5: the window menu, as Select on a filled window; nothing on an empty one.
            if multiview?.focusedChannelID != nil {
                menuParent = nil
                menu = windowMenu()
            }
        case .channelUp, .channelDown:
            zapWindow(channelStep(command))
        case .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            break   // M7h L3: handled before screens
        }
        return .handled
    }

    /// M7 L6: the highlighted window steps through the zap list, skipping channels shown in other windows.
    private func zapWindow(_ step: Int) {
        guard let multiview, let id = multiview.focusedChannelID, let current = channel(id) else { return }
        let others = Set(multiview.slots.compactMap { $0 }).subtracting([id])
        let list = zapList(around: current).filter { !others.contains($0.id) }
        guard !list.isEmpty else { return }
        let next: Channel
        if let index = list.firstIndex(where: { $0.id == id }) {
            guard list.count > 1 else { return }
            next = list[(index + step + list.count) % list.count]
        } else {
            next = step > 0 ? list[0] : list[list.count - 1]
        }
        assignWindow(next.id, to: multiview.focusedSlot)
        showWindowChip()
    }

    /// L12: the highlighted window (else the one with sound, else the first) goes full screen without reconnecting.
    private func exitMultiview() {
        guard let multiview,
              let slot = [multiview.focusedSlot, multiview.audioSlot].compactMap({ $0 }).first(where: { multiview.slots[$0] != nil })
                ?? multiview.slots.firstIndex(where: { $0 != nil }),
              let id = multiview.slots[slot]
        else {
            removeAllWindows()
            return
        }
        let target = tilePlayers[id]
        // M7j L8: a window the tuner budget never started, or whose start (a diagnosis retry) it blocked, plays now
        // that the other windows are gone.
        let waitsForATuner = target?.state.phase == .idle || isWaitingForATuner(id)
        for (otherID, other) in tilePlayers where otherID != id {
            release(other)
        }
        if let target {
            player = target
        }
        player.setBufferProfile(.full)
        player.setAudible(true)
        let channel = self.channel(id)
        currentChannel = channel ?? currentChannel
        library.rememberChannel(id)
        playbackError = windowErrors[id]
        refreshedAfterFailure = refreshedWindows.contains(id)
        saveSnapshot(false)
        self.multiview = nil
        tilePlayers = [:]
        windowErrors = [:]
        refreshedWindows = []
        guide = nil
        guidePurpose = .watch
        menu = nil
        menuParent = nil
        mode = .player
        if target == nil || waitsForATuner, let channel {
            play(channel)
        } else {
            showBanner()
        }
    }

    /// L11: the guide picks the channel for `slot`; the window with sound is its preview.
    private func openPicker(slot: Int) {
        guard let multiview else { return }
        guide = GuideModel(lineup: library.lineup, group: library.state.lastGroup,
                           focusedChannelID: multiview.slots[slot] ?? multiview.audioChannelID, now: now())
        guidePurpose = .pick(slot: slot)
        mode = .guide
        hideOverlays()
        loadProgrammes()
    }

    private func closePicker() {
        guide = nil
        guidePurpose = .watch
        mode = .multiview
        showWindowChip()
        showMultiviewHighlight()
    }

    /// L11. Releases the displaced channel's player before acquiring one, so a full 1 + 4 never needs a sixth.
    /// M7j L8 (orchestrator, 2026-11-15): the channel just picked wins a tuner. Picking a window that waits for a
    /// tuner for a window playing an antenna channel of the same device swaps them and stops the other one, which
    /// then waits; a released window's tuner goes to the first window waiting.
    private func assignWindow(_ id: Channel.ID, to slot: Int) {
        guard let current = multiview else { return }
        let swapped = current.slot(of: id).flatMap { $0 != slot ? current.slots[slot] : nil }
        if let displaced = multiview?.assign(id, to: slot) {
            if let player = tilePlayers.removeValue(forKey: displaced) { release(player) }
            windowErrors[displaced] = nil
            refreshedWindows.remove(displaced)
        }
        if tilePlayers[id] == nil {
            startWindow(id)
        } else if let swapped, isWaitingForATuner(id) {
            takeTuner(for: id, from: swapped)
        }
        startWindowsWaitingForATuner()
        applyAudio()
        saveSnapshot(true)
    }

    /// The picked window `id` (waiting for a tuner) gets the tuner of `other`'s window when that one holds a stream
    /// on the same device: `other` stops and shows the busy text.
    private func takeTuner(for id: Channel.ID, from other: Channel.ID) {
        guard let channel = channel(id), let otherChannel = self.channel(other), otherChannel.isDirectStream,
              otherChannel.source == channel.source, let tile = tilePlayers[id], let otherTile = tilePlayers[other],
              [.loading, .playing, .paused].contains(otherTile.state.phase), let busy = busyMessage(for: otherChannel)
        else { return }
        release(otherTile)
        windowErrors[other] = busy
        windowErrors[id] = nil
        refreshedWindows.remove(id)
        playWindow(id, channel, on: tile)
    }

    /// M7j L8 (orchestrator, 2026-11-15): after a window released its tuner, the windows waiting for one start in
    /// window order, as far as the budget allows. Windows that failed for other reasons stay as they are.
    private func startWindowsWaitingForATuner() {
        guard let multiview else { return }
        for id in multiview.slots.compactMap({ $0 }) where isWaitingForATuner(id) {
            guard let channel = channel(id), let tile = tilePlayers[id],
                  tunerBudgetProblem(for: channel, excluding: tile, logs: false) == nil
            else { continue }
            windowErrors[id] = nil
            refreshedWindows.remove(id)
            playWindow(id, channel, on: tile)
        }
    }

    /// A window showing its device's busy text whose player holds no stream: never started (the budget), or a
    /// start that was blocked or found every tuner busy.
    private func isWaitingForATuner(_ id: Channel.ID) -> Bool {
        guard let channel = channel(id), let busy = busyMessage(for: channel), windowErrors[id] == busy,
              let tile = tilePlayers[id]
        else { return false }
        return tile.state.phase == .idle || tile.state.phase == .failed
    }

    /// The busy text of `channel`'s device ("Both antenna tuners are in use"); nil for playlist channels and
    /// devices no longer known.
    private func busyMessage(for channel: Channel) -> String? {
        guard case .antenna(let deviceID) = channel.source,
              let device = library.antenna.devices.first(where: { $0.id == deviceID })
        else { return nil }
        return AntennaProblem.allTunersInUse(device.tunerCount).message
    }

    private func removeWindow(_ slot: Int) {
        guard let id = multiview?.remove(slot) else { return }
        if let player = tilePlayers.removeValue(forKey: id) { release(player) }
        windowErrors[id] = nil
        refreshedWindows.remove(id)
        if multiview?.isEmpty != false {
            removeAllWindows()
        } else {
            startWindowsWaitingForATuner()
            applyAudio()
            saveSnapshot(true)
        }
    }

    /// Every window gone: nothing plays and the watch guide opens (L12).
    private func removeAllWindows() {
        for player in tilePlayers.values { release(player) }
        player.setBufferProfile(.full)
        tilePlayers = [:]
        windowErrors = [:]
        refreshedWindows = []
        multiview = nil
        library.rememberMultiview(nil)
        guidePurpose = .watch
        openGuide()
    }

    /// The banner as a chip on the highlighted window; none on an empty one.
    private func showWindowChip() {
        guard let channel = multiview?.focusedChannelID.flatMap(self.channel) else {
            bannerGeneration += 1
            banner = nil
            return
        }
        showBanner(for: channel)
    }

    private func saveSnapshot(_ active: Bool) {
        library.rememberMultiview(multiview?.snapshot(isActive: active))
    }

    private func openGuide() {
        restartGuideIdle()
        guide = GuideModel(lineup: library.lineup, group: library.state.lastGroup,
                           focusedChannelID: currentChannel?.id, now: now())
        mode = .guide
        hideOverlays()
        loadProgrammes()
    }

    /// [now − 1 h, now + 24 h] for the guide's channels, kept only if the guide still shows the same group.
    private func loadProgrammes() {
        guard let guide else { return }
        let group = guide.selectedGroup
        let channels = guide.channels
        // M7c L24: the logos around the focused row first (M7l 8c: upcoming games' channels too).
        let rows = guide.rows
        let around = max(guide.row - Self.logoPrefetchRows, 0)..<min(guide.row + Self.logoPrefetchRows, rows.count)
        prefetchLogos(rows[around.clamped(to: rows.indices)].compactMap { $0.channel?.logoURL })
        let date = now()
        let library = library
        pendingTask = Task {
            let interval = DateInterval(start: date - 3600, end: date + GuideTimeline.horizon)
            let programmes = await library.programmes(for: channels, in: interval)
            guard !Task.isCancelled, self.guide?.selectedGroup == group else { return }
            self.guide?.programmes = programmes
        }
    }

    /// Up/Down over the lineup (M6b L11): the remembered group if it holds the current channel, else its own group,
    /// else every visible channel. Wraps. A channel not in the list (hidden while playing): Down plays the first, Up the last.
    private func zap(_ step: Int) {
        guard let current = currentChannel else { return }
        let list = zapList(around: current)
        guard !list.isEmpty else { return }
        guard let index = list.firstIndex(where: { $0.id == current.id }) else {
            play(step > 0 ? list[0] : list[list.count - 1])
            return
        }
        guard list.count > 1 else { return }
        play(list[(index + step + list.count) % list.count])
    }

    /// M7c L29: the channels one zap away, resolved ahead of time. M7j L7: not antenna channels (a resolve is a GET,
    /// which takes a tuner).
    private func prefetchNeighbors(of channel: Channel) {
        let list = zapList(around: channel)
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == channel.id }) else { return }
        let neighbors = [list[(index + 1) % list.count], list[(index - 1 + list.count) % list.count]]
            .filter { !$0.isDirectStream }
        guard !neighbors.isEmpty else { return }
        prefetchStreams(Array(Set(neighbors.map(\.streamURL))).sorted { $0.absoluteString < $1.absoluteString })
    }

    /// The list zapping steps through from `current` (see `zap`).
    private func zapList(around current: Channel) -> [Channel] {
        let lineup = library.lineup
        if let group = lineup.resolvedGroup(library.state.lastGroup) {
            let remembered = lineup.channels(in: group)
            if remembered.contains(where: { $0.id == current.id }) { return remembered }
        }
        let own = lineup.channels(in: current.group)
        return own.isEmpty ? lineup.visibleChannels : own
    }

    private func seek(_ seconds: Double) {
        player.seek(by: seconds)
        showTimeshiftBar()
    }

    /// Also the paused bar (M7m L15): Select or Back hides it while paused; the next press shows it again.
    private func hideOverlays() {
        banner = nil
        showsTimeshiftBar = false
        bannerGeneration += 1
        barGeneration += 1
        pausedOverlayTask?.cancel()
        pausedOverlayTask = nil
        pausedOverlayVisible = false
    }

    private func showBanner() {
        guard let channel = currentChannel else { return }
        showBanner(for: channel)
    }

    /// The banner shows the channel at once, then its now/next, and hides after `overlayDuration`.
    private func showBanner(for channel: Channel) {
        bannerGeneration += 1
        let generation = bannerGeneration
        banner = Banner(channel: channel)
        let library = library
        let date = now()
        let duration = overlayDuration
        Task {
            let (current, next) = await library.nowNext(for: channel, at: date)
            guard bannerGeneration == generation, banner?.channel.id == channel.id else { return }
            banner?.now = current
            banner?.next = next
            try? await Task.sleep(for: duration)
            if bannerGeneration == generation { banner = nil }
        }
    }

    /// M7m L12: the bold outline, for `multiviewHighlightDuration`.
    private func showMultiviewHighlight() {
        multiviewHighlightTask?.cancel()
        multiviewHighlightVisible = true
        let duration = multiviewHighlightDuration
        multiviewHighlightTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.multiviewHighlightVisible = false
        }
    }

    /// M7m L15: the paused overlays, for `pausedOverlayDuration`.
    private func showPausedOverlay() {
        pausedOverlayTask?.cancel()
        pausedOverlayVisible = true
        let duration = pausedOverlayDuration
        pausedOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.pausedOverlayVisible = false
        }
    }

    /// Hides after `overlayDuration`; while paused the view keeps it as long as `pausedOverlayVisible` (M7m L15).
    private func showTimeshiftBar() {
        barGeneration += 1
        let generation = barGeneration
        showsTimeshiftBar = true
        let duration = overlayDuration
        Task {
            try? await Task.sleep(for: duration)
            if barGeneration == generation { showsTimeshiftBar = false }
        }
    }

    /// M4 L13: after the player's own retries, refresh the playlist once (tokens may have rotated), then give up.
    /// M6 L14: the same per Multiview window.
    private func playerFailed(_ failed: any LivePlayer) {
        // M7c L16: a failed preview shows the art and isn't retried until focus comes back.
        if previewChannelID != nil, failed === player {
            endPreview()
            previewFailed = true
            return
        }
        if multiview != nil {
            guard let id = tilePlayers.first(where: { $0.value === failed })?.key else { return }   // a released player
            windowFailed(id, player: failed)
            return
        }
        guard failed === player, let channel = currentChannel else { return }
        // M7j L9: an antenna channel asks the tuner instead of re-fetching the playlist.
        if channel.isDirectStream {
            antennaFailed(channel, player: failed)
            return
        }
        guard !refreshedAfterFailure else {
            playbackError = Self.playbackErrorMessage
            logger.error("Can't play \(channel.name, privacy: .public)")
            return
        }
        refreshedAfterFailure = true
        let library = library
        pendingTask = Task {
            await library.refreshPlaylist()
            guard !Task.isCancelled, currentChannel?.id == channel.id else { return }
            let fresh = library.channels.first { $0.id == channel.id } ?? channel
            currentChannel = fresh
            player.play(fresh.streamURL, direct: fresh.isDirectStream)
        }
    }

    private func windowFailed(_ id: Channel.ID, player failed: any LivePlayer) {
        if let channel = channel(id), channel.isDirectStream {
            antennaWindowFailed(id, channel, player: failed)
            return
        }
        guard !refreshedWindows.contains(id) else {
            windowErrors[id] = Self.playbackErrorMessage
            logger.error("Can't play \(self.channel(id)?.name ?? id, privacy: .public) in a window")
            return
        }
        refreshedWindows.insert(id)
        let library = library
        pendingTask = Task {
            await library.refreshPlaylist()
            guard !Task.isCancelled, tilePlayers[id] === failed, let fresh = channel(id) else { return }
            failed.play(fresh.streamURL, direct: fresh.isDirectStream)
        }
    }

    // MARK: - Antenna failures (M7j L9)

    /// Full screen: the tuner says why (`IPTVLibrary.diagnose`); a search or lineup read that still has the
    /// channel plays it once more (`refreshedAfterFailure`), else the problem shows. The diagnosis reads the
    /// failed load's `httpStatus` now, before anything else loads on the player.
    private func antennaFailed(_ channel: Channel, player failed: any LivePlayer) {
        let mayRetry = !refreshedAfterFailure
        refreshedAfterFailure = true
        let httpStatus = failed.state.httpStatus
        let library = library
        pendingTask = Task {
            let outcome = await library.diagnose(channel, httpStatus: httpStatus, mayRetry: mayRetry)
            // Another channel, or this one chosen again, meanwhile: that load decides.
            guard !Task.isCancelled, currentChannel?.id == channel.id, player === failed,
                  failed.state.phase == .failed
            else { return }
            switch outcome {
            case .retry(let fresh):
                currentChannel = fresh
                if let problem = tunerBudgetProblem(for: fresh, excluding: failed) {
                    playbackError = problem.message
                } else {
                    failed.play(fresh.streamURL, direct: fresh.isDirectStream)
                }
            case .show(let problem):
                playbackError = problem.message
                logger.error("Can't play \(channel.name, privacy: .public): \(problem.logText, privacy: .public)")
            }
        }
    }

    /// The same for a Multiview window (`refreshedWindows`); the problem is the window's text.
    private func antennaWindowFailed(_ id: Channel.ID, _ channel: Channel, player failed: any LivePlayer) {
        let mayRetry = !refreshedWindows.contains(id)
        refreshedWindows.insert(id)
        let httpStatus = failed.state.httpStatus
        let library = library
        pendingTask = Task {
            let outcome = await library.diagnose(channel, httpStatus: httpStatus, mayRetry: mayRetry)
            guard !Task.isCancelled, tilePlayers[id] === failed, failed.state.phase == .failed else { return }
            switch outcome {
            case .retry(let fresh):
                playWindow(id, fresh, on: failed)
            case .show(let problem):
                windowErrors[id] = problem.message
                logger.error("Can't play \(channel.name, privacy: .public) in a window: \(problem.logText, privacy: .public)")
            }
        }
    }
}
