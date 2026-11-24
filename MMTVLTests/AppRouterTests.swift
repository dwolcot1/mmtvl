import Foundation
import Testing
@testable import MMTVL

struct AppRouterTests {
    private func makeRouter(
        items: [LaunchItem] = LaunchItem.defaults,
        youtube: FakeYouTube = FakeYouTube(),
        liveTV: FakeLiveTV = FakeLiveTV(),
        pin: String? = nil,
        topShelf: any TopShelfProviding = NoTopShelf(),
        launcher: AppLauncher = AppLauncher()
    ) -> AppRouter {
        let (settings, _) = makeSettingsModel(items: items)
        return AppRouter(items: items, launcher: launcher, settings: settings, youtube: youtube, liveTV: liveTV,
                         pinStore: .inMemory(pin), tileArt: makeTestTileArt(), topShelf: topShelf)
    }

    private func enterPIN(_ code: String, _ router: AppRouter) {
        for command in pinCommands(for: code, startRow: router.pinEntry?.pad.row ?? 0) {
            _ = router.handle(command)
        }
    }

    /// The YouTube tile is the second tile in the defaults.
    private func openYouTubeFromTile(_ router: AppRouter) {
        _ = router.handle(.right)
        #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.youtube))
        _ = router.handle(.select)
    }

    /// The Settings tile is the last tile of the first row in the defaults (six per row, M7c L19).
    private func openSettingsFromTile(_ router: AppRouter) {
        for _ in 0..<5 { _ = router.handle(.right) }
        #expect(router.visibleItems[router.focus.index!].isSettingsTile)
        _ = router.handle(.select)
    }

