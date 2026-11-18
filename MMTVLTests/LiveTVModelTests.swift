import Foundation
import Testing
@testable import MMTVL

struct LiveTVModelTests {
    /// Last watched: NFL Network, the first channel.
    static let watching = IPTVState(lastChannelID: "id:nflnetwork.us")
    private func makeModel(playlist: URL? = IPTVFixtures.playlistURL, state: IPTVState? = nil,
                           preferences: ChannelPreferences? = nil, guideIdleReturn: Duration = .seconds(180)) throws
        -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: playlist, state: state, preferences: preferences)
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library, now: { fixture.clock.now },
                                guideIdleReturn: guideIdleReturn)
        return (model, player, fixture)
    }

    private func open(_ model: LiveTVModel) async {
        model.open()
        await model.pendingTask?.value
    }

    @Test func noPlaylistNeedsSetup() async throws {
        let (model, player, fixture) = try makeModel(playlist: nil)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .setupNeeded)
        #expect(model.handle(.down) == .handled)
        #expect(model.handle(.select) == .openSettings)
        #expect(model.handle(.back) == .leave)
        #expect(player.played.isEmpty)
    }

    @Test func noLastChannelOpensTheGuide() async throws {
        let (model, player, fixture) = try makeModel()
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .guide)
        #expect(player.played.isEmpty)
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        // M7m L2: Back with no channel to return to does nothing; the guide stays.
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .guide)
        #expect(player.played.isEmpty)
    }

    /// M7m L1: Back while the channels load stays in Live TV.
    @Test func backWhileLoadingDoesNothing() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        model.open()
        #expect(model.mode == .loading)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .loading)
        await model.pendingTask?.value
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(1)])
    }

    @Test func lastChannelResumes() async throws {
        let (model, player, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nbatv.us"))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.name == "NBA TV")
    }

    @Test func emptyPlaylistIsUnavailable() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: "#EXTM3U\n"])
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("The playlist has no channels"))
        #expect(model.handle(.back) == .leave)
    }

    @Test func failedPlaylistIsUnavailableAndSelectRetries() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [:], state: Self.watching)
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("Server error (HTTP 404)"))

        fixture.network.setText(IPTVFixtures.playlist, for: IPTVFixtures.playlistURL)
        #expect(model.handle(.select) == .handled)
        await model.pendingTask?.value
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
    }

    @Test func upDownZapWithinTheRememberedGroupAndWrap() async throws {
        let (model, player, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:lakers @ celtics", lastGroup: "NBA Games"))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.currentChannel?.name == "Lakers @ Celtics")

        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        #expect(fixture.library.state.lastChannelID == "id:knicks @ heat")
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Lakers @ Celtics")
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        #expect(player.played == [IPTVFixtures.streamURL(4), IPTVFixtures.streamURL(5), IPTVFixtures.streamURL(4), IPTVFixtures.streamURL(5)])
        #expect(model.banner?.channel.name == "Knicks @ Heat")
    }

    /// M7c L29: the channels one zap away are resolved ahead of time.
    @Test func playingPrefetchesTheNeighbors() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:lakers @ celtics", lastGroup: "NBA Games"))
        defer { fixture.cleanUp() }
        var prefetched: [[URL]] = []
        model.prefetchStreams = { prefetched.append($0) }
        await open(model)
        #expect(prefetched == [[IPTVFixtures.streamURL(5)]])
        _ = model.handle(.down)
        #expect(prefetched.last == [IPTVFixtures.streamURL(4)])
    }

    @Test func zapUsesTheChannelsOwnGroupWhenTheRememberedOneLacksIt() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nflnetwork.us", lastGroup: "NBA Games"))
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    // MARK: Lineup (M6b L11)

    @Test func zapSkipsAHiddenChannel() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching, preferences: ChannelPreferences(hiddenChannels: ["id:nbatv.us"]))
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    @Test func zapInFavoritesWraps() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "name:red zone", lastGroup: "Favorites"),
                                                preferences: ChannelPreferences(favorites: ["id:knicks @ heat", "name:red zone"]))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.currentChannel?.name == "Red Zone")
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    @Test func zapFromAChannelHiddenWhilePlaying() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        fixture.library.setChannelHidden("id:nflnetwork.us", true)
        #expect(player.played == [IPTVFixtures.streamURL(1)])    // hiding stops nothing
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "NBA TV")
    }

    @Test func seeks() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        for command in [RemoteCommand.left, .right, .rewind, .fastForward] {
            #expect(model.handle(command) == .handled)
        }
        #expect(player.seeks == [-10, 10, -30, 30])
        #expect(model.showsTimeshiftBar)
    }

    @Test func playPauseToggles() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.playPause)
        #expect(player.pauses == 1)
    }

    /// M7c L11.
    @Test func backHidesOverlaysThenOpensTheGuide() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.banner != nil)
        #expect(model.handle(.back) == .handled)
        #expect(model.banner == nil)
        #expect(model.mode == .player)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .guide)
        #expect(model.guide?.focusedChannel?.id == model.currentChannel?.id)
        #expect(player.played.count == 1)
    }

    /// M7c L11: Select shows the banner and timeshift bar; a second Select hides them.
    @Test func selectShowsThenHidesTheBanner() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.back)
        #expect(model.banner == nil)
        #expect(model.handle(.select) == .handled)
        #expect(model.mode == .player)
        #expect(model.banner != nil)
        #expect(model.showsTimeshiftBar)
        _ = model.handle(.select)
        #expect(model.banner == nil)
        #expect(!model.showsTimeshiftBar)
        #expect(model.mode == .player)
    }

    @Test func failureRefreshesThePlaylistOnceThenShowsAnError() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        let fetches = fixture.network.fetchCount

        player.fail()
        await model.pendingTask?.value
        #expect(fixture.network.fetchCount == fetches + 1)
        #expect(player.played.count == 2)
        #expect(model.playbackError == nil)

        player.fail()
        #expect(model.playbackError == "Can't play this channel")
        #expect(player.played.count == 2)

        _ = model.handle(.select)
        #expect(player.played.count == 3)
        #expect(model.playbackError == nil)
    }

    @Test func leaveStops() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        model.leave()
        #expect(player.stops == 1)
        #expect(model.banner == nil)
        #expect(model.currentChannel?.name == "NFL Network")
    }

    @Test func homeLeaves() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.handle(.home) == .leave)
    }

    @Test func canvasGeometry() {
        let rect = CanvasGeometry.windowRect(forCanvasRect: CGRect(x: 1160, y: 60, width: 640, height: 360),
                                             in: CGSize(width: 960, height: 540))
        #expect(rect == CGRect(x: 580, y: 30, width: 320, height: 180))
        // A taller window centers the canvas vertically.
        let tall = CanvasGeometry.windowRect(forCanvasRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                             in: CGSize(width: 1920, height: 1200))
        #expect(tall == CGRect(x: 0, y: 60, width: 1920, height: 1080))
    }
    // MARK: Guide

    /// Playing NBA TV (row 2 of "All Channels"), with the fixture guide imported.
    private func makeGuideModel(preferences: ChannelPreferences? = nil, guideIdleReturn: Duration = .seconds(180),
                                pausedOverlayDuration: Duration = .seconds(15))
        async throws -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      state: IPTVState(lastChannelID: "id:nbatv.us"), preferences: preferences)
        await fixture.library.refreshAll()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library, now: { fixture.clock.now },
                                guideIdleReturn: guideIdleReturn, pausedOverlayDuration: pausedOverlayDuration)
        await open(model)
        player.state.phase = .playing
        return (model, player, fixture)
    }

    /// M7c L11: Back hides the banner shown on opening, then opens the guide.
    private func openGuide(_ model: LiveTVModel) {
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
    }

    @Test func backInThePlayerOpensTheGuideOnTheCurrentChannel() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        #expect(model.mode == .guide)
        #expect(model.guide?.selectedGroup == "All Channels")
        #expect(model.guide?.focusedChannel?.id == "id:nbatv.us")
        #expect(model.banner == nil)
    }

    /// M7c L31: the highlighted channel is warmed once the highlight rests; scrolling past isn't, nor the one playing.
    @Test func theHighlightedChannelIsWarmed() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        var warmed: [URL] = []
        model.warmStream = { warmed.append($0) }
        model.guideWarmDelay = .milliseconds(30)
        // Each step awaits the warm task itself, never the wall clock (it flaked under load).
        openGuide(model)
        await model.guideWarmTask?.value
        #expect(warmed.isEmpty)   // NBA TV is playing

        _ = model.handle(.down)
        _ = model.handle(.down)
        await model.guideWarmTask?.value
        let resting = try #require(model.guide?.focusedChannel)
        #expect(warmed == [resting.streamURL])

        _ = model.handle(.right)   // the same channel again, within the rewarm interval
        await model.guideWarmTask?.value
        #expect(warmed.count == 1)

        _ = model.handle(.up)
        _ = model.handle(.up)   // back on NBA TV
        await model.guideWarmTask?.value
        #expect(warmed.count == 1)
    }

    @Test func programmesAreLoadedForTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        await model.pendingTask?.value
        #expect(model.guide?.programmes["id:nbatv.us"]?.first?.title == "NBA TV 0")
        #expect(model.guide?.programmes["id:nflnetwork.us"]?.count == 4)
        #expect(model.guide?.focusedCell(now: fixture.clock.now)?.programme?.title == "NBA TV 1")
    }

    @Test func selectOnAnotherRowPlaysIt() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.up)
        #expect(model.handle(.select) == .handled)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.currentChannel?.name == "NFL Network")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(1)])
    }

    @Test func selectOnTheCurrentRowReturnsWithoutReloading() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.id == "id:nbatv.us")
    }

    /// M7m L2 (D49): Back in the watch guide returns to the playing channel, without reloading it.
    @Test func backInTheGuideReturnsToTheChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        #expect(model.mode == .guide)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.player === player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.id == "id:nbatv.us")
    }

    /// M7m L2: after a stream error, Back in the guide plays the failed channel again (a retry).
    @Test func backInTheGuideAfterAStreamErrorRetriesTheChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        player.fail()                           // refreshes the playlist once and plays again
        await model.pendingTask?.value
        player.fail()
        #expect(model.playbackError == "Can't play this channel")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(2)])
        #expect(model.canReturnToChannel)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.currentChannel?.id == "id:nbatv.us")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(2)])
        #expect(model.playbackError == nil)
    }

    /// The fixture playlist without NBA TV (the channel `makeGuideModel` plays).
    private func dropNBATV(_ model: LiveTVModel, _ fixture: LibraryFixture) async {
        let withoutNBATV = IPTVFixtures.playlist.components(separatedBy: "\n").enumerated()
            .filter { ![3, 4].contains($0.offset) }.map(\.element).joined(separator: "\n")
        fixture.network.setText(withoutNBATV, for: IPTVFixtures.playlistURL)
        await fixture.library.refreshPlaylist()
        model.channelsChanged()
    }

    /// M7m L2, L4: a refresh dropped the playing channel; Back still returns to it while it plays.
    @Test func backInTheGuideReturnsToAPlayingChannelTheRefreshDropped() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        await dropNBATV(model, fixture)
        #expect(!fixture.library.channels.contains { $0.id == "id:nbatv.us" })
        #expect(model.canReturnToChannel)
        #expect(GuideView.hint(focus: .grid, isPicking: false, hasChannel: model.canReturnToChannel)
                .hasSuffix("Back: back to the channel"))
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.player === player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.id == "id:nbatv.us")
    }

    /// M7m L2, L4: a dropped channel that failed or stopped has nothing to return to: Back does nothing, the hint
    /// doesn't offer it.
    @Test(arguments: [PlayerState.Phase.failed, .idle])
    func backInTheGuideDoesNothingForADroppedChannelThatIsntPlaying(_ phase: PlayerState.Phase) async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        await dropNBATV(model, fixture)
        player.state.phase = phase
        #expect(!model.canReturnToChannel)
        #expect(!GuideView.hint(focus: .grid, isPicking: false, hasChannel: model.canReturnToChannel).contains("Back"))
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .guide)
        #expect(model.guide != nil)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    /// M7m L2: Back from the group list goes to the grid, then to the channel.
    @Test func backFromTheGroupListGoesToTheGridThenTheChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.left)                 // the now-cell → the channel cell
        _ = model.handle(.left)                 // → groups
        #expect(model.guide?.focus == .groups(1))
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .guide)
        #expect(model.guide?.focus == .grid)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    @Test func playPauseInTheGuidePausesThePreview() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.playPause)
        #expect(player.pauses == 1)
        #expect(model.mode == .guide)
    }

    @Test func groupChangeIsRemembered() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.left)                 // the now-cell → the channel cell
        _ = model.handle(.left)                 // → groups (All Channels; My Teams is above it, M7l 8c)
        #expect(model.guide?.focus == .groups(1))
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.guide?.selectedGroup == "NBA Games")
        #expect(fixture.library.state.lastGroup == "NBA Games")
        await model.pendingTask?.value
        #expect(model.guide?.channels.map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat"])
    }

    @Test func leaveClearsTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        model.leave()
        #expect(model.guide == nil)
    }

    // MARK: Channel menu (M6 L8)

    @Test func selectOnTheChannelCellOpensTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.up)
        _ = model.handle(.left)
        #expect(model.handle(.select) == .handled)
        #expect(model.menu?.title == "NFL Network")
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "matchGuide", "hide"])
    }

    // MARK: Channel menu (M6b L8)

    /// Guide on NBA TV, then Up to NFL Network, Left to its channel cell, Select.
    private func openNFLMenu(_ model: LiveTVModel) {
        openGuide(model)
        _ = model.handle(.up)
        _ = model.handle(.left)
        _ = model.handle(.select)
    }

    private func choose(_ itemID: String, in model: LiveTVModel) {
        guard let index = model.menu?.items.firstIndex(where: { $0.id == itemID }) else {
            Issue.record("No \(itemID) item")
            return
        }
        for _ in 0..<index { _ = model.handle(.down) }
        _ = model.handle(.select)
    }

    @Test func addToFavorites() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.menu?.items.first { $0.id == "favorite" }?.title == "Add to Favorites")
        choose("favorite", in: model)
        #expect(model.menu == nil)
        #expect(fixture.library.isFavorite("id:nflnetwork.us"))
        #expect(model.guide?.groups.first == "Favorites")
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        _ = model.handle(.select)
        #expect(model.menu?.items.first { $0.id == "favorite" }?.title == "Remove from Favorites")
    }

    @Test func moveInFavoritesKeepsTheMenuOpen() async throws {
        let (model, _, fixture) = try await makeGuideModel(
            preferences: ChannelPreferences(favorites: ["id:nflnetwork.us", "id:nbatv.us"]))
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.guide?.selectedGroup == "Favorites")
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "moveDown", "matchGuide", "hide"])
        choose("moveDown", in: model)
        #expect(fixture.library.preferences.favorites == ["id:nbatv.us", "id:nflnetwork.us"])
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "moveUp", "matchGuide", "hide"])
        #expect(model.menu?.focusedItem?.id == "moveUp")
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        #expect(model.guide?.channels.map(\.name) == ["NBA TV", "NFL Network"])
    }

    // MARK: Match Guide (M6b L9)

    @Test func matchGuideValueNamesTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.menu?.items.first { $0.id == "matchGuide" }?.value == "custom")
        _ = model.handle(.back)
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.menu?.title == "Red Zone")
        #expect(model.menu?.items.first { $0.id == "matchGuide" }?.value == "None")
    }

    @Test func matchGuideMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.down)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu?.title == "Red Zone")
        choose("matchGuide", in: model)
        #expect(model.menu == nil)
        await model.pendingTask?.value
        let menu = try #require(model.menu)
        #expect(menu.title == "Guide for Red Zone")
        #expect(menu.isWide)
        #expect(Array(menu.items.map(\.id).prefix(2)) == ["match.automatic", "match.none"])
        #expect(menu.focusedItem?.id == "match.automatic")
        #expect(menu.focusedItem?.value == "Selected")
    }

    /// M7l (QA): options that load after Choose Teams opened don't draw a second menu over it.
    @Test func matchGuideOptionsDontOpenOverChooseTeams() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        #expect(model.menu == nil)
        // Opening My Teams loads its programmes in a new task; wait for the options' own.
        let options = model.pendingTask
        // The options haven't loaded yet: the channel cell → groups → My Teams → Choose Teams (M7l 8c).
        openChooseTeams(model)
        #expect(model.teamPickerMenu != nil)
        await options?.value
        #expect(model.menu == nil)
        #expect(model.teamPickerMenu?.title == "Choose Teams")
    }

    @Test func choosingACandidateMatches() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        await model.pendingTask?.value
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        let current = "match.\(customID).nfl.network.hd.us2"
        let redZone = "match.\(customID).nfl.redzone.hd.us2"
        #expect(model.menu?.items.map(\.id).dropFirst(2).first == current)
        #expect(model.menu?.items.first { $0.id == current }?.value == "custom · Automatic")
        choose(redZone, in: model)
        await model.pendingTask?.value
        #expect(fixture.library.epgMatches["id:nflnetwork.us"] == EPGRef(sourceID: customID, epgID: "nfl.redzone.hd.us2"))
        #expect(fixture.overridesFile.load() == ["NFL Network": "nfl.redzone.hd.us2"])
    }

    @Test func hideChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("hide", in: model)
        #expect(model.menu == nil)
        #expect(model.guide?.channels.contains { $0.name == "NFL Network" } == false)
        #expect(model.guide?.focusedChannel?.name == "NBA TV")
        #expect(model.currentChannel?.name == "NBA TV")
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    @Test func watchInTheChannelMenuPlays() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.up)
        _ = model.handle(.left)
        _ = model.handle(.select)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(model.menu == nil)
        #expect(model.currentChannel?.name == "NFL Network")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(1)])
    }

    @Test func backClosesTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu != nil)
        #expect(model.handle(.back) == .handled)
        #expect(model.menu == nil)
        #expect(model.mode == .guide)
    }

    /// M7m L3: Back from Match Guide goes back to the channel menu, focused on its Match Guide row.
    @Test func backFromMatchGuideReturnsToTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        await model.pendingTask?.value
        #expect(model.menu?.title == "Guide for NFL Network")
        #expect(model.isSubmenu)
        #expect(model.handle(.back) == .handled)
        #expect(model.menu?.title == "NFL Network")
        #expect(model.menu?.focusedItem?.id == "matchGuide")
        #expect(!model.isSubmenu)
        #expect(model.mode == .guide)
    }

    /// M7m L3 (QA): a second Match Guide opened while the first's options load cancels the first, so the
    /// first can't open its channel's menu or clear the second's parent.
    @Test func aNewerMatchGuideOpenCancelsTheOlderOne() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        let first = model.pendingTask
        #expect(model.menu == nil)
        // The options haven't loaded: Red Zone's channel menu (two rows down), then its Match Guide.
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.menu?.title == "Red Zone")
        choose("matchGuide", in: model)
        let second = model.pendingTask
        await first?.value
        await second?.value
        #expect(model.menu?.title == "Guide for Red Zone")
        #expect(model.isSubmenu)
        _ = model.handle(.back)
        #expect(model.menu?.title == "Red Zone")
        #expect(model.menu?.focusedItem?.id == "matchGuide")
    }

    /// M7m L3: once back in the channel menu, Back closes it (the parent isn't kept twice).
    @Test func backFromTheChannelMenuClosesIt() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        await model.pendingTask?.value
        _ = model.handle(.back)
        #expect(model.menu?.title == "NFL Network")
        #expect(model.handle(.back) == .handled)
        #expect(model.menu == nil)
        #expect(model.mode == .guide)
    }

    /// M7m L3: a match chosen closes both menus; the next channel menu's Back closes it at once.
    @Test func choosingAGuideMatchClosesBothMenus() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        await model.pendingTask?.value
        choose("match.none", in: model)
        #expect(model.menu == nil)
        await model.pendingTask?.value
        _ = model.handle(.select)
        #expect(model.menu?.title == "NFL Network")
        _ = model.handle(.back)
        #expect(model.menu == nil)
    }

    @Test func homeWithTheMenuOpenLeaves() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.handle(.home) == .leave)
    }

    // MARK: Menu and Channel Up/Down (M7 L5, L22)

    @Test func channelUpZapsUpTheListByDefault() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nbatv.us"))
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.channelUp)
        #expect(model.currentChannel?.name == "NFL Network")
        _ = model.handle(.channelDown)
        _ = model.handle(.channelDown)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    @Test func channelUpCanMeanTheHigherNumber() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nbatv.us"))
        defer { fixture.cleanUp() }
        model.channelUpMovesUpList = false
        await open(model)
        _ = model.handle(.channelUp)
        #expect(model.currentChannel?.name == "Red Zone")
        _ = model.handle(.channelDown)
        _ = model.handle(.channelDown)
        #expect(model.currentChannel?.name == "NFL Network")
    }

    @Test func menuInThePlayerOpensTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        #expect(model.handle(.menu) == .handled)
        #expect(model.mode == .player)
        #expect(model.menu?.title == "NBA TV")
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "matchGuide", "hide"])
        _ = model.handle(.menu)
        #expect(model.menu == nil)
    }

    @Test func menuInTheGuideOpensTheFocusedChannelsMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.up)
        #expect(model.handle(.menu) == .handled)
        #expect(model.menu?.title == "NFL Network")
    }

    @Test func channelUpDownPageTheGuide() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.channelDown)
        #expect(model.guide?.focusedChannel?.name == "Knicks @ Heat")
        _ = model.handle(.channelUp)
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        #expect(model.mode == .guide)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    // MARK: Choose Teams (M7l L12, 8c)

    /// From the channel cell: Left to the groups, up to My Teams, open it; Select on its first row, Choose Teams.
    private func openChooseTeams(_ model: LiveTVModel) {
        _ = model.handle(.left)   // → groups
        for _ in 0..<20 where model.guide?.focus != .groups(0) { _ = model.handle(.up) }
        #expect(model.guide?.groups.first == "My Teams")
        _ = model.handle(.select)   // My Teams
        #expect(model.guide?.focusedRow == .chooseTeams)
        #expect(model.handle(.select) == .handled)
    }

    @Test func chooseTeamsFromTheGuideTogglesATeamAndBackReturnsToTheRow() async throws {
        let (model, _, fixture) = try makeModel()
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .guide)
        _ = model.handle(.left)   // the now-cell → the channel cell
        openChooseTeams(model)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.focusedRow == .chooseTeams)
        #expect(model.teamPickerMenu?.title == "Choose Teams")

        // College Basketball → its first conference → its first team.
        let league = TeamLeague.allCases.firstIndex(of: .ncaam)!
        for _ in 0..<league { _ = model.handle(.down) }
        _ = model.handle(.select)
        #expect(model.teamPicker?.level == .league(.ncaam))
        #expect(model.teamPickerMenu?.title == "College Basketball")
        let conference = TeamCatalog.conferences(in: .ncaam)[0]
        _ = model.handle(.select)
        #expect(model.teamPickerMenu?.title == conference)
        let team = TeamCatalog.teams(in: .ncaam, conference: conference)[1]
        _ = model.handle(.down)
        #expect(model.handle(.select) == .handled)
        #expect(fixture.library.isTeamPicked(team.id))
        // The level is rebuilt with the value and the focus kept.
        #expect(model.teamPickerMenu?.focusedIndex == 1)
        #expect(model.teamPickerMenu?.focusedItem?.value == "In My Teams")

        // Back: the conferences, focused on the one left, now "1 On".
        _ = model.handle(.back)
        #expect(model.teamPickerMenu?.title == "College Basketball")
        #expect(model.teamPickerMenu?.focusedIndex == 0)
        #expect(model.teamPickerMenu?.focusedItem?.value == "1 On")
        // Back: the leagues, on College Basketball; Home still leaves.
        _ = model.handle(.back)
        #expect(model.teamPickerMenu?.title == "Choose Teams")
        #expect(model.teamPickerMenu?.focusedIndex == league)
        #expect(model.teamPickerMenu?.focusedItem?.value == "1 On")
        // Back on level 1: the guide, on My Teams' Choose Teams row.
        _ = model.handle(.back)
        #expect(model.teamPicker == nil)
        #expect(model.teamPickerMenu == nil)
        #expect(model.mode == .guide)
        #expect(model.guide?.focus == .grid)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.focusedRow == .chooseTeams)
        #expect(fixture.library.isTeamPicked(team.id))
        _ = model.handle(.select)
        #expect(model.handle(.home) == .leave)
    }

    // MARK: Guide idle return (M7m L16)

    static let shortIdle: Duration = .milliseconds(30)

    @Test func idleGuideReturnsToThePlayingChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel(guideIdleReturn: Self.shortIdle)
        defer { fixture.cleanUp() }
        openGuide(model)
        #expect(model.mode == .guide)
        await model.guideIdleTask?.value
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.player === player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])   // no reconnect
        #expect(model.banner?.channel.id == "id:nbatv.us")
    }

    @Test func idleGuideWithNothingPlayingStays() async throws {
        let (model, player, fixture) = try makeModel(guideIdleReturn: Self.shortIdle)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .guide)
        await model.guideIdleTask?.value
        #expect(model.mode == .guide)
        #expect(model.guide != nil)
        #expect(player.played.isEmpty)
    }

    @Test func idleChannelMenuInThePlayerCloses() async throws {
        let (model, player, fixture) = try await makeGuideModel(guideIdleReturn: Self.shortIdle)
        defer { fixture.cleanUp() }
        _ = model.handle(.menu)
        #expect(model.menu?.title == "NBA TV")
        await model.guideIdleTask?.value
        #expect(model.menu == nil)
        #expect(!model.isSubmenu)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    @Test func idleSearchOverTheGuideReturnsToTheChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel(guideIdleReturn: Self.shortIdle)
        defer { fixture.cleanUp() }
        openGuide(model)
        _ = model.handle(.left)     // the channel cell
        _ = model.handle(.left)     // groups
        _ = model.handle(.channelUp)   // a page up stops at the Search row (Up loops, M7n)
        #expect(model.guide?.focus == .search)
        _ = model.handle(.select)
        #expect(model.search != nil)
        await model.guideIdleTask?.value
        #expect(model.search == nil)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    /// L16 with L3: the idle return cancels a Match Guide still loading, so it can't open after it.
    @Test func idleCancelsAMatchGuideStillLoading() async throws {
        let (model, player, fixture) = try await makeGuideModel(guideIdleReturn: Self.shortIdle)
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        let matchGuide = try #require(model.pendingTask)   // also `matchGuideTask`
        await model.guideIdleTask?.value
        await matchGuide.value
        // Pins the cancel: nothing else cancels this task, and `isCancelled` turns true even on a finished task,
        // so it holds whichever finished first.
        #expect(matchGuide.isCancelled)
        #expect(model.menu == nil)
        #expect(!model.isSubmenu)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    @Test func aPressRestartsTheGuideIdleTimer() async throws {
        let (model, _, fixture) = try await makeGuideModel(guideIdleReturn: .milliseconds(100))
        defer { fixture.cleanUp() }
        openGuide(model)
        let first = try #require(model.guideIdleTask)
        _ = model.handle(.down)
        let second = try #require(model.guideIdleTask)
        #expect(first.isCancelled)
        #expect(first != second)
        #expect(model.mode == .guide)
        await second.value
        #expect(model.mode == .player)
    }

    // MARK: Paused overlays (M7m L15)

    @Test func pausedOverlayHidesAfter15sAndAPressShowsItAgain() async throws {
        let (model, player, fixture) = try await makeGuideModel(pausedOverlayDuration: .milliseconds(30))
        defer { fixture.cleanUp() }
        _ = model.handle(.playPause)
        #expect(player.state.phase == .paused)
        #expect(model.pausedOverlayVisible)
        await model.pausedOverlayTask?.value
        #expect(!model.pausedOverlayVisible)
        #expect(player.state.phase == .paused)
        _ = model.handle(.left)   // any press while paused
        #expect(model.pausedOverlayVisible)
        await model.pausedOverlayTask?.value
        #expect(!model.pausedOverlayVisible)
    }

    @Test func pausedOverlayDoesntAffectTheBannerTimer() async throws {
        let (model, player, fixture) = try await makeGuideModel(pausedOverlayDuration: .milliseconds(30))
        defer { fixture.cleanUp() }
        _ = model.handle(.playPause)
        #expect(player.state.phase == .paused)
        #expect(model.banner != nil)
        #expect(model.showsTimeshiftBar)
        await model.pausedOverlayTask?.value
        #expect(!model.pausedOverlayVisible)
        // The banner and the 5 s bar run on their own timer.
        #expect(model.banner != nil)
        #expect(model.showsTimeshiftBar)
    }

    /// Select hides the paused bar with the banner (M7c L11 still toggles); the next Select shows both again.
    @Test func selectWhilePausedTogglesThePausedBar() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.playPause)
        #expect(player.state.phase == .paused)
        _ = model.handle(.select)
        #expect(model.banner == nil)
        #expect(!model.showsTimeshiftBar)
        #expect(!model.pausedOverlayVisible)
        _ = model.handle(.select)
        #expect(model.banner != nil)
        #expect(model.showsTimeshiftBar)
        #expect(model.pausedOverlayVisible)
    }

    @Test func leavingCancelsTheGuideIdleTimer() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openGuide(model)
        let task = try #require(model.guideIdleTask)
        model.leave()
        #expect(task.isCancelled)
        #expect(model.guideIdleTask == nil)
    }

    @Test func leavingCancelsThePausedOverlayTimer() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.playPause)
        let task = try #require(model.pausedOverlayTask)
        model.leave()
        #expect(task.isCancelled)
        #expect(model.pausedOverlayTask == nil)
        #expect(!model.pausedOverlayVisible)
    }

    // MARK: M7j L13: Live TV with only an antenna

    @Test func antennaOnlyOpensTheGuide() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .guide)
        #expect(model.guide?.groups == ["My Teams", "Antenna"])
        #expect(model.guide?.selectedGroup == "Antenna")
        #expect(model.guide?.focusedChannel?.name == "WSB-HD")
        #expect(fixture.tuner?.searchCount == 1)
        #expect(player.played.isEmpty)
    }

    @Test func noPlaylistAndNoTunerNeedsSetup() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner(devices: []))
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .setupNeeded)
        #expect(fixture.tuner?.searchCount == 1)
        // The search isn't repeated on the next open while it's fresh.
        await open(model)
        #expect(model.mode == .setupNeeded)
        #expect(fixture.tuner?.searchCount == 1)
    }

    @Test func antennaOnlyWithoutChannelsSaysNoChannelsFound() async throws {
        let tuner = FakeTuner(lineups: [AntennaFixtures.device().lineupURL: "[]"])
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("No channels found"))
    }

    @Test func previewStartsWithOnlyATuner() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library)
        model.startPreview(channelID: "antenna:5.1")
        #expect(player.played.isEmpty)   // no tuner found yet

        await fixture.library.discoverAntenna()
        model.startPreview(channelID: "antenna:5.1")
        #expect(model.previewChannelID == "antenna:5.1")
        #expect(player.played == [AntennaFixtures.streamURL("5.1")])
    }

    // MARK: M7j L6, L7: antenna channels play direct and are never touched ahead

    /// The playlist and a fake tuner (2.1, 5.1, 11.1 after the playlist's five channels in All Channels).
    private func makeAntennaModel(state: IPTVState) async throws -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, state: state, tuner: FakeTuner())
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library,
                                now: { fixture.clock.now })
        await open(model)
        return (model, player, fixture)
    }

    @Test func antennaChannelPlaysDirect() async throws {
        let (model, player, fixture) = try await makeAntennaModel(state: IPTVState(lastChannelID: "antenna:5.1",
                                                                                   lastGroup: "Antenna"))
        defer { fixture.cleanUp() }
        #expect(model.mode == .player)
        #expect(player.played == [AntennaFixtures.streamURL("5.1")])
        #expect(player.playedDirect == [true])
        _ = model.handle(.down)
        #expect(player.played.last == AntennaFixtures.streamURL("11.1"))
        #expect(player.playedDirect == [true, true])
    }

    /// M7j L18 (step 9b QA minor 1): while a channel scan runs, no antenna stream is asked for: no preview, and full
    /// screen says so without a `play`. Playlist channels still play.
    @Test func noAntennaStreamWhileTheTunerScans() async throws {
        let tuner = FakeTuner()
        tuner.setLineupStatusSequence([AntennaFixtures.scanningLineupStatusJSON(progress: 10, found: 1)])
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      state: IPTVState(lastChannelID: "antenna:5.1", lastGroup: "Antenna"), tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        await library.antennaPageVisible(true)   // a scan started elsewhere
        #expect(library.antenna.isScanning)
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })

        model.startPreview(channelID: "antenna:5.1")
        #expect(model.previewChannelID == nil)
        #expect(player.played.isEmpty)

        await open(model)
        #expect(model.mode == .player)
        #expect(model.currentChannel?.id == "antenna:5.1")
        #expect(model.playbackError == "The tuner is scanning for channels")
        #expect(player.played.isEmpty)
        _ = model.handle(.up)   // 2.1, an antenna channel too
        #expect(player.played.isEmpty)

        library.stopAntennaScan()
        model.startPreview(channelID: "id:nbatv.us")
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    /// Step 10 (security N1): a scan blocks only its own tuner's channels. Tuner B reports a scan when Settings →
    /// Antenna opens (a scan elsewhere, or a LAN host that always says so); tuner A's channels still preview and play,
    /// B's show "The tuner is scanning for channels" without a `play`.
    @Test func aScanBlocksOnlyItsOwnTunersChannels() async throws {
        let deviceA = AntennaFixtures.device()
        let deviceB = AntennaFixtures.device(id: "5678ABCD", host: "10.0.0.10")
        let tuner = FakeTuner(devices: [deviceA, deviceB], lineups: [
            deviceA.lineupURL: AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("5.1", "WAGA-HD")]),
            deviceB.lineupURL: AntennaFixtures.lineupJSON([("11.1", "WXIA-HD")], host: "10.0.0.10"),
        ])
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON()], for: deviceA)
        tuner.setLineupStatusSequence([AntennaFixtures.scanningLineupStatusJSON(progress: 10, found: 1)], for: deviceB)
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      state: IPTVState(lastChannelID: "antenna:5.1", lastGroup: "Antenna"), tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        await library.antennaPageVisible(true)
        #expect(library.antenna.isScanning)
        #expect(library.antenna.isScanning(deviceID: deviceB.id))
        #expect(!library.antenna.isScanning(deviceID: deviceA.id))
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })

        // The preview: B's channel doesn't start, A's does.
        model.startPreview(channelID: "antenna:11.1")
        #expect(model.previewChannelID == nil)
        #expect(player.played.isEmpty)
        model.startPreview(channelID: "antenna:5.1")
        #expect(model.previewChannelID == "antenna:5.1")
        #expect(player.played == [AntennaFixtures.streamURL("5.1")])
        model.stopPreview()

        // Full screen: A's 5.1 plays; Down to B's 11.1 says the tuner is scanning, with no stream request.
        await open(model)
        #expect(model.mode == .player)
        #expect(model.currentChannel?.id == "antenna:5.1")
        #expect(model.playbackError == nil)
        let playedBefore = player.played.count
        #expect(player.played.last == AntennaFixtures.streamURL("5.1"))
        _ = model.handle(.down)
        #expect(model.currentChannel?.id == "antenna:11.1")
        #expect(model.playbackError == "The tuner is scanning for channels")
        #expect(player.played.count == playedBefore)
        _ = model.handle(.up)   // back to A's 5.1: plays
        #expect(model.currentChannel?.id == "antenna:5.1")
        #expect(player.played.count == playedBefore + 1)
        #expect(player.played.last == AntennaFixtures.streamURL("5.1"))
    }

    @Test func playlistChannelPlaysThroughTheRelay() async throws {
        let (model, player, fixture) = try await makeAntennaModel(state: Self.watching)
        defer { fixture.cleanUp() }
        #expect(model.currentChannel?.name == "NFL Network")
        #expect(player.played == [IPTVFixtures.streamURL(1)])
        #expect(player.playedDirect == [false])
    }

    /// L7: a zap's neighbors are resolved ahead only when they're playlist channels.
    @Test func neighborsSkipAntennaChannels() async throws {
        let (model, _, fixture) = try await makeAntennaModel(state: IPTVState(lastChannelID: "id:knicks @ heat",
                                                                              lastGroup: "All Channels"))
        defer { fixture.cleanUp() }
        var prefetched: [[URL]] = []
        model.prefetchStreams = { prefetched.append($0) }
        _ = model.handle(.up)   // Lakers @ Celtics: Red Zone and Knicks @ Heat
        #expect(prefetched == [[IPTVFixtures.streamURL(3), IPTVFixtures.streamURL(5)]])
        _ = model.handle(.down)   // Knicks @ Heat: Lakers @ Celtics, not 2.1
        #expect(prefetched.last == [IPTVFixtures.streamURL(4)])
        _ = model.handle(.down)   // 2.1: Knicks @ Heat, not 5.1
        #expect(model.currentChannel?.id == "antenna:2.1")
        #expect(prefetched.last == [IPTVFixtures.streamURL(5)])
        _ = model.handle(.down)   // 5.1: 2.1 and 11.1, both antenna: nothing
        #expect(model.currentChannel?.id == "antenna:5.1")
        #expect(prefetched.count == 3)
    }

    /// L7: the guide's highlight resting on an antenna channel doesn't warm it.
    @Test func guideWarmUpSkipsAntennaChannels() async throws {
        let (model, player, fixture) = try await makeAntennaModel(state: IPTVState(lastChannelID: "id:knicks @ heat",
                                                                                   lastGroup: "All Channels"))
        defer { fixture.cleanUp() }
        player.state.phase = .playing
        var warmed: [URL] = []
        model.warmStream = { warmed.append($0) }
        model.guideWarmDelay = .milliseconds(30)
        openGuide(model)
        #expect(model.guide?.focusedChannel?.id == "id:knicks @ heat")
        _ = model.handle(.down)
        #expect(model.guide?.focusedChannel?.id == "antenna:2.1")
        await model.guideWarmTask?.value
        #expect(warmed.isEmpty)
        _ = model.handle(.down)
        await model.guideWarmTask?.value
        #expect(warmed.isEmpty)

        // A playlist channel still is (the warm-up works in this setup).
        _ = model.handle(.up)
        _ = model.handle(.up)
        _ = model.handle(.up)
        #expect(model.guide?.focusedChannel?.id == "id:lakers @ celtics")
        await model.guideWarmTask?.value
        #expect(warmed == [IPTVFixtures.streamURL(4)])
    }

    // MARK: M7j L9: why an antenna channel didn't play

    /// 5.1 full screen (the playlist and a fake tuner), its tuner answering `status`.
    private func makeFailingAntennaModel(status: String? = AntennaFixtures.statusJSON(busy: 0)) async throws
        -> (LiveTVModel, FakePlayer, LibraryFixture, FakeTuner) {
        let (model, player, fixture) = try await makeAntennaModel(state: IPTVState(lastChannelID: "antenna:5.1",
                                                                                   lastGroup: "Antenna"))
        let tuner = try #require(fixture.tuner)
        tuner.setStatus(status)
        tuner.setLineupStatus(AntennaFixtures.lineupStatusJSON(scanning: false))
        #expect(player.played == [AntennaFixtures.streamURL("5.1")])
        return (model, player, fixture, tuner)
    }

    /// Retries exhausted with mpv's last "HTTP error NNN" (`httpStatus`), then the diagnosis.
    private func fail(_ player: FakePlayer, httpStatus: Int?, _ model: LiveTVModel) async {
        player.state.httpStatus = httpStatus
        player.fail()
        await model.pendingTask?.value
    }

    @Test func antennaFailureShowsNoSignal() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel()
        defer { fixture.cleanUp() }
        await fail(player, httpStatus: 503, model)
        #expect(tuner.statusFetchCount == 1)
        #expect(model.playbackError == "No signal on this channel")
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
        // Select tries again (as for any failure).
        _ = model.handle(.select)
        #expect(player.played == [AntennaFixtures.streamURL("5.1"), AntennaFixtures.streamURL("5.1")])
        #expect(model.playbackError == nil)
    }

    @Test func antennaFailureDoesntRefreshThePlaylist() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel()
        defer { fixture.cleanUp() }
        let fetches = fixture.network.fetchCount
        let lineupFetches = tuner.lineupFetchCount
        await fail(player, httpStatus: nil, model)
        #expect(fixture.network.fetchCount == fetches)
        #expect(tuner.lineupFetchCount == lineupFetches)
        #expect(model.playbackError == "No signal on this channel")
        #expect(player.played.count == 1)
    }

    /// Every tuner busy (another device has them): said at once, without a retry.
    @Test func antennaFailureWithEveryTunerBusySaysSo() async throws {
        let (model, player, fixture, _) = try await makeFailingAntennaModel(status: AntennaFixtures.statusJSON(busy: 2))
        defer { fixture.cleanUp() }
        await fail(player, httpStatus: 503, model)
        #expect(model.playbackError == "Both antenna tuners are in use")
        #expect(player.played.count == 1)
    }

    @Test func unknownChannelRefreshesTheLineupAndRetriesOnce() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel()
        defer { fixture.cleanUp() }
        let lineupFetches = tuner.lineupFetchCount
        await fail(player, httpStatus: 404, model)
        #expect(tuner.lineupFetchCount == lineupFetches + 1)
        #expect(player.played == [AntennaFixtures.streamURL("5.1"), AntennaFixtures.streamURL("5.1")])
        #expect(player.playedDirect == [true, true])
        #expect(model.playbackError == nil)

        // The retry fails too: the message, with no second lineup read.
        await fail(player, httpStatus: 404, model)
        #expect(tuner.lineupFetchCount == lineupFetches + 1)
        #expect(player.played.count == 2)
        #expect(model.playbackError == "This channel is no longer on the tuner")
    }

    @Test func unknownChannelGoneFromTheLineupIsNotRetried() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel()
        defer { fixture.cleanUp() }
        tuner.setLineup(AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("11.1", "WXIA-HD")]),
                        for: AntennaFixtures.device())
        await fail(player, httpStatus: 404, model)
        #expect(player.played.count == 1)
        #expect(model.playbackError == "This channel is no longer on the tuner")
    }

    @Test func unreachableTunerRediscoversAndRetriesOnce() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel(status: nil)
        defer { fixture.cleanUp() }
        let searches = tuner.searchCount
        let lineupFetches = tuner.lineupFetchCount
        await fail(player, httpStatus: nil, model)
        #expect(tuner.searchCount == searches + 1)
        #expect(tuner.lineupFetchCount == lineupFetches + 1)
        #expect(player.played == [AntennaFixtures.streamURL("5.1"), AntennaFixtures.streamURL("5.1")])
        #expect(model.playbackError == nil)

        await fail(player, httpStatus: nil, model)
        #expect(tuner.searchCount == searches + 1)
        #expect(player.played.count == 2)
        #expect(model.playbackError == "The antenna tuner isn't answering")
    }

    /// The search finds the tuner but its lineup doesn't come: no retry on the kept channels.
    @Test func unreachableTunerWithoutALineupIsNotRetried() async throws {
        let (model, player, fixture, tuner) = try await makeFailingAntennaModel(status: nil)
        defer { fixture.cleanUp() }
        tuner.setLineup(nil, for: AntennaFixtures.device())
        await fail(player, httpStatus: nil, model)
        #expect(player.played.count == 1)
        #expect(model.playbackError == "The antenna tuner isn't answering")
    }

    /// A zap while the tuner is asked: the new channel's load decides, not the old diagnosis.
    @Test func aZapDuringTheDiagnosisWins() async throws {
        let (model, player, fixture, _) = try await makeFailingAntennaModel()
        defer { fixture.cleanUp() }
        player.state.httpStatus = 503
        player.fail()
        _ = model.handle(.down)   // 11.1
        await model.pendingTask?.value
        #expect(model.currentChannel?.id == "antenna:11.1")
        #expect(model.playbackError == nil)
    }

    @Test func previewFailureOnAnAntennaChannelEnds() async throws {
        let tuner = FakeTuner()
        tuner.setStatus(AntennaFixtures.statusJSON(busy: 0))
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library)
        await fixture.library.discoverAntenna()
        model.startPreview(channelID: "antenna:5.1")
        #expect(player.played == [AntennaFixtures.streamURL("5.1")])
        player.state.httpStatus = 503
        player.fail()
        await model.pendingTask?.value
        #expect(model.previewFailed)
        #expect(model.previewChannelID == nil)
        #expect(model.playbackError == nil)
        #expect(tuner.statusFetchCount == 0)
        #expect(player.played.count == 1)
    }

    /// QA (step 4) finding 1: a tuner was found but its lineup couldn't be read: the antenna's failure, not setup.
    @Test func unreadableLineupWithOnlyATunerIsUnavailable() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner(lineups: [:]))
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(fixture.tuner?.searchCount == 1)
        #expect(model.mode == .unavailable("The antenna tuner isn't answering"))
        #expect(model.mode != .setupNeeded)
    }
}