    @Test func goHomeFromSettingsEndsPhonePairing() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.phoneRemote))
        router.settings.perform(.push(.pairPhone))
        #expect(recorder.pairingCalls == [true])
        router.goHome()
        #expect(router.screen == .home)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func goHomeFromSettingsStopsButtonLearning() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.remoteButtons))
        router.settings.perform(.push(.remoteCommand(.select)))
        router.settings.perform(.startLearning(.select))
        #expect(recorder.learningHandler != nil)
        _ = router.handle(.home)
        #expect(router.screen == .home)
        #expect(recorder.learningHandler == nil)
    }

    /// M7g review fixes: a held Left or Right repeats; in Settings only the fresh press changes page.
    @Test func settingsIgnoresRepeatedLeftAndRight() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
        #expect(router.handle(.right, isRepeat: true))
        #expect(router.settings.page == .root)
        #expect(router.handle(.right))
        #expect(router.settings.page == .homeScreen)
        #expect(router.handle(.left, isRepeat: true))
        #expect(router.settings.page == .homeScreen)
        #expect(router.handle(.left))
        #expect(router.settings.page == .root)
        #expect(router.screen == .settings)
    }

    /// M7c L32.
    @Test func launchFocusesTheStartTileOutOfTheShelf() {
        let router = makeRouter()
        _ = router.handle(.right)
        router.focusStartTile(id: "iptv")
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)
        #expect(router.shelfIndex == nil)
        router.focusStartTile(id: "missing")
        #expect(router.focusedItem?.id == "plex")
    }

    /// M7c L32: Home lands on the start tile, from the home screen and from another screen.
    @Test func homeGoesToTheStartTile() {
        let router = makeRouter()
        router.startTileID = "iptv"
        _ = router.handle(.down)
        #expect(router.focus.position.row == 1)
        _ = router.handle(.home)
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)

        _ = router.handle(.left)
        let settingsIndex = router.visibleItems.firstIndex { $0.isSettingsTile }!
        router.hover(settingsIndex)
        router.activate(settingsIndex)
        #expect(router.screen == .settings)
        _ = router.handle(.home)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "iptv")

        router.goHomeToStartTile()
        #expect(router.focusedItem?.id == "iptv")
    }

    /// M7c L32 (2026-10-10): Back that reaches the home screen lands on the start tile too.
    @Test func backToHomeGoesToTheStartTile() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.startTileID = "iptv"

        // Back on the tiles, from another row.
        _ = router.handle(.down)
        #expect(router.focus.position.row == 1)
        _ = router.handle(.back)
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)

        // Back on Settings' root page.
        let settingsIndex = router.visibleItems.firstIndex { $0.isSettingsTile }!
        router.hover(settingsIndex)
        router.activate(settingsIndex)
        #expect(router.screen == .settings)
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "iptv")

        // Back out of Live TV's guide (opened from its tile, now focused), with another start tile.
        router.startTileID = "plex"
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "plex")
    }

    /// M7c L32: the pointer resting over the home screen at launch (no move yet) doesn't take the focus.
    @Test func aRestingPointerDoesntMoveTheStartFocus() {
        let router = makeRouter()
        router.focusStartTile(id: "plex")
        router.hover(7)
        router.hoverShelfCard(0)
        #expect(router.focusedItem?.id == "plex")
        #expect(router.shelfIndex == nil)
    }

    @Test func settingsTileOpensSettings() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
    }

    /// M7c L32 (2026-10-10): onto the start tile, not the Settings tile.
    @Test func backOnSettingsRootGoesHomeToTheStartTile() {
        let router = makeRouter()
        openSettingsFromTile(router)
        let handled = router.handle(.back)
        #expect(handled)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "plex")
    }

    /// M7h step 13e: Settings' status refreshes run only while the Settings screen shows.
    @Test func settingsIsShowingFollowsTheScreen() {
        let router = makeRouter()
        #expect(!router.settings.isShowing())
        router.openSettings()
        #expect(router.settings.isShowing())
        _ = router.handle(.home)
        #expect(!router.settings.isShowing())
    }

    @Test func homeInSettingsGoesHome() {
        let router = makeRouter()
        router.openSettings()
        _ = router.handle(.down)
        let handled = router.handle(.home)
        #expect(handled)
        #expect(router.screen == .home)
    }

    @Test func setItemsKeepsFocusOnSameItem() {
        let router = makeRouter()
        _ = router.handle(.right)
        _ = router.handle(.right)
        let focusedID = router.visibleItems[router.focus.index!].id
        router.setItems(router.items.settingHidden(true, id: router.items[0].id))
        #expect(router.visibleItems[router.focus.index!].id == focusedID)
    }

    @Test func hidingFocusedItemClampsIndex() {
        let items = Array(LaunchItem.defaults.prefix(3))
        let router = makeRouter(items: items)
        _ = router.handle(.right)
        _ = router.handle(.right)
        router.setItems(items.settingHidden(true, id: items[2].id))
        #expect(router.focus.index == 1)
    }

    @Test func youtubeTileOpensYouTube() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func youtubeForwardsCommandsExceptHome() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        let commands: [RemoteCommand] = [.up, .down, .left, .right, .select, .back, .playPause, .fastForward, .rewind]
        for command in commands {
            #expect(router.handle(command))
        }
        #expect(youtube.sent == commands)
        #expect(router.screen == .youtube)
    }

    @Test func homeLeavesYouTubeAndPauses() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(youtube.pauses == 1)
        #expect(youtube.sent.isEmpty)
        // M7c L32: Home lands on the start tile.
        #expect(router.focusedItem?.id == "plex")
    }

    @Test func reopeningYouTubeAsksControllerEachTime() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.startTileID = "youtube"
        openYouTubeFromTile(router)
        _ = router.handle(.home)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 2)
    }

    // MARK: PIN (D20)

    @Test func settingsTileOpensDirectlyWithoutPIN() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
        #expect(router.pinEntry == nil)
    }

    @Test func settingsTileAsksForPIN() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        #expect(router.screen == .pin(.openSettings))
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(router.pinEntry == nil)
    }

    @Test func wrongPINStaysOnPINScreen() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        enterPIN("2468", router)
        #expect(router.screen == .pin(.openSettings))
        #expect(router.pinEntry?.message == "Wrong PIN")
    }

    @Test func backOnEmptyPINAndHomeReturnHome() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        openSettingsFromTile(router)
        _ = router.handle(.left)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(router.pinEntry == nil)
    }

    @Test func exitTileAsksForPINThenExits() {
        let router = makeRouter(pin: "1357")
        var exits = 0
        router.onExitToDesktop = { exits += 1 }
        _ = router.handle(.down)            // row 1 holds only Exit to Desktop
        #expect(router.visibleItems[router.focus.index!].isExitToDesktop)
        _ = router.handle(.select)
        #expect(router.screen == .pin(.exitToDesktop))
        #expect(exits == 0)
        enterPIN("1357", router)
        #expect(exits == 1)
        #expect(router.screen == .home)
    }

    /// M7c L9.
    @Test func quitWithoutPINQuitsAtOnce() {
        let router = makeRouter()
        var quits = 0
        router.onQuit = { quits += 1 }
        router.requestQuit()
        #expect(quits == 1)
        #expect(router.screen == .home)
    }

    @Test func quitAsksForPINFirst() {
        let router = makeRouter(pin: "1357")
        var quits = 0
        router.onQuit = { quits += 1 }
        router.requestQuit()
        #expect(router.screen == .pin(.quit))
        #expect(router.pinEntry?.title == "Enter PIN to quit MMTVL")
        enterPIN("2468", router)
        #expect(quits == 0)
        #expect(router.screen == .pin(.quit))
        enterPIN("1357", router)
        #expect(quits == 1)
    }

    @Test func cancellingTheQuitPINReturnsToSettings() {
        let router = makeRouter(pin: "1357")
        var quits = 0
        router.onQuit = { quits += 1 }
        router.openSettings()
        router.requestQuit()
        #expect(router.handle(.back))
        #expect(router.screen == .settings)
        #expect(quits == 0)
    }

    @Test func flaggedTileAsksForPINThenOpens() {
        let items = LaunchItem.defaults.settingRequiresPIN(true, id: "youtube")
        let youtube = FakeYouTube()
        let router = makeRouter(items: items, youtube: youtube, pin: "1357")
        openYouTubeFromTile(router)
        #expect(router.screen == .pin(.openTile(id: "youtube")))
        #expect(youtube.opens == 0)
        enterPIN("1357", router)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func unflaggedTileOpensWithoutPIN() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube, pin: "1357")
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
    }

    @Test func lockoutSurvivesCancel() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        for _ in 0..<5 { enterPIN("2468", router) }
        _ = router.handle(.back)
        #expect(router.screen == .home)
        _ = router.handle(.select)
        _ = router.handle(.left)
        #expect(router.pinEntry?.message?.hasPrefix("Too many tries") == true)
    }

    @Test func settingsPINFlowReturnsToSameSettingsPage() {
        let router = makeRouter()
        router.openSettings()
        router.settings.perform(.push(.homeScreen))
        router.requestPIN(.setNew)
        #expect(router.screen == .pin(.setNew))
        enterPIN("2580", router)
        enterPIN("2580", router)
        #expect(router.screen == .settings)
        #expect(router.settings.page == .homeScreen)
        #expect(router.hasPIN)
    }

    @Test func cancellingSettingsPINFlowReturnsToSettings() {
        let router = makeRouter(pin: "1357")
        router.openSettings()
        router.requestPIN(.turnOff)
        _ = router.handle(.back)
        #expect(router.screen == .settings)
        #expect(router.hasPIN)
        router.requestPIN(.turnOff)
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(!router.hasPIN)
    }

    /// Settings with a PIN, on the Home Screen page, and its recorder (pre-build 26 QA/security: status after a PIN).
    private func makeSettingsRouterWithPIN() -> (AppRouter, SettingsRecorder) {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory("1357"), tileArt: makeTestTileArt())
        router.openSettings()
        router.settings.perform(.push(.homeScreen))
        return (router, recorder)
    }

    /// M7h step 13e regression: part refreshes during PIN entry are dropped (Settings isn't showing), so cancelling
    /// back to Settings re-reads every status, on the same page.
    @Test func cancellingAPINBackToSettingsRereadsStatus() {
        let (router, recorder) = makeSettingsRouterWithPIN()
        router.requestPIN(.turnOff)
        recorder.receiver.isConnected = true
        recorder.siriRemote.isConnected = true
        router.settings.refreshStatus([.receiver, .siriRemote])
        #expect(!router.settings.receiver.isConnected)
        _ = router.handle(.back)
        #expect(router.screen == .settings)
        #expect(router.settings.page == .homeScreen)
        #expect(router.settings.receiver.isConnected)
        #expect(router.settings.siriRemote.isConnected)
    }

    /// The same for a verified PIN that returns to Settings (the power menu's Relaunch over Settings).
    @Test func aVerifiedPINBackToSettingsRereadsStatus() {
        let (router, recorder) = makeSettingsRouterWithPIN()
        var actions: [PowerMenuAction] = []
        router.onPowerAction = { actions.append($0) }
        router.requestPIN(.relaunch)
        recorder.receiver.isConnected = true
        router.settings.refreshStatus(.receiver)
        #expect(!router.settings.receiver.isConnected)
        enterPIN("1357", router)
        #expect(actions == [.relaunch])
        #expect(router.screen == .settings)
        #expect(router.settings.page == .homeScreen)
        #expect(router.settings.receiver.isConnected)
    }

    /// A PIN from home goes back home without reading Settings' status.
    @Test func cancellingAPINBackHomeDoesntReadSettingsStatus() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory("1357"), tileArt: makeTestTileArt())
        router.requestPIN(.exitToDesktop)
        let loginReads = recorder.loginItemReads
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(recorder.loginItemReads == loginReads)
    }
    // MARK: Focus motion (M7 L2)

    @Test func movingArrowsBumpFocusMotion() {
        let router = makeRouter()
        #expect(router.focusMotion == FocusMotion())
        _ = router.handle(.right)
        #expect(router.focusMotion == FocusMotion(direction: .right, generation: 1))
        _ = router.handle(.down)
        #expect(router.focusMotion == FocusMotion(direction: .down, generation: 2))
    }

    @Test func blockedArrowsAndHoverDontBumpFocusMotion() {
        let router = makeRouter()
        _ = router.handle(.left)
        _ = router.handle(.up)
        #expect(router.focusMotion.generation == 0)
        router.hover(3)
        #expect(router.focusMotion.generation == 0)
    }

    @Test func selectBumpsFocusMotion() {
        let router = makeRouter()
        router.openSettings()
        router.goHome()
        _ = router.handle(.down)   // Exit to Desktop (row 1)
        _ = router.handle(.select)
        #expect(router.focusMotion.direction == .select)
        #expect(router.focusMotion.generation == 2)
    }

    // MARK: Top shelf (M7 L12)

    private func card(_ id: String, _ action: ShelfCard.Action) -> ShelfCard {
        ShelfCard(id: id, title: id, subtitle: "", image: .channelLogo(nil), progress: nil, action: action)
    }

    /// Plex (the first tile) has three cards.
    private func shelfRouter(pin: String? = nil, liveTV: FakeLiveTV = FakeLiveTV()) -> (AppRouter, FakeTopShelf) {
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Continue Watching", [
            card("a", .openTile(id: "plex")), card("b", .playChannel("id:nbatv.us")), card("c", .openTile(id: "youtube")),
        ])
        return (makeRouter(liveTV: liveTV, pin: pin, topShelf: shelf), shelf)
    }

    @Test func upFromTheFirstRowEntersTheShelfOnlyWithCards() {
        let (router, _) = shelfRouter()
        #expect(router.handle(.up))
        #expect(router.shelfIndex == 0)
        #expect(router.focus.index == 0)

        let (other, _) = shelfRouter()
        _ = other.handle(.right)          // YouTube: banner
        _ = other.handle(.up)
        #expect(other.shelfIndex == nil)
    }

    // MARK: Live TV preview (M7c L15, L16)

    /// Live TV (the third tile) has two channel pages (M7c L21): NFL Network (the default preview), then NBA TV.
    private func previewRouter(items: [LaunchItem] = LaunchItem.defaults, pin: String? = nil) -> (AppRouter, FakeLiveTV) {
        let liveTV = FakeLiveTV()
        liveTV.defaultPreviewChannelID = "id:nflnetwork.us"
        let shelf = FakeTopShelf()
        shelf.contents["iptv"] = .carousel(title: "On Now", [
            card("live.nfl", .playChannel("id:nflnetwork.us")), card("live.nba", .playChannel("id:nbatv.us")),
        ], autoAdvances: false)
        let router = makeRouter(items: items, liveTV: liveTV, pin: pin, topShelf: shelf)
        router.previewDelay = .zero
        router.previewIdleTimeout = .seconds(3600)
        return (router, liveTV)
    }

    private func focusLiveTV(_ router: AppRouter) {
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.focusedItem?.id == "iptv")
    }

    @Test func focusingLiveTVStartsThePreview() {
        let (router, liveTV) = previewRouter()
        #expect(liveTV.previewStarts.isEmpty)
        focusLiveTV(router)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
    }

    /// M7c L21: Left/Right in the hero change channel; Down keeps the page and its channel.
    @Test func livePagesSwitchTheChannel() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.up)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        _ = router.handle(.right)
        #expect(liveTV.previewChannelID == "id:nbatv.us")
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.carouselPage == 1)
        #expect(liveTV.previewChannelID == "id:nbatv.us")
        _ = router.handle(.left)
        _ = router.handle(.right)
        #expect(router.carouselPage == 0)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
    }

    @Test func livePagesDontAutoAdvance() {
        let (router, _) = previewRouter()
        focusLiveTV(router)
        router.advanceCarousel()
        #expect(router.carouselPage == 0)
    }

    /// M7c L21: Select on the tile opens the page's channel when it isn't the first page.
    @Test func selectOnTheTileOpensTheKeptPage() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(liveTV.openedChannelIDs == [nil])
        router.goHome()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.down)
        _ = router.handle(.select)
        #expect(liveTV.openedChannelIDs == [nil, "id:nbatv.us"])
    }

    /// M7c L25: moving off the tile keeps the stream (hidden), so coming back is instant.
    @Test func movingOffTheTileKeepsThePreviewHidden() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        #expect(router.showsLivePreviewVideo)
        _ = router.handle(.right)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.previewStops == 0)
        #expect(!router.showsLivePreviewVideo)
        _ = router.handle(.left)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(router.showsLivePreviewVideo)
    }

    /// M7c L25: the home screen preloads the default channel with any tile focused.
    @Test func theHomeScreenPreloadsWithAnotherTileFocused() {
        let (router, liveTV) = previewRouter()
        _ = router.handle(.right)
        #expect(router.focusedItem?.id != "iptv")
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(!router.showsLivePreviewVideo)
        _ = router.handle(.right)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(router.showsLivePreviewVideo)
    }

    /// M7c L25: Back from Live TV keeps the channel running as the preview (no stop, no new start).
    @Test func leavingLiveTVKeepsTheChannelPlaying() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        liveTV.previewChannelID = nil   // adopted by Live TV
        liveTV.playingChannelID = "id:nflnetwork.us"
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(liveTV.leavesKeepingPreview == [true])
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open", "leave"])
    }

    /// M15 L16: Power-off (`stopPlaybackForPowerOff`, then AppDelegate's `goHomeFromAnywhere`) leaves Live TV without
    /// a preview, and none starts until the next command.
    @Test func powerOffLeavesLiveTVWithoutPreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        liveTV.previewChannelID = nil   // adopted by Live TV
        liveTV.playingChannelID = "id:nflnetwork.us"
        liveTV.calls = []
        router.stopPlaybackForPowerOff()
        router.goHomeToStartTile()
        #expect(router.screen == .home)
        #expect(liveTV.leavesKeepingPreview.first == false)
        #expect(liveTV.previewChannelID == nil)
        #expect(!liveTV.isPreviewPlaying)
        #expect(!liveTV.calls.contains { $0.hasPrefix("start") })
        // The next command (Power-on's first press) brings the preview back.
        router.noteActivity()
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(liveTV.previewChannelID != nil)
    }

    /// M15 L16: Power-off on YouTube pauses it and goes home.
    @Test func powerOffPausesYouTube() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
        router.stopPlaybackForPowerOff()
        #expect(youtube.pauses >= 1)
        router.goHomeToStartTile()
        #expect(router.screen == .home)
        #expect(youtube.sent.isEmpty)
    }

    @Test func withThePreviewOffLeavingLiveTVStopsIt() {
        let (router, liveTV) = previewRouter()
        router.livePreviewEnabled = false
        focusLiveTV(router)
        _ = router.handle(.select)
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(liveTV.leavesKeepingPreview == [false])
        #expect(liveTV.previewStarts.isEmpty)
    }

    /// M7c L26.
    @Test func theScreenSaverStopsThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.screenSaverDidStart()
        #expect(liveTV.previewChannelID == nil)
        router.screenSaverDidStop()
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
    }

    @Test func aPINLockedLiveTVTileHasNoPreview() {
        var items = LaunchItem.defaults
        items[2].requiresPIN = true
        let (router, liveTV) = previewRouter(items: items, pin: "1234")
        focusLiveTV(router)
        #expect(liveTV.previewStarts.isEmpty)
    }

    @Test func theSettingInactivityAndIdleStopThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.livePreviewEnabled = false
        #expect(liveTV.previewChannelID == nil)
        router.livePreviewEnabled = true
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")

        router.isAppActive = false
        #expect(liveTV.previewChannelID == nil)
        router.isAppActive = true
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")

        router.screensDidSleep()
        #expect(liveTV.previewChannelID == nil)
        router.noteActivity()
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.previewStarts.count == 4)
    }

    @Test func aFailedPreviewWaitsForFocusToComeBack() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        liveTV.previewChannelID = nil
        liveTV.previewFailed = true
        _ = router.handle(.up)
        _ = router.handle(.down)
        #expect(liveTV.previewStarts.count == 1)
        _ = router.handle(.left)
        _ = router.handle(.right)
        #expect(liveTV.previewStarts.count == 2)
    }

    @Test func openingSettingsStopsThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.openSettings()
        #expect(liveTV.previewChannelID == nil)
    }

    @Test func openingLiveTVKeepsThePreviewForAdoption() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open"])
    }

    @Test func noPreviewWithoutAChannel() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV, topShelf: FakeTopShelf())   // no pages, no default channel
        router.previewDelay = .zero
        focusLiveTV(router)
        #expect(liveTV.previewStarts.isEmpty)
    }

    // MARK: Leaving home (M7c L22, L23)

    @Test func selectOnLiveTVAnimatesThenAdopts() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        #expect(liveTV.opens == 0)
        await router.homeExitTask?.value
        #expect(!router.isLeavingHome)
        #expect(router.screen == .liveTV)
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open"])
    }

    @Test func commandsWaitDuringTheExit() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.handle(.right))
        #expect(router.focusedItem?.id == "iptv")
        await router.homeExitTask?.value
        #expect(liveTV.opens == 1)
    }

    @Test func homeCancelsTheExit() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        let task = router.homeExitTask
        _ = router.handle(.home)
        #expect(!router.isLeavingHome)
        await task?.value
        #expect(liveTV.opens == 0)
        #expect(router.screen == .home)
    }

    @Test func aLivePageAnimatesThenOpensItsChannel() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        await router.homeExitTask?.value
        #expect(liveTV.openedChannelIDs == ["id:nbatv.us"])
    }

    @Test func aPlexPageAnimatesThenOpens() async {
        let router = carouselRouter()
        router.homeExitDelay = .milliseconds(20)
        _ = router.handle(.up)
        _ = router.handle(.left)            // the page that opens YouTube (nothing real launches)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        #expect(router.screen == .home)
        await router.homeExitTask?.value
        #expect(router.screen == .youtube)
        #expect(!router.isLeavingHome)
    }

    /// M7h L16, QA minor 2: while Select on the Plex tile restarts Plex (after a hot-plug), the home UI stays away;
    /// its fallback starts only once the new process has opened. Fakes only: nothing real is quit or opened.
    @Test func aPlexRestartHoldsTheHomeExit() async throws {
        let fake = FakeLauncherWorkspace()
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        let base = fake.workspace
        // The restart's polls wait (real time) until the test lets the old Plex quit.
        let workspace = LauncherWorkspace(appURL: base.appURL, runningApps: base.runningApps,
                                          openApplication: base.openApplication) { duration in
            await base.sleep(duration)
            try? await Task.sleep(for: .milliseconds(5))
        }
        let launcher = AppLauncher(workspace: workspace)
        launcher.noteDisplayChange(frontmostBundleID: "dev.mmtvl.launcher")
        let router = carouselRouter(launcher: launcher)
        router.homeExitDelay = .milliseconds(20)
        router.homeExitAppFallback = .milliseconds(10)
        #expect(router.focusedItem?.id == "plex")
        _ = router.handle(.select)
        #expect(router.isLeavingHome)

        // The restart is waiting for the old Plex; well past the exit delay and the fallback, the UI is still away.
        for _ in 0..<200 where fake.sleeps.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!fake.sleeps.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        #expect(router.isLeavingHome)
        #expect(fake.events == ["terminate 100001"])

        old.isTerminated = true
        await router.homeExitTask?.value
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
        // MMTVL stayed active in the test (no app took the screen): the fallback brought the UI back after the open.
        #expect(!router.isLeavingHome)
    }

    @Test func noAnimationWithoutADelay() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(!router.isLeavingHome)
        #expect(liveTV.opens == 1)
    }

    // MARK: Carousel (M7c L14)

    /// Plex (the first tile) shows a carousel of three pages; the last opens YouTube.
    private func carouselRouter(launcher: AppLauncher = AppLauncher()) -> AppRouter {
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .carousel(title: "Continue Watching", [
            card("a", .openTile(id: "plex")), card("b", .openTile(id: "plex")), card("c", .openTile(id: "youtube")),
        ], autoAdvances: true)
        let router = makeRouter(topShelf: shelf, launcher: launcher)
        router.carouselInterval = .seconds(3600)
        return router
    }

    @Test func carouselAdvancesAndWraps() {
        let router = carouselRouter()
        #expect(router.carouselPage == 0)
        router.advanceCarousel()
        router.advanceCarousel()
        #expect(router.carouselPage == 2)
        router.advanceCarousel()
        #expect(router.carouselPage == 0)
    }

    @Test func upEntersTheCarouselOnItsPage() {
        let router = carouselRouter()
        router.advanceCarousel()
        #expect(router.handle(.up))
        #expect(router.shelfIndex == 1)
        // No auto-advance while the carousel has focus.
        router.advanceCarousel()
        #expect(router.carouselPage == 1)
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.carouselPage == 1)
        router.advanceCarousel()
        #expect(router.carouselPage == 2)
    }

    @Test func carouselLeftRightWrap() {
        let router = carouselRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        #expect(router.shelfIndex == 2)
        #expect(router.carouselPage == 2)
        _ = router.handle(.right)
        #expect(router.shelfIndex == 0)
        #expect(router.carouselPage == 0)
    }

    @Test func selectInTheCarouselActivatesThePage() {
        let router = carouselRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
    }

    @Test func carouselPageResetsWhenTheTileChanges() {
        let router = carouselRouter()
        router.advanceCarousel()
        _ = router.handle(.right)
        _ = router.handle(.left)
        #expect(router.carouselPage == 0)
    }

    @Test func upFromTheSecondRowMovesToTheFirst() {
        let (router, _) = shelfRouter()
        _ = router.handle(.down)
        _ = router.handle(.up)
        #expect(router.shelfIndex == nil)
        #expect(router.focus.index == 0)
    }

    @Test func downAndBackReturnToTheTile() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.focus.index == 0)
        _ = router.handle(.up)
        _ = router.handle(.back)
        #expect(router.shelfIndex == nil)
        #expect(router.screen == .home)
        _ = router.handle(.up)
        _ = router.handle(.up)
        #expect(router.shelfIndex == 0)
    }

    @Test func leftRightClampInTheShelf() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        #expect(router.shelfIndex == 0)
        _ = router.handle(.right)
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.shelfIndex == 2)
        #expect(router.focus.index == 0)
    }

    @Test func selectOnAChannelCardOpensLiveTVOnIt() {
        let liveTV = FakeLiveTV()
        let (router, _) = shelfRouter(liveTV: liveTV)
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        #expect(liveTV.openedChannelIDs == ["id:nbatv.us"])
        #expect(router.shelfIndex == nil)
    }

    @Test func selectOnATileCardOpensThatTile() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
    }

    @Test func aTileCardAsksForThePINWhenTheTileNeedsIt() {
        var items = LaunchItem.defaults
        items[1].requiresPIN = true
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Cards", [card("c", .openTile(id: "youtube"))])
        let router = makeRouter(items: items, pin: "1234", topShelf: shelf)
        _ = router.handle(.up)
        _ = router.handle(.select)
        #expect(router.screen == .pin(.openTile(id: "youtube")))
    }

    @Test func aPINProtectedTileNeverEntersItsShelf() {
        var items = LaunchItem.defaults
        items[0].requiresPIN = true
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Cards", [card("a", .openTile(id: "plex"))])
        let router = makeRouter(items: items, pin: "1234", topShelf: shelf)
        #expect(router.shelfContent == .banner)
        _ = router.handle(.up)
        #expect(router.shelfIndex == nil)
        // Without a PIN set, the flag doesn't matter.
        let open = makeRouter(items: items, topShelf: shelf)
        _ = open.handle(.up)
        #expect(open.shelfIndex == 0)
    }

    @Test func shrinkingContentClampsOrLeavesTheShelf() {
        let (router, shelf) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.right)
        shelf.contents["plex"] = .cards(title: "Fewer", [card("a", .openTile(id: "plex"))])
        router.shelfContentChanged()
        #expect(router.shelfIndex == 0)
        shelf.contents["plex"] = .banner
        router.shelfContentChanged()
        #expect(router.shelfIndex == nil)
    }

    @Test func focusChangesAndGoingHomeRefreshTheShelf() {
        let (router, shelf) = shelfRouter()
        _ = router.handle(.right)
        router.openSettings()
        router.goHome()
        #expect(shelf.refreshes == ["youtube", "youtube"])
    }

    // MARK: Mouse wheel (M7 L21)

    @Test func twoPreciseDeltasMoveOneRow() {
        let router = makeRouter()
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 0)
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 1)
        router.scrollWheel(deltaY: 40, precise: true)
        #expect(router.focus.position.row == 0)
    }

    @Test func oneWheelLineMovesOneRow() {
        let router = makeRouter()
        router.scrollWheel(deltaY: -1, precise: false)
        #expect(router.focus.position.row == 1)
        router.scrollWheel(deltaY: 1, precise: false)
        #expect(router.focus.position.row == 0)
    }

    @Test func scrollAccumulatorResetsAfterAPause() {
        let router = makeRouter()
        var time = Date(timeIntervalSince1970: 0)
        router.now = { time }
        router.scrollWheel(deltaY: -25, precise: true)
        time += 0.5
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 0)
    }

    @Test func wheelOnAnotherScreenDoesNothing() {
        let router = makeRouter()
        router.openSettings()
        router.scrollWheel(deltaY: -3, precise: false)
        router.goHome()
        #expect(router.focus.position.row == 0)
    }


    // MARK: Casting (M7b L4)

    @Test func castFromHomeOpensYouTube() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
        #expect(youtube.launches.isEmpty)
    }

    @Test func castWithQueryLaunchesIt() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.castYouTube(query: "pairingCode=x")
        #expect(router.screen == .youtube)
        #expect(youtube.launches == ["pairingCode=x"])
        #expect(youtube.opens == 0)
    }

    @Test func castLeavesLiveTV() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        router.castYouTube(query: nil)
        #expect(liveTV.leaves == 1)
        #expect(router.screen == .youtube)
    }

    @Test func castFromSettingsEndsPhonePairing() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.phoneRemote))
        router.settings.perform(.push(.pairPhone))
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func castClosesThePINScreen() {
        let router = makeRouter(pin: "1357")
        router.requestPIN(.exitToDesktop)
        #expect(router.pinEntry != nil)
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(router.pinEntry == nil)
    }

    @Test func castWhileOnYouTubeDoesNotPause() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.openYouTube()
        router.castYouTube(query: "pairingCode=y")
        #expect(youtube.pauses == 0)
        #expect(youtube.launches == ["pairingCode=y"])
        #expect(router.screen == .youtube)
    }

    @Test func castIgnoresTheYouTubeTilePIN() {
        let youtube = FakeYouTube()
        let items = LaunchItem.defaults.settingRequiresPIN(true, id: "youtube")
        let router = makeRouter(items: items, youtube: youtube, pin: "1357")
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(router.pinEntry == nil)
        #expect(youtube.opens == 1)
    }

    // MARK: Still screens dim (M7m L17–L19)

    /// The dimmer's clock, advanced by hand.
    private final class IdleClock {
        var now = ContinuousClock.now
        func advance(seconds: Int) { now += .seconds(seconds) }
        func advance(milliseconds: Int) { now += .milliseconds(milliseconds) }
    }

    private func useIdleClock(_ router: AppRouter) -> IdleClock {
        let clock = IdleClock()
        router.idleNow = { clock.now }
        router.updateStillness()
        return clock
    }

    /// A press the way `InputRouter` delivers it: activity first, then the command.
    private func press(_ command: RemoteCommand, _ router: AppRouter) -> Bool {
        router.noteActivity()
        return router.handle(command)
    }

    @Test func aPressWhileDimmedOnlyWakes() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        let clock = useIdleClock(router)
        #expect(press(.right, router))
        let focused = router.focus.index
        #expect(router.visibleItems[focused!].kind == .internalDestination(.youtube))
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 1)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
        // Select only wakes: the tile doesn't open.
        #expect(press(.select, router))
        #expect(router.idlePhase == .awake)
        #expect(router.screen == .home)
        #expect(youtube.opens == 0)
        // An arrow only wakes too: focus stays.
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
        #expect(press(.right, router))
        #expect(router.idlePhase == .awake)
        #expect(router.focus.index == focused)
        // The next press acts.
        #expect(press(.select, router))
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func powerWhileDimmedWakesAndActs() {
        let router = makeRouter()
        var powerPresses = 0
        router.onPowerButton = { powerPresses += 1 }
        let clock = useIdleClock(router)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
        #expect(press(.power, router))
        #expect(router.idlePhase == .awake)
        #expect(powerPresses == 1)
        // The power menu too (the screen saver phase alike).
        clock.advance(seconds: 300)
        router.idleTick()
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        #expect(press(.powerMenu, router))
        #expect(router.idlePhase == .awake)
        #expect(router.powerMenu != nil)
    }

    @Test func liveTVPlayingNeverDims() {
        let liveTV = FakeLiveTV()
        liveTV.isShowingVideo = true
        let router = makeRouter(liveTV: liveTV)
        var saverRequests = 0
        router.startScreenSaver = { saverRequests += 1 }
        let clock = useIdleClock(router)
        router.openLiveTV()
        #expect(router.screen == .liveTV)
        clock.advance(seconds: 3600)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        // Paused: still from now, dimmed five minutes later, then the screen saver.
        liveTV.isShowingVideo = false
        router.idleTick()
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 1)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        #expect(saverRequests == 1)
        // Playing again wakes it.
        liveTV.isShowingVideo = true
        router.idleTick()
        #expect(router.idlePhase == .awake)
    }

    @Test func youTubeNeverDims() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
        clock.advance(seconds: 3600)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        #expect(!router.isStillScreen)
    }

    private func dim(_ router: AppRouter, _ clock: IdleClock) {
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
    }

    /// The Siri Remote's Power path: `PowerMenuPresenter`, never `handle`.
    private func makePresenter(_ router: AppRouter) -> PowerMenuPresenter {
        PowerMenuPresenter(router: router, isLauncherActive: { true }, frontApp: { nil }, bringForward: {},
                           returnToApp: { _ in }, mayReturn: { _ in true }, desktopExit: nil)
    }

    /// QA step 6, finding 1: the Siri Remote's Power Menu wakes the dimmer and opens the menu above it.
    @Test func siriPowerMenuWhileDimmedWakesAndOpens() {
        let router = makeRouter()
        let presenter = makePresenter(router)
        let clock = useIdleClock(router)
        dim(router, clock)
        presenter.handle(.powerMenu)
        #expect(router.idlePhase == .awake)
        #expect(router.powerMenu != nil)
        // Dimmed with the menu open: a long press again only wakes (the menu stays as it is).
        dim(router, clock)
        presenter.handle(.powerMenu)
        #expect(router.idlePhase == .awake)
        #expect(router.powerMenu != nil)
    }

    /// QA step 6, finding 1: the Siri Remote's Power wakes and acts once; a bound key's Power through `handle` too.
    @Test func siriPowerWhileDimmedWakesAndActsOnce() {
        let router = makeRouter()
        var powerPresses = 0
        router.onPowerButton = { powerPresses += 1 }
        let presenter = makePresenter(router)
        let clock = useIdleClock(router)
        dim(router, clock)
        presenter.handle(.power)
        #expect(router.idlePhase == .awake)
        #expect(powerPresses == 1)
        dim(router, clock)
        #expect(press(.power, router))
        #expect(router.idlePhase == .awake)
        #expect(powerPresses == 2)
        // It's activity: the five minutes start over.
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
    }

    /// QA step 6, finding 2: a wheel event while dimmed only wakes; awake, it counts as activity.
    @Test func scrollWhileDimmedOnlyWakes() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        let focused = router.focus.index
        dim(router, clock)
        router.scrollWheel(deltaY: 3, precise: false)
        #expect(router.idlePhase == .awake)
        #expect(router.focus.index == focused)
        #expect(router.shelfIndex == nil)
        dim(router, clock)
        router.scrollWheel(deltaY: -3, precise: false)
        #expect(router.idlePhase == .awake)
        #expect(router.focus.index == focused)
        // Awake, it moves focus and resets the wait.
        clock.advance(seconds: 299)
        router.scrollWheel(deltaY: -1, precise: false)
        #expect(router.focus.index != focused)
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
    }

    /// QA step 6, findings 3 and 5: input outside `handle` (phone text into Live TV, a learnt button) wakes the
    /// dimmer through `wakeFromIdle(by:)`, from either phase.
    @Test func wakeFromIdleWakesFromEitherPhase() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        dim(router, clock)
        router.wakeFromIdle(by: "phone text")
        #expect(router.idlePhase == .awake)
        dim(router, clock)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        router.wakeFromIdle(by: "a learnt button")
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
    }

    /// QA step 6, finding 4: a click that opens another screen through the dim wakes it.
    @Test func aScreenChangeWakes() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        dim(router, clock)
        router.openSettings()
        #expect(router.screen == .settings)
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 1)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
    }

    // MARK: The screen saver (M7m L20)

    /// Dimmed for five minutes, then the screen saver phase; the screen saver takes the screen (MMTVL in the
    /// background, its engine running) and macOS says it started.
    private func startScreenSaver(_ router: AppRouter, _ clock: IdleClock) {
        router.isScreenSaverEngineRunning = { true }
        dim(router, clock)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        router.isAppActive = false
        router.screenSaverDidStart()
    }

    @Test func screenSaverPhaseStartsIt() {
        let router = makeRouter()
        var starts = 0
        router.startScreenSaver = { starts += 1 }
        router.isScreenSaverEngineRunning = { true }
        let clock = useIdleClock(router)
        dim(router, clock)
        #expect(starts == 0)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        #expect(starts == 1)
        clock.advance(seconds: 600)
        router.idleTick()
        #expect(starts == 1)
        // The screen saver taking the screen isn't the screen starting to move: the phase stays.
        router.isAppActive = false
        #expect(router.idlePhase == .screenSaver)
        #expect(router.isScreenSaverShowing)
        router.screenSaverDidStart()
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        #expect(starts == 1)
    }

    @Test func aPressDuringTheScreenSaverEndsItAndIsSwallowed() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        let clock = useIdleClock(router)
        #expect(press(.right, router))
        let focused = router.focus.index
        startScreenSaver(router, clock)
        #expect(press(.select, router))
        #expect(ends == 1)
        #expect(router.idlePhase == .awake)
        #expect(router.screen == .home)
        #expect(router.focus.index == focused)
        #expect(youtube.opens == 0)
        // Until macOS says it stopped, every press only ends it (`ScreenSaver.end()` ignores the repeats).
        #expect(press(.select, router))
        #expect(ends == 2)
        #expect(youtube.opens == 0)
        router.screenSaverDidStop()
        router.isAppActive = true
        #expect(press(.select, router))
        #expect(ends == 2)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    /// The Siri Remote's and the phone's commands (`ExternalRouter`) never become keys for the app in front while
    /// the screen saver shows, also when macOS started it (MMTVL awake, behind another app).
    @Test func externalCommandsDuringTheScreenSaverOnlyEndIt() {
        let router = makeRouter()
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        var posted: [ExternalKey] = []
        var dispatched: [RemoteCommand] = []
        let external = ExternalRouter(
            isLauncherInFront: { router.isAppActive },
            dispatch: { command, _, _ in dispatched.append(command) },
            canPostEvents: { true },
            postExternal: { posted.append($0) },
            endsScreenSaver: { router.endScreenSaverIfShowing(by: "\($0)") }
        )
        let clock = useIdleClock(router)
        startScreenSaver(router, clock)
        #expect(external.route(.down) == .endedScreenSaver)
        #expect(external.route(.home) == .endedScreenSaver)
        #expect(ends == 2)
        #expect(posted.isEmpty)
        #expect(dispatched.isEmpty)
        router.screenSaverDidStop()
        #expect(external.route(.down) == .posted(ExternalKeyMap.key(for: .down)!))
        // macOS's own screen saver over another app: MMTVL awake and in the background.
        router.screenSaverDidStart()
        #expect(router.idlePhase == .awake)
        #expect(external.route(.select) == .endedScreenSaver)
        #expect(ends == 3)
        #expect(posted.count == 1)
        router.screenSaverDidStop()
        #expect(!router.isScreenSaverShowing)
    }

    /// QA step 7, major 1: macOS ends the screen saver on the Siri Remote's touch, so `didstop` can come before the
    /// press. The first press within `screenSaverWakeGrace` after a stop no press caused is swallowed (without ending
    /// anything); later presses act.
    @Test func aPressJustAfterDidstopIsSwallowedOnce() {
        func stoppedByMacOS() -> (AppRouter, FakeYouTube, IdleClock, () -> Int) {
            let youtube = FakeYouTube()
            let router = makeRouter(youtube: youtube)
            var ends = 0
            router.endScreenSaver = { ends += 1 }
            let clock = useIdleClock(router)
            #expect(press(.right, router))
            #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.youtube))
            startScreenSaver(router, clock)
            return (router, youtube, clock, { ends })
        }
        // 0.5 s after didstop: swallowed once, then the next Select opens.
        do {
            let (router, youtube, clock, ends) = stoppedByMacOS()
            router.screenSaverDidStop()
            router.isAppActive = true
            clock.advance(milliseconds: 500)
            #expect(press(.select, router))
            #expect(youtube.opens == 0)
            #expect(router.screen == .home)
            #expect(ends() == 0)
            #expect(press(.select, router))
            #expect(youtube.opens == 1)
        }
        // 1.1 s after didstop: it acts.
        do {
            let (router, youtube, clock, _) = stoppedByMacOS()
            router.screenSaverDidStop()
            router.isAppActive = true
            clock.advance(milliseconds: 1100)
            #expect(press(.select, router))
            #expect(youtube.opens == 1)
        }
        // A press before didstop ended it: only that one is swallowed.
        do {
            let (router, youtube, clock, ends) = stoppedByMacOS()
            #expect(press(.select, router))
            #expect(ends() == 1)
            router.screenSaverDidStop()
            router.isAppActive = true
            clock.advance(milliseconds: 500)
            #expect(press(.select, router))
            #expect(youtube.opens == 1)
        }
        // Through `ExternalRouter` (the Siri Remote, the phone) alike: swallowed, not posted to the app in front.
        do {
            let (router, _, clock, _) = stoppedByMacOS()
            var posted: [ExternalKey] = []
            let external = ExternalRouter(
                isLauncherInFront: { router.isAppActive },
                dispatch: { _, _, _ in },
                canPostEvents: { true },
                postExternal: { posted.append($0) },
                endsScreenSaver: { router.endScreenSaverIfShowing(by: "\($0)") }
            )
            router.screenSaverDidStop()
            clock.advance(milliseconds: 500)
            #expect(external.route(.select) == .endedScreenSaver)
            #expect(external.route(.select) == .posted(ExternalKeyMap.key(for: .select)!))
            #expect(posted.count == 1)
        }
    }

    /// QA step 7, major 2: no screen saver while the displays sleep (a Power off at night); after they wake the wait
    /// starts over.
    @Test func noScreenSaverWhileTheDisplaysSleep() {
        let router = makeRouter()
        var starts = 0
        router.startScreenSaver = { starts += 1 }
        let clock = useIdleClock(router)
        dim(router, clock)
        router.screensDidSleep()
        clock.advance(seconds: 600)
        router.idleTick()
        #expect(starts == 0)
        #expect(router.idlePhase == .dimmed)
        router.screensDidWake()
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(starts == 0)
        clock.advance(seconds: 1)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        #expect(starts == 1)
    }

    /// Security medium: a `didstart` with no `didstop` (a crash, a kill, a forged notification) never swallows
    /// presses for good: only while a screen saver engine really runs.
    @Test func aStuckDidstartDoesntSwallowPresses() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        var engineRunning = false
        router.isScreenSaverEngineRunning = { engineRunning }
        var posted: [ExternalKey] = []
        let external = ExternalRouter(
            isLauncherInFront: { router.isAppActive },
            dispatch: { _, _, _ in },
            canPostEvents: { true },
            postExternal: { posted.append($0) },
            endsScreenSaver: { router.endScreenSaverIfShowing(by: "\($0)") }
        )
        _ = useIdleClock(router)
        #expect(press(.right, router))
        router.isAppActive = false
        // A forged didstart, no engine ever seen: nothing is swallowed (no grace window either).
        router.screenSaverDidStart()
        #expect(!router.isScreenSaverShowing)
        #expect(external.route(.down) == .posted(ExternalKeyMap.key(for: .down)!))
        #expect(external.route(.down) == .posted(ExternalKeyMap.key(for: .down)!))
        #expect(ends == 0)
        // A real one: a press ends it; the engine is gone after the end check, but no didstop came.
        engineRunning = true
        router.screenSaverDidStart()
        #expect(external.route(.down) == .endedScreenSaver)
        #expect(ends == 1)
        engineRunning = false
        #expect(external.route(.down) == .posted(ExternalKeyMap.key(for: .down)!))
        #expect(press(.select, router))
        #expect(youtube.opens == 1)
        #expect(posted.count == 3)
    }

    /// Pre-build review (security medium): a stream of forged `didstart`s, one before each press, with no engine ever
    /// running, swallows nothing, through `ExternalRouter` or `handle`.
    @Test func forgedDidstartsBeforeEachPressSwallowNothing() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        router.isScreenSaverEngineRunning = { false }
        var posted: [ExternalKey] = []
        let external = ExternalRouter(
            isLauncherInFront: { router.isAppActive },
            dispatch: { _, _, _ in },
            canPostEvents: { true },
            postExternal: { posted.append($0) },
            endsScreenSaver: { router.endScreenSaverIfShowing(by: "\($0)") }
        )
        let clock = useIdleClock(router)
        router.isAppActive = false
        for _ in 0..<4 {
            router.screenSaverDidStart()
            clock.advance(milliseconds: 50)
            #expect(external.route(.down) == .posted(ExternalKeyMap.key(for: .down)!))
        }
        #expect(posted.count == 4)
        // Home is the first tile; Right focuses YouTube.
        router.screenSaverDidStart()
        #expect(press(.right, router))
        router.screenSaverDidStart()
        clock.advance(milliseconds: 50)
        #expect(press(.select, router))
        #expect(youtube.opens == 1)
        #expect(router.screen == .youtube)
        #expect(ends == 0)
    }

    /// Pre-build review follow-up: the engine isn't listed yet at `didstart` and the idle tick doesn't run behind the
    /// screen saver; the re-check after `didstart` sees it, so a `didstop` no press caused still opens the grace window.
    @Test func theEngineSeenAfterDidstartStillOpensTheGraceWindow() async {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.screenSaverEngineRecheckWaits = [.zero, .zero]
        var engineRunning = false
        router.isScreenSaverEngineRunning = { engineRunning }
        let clock = useIdleClock(router)
        #expect(press(.right, router))
        router.isAppActive = false
        router.screenSaverDidStart()
        engineRunning = true
        await router.screenSaverEngineRecheckTask?.value
        // macOS ends it on the remote's touch: the engine goes, then didstop.
        engineRunning = false
        router.screenSaverDidStop()
        router.isAppActive = true
        clock.advance(milliseconds: 500)
        #expect(press(.select, router))
        #expect(youtube.opens == 0)
        #expect(press(.select, router))
        #expect(youtube.opens == 1)
    }

    /// The re-check stops at `didstop`: an engine listed later doesn't count for a session already over.
    @Test func theEngineRecheckEndsWithTheSession() async {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.screenSaverEngineRecheckWaits = [.seconds(60)]
        var engineRunning = false
        router.isScreenSaverEngineRunning = { engineRunning }
        _ = useIdleClock(router)
        #expect(press(.right, router))
        router.screenSaverDidStart()
        let task = router.screenSaverEngineRecheckTask
        #expect(task != nil)
        router.screenSaverDidStop()
        #expect(router.screenSaverEngineRecheckTask == nil)
        await task?.value
        engineRunning = true
        #expect(press(.select, router))
        #expect(youtube.opens == 1)
    }

    /// Pre-build review (QA minor): while dimmed a click on the dim only wakes; hover moves nothing under it.
    @Test func aClickWhileDimmedOnlyWakes() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        router.openPowerMenu()
        let menuFocus = router.powerMenu?.focusedIndex
        dim(router, clock)
        // The pointer has moved since the last command, so hover would act if awake.
        router.pointerLocationAtLastCommand = NSPoint(x: -100_000, y: -100_000)
        router.hoverPowerMenuItem(2)
        #expect(router.powerMenu?.focusedIndex == menuFocus)
        router.clickOnIdleDim()
        #expect(router.idlePhase == .awake)
        #expect(router.powerMenu != nil)
        #expect(router.powerMenu?.focusedIndex == menuFocus)
        // Awake, a click on the (clear) dim does nothing, and hover acts again.
        router.clickOnIdleDim()
        #expect(router.idlePhase == .awake)
        router.hoverPowerMenuItem(2)
        #expect(router.powerMenu?.focusedIndex == 2)

        // Home: hover doesn't move tile focus under the dim.
        router.closePowerMenu()
        let focused = router.focus.index
        dim(router, clock)
        router.pointerLocationAtLastCommand = NSPoint(x: -100_000, y: -100_000)
        router.hover(3)
        #expect(router.focus.index == focused)
        router.clickOnIdleDim()
        #expect(router.idlePhase == .awake)
        #expect(router.focus.index == focused)
        #expect(router.screen == .home)
    }

    /// Pre-build review (QA minor): a held key that wakes the dim only wakes; its repeats do nothing until a fresh
    /// press.
    @Test func heldKeyWhileDimmedOnlyWakes() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        let focused = router.focus.index
        dim(router, clock)
        #expect(router.handle(.down))
        #expect(router.handle(.down, isRepeat: true))
        #expect(router.handle(.down, isRepeat: true))
        #expect(router.idlePhase == .awake)
        #expect(router.focus.index == focused)
        _ = router.handle(.right)
        #expect(router.focus.index != focused)
        // Repeats after that fresh press act as usual.
        _ = router.handle(.left, isRepeat: true)
        #expect(router.focus.index == focused)
    }

    /// QA step 7 (minor): the engine's exit can show before `didstop`; with no press having ended it, the first press
    /// in that gap is swallowed (as just after `didstop`), the second acts, and the late `didstop` opens no new window.
    @Test func theEngineGoneBeforeDidstopSwallowsOnePress() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        let clock = useIdleClock(router)
        #expect(press(.right, router))
        startScreenSaver(router, clock)
        router.isScreenSaverEngineRunning = { false }
        #expect(press(.select, router))
        #expect(youtube.opens == 0)
        #expect(ends == 0)
        #expect(press(.select, router))
        #expect(youtube.opens == 1)
        router.goHome()
        router.screenSaverDidStop()
        #expect(router.endScreenSaverIfShowing(by: "select") == false)
    }

    @Test func didstopWakesTheDimmer() {
        let router = makeRouter()
        var ends = 0
        router.endScreenSaver = { ends += 1 }
        let clock = useIdleClock(router)
        startScreenSaver(router, clock)
        router.screenSaverDidStop()
        #expect(router.idlePhase == .awake)
        #expect(!router.isScreenSaverShowing)
        #expect(ends == 0)
        // Back in front: five more minutes before it dims again.
        router.isAppActive = true
        clock.advance(seconds: 299)
        router.idleTick()
        #expect(router.idlePhase == .awake)
        clock.advance(seconds: 1)
        router.idleTick()
        #expect(router.idlePhase == .dimmed)
    }

    /// No `didstop` (the screen saver didn't start, or macOS didn't say): coming back in front wakes it.
    @Test func backInFrontWithoutDidstopWakes() {
        let router = makeRouter()
        let clock = useIdleClock(router)
        dim(router, clock)
        clock.advance(seconds: 300)
        router.idleTick()
        #expect(router.idlePhase == .screenSaver)
        router.isAppActive = false
        #expect(router.idlePhase == .screenSaver)
        router.isAppActive = true
        #expect(router.idlePhase == .awake)
    }
}

struct AppRouterLiveTVTests {
    private func makeRouter(liveTV: FakeLiveTV, pin: String? = nil) -> AppRouter {
        let (settings, _) = makeSettingsModel()
        return AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                         liveTV: liveTV, pinStore: .inMemory(pin), tileArt: makeTestTileArt())
    }

    /// The Live TV tile is the third tile in the defaults.
    private func openLiveTVFromTile(_ router: AppRouter) {
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.iptv))
        _ = router.handle(.select)
    }

    @Test func tileOpensLiveTV() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        openLiveTVFromTile(router)
        #expect(router.screen == .liveTV)
        #expect(liveTV.opens == 1)
    }

    @Test func homeLeaves() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        openLiveTVFromTile(router)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(liveTV.leaves == 1)
        #expect(liveTV.handled.isEmpty)
    }

    @Test func leaveOutcomeGoesHome() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        liveTV.outcome = .leave
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        #expect(liveTV.leaves == 1)
    }

    @Test func commandsAreForwarded() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        for command in [RemoteCommand.up, .down, .left, .right, .select, .playPause, .fastForward, .rewind, .back] {
            #expect(router.handle(command))
        }
        #expect(liveTV.handled == [.up, .down, .left, .right, .select, .playPause, .fastForward, .rewind, .back])
        #expect(router.screen == .liveTV)
    }

    @Test func openSettingsWithoutPIN() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        liveTV.outcome = .openSettings
        _ = router.handle(.select)
        #expect(router.screen == .settings)
        #expect(liveTV.leaves == 1)
    }

    @Test func openSettingsWithPIN() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV, pin: "1357")
        router.openLiveTV()
        liveTV.outcome = .openSettings
        _ = router.handle(.select)
        #expect(router.screen == .pin(.openSettings))
        #expect(liveTV.leaves == 1)
        // Cancelling returns home.
        _ = router.handle(.back)
        #expect(router.screen == .home)
    }
}