/// M7c L15, L16: the home screen's muted preview and Select adopting it.
struct LiveTVPreviewTests {
    static let nfl = "id:nflnetwork.us"
    static let nba = "id:nbatv.us"

    /// The playlist loaded, Live TV not open; last watched NFL Network.
    private func makeModel(state: IPTVState = IPTVState(lastChannelID: "id:nflnetwork.us")) async throws
        -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, state: state)
        await fixture.library.refreshPlaylist()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library,
                                now: { fixture.clock.now })
        return (model, player, fixture)
    }

    @Test func startMutesWithoutASleepAssertion() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nfl)
        #expect(model.previewChannelID == Self.nfl)
        #expect(player.played == [IPTVFixtures.streamURL(1)])
        #expect(!player.audible)
        #expect(!player.holdsSleepAssertion)
        #expect(!model.isPreviewPlaying)
        player.state.phase = .playing
        #expect(model.isPreviewPlaying)

        model.startPreview(channelID: Self.nfl)
        #expect(player.played.count == 1)
    }

    @Test func unknownChannelIsIgnored() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: "id:nope")
        #expect(model.previewChannelID == nil)
        #expect(player.played.isEmpty)
    }

    /// M7c L25: leaving keeps a playing channel as the preview: muted, no sleep assertion, no reconnect.
    @Test func leaveCanKeepTheChannelAsThePreview() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.open()
        await model.pendingTask?.value
        #expect(model.mode == .player)
        player.state.phase = .playing
        let stops = player.stops
        model.leave(keepingPreview: true)
        #expect(model.previewChannelID == Self.nfl)
        #expect(player.stops == stops)
        #expect(!player.audible)
        #expect(!player.holdsSleepAssertion)

        // Opening again adopts it.
        model.open()
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
        #expect(player.audible)
    }

    @Test func leaveWithoutKeepingStops() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.open()
        await model.pendingTask?.value
        #expect(model.mode == .player)
        player.state.phase = .playing
        model.leave(keepingPreview: false)
        #expect(model.previewChannelID == nil)
        #expect(player.state.phase == .idle)
    }

    @Test func aFailedChannelIsntKept() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.open()
        await model.pendingTask?.value
        #expect(model.mode == .player)
        player.state.phase = .failed
        model.leave(keepingPreview: true)
        #expect(model.previewChannelID == nil)
    }

    @Test func stopRestores() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nfl)
        model.stopPreview()
        #expect(model.previewChannelID == nil)
        #expect(player.stops == 1)
        #expect(player.audible)
        #expect(player.holdsSleepAssertion)
    }

    @Test func openingThePreviewedChannelAdoptsIt() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nfl)
        player.state.phase = .playing
        model.open()
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
        #expect(player.stops == 0)
        #expect(player.audible)
        #expect(player.holdsSleepAssertion)
        #expect(model.previewChannelID == nil)
        #expect(model.currentChannel?.id == Self.nfl)
        #expect(model.banner?.channel.id == Self.nfl)
    }

    @Test func aCardOnThePreviewedChannelAdoptsIt() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nba)
        model.open(channelID: Self.nba)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(fixture.library.state.lastChannelID == Self.nba)
    }

    @Test func openingAnotherChannelStopsThePreview() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nba)
        model.open()
        #expect(model.previewChannelID == nil)
        #expect(player.stops == 1)
        await model.pendingTask?.value
        #expect(model.currentChannel?.id == Self.nfl)
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(1)])
        #expect(player.audible)
    }

    @Test func aFailedPreviewStops() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nfl)
        player.fail()
        #expect(model.previewChannelID == nil)
        #expect(model.previewFailed)
        #expect(player.audible)
        model.startPreview(channelID: Self.nfl)
        #expect(!model.previewFailed)
        #expect(model.previewChannelID == Self.nfl)
    }

    /// M7f L5: an open that adopts the preview checks the playlist too, without touching playback.
    @Test func adoptingThePreviewRefreshesAStalePlaylist() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        model.startPreview(channelID: Self.nfl)
        player.state.phase = .playing
        let fetches = fixture.network.fetchCount
        fixture.clock.advance(IPTVLibrary.playlistStaleness + 60)
        model.open()
        await model.adoptRefreshTask?.value
        #expect(fixture.network.fetchCount == fetches + 1)
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
        #expect(player.stops == 0)
        #expect(model.currentChannel?.id == Self.nfl)
    }

    /// M7f L5: the last channel only while it's in the playlist; else the first favorite; else nil.
    @Test func defaultFallsBackToTheFirstFavorite() async throws {
        let (present, _, presentFixture) = try await makeModel()
        defer { presentFixture.cleanUp() }
        #expect(present.defaultPreviewChannelID == Self.nfl)

        let gone = IPTVState(lastChannelID: "id:gone")
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, state: gone,
                                      preferences: ChannelPreferences(favorites: [Self.nba]))
        defer { fixture.cleanUp() }
        await fixture.library.refreshPlaylist()
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        #expect(model.defaultPreviewChannelID == Self.nba)

        let (none, _, noneFixture) = try await makeModel(state: gone)
        defer { noneFixture.cleanUp() }
        #expect(none.defaultPreviewChannelID == nil)
    }

    /// M7f L5: a re-fetch that drops the preview's channel (a game ended) stops it; one still there keeps playing.
    @Test func aPreviewWhoseChannelLeftThePlaylistStops() async throws {
        let (model, player, fixture) = try await makeModel()
        defer { fixture.cleanUp() }
        let game = "id:lakers @ celtics"
        model.startPreview(channelID: game)
        #expect(model.previewChannelID == game)
        model.playlistDidChange()
        #expect(model.previewChannelID == game)
        #expect(player.stops == 0)

        let withoutGames = IPTVFixtures.playlist.components(separatedBy: "\n").prefix(7).joined(separator: "\n")
        fixture.network.setText(withoutGames, for: IPTVFixtures.playlistURL)
        await fixture.library.refreshPlaylist()
        #expect(!fixture.library.channels.contains { $0.id == game })
        model.playlistDidChange()
        #expect(model.previewChannelID == nil)
        #expect(player.stops == 1)
        #expect(player.audible)
    }

    @Test func defaultPrefersMultiviewsHighlightedWindow() async throws {
        let (plain, _, plainFixture) = try await makeModel()
        defer { plainFixture.cleanUp() }
        #expect(plain.defaultPreviewChannelID == Self.nfl)

        var state = IPTVState(lastChannelID: Self.nfl)
        state.multiview = MultiviewSnapshot(layout: .sideBySide, slots: [Self.nfl, Self.nba], focusedSlot: 1, isActive: true)
        let (model, _, fixture) = try await makeModel(state: state)
        defer { fixture.cleanUp() }
        #expect(model.defaultPreviewChannelID == Self.nba)
    }
}