/// M7h L14, L15: Power and the power menu on every screen; Relaunch and Restart behind the PIN.
struct AppRouterPowerTests {
    private let youtube = FakeYouTube()
    private let liveTV = FakeLiveTV()

    private func makeRouter(pin: String? = nil) -> (AppRouter, Recorder) {
        let (settings, _) = makeSettingsModel()
        let router = AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings, youtube: youtube,
                               liveTV: liveTV, pinStore: .inMemory(pin), tileArt: makeTestTileArt())
        let recorder = Recorder()
        router.onPowerButton = { recorder.powerPresses += 1 }
        router.onPowerAction = { recorder.actions.append($0) }
        return (router, recorder)
    }

    final class Recorder {
        var powerPresses = 0
        var actions: [PowerMenuAction] = []
    }

    private func enterPIN(_ code: String, _ router: AppRouter) {
        for command in pinCommands(for: code, startRow: router.pinEntry?.pad.row ?? 0) {
            _ = router.handle(command)
        }
    }

    /// Opens the menu and selects `action`.
    private func choose(_ action: PowerMenuAction, _ router: AppRouter) {
        #expect(router.handle(.powerMenu))
        let index = PowerMenu.allItems.firstIndex { $0.action == action }!
        for _ in 0..<index { _ = router.handle(.down) }
        #expect(router.powerMenu?.focusedItem.action == action)
        #expect(router.handle(.select))
    }

    @Test func menuOpensOverSettingsAndBackCloses() {
        let (router, recorder) = makeRouter()
        router.openSettings()
        #expect(router.handle(.powerMenu))
        #expect(router.powerMenu != nil)
        #expect(router.screen == .settings)
        // Commands go to the menu, not to Settings.
        _ = router.handle(.down)
        #expect(router.powerMenu?.focusedItem.action == .sleepMac)
        #expect(router.settings.page == .root)
        #expect(router.handle(.back))
        #expect(router.powerMenu == nil)
        #expect(router.screen == .settings)
        #expect(recorder.actions.isEmpty)
    }

    @Test func menuOpensOverLiveTVAndYouTubeAndTakesTheirCommands() {
        let (router, recorder) = makeRouter()
        router.openLiveTV()
        #expect(router.handle(.powerMenu))
        _ = router.handle(.down)
        _ = router.handle(.select)   // Sleep Mac mini
        #expect(liveTV.handled.isEmpty)
        #expect(router.screen == .liveTV)
        #expect(recorder.actions == [.sleepMac])

        router.openYouTube()
        #expect(router.handle(.powerMenu))
        _ = router.handle(.down)
        _ = router.handle(.back)
        #expect(youtube.sent.isEmpty)
        #expect(router.powerMenu == nil)
        #expect(router.screen == .youtube)
    }

    @Test func cancelCloses() {
        let (router, recorder) = makeRouter()
        choose(.cancel, router)
        #expect(router.powerMenu == nil)
        #expect(recorder.actions.isEmpty)
    }

    @Test func homeClosesTheMenuAndGoesHome() {
        let (router, _) = makeRouter()
        router.openLiveTV()
        _ = router.handle(.powerMenu)
        #expect(router.handle(.home))
        #expect(router.powerMenu == nil)
        #expect(router.screen == .home)
    }

    @Test func powerPressWorksEverywhereAndClosesTheMenu() {
        let (router, recorder) = makeRouter()
        #expect(router.handle(.power))
        router.openSettings()
        #expect(router.handle(.power))
        _ = router.handle(.powerMenu)
        #expect(router.handle(.power))
        #expect(router.powerMenu == nil)
        #expect(recorder.powerPresses == 3)
        #expect(router.screen == .settings)
    }

    @Test func turnOffAndSleepNeedNoPIN() {
        let (router, recorder) = makeRouter(pin: "1357")
        choose(.turnOff, router)
        choose(.sleepMac, router)
        #expect(recorder.actions == [.turnOff, .sleepMac])
        #expect(router.screen == .home)
        #expect(router.pinEntry == nil)
    }

    @Test func restartWithoutAPINRunsAtOnce() {
        let (router, recorder) = makeRouter()
        choose(.restartMac, router)
        choose(.relaunch, router)
        #expect(recorder.actions == [.restartMac, .relaunch])
        #expect(router.screen == .home)
    }

    @Test func restartWithAPINAsksForItAndAWrongPINDoesntRestart() {
        let (router, recorder) = makeRouter(pin: "1357")
        #expect(router.handle(.powerMenu))
        #expect(router.powerMenuShowsPINLock)
        _ = router.handle(.back)
        choose(.restartMac, router)
        #expect(router.screen == .pin(.restartMac))
        #expect(router.pinEntry?.title == "Enter PIN to restart the Mac mini")
        #expect(router.powerMenu == nil)
        enterPIN("2468", router)
        #expect(recorder.actions.isEmpty)
        #expect(router.screen == .pin(.restartMac))
        enterPIN("1357", router)
        #expect(recorder.actions == [.restartMac])
        #expect(router.screen == .home)
    }

    @Test func relaunchPINOverSettingsCancelsBackToSettings() {
        let (router, recorder) = makeRouter(pin: "1357")
        router.openSettings()
        choose(.relaunch, router)
        #expect(router.screen == .pin(.relaunch))
        #expect(router.pinEntry?.title == "Enter PIN to relaunch MMTVL")
        _ = router.handle(.back)
        #expect(router.screen == .settings)
        #expect(router.powerMenu == nil)
        #expect(recorder.actions.isEmpty)
    }

    /// Security S3: a held key's repeats neither press Power again nor reopen the menu.
    @Test func repeatsOfPowerAndPowerMenuDoNothing() {
        let (router, recorder) = makeRouter()
        #expect(router.handle(.power))
        #expect(router.handle(.power, isRepeat: true))
        #expect(router.handle(.power, isRepeat: true))
        #expect(recorder.powerPresses == 1)
        #expect(router.handle(.powerMenu, isRepeat: true))
        #expect(router.powerMenu == nil)
        #expect(router.handle(.powerMenu))
        #expect(router.powerMenu != nil)
        // Repeats in the open menu are the menu's (a held Down still moves).
        _ = router.handle(.down, isRepeat: true)
        #expect(router.powerMenu?.focusedItem.action == .sleepMac)
    }

    /// Security S4: the menu over the quit PIN; Relaunch asks for its own PIN, a wrong one doesn't relaunch.
    @Test func relaunchOverTheQuitPIN() {
        let (router, recorder) = makeRouter(pin: "1357")
        var quits = 0
        router.onQuit = { quits += 1 }
        router.requestQuit()
        #expect(router.screen == .pin(.quit))
        choose(.relaunch, router)
        #expect(router.screen == .pin(.relaunch))
        #expect(recorder.actions.isEmpty)
        enterPIN("2468", router)
        #expect(recorder.actions.isEmpty)
        #expect(router.screen == .pin(.relaunch))
        enterPIN("1357", router)
        #expect(recorder.actions == [.relaunch])
        #expect(quits == 0)
    }

    /// U1 and the Exit to Desktop re-review: why the menu closed. An item is reported after it ran (Relaunch's PIN
    /// screen is up by then).
    @Test func closeReasons() {
        let (router, _) = makeRouter(pin: "1357")
        var closes: [PowerMenuCloseReason] = []
        var screensAtClose: [AppRouter.Screen] = []
        router.onPowerMenuClose = {
            closes.append($0)
            screensAtClose.append(router.screen)
        }
        choose(.cancel, router)
        _ = router.handle(.powerMenu)
        _ = router.handle(.back)
        _ = router.handle(.powerMenu)
        _ = router.handle(.menu)
        #expect(closes == [.cancelled, .cancelled, .cancelled])
        closes = []
        choose(.turnOff, router)
        _ = router.handle(.powerMenu)
        _ = router.handle(.home)
        _ = router.handle(.powerMenu)
        _ = router.handle(.power)
        _ = router.handle(.powerMenu)
        router.openLiveTV()
        router.goHome()
        #expect(closes == [.other, .home, .other, .other])
        closes = []
        screensAtClose = []
        router.openLiveTV()
        choose(.relaunch, router)
        #expect(closes == [.other])
        #expect(screensAtClose == [.pin(.relaunch)])
    }

    /// Like Quit: the PIN screen can't sit over Live TV, so it goes home first; cancelling stays home.
    @Test func relaunchPINOverLiveTVGoesHomeFirst() {
        let (router, recorder) = makeRouter(pin: "1357")
        router.openLiveTV()
        choose(.relaunch, router)
        #expect(liveTV.leaves == 1)
        #expect(router.screen == .pin(.relaunch))
        enterPIN("1357", router)
        #expect(recorder.actions == [.relaunch])
        #expect(router.screen == .home)
    }
}

/// M7m L5–L11 (D50): the home tile menu in the router. Fakes only: nothing real is quit or opened.
struct AppRouterTileMenuTests {
    private let fake = FakeLauncherWorkspace()
    private let youtube = FakeYouTube()
    private let toasts = Toasts()

    final class Toasts {
        var shown: [String] = []
    }

    private func makeRouter(items: [LaunchItem] = LaunchItem.defaults, pin: String? = nil,
                            topShelf: any TopShelfProviding = NoTopShelf(),
                            workspace: LauncherWorkspace? = nil) -> (AppRouter, SettingsRecorder) {
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(workspace: workspace ?? fake.workspace),
                               settings: settings,
                               youtube: youtube, liveTV: FakeLiveTV(), pinStore: .inMemory(pin),
                               tileArt: makeTestTileArt(), topShelf: topShelf)
        let toasts = toasts
        router.showToast = { text, _ in toasts.shown.append(text) }
        return (router, recorder)
    }

    private func enterPIN(_ code: String, _ router: AppRouter) {
        for command in pinCommands(for: code, startRow: router.pinEntry?.pad.row ?? 0) {
            _ = router.handle(command)
        }
    }

    /// Focuses a first-row tile by pressing Left/Right.
    private func focus(_ id: String, _ router: AppRouter) {
        let target = router.visibleItems.firstIndex { $0.id == id }!
        #expect(target < Theme.tilesPerRow)
        while let index = router.focus.index, index != target {
            _ = router.handle(index < target ? .right : .left)
        }
    }

    /// Opens the focused tile's menu and selects `action`.
    private func choose(_ action: TileMenuAction, on id: String, _ router: AppRouter) {
        focus(id, router)
        #expect(router.handle(.menu))
        let index = try! #require(router.tileMenu?.items.firstIndex { $0.action == action })
        for _ in 0..<index { _ = router.handle(.down) }
        #expect(router.tileMenu?.focusedItem.action == action)
        #expect(router.handle(.select))
        #expect(router.tileMenu == nil)
    }

    private func item(_ id: String, in items: [LaunchItem]?) -> LaunchItem? {
        items?.first { $0.id == id }
    }

    @Test func menuOnATileOpensItsMenu() {
        let (router, _) = makeRouter()
        #expect(router.focusedItem?.id == "plex")
        #expect(router.handle(.menu))
        let menu = try! #require(router.tileMenu)
        #expect(menu.tileID == "plex")
        #expect(menu.items.map(\.action) == [.move, .hide, .startHere, .toggleFullScreen, .toggleRequiresPIN,
                                             .tileSettings])
        #expect(menu.items.first { $0.action == .startHere }?.value == "On")
        #expect(router.isStillScreen)
        // Commands go to the menu, not to the tiles.
        #expect(router.handle(.down))
        #expect(router.tileMenu?.focusedIndex == 1)
        #expect(router.handle(.right))
        #expect(router.focus.index == 0)
        #expect(router.handle(.back))
        #expect(router.tileMenu == nil)
        #expect(router.screen == .home)

        // Plex running: Quit and Restart.
        fake.start("tv.plex.htpc")
        #expect(router.handle(.menu))
        #expect(router.tileMenu?.items.map(\.title).prefix(3) == ["Move", "Quit Plex", "Restart Plex"])
        // Menu closes it again; a held Menu key's repeat doesn't.
        #expect(router.handle(.menu, isRepeat: true))
        #expect(router.tileMenu != nil)
        #expect(router.handle(.menu))
        #expect(router.tileMenu == nil)
    }

    @Test func menuInTheShelfDoesNothing() {
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Continue Watching", [
            ShelfCard(id: "a", title: "a", subtitle: "", image: .channelLogo(nil), progress: nil,
                      action: .openTile(id: "plex")),
        ])
        let (router, _) = makeRouter(topShelf: shelf)
        #expect(router.handle(.up))
        #expect(router.shelfIndex == 0)
        #expect(!router.handle(.menu))
        #expect(router.tileMenu == nil)
    }

    @Test func withAPINHideAsksFirstThenHides() {
        let (router, recorder) = makeRouter(pin: "1357")
        focus("youtube", router)
        #expect(router.handle(.menu))
        #expect(router.tileMenuShowsPINLock)
        #expect(router.handle(.back))

        // Cancelling the PIN changes nothing.
        choose(.hide, on: "youtube", router)
        #expect(router.screen == .pin(.tileAction(id: "youtube", action: .hide)))
        #expect(router.pinEntry?.title == "Enter PIN to change this tile")
        #expect(recorder.appliedItems.isEmpty)
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        #expect(recorder.appliedItems.isEmpty)
        #expect(toasts.shown.isEmpty)

        choose(.hide, on: "youtube", router)
        enterPIN("1357", router)
        #expect(router.screen == .home)
        #expect(item("youtube", in: recorder.appliedItems.last)?.isVisible == false)
        #expect(toasts.shown == ["Hidden · Settings → Home Screen shows it again"])
    }

    @Test func withAPINQuitDoesntAsk() async {
        let (router, _) = makeRouter(pin: "1357")
        fake.start("tv.plex.htpc")
        choose(.quit, on: "plex", router)
        #expect(router.screen == .home)
        await router.tileMenuTask?.value
        #expect(fake.events == ["terminate 100001"])
        #expect(!router.launcher.isRunning(router.visibleItems[0]))
    }

    @Test func withoutAPINEditsRunAtOnce() {
        let (router, recorder) = makeRouter()
        choose(.toggleRequiresPIN, on: "youtube", router)
        #expect(router.screen == .home)
        #expect(item("youtube", in: recorder.appliedItems.last)?.requiresPIN == true)

        choose(.startHere, on: "youtube", router)
        #expect(router.screen == .home)
        #expect(recorder.appliedSettings.last?.homeStartTile == "youtube")

        choose(.toggleFullScreen, on: "plex", router)
        #expect(router.screen == .home)
        #expect(item("plex", in: recorder.appliedItems.last)?.launchFullScreen == true)

        choose(.tileSettings, on: "plex", router)
        #expect(router.screen == .settings)
        #expect(router.settings.page == .tile(id: "plex"))
    }

    @Test func tileSettingsOpensSettingsAtTheTileWithOnePIN() {
        let (router, _) = makeRouter(pin: "1357")
        choose(.tileSettings, on: "youtube", router)
        #expect(router.screen == .pin(.tileAction(id: "youtube", action: .tileSettings)))
        #expect(router.pinEntry?.title == "Enter PIN to open Settings")
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(router.settings.stack.map(\.page) == [.root, .homeScreen, .tile(id: "youtube")])
        #expect(router.settings.stack[0].focusedRowID == "homeScreen")
        #expect(router.settings.stack[1].focusedRowID == SettingsModel.tileRowID("youtube"))
        // Back walks out through Home Screen, on the tile's row.
        #expect(router.handle(.back))
        #expect(router.settings.page == .homeScreen)
        #expect(router.settings.stack.last?.focusedRowID == SettingsModel.tileRowID("youtube"))
    }

    @Test func restartQuitsThenOpensLikeSelect() async throws {
        // A protected Plex: Restart doesn't ask, the reopen does.
        var items = LaunchItem.defaults
        items[0].requiresPIN = true
        let (router, _) = makeRouter(items: items, pin: "1357")
        fake.start("tv.plex.htpc")
        choose(.restart, on: "plex", router)
        #expect(router.screen == .home)
        await router.tileMenuTask?.value
        #expect(fake.events == ["terminate 100001"])
        #expect(router.screen == .pin(.openTile(id: "plex")))
        enterPIN("1357", router)
        for _ in 0..<200 where fake.events.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
    }

    @Test func restartOfAnUnprotectedTileOpensItAgain() async throws {
        let (router, _) = makeRouter()
        fake.start("tv.plex.htpc")
        choose(.restart, on: "plex", router)
        await router.tileMenuTask?.value
        for _ in 0..<200 where fake.events.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
    }

    @Test func reloadYouTubeReloadsThenOpens() {
        let (router, _) = makeRouter()
        youtube.hasOpened = true
        choose(.reloadYouTube, on: "youtube", router)
        #expect(youtube.reloads == 1)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func homeClosesTheTileMenuAndGoesHome() {
        let (router, _) = makeRouter()
        focus("youtube", router)
        #expect(router.handle(.menu))
        #expect(router.handle(.home))
        #expect(router.tileMenu == nil)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "plex")
    }

    @Test func aScreenChangeClosesTheTileMenu() {
        let (router, _) = makeRouter()
        #expect(router.handle(.menu))
        router.castYouTube(query: nil)
        #expect(router.tileMenu == nil)
        #expect(router.screen == .youtube)
    }

    /// A fake whose Plex ignores the quit request until the test sets `isTerminated`; the restart's polls wait in real
    /// time meanwhile.
    private func slowQuittingPlex() -> (FakeRunningApp, LauncherWorkspace) {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        let base = fake.workspace
        let workspace = LauncherWorkspace(appURL: base.appURL, runningApps: base.runningApps,
                                          openApplication: base.openApplication) { duration in
            await base.sleep(duration)
            try? await Task.sleep(for: .milliseconds(5))
        }
        return (old, workspace)
    }

    /// Prime without full screen, so its fake open never asks Accessibility for a window.
    private var itemsWithPlainPrime: [LaunchItem] {
        var items = LaunchItem.defaults
        items[3].launchFullScreen = false
        return items
    }

    /// QA step 9: another app opened while Restart waited for Plex to quit; Plex isn't reopened over it.
    @Test func restartDoesntReopenAfterAnotherAppOpened() async throws {
        let (old, workspace) = slowQuittingPlex()
        let (router, _) = makeRouter(items: itemsWithPlainPrime, workspace: workspace)
        choose(.restart, on: "plex", router)
        for _ in 0..<200 where fake.sleeps.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fake.events == ["terminate 100001"])

        focus("prime", router)
        #expect(router.handle(.select))
        for _ in 0..<200 where fake.events.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fake.events == ["terminate 100001", "open com.amazon.aiv.AIVApp 100002"])
        router.isAppActive = false   // Prime took the screen (AppDelegate's didResignActive)

        old.isTerminated = true
        await router.tileMenuTask?.value
        try await Task.sleep(for: .milliseconds(20))
        #expect(fake.events == ["terminate 100001", "open com.amazon.aiv.AIVApp 100002"])
    }

    /// QA step 9: another tile's home exit animation runs when Plex has quit; Plex isn't reopened.
    @Test func restartDoesntReopenWhileAnotherTileIsOpening() async throws {
        let (old, workspace) = slowQuittingPlex()
        let liveTV = FakeLiveTV()
        let (settings, _) = makeSettingsModel()
        let router = AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(workspace: workspace),
                               settings: settings, youtube: youtube, liveTV: liveTV, pinStore: .inMemory(),
                               tileArt: makeTestTileArt())
        router.homeExitDelay = .seconds(3600)
        choose(.restart, on: "plex", router)
        for _ in 0..<200 where fake.sleeps.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        focus("iptv", router)
        #expect(router.handle(.select))
        #expect(router.isLeavingHome)

        old.isTerminated = true
        await router.tileMenuTask?.value
        try await Task.sleep(for: .milliseconds(20))
        #expect(fake.events == ["terminate 100001"])
        #expect(router.isLeavingHome)
        router.goHome()
    }

    /// Security hardening: MMTVL's own app on a tile never offers Quit or Restart.
    @Test func mmtvlsOwnTileHasNoQuit() {
        let own = try! #require(Bundle.main.bundleIdentifier)
        var items = LaunchItem.defaults
        items[0] = LaunchItem(id: "self", title: "MMTVL", kind: .application(bundleID: own))
        let (router, _) = makeRouter(items: items)
        fake.start(own)
        #expect(router.launcher.isRunning(items[0]))
        #expect(router.handle(.menu))
        #expect(router.tileMenu?.tileID == "self")
        #expect(router.tileMenu?.items.contains { $0.action == .quit || $0.action == .restart } == false)
    }

    // MARK: PIN gate (security review, step 9)

    @Test func cancelledEditIsNeverAppliedByALaterPIN() {
        let (router, recorder) = makeRouter(pin: "1357")
        choose(.toggleRequiresPIN, on: "youtube", router)
        #expect(router.screen == .pin(.tileAction(id: "youtube", action: .toggleRequiresPIN)))
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        #expect(recorder.appliedItems.isEmpty)

        // Another purpose, verified: Settings opens, the cancelled edit stays undone.
        router.requestPIN(.openSettings)
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(recorder.appliedItems.isEmpty)
        #expect(recorder.appliedSettings.isEmpty)
    }

    @Test func wrongPINChangesNothingAndCountsTowardTheLockout() {
        let (router, recorder) = makeRouter(pin: "1357")
        choose(.toggleRequiresPIN, on: "youtube", router)
        enterPIN("2468", router)
        #expect(router.screen == .pin(.tileAction(id: "youtube", action: .toggleRequiresPIN)))
        #expect(router.pinEntry?.lockout.failures == 1)
        #expect(router.pinEntry?.message == "Wrong PIN")
        #expect(recorder.appliedItems.isEmpty)
    }

    @Test func clickingAnEditRowAsksForThePIN() {
        let (router, recorder) = makeRouter(pin: "1357")
        focus("youtube", router)
        #expect(router.handle(.menu))
        let index = try! #require(router.tileMenu?.items.firstIndex { $0.action == .toggleRequiresPIN })
        router.chooseTileMenuItem(index)
        #expect(router.tileMenu == nil)
        #expect(router.screen == .pin(.tileAction(id: "youtube", action: .toggleRequiresPIN)))
        #expect(recorder.appliedItems.isEmpty)
    }

    @Test func reloadOfAProtectedYouTubeAsksWhenItOpens() {
        var items = LaunchItem.defaults
        items[1].requiresPIN = true
        let (router, _) = makeRouter(items: items, pin: "1357")
        youtube.hasOpened = true
        choose(.reloadYouTube, on: "youtube", router)
        #expect(youtube.reloads == 1)
        #expect(youtube.opens == 0)
        #expect(router.screen == .pin(.openTile(id: "youtube")))
    }

    @Test func hidingTheStartTileFallsBackToTheFirst() {
        let (router, recorder) = makeRouter()
        #expect(router.startTileID == "plex")
        choose(.hide, on: "plex", router)
        // AppDelegate's `applyItems` gives the router the new tiles.
        router.setItems(try! #require(recorder.appliedItems.last))
        #expect(router.focusedItem?.id == "youtube")
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.handle(.home))
        #expect(router.focus.index == 0)
        #expect(router.focusedItem?.id == "youtube")
    }
}

/// M7m L8: move mode on the home screen (the tile menu's Move).
struct AppRouterMoveTests {
    private let fake = FakeLauncherWorkspace()

    /// t0 … t8 with a hidden tile "h" after t1: rows [t0 … t5] and [t6, t7, t8].
    private static let tiles: [LaunchItem] = {
        var items = (0..<9).map {
            LaunchItem(id: "t\($0)", title: "T\($0)", kind: .application(bundleID: "com.example.t\($0)"))
        }
        items.insert(LaunchItem(id: "h", title: "H", kind: .application(bundleID: "com.example.h")), at: 2)
        return items.settingHidden(true, id: "h")
    }()

    private func makeRouter(pin: String? = nil, topShelf: any TopShelfProviding = NoTopShelf())
        -> (AppRouter, SettingsRecorder) {
        let (settings, recorder) = makeSettingsModel(items: Self.tiles)
        let router = AppRouter(items: Self.tiles, launcher: AppLauncher(workspace: fake.workspace),
                               settings: settings, youtube: FakeYouTube(), liveTV: FakeLiveTV(),
                               pinStore: .inMemory(pin), tileArt: makeTestTileArt(), topShelf: topShelf)
        return (router, recorder)
    }

    /// `handle`, then what AppDelegate's `applyItems` does with a saved edit: give the router the new tiles.
    @discardableResult
    private func press(_ command: RemoteCommand, _ router: AppRouter, _ recorder: SettingsRecorder,
                       isRepeat: Bool = false) -> Bool {
        let saved = recorder.appliedItems.count
        let consumed = router.handle(command, isRepeat: isRepeat)
        if recorder.appliedItems.count > saved, let items = recorder.appliedItems.last { router.setItems(items) }
        return consumed
    }

    /// Focuses `id`, opens its menu and chooses Move (the first item).
    private func startMoving(_ id: String, _ router: AppRouter) {
        router.focusStartTile(id: id)
        #expect(router.focusedItem?.id == id)
        #expect(router.handle(.menu))
        #expect(router.tileMenu?.focusedItem.action == .move)
        #expect(router.handle(.select))
        #expect(router.tileMenu == nil)
    }

    private func visibleIDs(_ router: AppRouter) -> [String] { router.visibleItems.map(\.id) }

    @Test func moveRightSwapsWithTheNeighbour() {
        let (router, recorder) = makeRouter()
        startMoving("t0", router)
        #expect(router.movingTileID == "t0")
        #expect(press(.right, router, recorder))
        #expect(visibleIDs(router) == ["t1", "t0", "t2", "t3", "t4", "t5", "t6", "t7", "t8"])
        // Saved at once; the hidden tile keeps its place between t1 and t2.
        #expect(recorder.appliedItems.last?.map(\.id) == ["t1", "h", "t0", "t2", "t3", "t4", "t5", "t6", "t7", "t8"])
        #expect(router.focusedItem?.id == "t0")
        #expect(router.focus.index == 1)
        #expect(router.movingTileID == "t0")
        // And back.
        #expect(press(.left, router, recorder))
        #expect(visibleIDs(router).prefix(2) == ["t0", "t1"])
        #expect(router.focusedItem?.id == "t0")
        #expect(router.isStillScreen)
    }

    @Test func moveDownJumpsARow() {
        let (router, recorder) = makeRouter()
        startMoving("t1", router)
        #expect(press(.down, router, recorder))
        #expect(visibleIDs(router) == ["t0", "t2", "t3", "t4", "t5", "t6", "t7", "t1", "t8"])
        #expect(router.focusedItem?.id == "t1")
        #expect(router.focus.position == LauncherFocusModel.Position(row: 1, column: 1))
        #expect(press(.up, router, recorder))
        #expect(visibleIDs(router).prefix(2) == ["t0", "t1"])
        #expect(router.focus.position == LauncherFocusModel.Position(row: 0, column: 1))
    }

    @Test func moveClampsAtTheEdges() {
        let (router, recorder) = makeRouter()
        startMoving("t0", router)
        // Left of the first place and Up from the first row: nothing moves or is saved.
        #expect(press(.left, router, recorder))
        #expect(press(.up, router, recorder))
        #expect(recorder.appliedItems.isEmpty)
        #expect(router.focusedItem?.id == "t0")
        _ = press(.select, router, recorder)

        // Down from the first row into the short last row: the last place.
        startMoving("t4", router)
        #expect(press(.down, router, recorder))
        #expect(visibleIDs(router).last == "t4")
        #expect(router.focus.index == 8)
        // Right of the last place and Down from the last row: nothing.
        let saved = recorder.appliedItems.count
        #expect(press(.right, router, recorder))
        #expect(press(.down, router, recorder))
        #expect(recorder.appliedItems.count == saved)
        #expect(router.focusedItem?.id == "t4")
        // Right from the end of a row goes on to the next row's first place.
        _ = press(.select, router, recorder)
        startMoving("t5", router)
        #expect(router.focus.index == 4)
        #expect(press(.right, router, recorder))
        #expect(router.focus.position == LauncherFocusModel.Position(row: 0, column: 5))
        #expect(press(.right, router, recorder))
        #expect(router.focus.position == LauncherFocusModel.Position(row: 1, column: 0))
        #expect(router.focusedItem?.id == "t5")
    }

    @Test func selectEndsMoveAndTheOrderIsSaved() {
        let (router, recorder) = makeRouter()
        startMoving("t0", router)
        _ = press(.right, router, recorder)
        _ = press(.right, router, recorder)
        // The Select that chose Move, held: its repeats don't end it.
        #expect(press(.select, router, recorder, isRepeat: true))
        #expect(router.movingTileID == "t0")
        #expect(press(.select, router, recorder))
        #expect(router.movingTileID == nil)
        // Nothing opened.
        #expect(router.screen == .home)
        #expect(fake.events.isEmpty)
        #expect(router.shakeTriggers.isEmpty)
        #expect(router.focusedItem?.id == "t0")
        #expect(recorder.appliedItems.last?.visible.map(\.id).prefix(3) == ["t1", "t2", "t0"])
        #expect(router.settings.items == recorder.appliedItems.last)
        // Arrows move focus again.
        #expect(press(.right, router, recorder))
        #expect(router.focusedItem?.id == "t3")
        #expect(recorder.appliedItems.count == 2)
    }

    @Test func backAndMenuEndMoveAndHomeGoesHome() {
        let (router, recorder) = makeRouter()
        startMoving("t2", router)
        #expect(press(.back, router, recorder))
        #expect(router.movingTileID == nil)
        // Back ended it and stayed on the tile (not the start tile).
        #expect(router.focusedItem?.id == "t2")

        startMoving("t2", router)
        #expect(press(.menu, router, recorder, isRepeat: true))
        #expect(router.movingTileID == "t2")
        #expect(press(.menu, router, recorder))
        #expect(router.movingTileID == nil)
        #expect(router.tileMenu == nil)

        startMoving("t2", router)
        _ = press(.right, router, recorder)
        #expect(press(.home, router, recorder))
        #expect(router.movingTileID == nil)
        #expect(router.screen == .home)
        // The start tile ("plex") isn't here: the first tile.
        #expect(router.focus.index == 0)

        // Any other screen ends it too.
        startMoving("t2", router)
        router.openSettings()
        #expect(router.movingTileID == nil)
        router.goHome()
        startMoving("t2", router)
        router.goHome()
        #expect(router.movingTileID == nil)
    }

    @Test func upInMoveModeDoesntEnterTheShelf() {
        let shelf = FakeTopShelf()
        shelf.contents["t0"] = .cards(title: "Continue Watching", [
            ShelfCard(id: "a", title: "a", subtitle: "", image: .channelLogo(nil), progress: nil,
                      action: .openTile(id: "t0")),
        ])
        let (router, recorder) = makeRouter(topShelf: shelf)
        startMoving("t6", router)
        #expect(press(.up, router, recorder))
        #expect(router.focus.index == 0)
        #expect(router.focusedItem?.id == "t6")
        #expect(press(.up, router, recorder))
        #expect(router.shelfIndex == nil)
        #expect(router.movingTileID == "t6")
        #expect(router.focusedItem?.id == "t6")
        // Once it ends, Up enters the shelf again (t0 is first again, with its cards).
        _ = press(.right, router, recorder)
        _ = press(.select, router, recorder)
        _ = press(.left, router, recorder)
        #expect(router.focusedItem?.id == "t0")
        #expect(press(.up, router, recorder))
        #expect(router.shelfIndex == 0)
    }

    @Test func aClickEndsMoveWithoutOpeningAndHoverDoesntMoveFocus() {
        let (router, recorder) = makeRouter()
        // The pointer counts as moved (nil never equals its location), so only move mode keeps hover out.
        router.pointerLocationAtLastCommand = nil
        router.hover(2)
        #expect(router.focusedItem?.id == "t2")
        startMoving("t0", router)
        router.pointerLocationAtLastCommand = nil
        router.hover(3)
        #expect(router.focusedItem?.id == "t0")
        #expect(router.movingTileID == "t0")
        router.activate(3)
        #expect(router.movingTileID == nil)
        #expect(router.screen == .home)
        #expect(fake.events.isEmpty)
        #expect(router.shakeTriggers.isEmpty)
        #expect(recorder.appliedItems.isEmpty)
    }

    @Test func aClickOnAShelfCardOnlyEndsMove() {
        let shelf = FakeTopShelf()
        shelf.contents["t0"] = .cards(title: "Continue Watching", [
            ShelfCard(id: "live", title: "live", subtitle: "", image: .channelLogo(nil), progress: nil,
                      action: .playChannel("id:nbatv.us")),
            ShelfCard(id: "tile", title: "tile", subtitle: "", image: .channelLogo(nil), progress: nil,
                      action: .openTile(id: "t1")),
        ])
        let (router, recorder) = makeRouter(topShelf: shelf)
        // The pointer counts as moved, so hovering a card would take focus if move mode let it.
        startMoving("t0", router)
        router.pointerLocationAtLastCommand = nil
        router.hoverShelfCard(1)
        #expect(router.shelfIndex == nil)
        for card in [0, 1] {
            if router.movingTileID == nil { startMoving("t0", router) }
            router.activateShelfCard(card)
            #expect(router.movingTileID == nil)
            #expect(!router.isLeavingHome)
            #expect(router.screen == .home)
            #expect(router.focusedItem?.id == "t0")
        }
        #expect(fake.events.isEmpty)
        #expect(router.shakeTriggers.isEmpty)
        #expect(recorder.appliedItems.isEmpty)
    }

    @Test func withAPINMoveAsksFirst() {
        let (router, recorder) = makeRouter(pin: "1357")
        startMoving("t0", router)
        #expect(router.screen == .pin(.tileAction(id: "t0", action: .move)))
        #expect(router.movingTileID == nil)
        for command in pinCommands(for: "1357", startRow: router.pinEntry?.pad.row ?? 0) {
            _ = router.handle(command)
        }
        #expect(router.screen == .home)
        #expect(router.movingTileID == "t0")
        #expect(press(.right, router, recorder))
        #expect(router.focusedItem?.id == "t0")
        #expect(router.focus.index == 1)
    }

    @Test func settingsSeesTheNewOrder() {
        let (router, recorder) = makeRouter()
        startMoving("t0", router)
        _ = press(.down, router, recorder)
        _ = press(.select, router, recorder)
        router.openSettings()
        router.settings.perform(.push(.homeScreen))
        let tileRows = router.settings.sections.first { $0.id == "tiles" }!.rows
        #expect(tileRows.map(\.id) == router.items.map { "tile.\($0.id)" })
        #expect(router.items.visible.map(\.id) == ["t1", "t2", "t3", "t4", "t5", "t6", "t0", "t7", "t8"])
    }
}
