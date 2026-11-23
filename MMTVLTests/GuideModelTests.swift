import Foundation
import Testing
@testable import MMTVL

struct GuideModelTests {
    private let now = GuideTimelineTests.utc(14, 47)

    private func channel(_ n: Int, group: String) -> Channel {
        Channel(id: "id:c\(n)", number: n, name: "Channel \(n)", group: group, tvgID: "c\(n)", tvgName: nil,
                logoURL: nil, streamURL: URL(string: "https://cdn/\(n).m3u8")!)
    }

    /// 10 channels: 1–6 "Live", 7–8 "NBA", 9–10 "NHL".
    private var channels: [Channel] {
        (1...10).map { channel($0, group: $0 <= 6 ? "Live" : ($0 <= 8 ? "NBA" : "NHL")) }
    }

    private func programme(_ channelID: String, _ startHour: Int, _ startMinute: Int, minutes: Int, _ title: String) -> Programme {
        let start = GuideTimelineTests.utc(startHour, startMinute)
        return Programme(channelID: channelID, start: start, stop: start + Double(minutes * 60), title: title)
    }

    /// Row 0 (c1): 14:00–15:00 A, 15:00–16:00 B, 16:00–17:30 C, 17:30–19:00 D.
    /// Row 1 (c2): 14:30–15:30 E, 15:30–16:30 F.
    private var programmes: [Channel.ID: [Programme]] {
        [
            "id:c1": [programme("c1", 14, 0, minutes: 60, "A"), programme("c1", 15, 0, minutes: 60, "B"),
                      programme("c1", 16, 0, minutes: 90, "C"), programme("c1", 17, 30, minutes: 90, "D")],
            "id:c2": [programme("c2", 14, 30, minutes: 60, "E"), programme("c2", 15, 30, minutes: 60, "F")],
        ]
    }

    private func model(group: String? = "Live", focused: Channel.ID? = nil) -> GuideModel {
        var model = GuideModel(allChannels: channels, group: group, focusedChannelID: focused, now: now)
        model.programmes = programmes
        return model
    }

    @Test func initFocusesTheChannelInTheRememberedGroup() {
        let model = model(group: "Live", focused: "id:c3")
        #expect(model.groups == ["Favorites", "My Teams", "All Channels", "Live", "NBA", "NHL"])
        #expect(model.selectedGroup == "Live")
        #expect(model.row == 2)
        #expect(model.focusedChannel?.id == "id:c3")
        #expect(model.focus == .grid)
        #expect(model.focusTime == now)
    }

    @Test func initFallsBackToAllChannels() {
        let model = model(group: "NBA", focused: "id:c10")
        #expect(model.selectedGroup == "All Channels")
        #expect(model.row == 9)
        #expect(model.firstVisibleRow + GuideModel.visibleRows > model.row)
    }

    @Test func favoritesAreTheDefaultGroup() {
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c9", "id:c2"]))
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: "id:c2", now: now)
        #expect(model.groups == ["Favorites", "My Teams", "All Channels", "Live", "NBA", "NHL"])
        #expect(model.selectedGroup == "Favorites")
        #expect(model.channels.map(\.id) == ["id:c9", "id:c2"])
        #expect(model.row == 1)
    }

    @Test func focusedChannelOutsideFavoritesOpensAllChannels() {
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c9"]))
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: "id:c4", now: now)
        #expect(model.selectedGroup == "All Channels")
        #expect(model.focusedChannel?.id == "id:c4")

        // With one visible group there is no All Channels: its own group.
        let oneGroup = ChannelLineup(channels: channels,
                                     preferences: ChannelPreferences(favorites: ["id:c1"], hiddenGroups: ["NBA", "NHL"]))
        let other = GuideModel(lineup: oneGroup, group: nil, focusedChannelID: "id:c4", now: now)
        #expect(other.groups == ["Favorites", "My Teams", "Live"])
        #expect(other.selectedGroup == "Live")
        #expect(other.focusedChannel?.id == "id:c4")
    }

    @Test func setLineupThatDropsTheFocusedChannelKeepsTheRow() {
        var last = model(group: "Live", focused: "id:c6")
        #expect(last.row == 5)
        last.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: ["id:c6"])))
        #expect(last.selectedGroup == "Live")
        #expect(last.row == 4)
        #expect(last.focusedChannel?.id == "id:c5")

        var middle = model(group: "Live", focused: "id:c3")
        middle.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: ["id:c3"])))
        #expect(middle.row == 2)
        #expect(middle.focusedChannel?.id == "id:c4")
    }

    /// M7n L3: Down on the last row goes to the top, Up on the first to the bottom, and the window follows.
    @Test func upDownLoopAndScroll() {
        var model = model(group: "All Channels")
        for _ in 0..<7 { _ = model.handle(.down, now: now) }
        #expect(model.row == 7)
        #expect(model.firstVisibleRow == 2)
        for _ in 0..<2 { _ = model.handle(.down, now: now) }
        #expect(model.row == 9)
        #expect(model.firstVisibleRow == 4)
        #expect(model.wrapCount == 0)
        _ = model.handle(.down, now: now)
        #expect(model.row == 0)
        #expect(model.firstVisibleRow == 0)
        #expect(model.wrapCount == 1)   // the view puts the rows in place, no slide
        _ = model.handle(.up, now: now)
        #expect(model.row == 9)
        #expect(model.firstVisibleRow == model.rows.count - GuideModel.visibleRows)
        #expect(model.wrapCount == 2)
        for _ in 0..<7 { _ = model.handle(.up, now: now) }
        #expect(model.row == 2)
        #expect(model.firstVisibleRow == 2)
        _ = model.handle(.up, now: now)
        #expect(model.firstVisibleRow == 1)
    }

    /// M7n L3: from the channel cell too, and in a list shorter than the window (no scrolling).
    @Test func theChannelCellAndShortListsLoop() {
        var model = model(group: "Live", focused: "id:c6")
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        #expect(model.focus == .channel)
        _ = model.handle(.down, now: now)
        #expect(model.focusedChannel?.id == "id:c1")
        #expect(model.focus == .channel)
        _ = model.handle(.up, now: now)
        #expect(model.focusedChannel?.id == "id:c6")
        #expect(model.firstVisibleRow == 0)

        var nba = GuideModel(allChannels: channels, group: "NBA", focusedChannelID: nil, now: now)
        _ = nba.handle(.down, now: now)
        _ = nba.handle(.down, now: now)
        #expect(nba.focusedChannel?.id == "id:c7")
        #expect(nba.firstVisibleRow == 0)
    }

    /// M7n L3: a list of one row doesn't move, whatever is pressed.
    @Test func aOneRowListStays() {
        let solo = channels + [channel(11, group: "Solo")]
        var model = GuideModel(allChannels: solo, group: "Solo", focusedChannelID: nil, now: now)
        #expect(model.rows.count == 1)
        for command in [RemoteCommand.down, .up, .channelDown, .channelUp] {
            _ = model.handle(command, now: now)
            #expect(model.row == 0)
            #expect(model.firstVisibleRow == 0)
        }

        var empty = GuideModel(lineup: ChannelLineup(channels: channels), group: "My Teams", focusedChannelID: nil,
                               now: now)
        #expect(empty.rows == [.chooseTeams])
        for command in [RemoteCommand.down, .up, .channelDown, .channelUp] {
            _ = empty.handle(command, now: now)
            #expect(empty.focusedRow == .chooseTeams)
        }
    }

    @Test func rightWalksProgrammesAndMovesTheWindow() {
        var model = model()
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "B")
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(14, 30))
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "C")
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(16, 0))
        _ = model.handle(.fastForward, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "D")
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "D")

        _ = model.handle(.left, now: now)
        _ = model.handle(.rewind, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
        #expect(model.focusTime == now)
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(14, 30))
        #expect(model.focus == .grid)

        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
    }

    @Test func groups() {
        var model = model()
        _ = model.handle(.down, now: now)
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(4))
        #expect(model.handle(.select, now: now) == .groupChanged("NBA"))
        #expect(model.focus == .grid)
        #expect(model.row == 0)
        #expect(model.channels.map(\.id) == ["id:c7", "id:c8"])

        // Back in groups → grid, no change.
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        _ = model.handle(.up, now: now)
        #expect(model.handle(.back, now: now) == .none)
        #expect(model.focus == .grid)
        #expect(model.selectedGroup == "NBA")

        // Right applies too; Up from the first group is the Search row (M7f L12), Down from it the first group
        // (Favorites, listed even when empty), then My Teams (M7l 8c), then All Channels.
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        for _ in 0..<5 { _ = model.handle(.up, now: now) }
        #expect(model.focus == .search)
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(0))
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(1))
        _ = model.handle(.down, now: now)
        #expect(model.handle(.right, now: now) == .groupChanged("All Channels"))
        #expect(model.channels.count == 10)
    }

    @Test func rowWithoutProgrammesHasOnePlaceholder() {
        var model = model()
        for _ in 0..<2 { _ = model.handle(.down, now: now) }
        let cells = model.cells(row: 2, now: now)
        #expect(cells.count == 1)
        #expect(cells.first?.programme == nil)
        #expect(cells.first?.start == now)
        #expect(cells.first?.stop == now + GuideTimeline.horizon)
        let before = model
        _ = model.handle(.right, now: now)
        #expect(model == before)
    }

    @Test func selectPlaysAndBackCloses() {
        var model = model()
        _ = model.handle(.down, now: now)
        #expect(model.handle(.select, now: now) == .play("id:c2"))
        #expect(model.handle(.back, now: now) == .close)
        #expect(model.handle(.playPause, now: now) == .none)
    }

    @Test func upDownKeepFocusTime() {
        var model = model()
        _ = model.handle(.right, now: now)                    // B, 15:00
        #expect(model.focusTime == GuideTimelineTests.utc(15, 0))
        _ = model.handle(.down, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "E")   // 14:30–15:30 covers 15:00
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "F")
        _ = model.handle(.up, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "B")   // 15:00–16:00 covers 15:30
    }

    @Test func programmesThatEndedAreNotCells() {
        var model = model()
        model.programmes["id:c1"]?.insert(programme("c1", 13, 0, minutes: 60, "Over"), at: 0)
        #expect(model.cells(row: 0, now: now).first?.programme?.title == "A")
    }

    @Test func setChannelsKeepsGroupAndRow() {
        var model = model(group: "Live", focused: "id:c4")
        let refreshed = channels.filter { $0.id != "id:c2" }
        model.setChannels(allChannels: refreshed)
        #expect(model.selectedGroup == "Live")
        #expect(model.focusedChannel?.id == "id:c4")
        #expect(model.row == 2)
    }

    // MARK: Channel cell (M6 L8)

    @Test func leftAtNowFocusesTheChannelThenTheGroups() {
        var model = model()
        #expect(model.handle(.left, now: now) == .none)
        #expect(model.focus == .channel)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
    }

    @Test func rightFromTheChannelReturnsToTheSameCell() {
        var model = model()
        _ = model.handle(.right, now: now)
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .channel)
        let time = model.focusTime
        _ = model.handle(.right, now: now)
        #expect(model.focus == .grid)
        #expect(model.focusTime == time)
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
    }

    @Test func upDownOnTheChannelMoveRows() {
        var model = model()
        _ = model.handle(.left, now: now)
        _ = model.handle(.down, now: now)
        _ = model.handle(.down, now: now)
        #expect(model.row == 2)
        #expect(model.focus == .channel)
        _ = model.handle(.up, now: now)
        #expect(model.row == 1)
        #expect(model.focus == .channel)
    }

    @Test func selectOnTheChannelOpensItsMenu() {
        var model = model()
        _ = model.handle(.down, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.handle(.select, now: now) == .channelMenu("id:c2"))
    }

    @Test func backOnTheChannelCloses() {
        var model = model()
        _ = model.handle(.left, now: now)
        #expect(model.handle(.back, now: now) == .close)
        #expect(model.handle(.playPause, now: now) == .none)
    }

    // MARK: M7 L5

    @Test func menuOpensTheChannelMenuFromTheGridAndTheChannelCell() {
        var model = model(group: "Live", focused: "id:c3")
        #expect(model.handle(.menu, now: now) == .channelMenu("id:c3"))
        model = self.model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)          // A → the channel cell
        #expect(model.focus == .channel)
        #expect(model.handle(.menu, now: now) == .channelMenu("id:c1"))
    }

    @Test func menuInTheGroupsColumnDoesNothing() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.handle(.menu, now: now) == .none)
    }

    @Test func channelUpDownPageTheRows() {
        var model = GuideModel(allChannels: channels, group: "All Channels", focusedChannelID: "id:c2", now: now)
        #expect(model.handle(.channelDown, now: now) == .none)
        #expect(model.focusedChannel?.id == "id:c8")
        #expect(model.firstVisibleRow == 2)
        _ = model.handle(.channelDown, now: now)
        #expect(model.focusedChannel?.id == "id:c10")
        _ = model.handle(.channelUp, now: now)
        #expect(model.focusedChannel?.id == "id:c4")
        _ = model.handle(.channelUp, now: now)
        #expect(model.focusedChannel?.id == "id:c1")
        #expect(model.firstVisibleRow == 0)
    }

    /// M7n L3: a page stops at the end row (it never skips past it unseen) and wraps only from that row.
    @Test func aPageClampsThenWrapsFromTheEndRow() {
        var model = GuideModel(allChannels: channels, group: "All Channels", focusedChannelID: "id:c6", now: now)
        _ = model.handle(.channelDown, now: now)
        #expect(model.row == 9)
        #expect(model.firstVisibleRow == 4)
        _ = model.handle(.channelDown, now: now)
        #expect(model.row == 0)
        #expect(model.firstVisibleRow == 0)
        _ = model.handle(.channelUp, now: now)
        #expect(model.row == 9)
        #expect(model.firstVisibleRow == 4)
        _ = model.handle(.channelUp, now: now)
        #expect(model.row == 3)
        _ = model.handle(.channelUp, now: now)
        #expect(model.row == 0)
        #expect(model.firstVisibleRow == 0)
        _ = model.handle(.channelUp, now: now)
        #expect(model.row == 9)

        // From the channel cell too.
        _ = model.handle(.left, now: now)
        #expect(model.focus == .channel)
        _ = model.handle(.channelDown, now: now)
        #expect(model.row == 0)
        #expect(model.focus == .channel)
    }

    @Test func channelUpDownPageTheGroups() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        guard case .groups = model.focus else {
            Issue.record("Not in the groups column")
            return
        }
        // A page stops at the last group or the Search row, and wraps only from it (as the channel list does).
        _ = model.handle(.channelDown, now: now)
        #expect(model.focus == .groups(model.groups.count - 1))
        _ = model.handle(.channelDown, now: now)
        #expect(model.focus == .search)
        _ = model.handle(.channelDown, now: now)
        #expect(model.focus == .groups(model.groups.count - 1))
        _ = model.handle(.channelUp, now: now)
        #expect(model.focus == .search)
        _ = model.handle(.channelUp, now: now)
        #expect(model.focus == .groups(model.groups.count - 1))
    }

    /// The group list loops: Down on the last group is the Search row, Up on the Search row the last group.
    @Test func theGroupListLoops() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
        _ = model.handle(.down, now: now)
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(5))   // NHL, the last
        let wraps = model.groupWrapCount
        _ = model.handle(.down, now: now)
        #expect(model.focus == .search)
        #expect(model.groupWrapCount == wraps + 1)
        _ = model.handle(.up, now: now)
        #expect(model.focus == .groups(5))
        #expect(model.groupWrapCount == wraps + 2)
        _ = model.handle(.up, now: now)   // an ordinary step isn't a loop
        #expect(model.focus == .groups(4))
        #expect(model.groupWrapCount == wraps + 2)
        // Nothing is selected by moving.
        #expect(model.selectedGroup == "Live")
    }

    /// With more groups than the panel shows, the window follows the focus and shows the end after a loop.
    @Test func theGroupPanelKeepsTheFocusedRowInView() {
        let channels = (1...12).map { channel($0, group: "Group \($0)") }
        var model = GuideModel(allChannels: channels, group: "Group 1", focusedChannelID: "id:c1", now: now)
        #expect(model.groups.count == 15)   // Favorites, My Teams, All Channels, Group 1…12; with Search, 16 rows
        #expect(model.firstVisibleGroupRow == 0)
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))   // row 4
        #expect(model.firstVisibleGroupRow == 0)
        for _ in 0..<3 { _ = model.handle(.down, now: now) }   // row 7, past the window's 7 rows
        #expect(model.groupPanelRow == 7)
        #expect(model.firstVisibleGroupRow == 1)
        _ = model.handle(.up, now: now)   // still in view: the window stays
        #expect(model.firstVisibleGroupRow == 1)
        // Up from Search loops to the last group, with the window at the end.
        for _ in 0..<6 { _ = model.handle(.up, now: now) }
        #expect(model.focus == .search)
        #expect(model.firstVisibleGroupRow == 0)
        _ = model.handle(.up, now: now)
        #expect(model.focus == .groups(14))
        #expect(model.firstVisibleGroupRow == 16 - GuideModel.visibleGroupRows)
        _ = model.handle(.down, now: now)
        #expect(model.focus == .search)
        #expect(model.firstVisibleGroupRow == 0)
        // Leaving and coming back keeps the selected group in view.
        _ = model.handle(.back, now: now)
        #expect(model.groupPanelRow == nil)
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
        #expect(model.firstVisibleGroupRow == 0)
    }

    /// The group panel's window is exactly `visibleGroupRows` rows (and their gaps) high.
    @Test func theGroupWindowFitsItsRows() {
        let pitch = Theme.guideRowHeight - 16 + Theme.settingsRowSpacing
        #expect(GuideView.groupWindowHeight == CGFloat(GuideModel.visibleGroupRows) * pitch - Theme.settingsRowSpacing)
    }

    // MARK: M7f L12

    @Test func theSearchRowOpensSearchAndKeepsTheGuide() {
        var model = model(group: "NBA", focused: "id:c8")
        _ = model.handle(.left, now: now)   // the channel cell
        _ = model.handle(.left, now: now)   // groups, on NBA
        #expect(model.focus == .groups(4))
        _ = model.handle(.up, now: now)
        _ = model.handle(.up, now: now)
        _ = model.handle(.up, now: now)   // My Teams (M7l 8c)
        _ = model.handle(.up, now: now)   // Favorites, listed with no favorites
        _ = model.handle(.up, now: now)
        #expect(model.focus == .search)
        // Up loops to the last group (M7n), Down comes back.
        #expect(model.handle(.up, now: now) == .none)
        #expect(model.focus == .groups(model.groups.count - 1))
        #expect(model.handle(.down, now: now) == .none)
        #expect(model.handle(.select, now: now) == .openSearch)
        // The guide keeps its group and row; focus stays on the Search row.
        #expect(model.focus == .search)
        #expect(model.selectedGroup == "NBA")
        #expect(model.focusedChannel?.id == "id:c8")
        #expect(model.handle(.right, now: now) == .openSearch)
        #expect(model.handle(.back, now: now) == .none)
        #expect(model.focus == .grid)
    }

    // MARK: M7l 8c: My Teams

    /// Up from the first group is Search again; Down from Search is the first group (no Choose Teams row there).
    @Test func searchAndTheFirstGroupAreNeighbours() {
        var model = model(group: "NBA", focused: "id:c8")
        _ = model.handle(.left, now: now)   // the channel cell
        _ = model.handle(.left, now: now)   // groups, on NBA
        for _ in 0..<4 { _ = model.handle(.up, now: now) }
        #expect(model.focus == .groups(0))
        #expect(model.groups.first == "Favorites")
        #expect(model.handle(.up, now: now) == .none)
        #expect(model.focus == .search)
        #expect(model.handle(.down, now: now) == .none)
        #expect(model.focus == .groups(0))
    }

    /// A lineup with c9 and c10 live team games, and two upcoming games (c2 at 18:00, c3 at 16:00, given late first).
    private var teamsLineup: ChannelLineup {
        let channels = channels
        let upcoming = [
            UpcomingTeamGame(channel: channels[2], programme: programme("c3", 16, 0, minutes: 180, "NFL Football")),
            UpcomingTeamGame(channel: channels[1], programme: programme("c2", 18, 0, minutes: 180, "NFL Football")),
        ]
        return ChannelLineup(channels: channels, teamChannelIDs: ["id:c9", "id:c10"], upcomingTeamGames: upcoming)
    }

    @Test func myTeamsShowsWithNoTeamsPickedAndIsNotTheDefault() {
        let lineup = ChannelLineup(channels: channels)
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live", "NBA", "NHL"])
        // No remembered group: All Channels, as before My Teams (and an empty Favorites is skipped).
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: nil, now: now)
        #expect(model.selectedGroup == "All Channels")
        // With favorites, My Teams comes right after them.
        let favorites = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c1"]))
        #expect(Array(favorites.groups.prefix(3)) == ["Favorites", "My Teams", "All Channels"])
        // Nothing picked: only Choose Teams.
        let empty = GuideModel(lineup: lineup, group: "My Teams", focusedChannelID: nil, now: now)
        #expect(empty.rows == [.chooseTeams])
        #expect(empty.channels.isEmpty)
    }

    @Test func myTeamsRowsAreChooseTeamsThenLiveThenUpcoming() {
        let model = GuideModel(lineup: teamsLineup, group: "My Teams", focusedChannelID: nil, now: now)
        #expect(model.rows.map(\.kind) == [.chooseTeams, .channel, .channel, .upcoming, .upcoming])
        #expect(model.rows.map { $0.channel?.id } == [nil, "id:c9", "id:c10", "id:c3", "id:c2"])
        // Only the live games are channel rows (programmes, zapping).
        #expect(model.channels.map(\.id) == ["id:c9", "id:c10"])
        #expect(model.cells(row: 0, now: now).isEmpty)
        #expect(model.cells(row: 3, now: now).isEmpty)
        #expect(model.cells(row: 1, now: now).count == 1)
        #expect(model.focusedRow == .chooseTeams)
        #expect(model.focusedChannel == nil)
    }

    @Test func selectOnChooseTeamsOpensThePickerAndKeepsTheRow() {
        var model = GuideModel(lineup: teamsLineup, group: "My Teams", focusedChannelID: nil, now: now)
        #expect(model.handle(.select, now: now) == .openTeamPicker)
        #expect(model.focus == .grid)
        #expect(model.focusedRow == .chooseTeams)
        // No channel menu, no programmes to the right; Left goes to the groups, on My Teams.
        #expect(model.handle(.menu, now: now) == .none)
        #expect(model.handle(.right, now: now) == .none)
        #expect(model.focusedRow == .chooseTeams)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(1))   // Favorites (the live games) is first
    }

    @Test func selectOnAnUpcomingGamePlaysItsChannel() {
        var model = GuideModel(lineup: teamsLineup, group: "My Teams", focusedChannelID: nil, now: now)
        for _ in 0..<3 { _ = model.handle(.down, now: now) }
        guard case .upcoming(let game) = model.focusedRow else {
            Issue.record("Not on an upcoming game")
            return
        }
        #expect(game.channel.id == "id:c3")
        #expect(model.focusedChannel?.id == "id:c3")
        #expect(model.handle(.menu, now: now) == .none)
        #expect(model.handle(.select, now: now) == .play("id:c3"))
        // From the channel cell of a live row, Down onto an upcoming row still selects the whole row.
        _ = model.handle(.up, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .channel)
        _ = model.handle(.down, now: now)
        #expect(model.handle(.select, now: now) == .play("id:c3"))
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(1))
    }

    /// M7n L3: My Teams' action rows loop too: Up on Choose Teams goes to the last upcoming game, Down back.
    @Test func myTeamsActionRowsLoop() {
        var model = GuideModel(lineup: teamsLineup, group: "My Teams", focusedChannelID: nil, now: now)
        #expect(model.focusedRow == .chooseTeams)
        _ = model.handle(.up, now: now)
        #expect(model.row == 4)
        #expect(model.focusedChannel?.id == "id:c2")
        if case .upcoming = model.focusedRow {} else { Issue.record("Not on the last upcoming game") }
        _ = model.handle(.down, now: now)
        #expect(model.focusedRow == .chooseTeams)
        // A page from Choose Teams stops at the last row, then wraps from it.
        _ = model.handle(.channelUp, now: now)
        #expect(model.row == 4)
        _ = model.handle(.channelDown, now: now)
        #expect(model.focusedRow == .chooseTeams)
    }

    /// M7n L4: the view draws a page above and two below the first row shown, keyed by the row ids.
    /// M7n L4 (QA minors 1 and 2): which moves slide, and what is drawn before `onChange` catches up.
    @Test func theGuideSlidesOnlyShortMovesInOneGroup() {
        typealias Position = GuideView.ScrollPosition
        let at = { (first: Int) in Position(group: "All Channels", first: first, wraps: 0) }
        #expect(GuideView.slides(from: at(4), to: at(5), reduceMotion: false))          // a row
        #expect(GuideView.slides(from: at(0), to: at(6), reduceMotion: false))          // a page
        #expect(!GuideView.slides(from: at(0), to: at(7), reduceMotion: false))         // a longer jump
        #expect(!GuideView.slides(from: at(4), to: Position(group: "All Channels", first: 0, wraps: 1),
                                  reduceMotion: false))                                 // a loop
        #expect(!GuideView.slides(from: at(4), to: Position(group: "Sports", first: 4, wraps: 0),
                                  reduceMotion: false))                                 // a new group
        #expect(!GuideView.slides(from: at(4), to: at(5), reduceMotion: true))          // Reduce Motion
        // Drawn: the old position while a slide is about to start; the new one at once otherwise.
        #expect(GuideView.drawnFirst(displayed: nil, current: at(3), reduceMotion: false) == 3)
        #expect(GuideView.drawnFirst(displayed: at(4), current: at(5), reduceMotion: false) == 4)
        #expect(GuideView.drawnFirst(displayed: at(90), current: at(44), reduceMotion: false) == 44)   // a shrink
        #expect(GuideView.drawnFirst(displayed: at(4), current: Position(group: "All Channels", first: 0, wraps: 1),
                                     reduceMotion: false) == 0)
    }

    @Test func theGuideDrawsABufferOfRowsAroundTheWindow() {
        let many = (1...40).map { channel($0, group: "Many") }
        let rows = GuideModel(allChannels: many, group: "Many", focusedChannelID: nil, now: now).rows
        #expect(GuideView.bufferedRows(rows, first: 0).map(\.index) == Array(0..<12))
        #expect(GuideView.bufferedRows(rows, first: 20).map(\.index) == Array(14..<32))
        #expect(GuideView.bufferedRows(rows, first: 34).map(\.index) == Array(28..<40))
        #expect(GuideView.bufferedRows(rows, first: 50).isEmpty)
        #expect(GuideView.bufferedRows(rows, first: 3).map(\.key) == rows[0..<15].map(\.id))
        #expect(GuideView.bufferedRows([], first: 0).isEmpty)
    }

    @Test func aRefreshKeepsTheFocusedUpcomingGame() {
        var model = GuideModel(lineup: teamsLineup, group: "My Teams", focusedChannelID: nil, now: now)
        for _ in 0..<4 { _ = model.handle(.down, now: now) }
        #expect(model.focusedChannel?.id == "id:c2")
        // The c10 game ends: the row moves up and stays focused.
        let channels = channels
        let upcoming = teamsLineup.upcomingTeamGames
        model.setLineup(ChannelLineup(channels: channels, teamChannelIDs: ["id:c9"], upcomingTeamGames: upcoming))
        #expect(model.row == 3)
        #expect(model.focusedChannel?.id == "id:c2")
        if case .upcoming = model.focusedRow {} else { Issue.record("Not on the upcoming game") }
    }

    /// QA minor from 8b: a group appearing above the focused group-list row keeps the same group focused.
    @Test func groupsAppearingAboveKeepTheFocusedGroup() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(3))
        #expect(model.groups[3] == "Live")
        // A game starts with no saved favorites: Favorites is already listed, so nothing moves.
        model.setLineup(ChannelLineup(channels: channels, teamChannelIDs: ["id:c9"]))
        #expect(model.groups.prefix(2) == ["Favorites", "My Teams"])
        #expect(model.focus == .groups(3))
        // A tuner appears: Antenna comes in above Live, and Live stays focused.
        model.setLineup(ChannelLineup(channels: channels + AntennaFixtures.liveChannels(firstNumber: 11)))
        #expect(model.groups[2] == "Antenna")
        #expect(model.focus == .groups(4))
        #expect(model.groups[4] == "Live")
        // And goes again.
        model.setLineup(ChannelLineup(channels: channels))
        #expect(model.focus == .groups(3))
        // A focused group that goes away: the same position, clamped.
        _ = model.handle(.down, now: now)
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(5))
        model.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenGroups: ["NHL"])))
        #expect(model.focus == .groups(4))
    }

    @Test func aRememberedTeamsGroupReadsAsMyTeams() {
        let model = GuideModel(lineup: teamsLineup, group: "Teams", focusedChannelID: nil, now: now)
        #expect(model.selectedGroup == "My Teams")
        #expect(teamsLineup.resolvedGroup("Teams") == "My Teams")
        #expect(teamsLineup.resolvedGroup("Live") == "Live")
        #expect(teamsLineup.resolvedGroup(nil) == nil)
        // A playlist group really named "Teams" stays itself.
        let named = ChannelLineup(channels: [channel(1, group: "Teams"), channel(2, group: "Live")])
        #expect(named.resolvedGroup("Teams") == "Teams")
    }

    @Test func focusOnALaterProgramme() {
        var model = model(group: "Live", focused: "id:c1")
        let later = GuideTimelineTests.utc(17, 30)
        // In the group: the row moves and the timeline shows the programme.
        let inGroup = model.focus(channelID: "id:c2", at: later, now: now)
        #expect(inGroup)
        #expect(model.selectedGroup == "Live")
        #expect(model.focusedChannel?.id == "id:c2")
        #expect(model.focus == .grid)
        #expect(model.focusTime == later)
        #expect(model.timeline.windowStart <= later && later < model.timeline.windowEnd)
        // Not in the group: All Channels.
        let inAllChannels = model.focus(channelID: "id:c10", at: later, now: now)
        #expect(inAllChannels)
        #expect(model.selectedGroup == "All Channels")
        #expect(model.focusedChannel?.id == "id:c10")
        #expect(model.firstVisibleRow + GuideModel.visibleRows > model.row)
        // A time before now focuses now; an unknown channel changes nothing.
        let beforeNow = model.focus(channelID: "id:c1", at: now - 3600, now: now)
        #expect(beforeNow)
        #expect(model.focusTime == now)
        let unknown = model.focus(channelID: "id:nope", at: later, now: now)
        #expect(!unknown)
        #expect(model.focusedChannel?.id == "id:c1")
    }

    // MARK: M7j L3: the Antenna group isn't the default

    @Test func defaultGroupSkipsAntenna() {
        let lineup = ChannelLineup(channels: channels + AntennaFixtures.liveChannels(firstNumber: 11))
        #expect(lineup.groups == ["Favorites", "My Teams", "Antenna", "All Channels", "Live", "NBA", "NHL"])
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: nil, now: now)
        #expect(model.selectedGroup == "All Channels")
        let favorites = ChannelLineup(channels: channels + AntennaFixtures.liveChannels(firstNumber: 11),
                                      preferences: ChannelPreferences(favorites: ["antenna:5.1"]))
        #expect(GuideModel(lineup: favorites, group: nil, focusedChannelID: nil, now: now).selectedGroup == "Favorites")
        // A remembered Antenna group still opens it.
        let remembered = GuideModel(lineup: lineup, group: "Antenna", focusedChannelID: nil, now: now)
        #expect(remembered.selectedGroup == "Antenna")
        #expect(remembered.channels.map(\.displayNumber) == ["2.1", "5.1", "11.1"])
    }

    @Test func antennaIsTheDefaultWhenItIsTheOnlyGroup() {
        let lineup = ChannelLineup(channels: AntennaFixtures.liveChannels())
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: nil, now: now)
        #expect(model.groups == ["Favorites", "My Teams", "Antenna"])
        #expect(model.selectedGroup == "Antenna")
        #expect(model.focusedChannel?.name == "WSB-HD")
    }

    // MARK: Favorites is always listed; empty, it has one row saying how to add one (2026-11-23)

    @Test func anEmptyFavoritesIsSkippedByDefaultButARememberedOneOpens() {
        let lineup = ChannelLineup(channels: channels)
        #expect(lineup.groups.first == "Favorites")
        // No remembered group: All Channels, as before Favorites was always listed.
        #expect(GuideModel(lineup: lineup, group: nil, focusedChannelID: nil, now: now).selectedGroup == "All Channels")
        // Antenna only: still Antenna.
        let antenna = ChannelLineup(channels: AntennaFixtures.liveChannels())
        #expect(GuideModel(lineup: antenna, group: nil, focusedChannelID: nil, now: now).selectedGroup == "Antenna")
        // A remembered Favorites opens it, empty.
        let remembered = GuideModel(lineup: lineup, group: "Favorites", focusedChannelID: nil, now: now)
        #expect(remembered.selectedGroup == "Favorites")
        #expect(remembered.rows == [.favoritesEmpty])
        // Live team games alone fill it, and then it's the default again.
        let games = ChannelLineup(channels: channels, teamChannelIDs: ["id:c9"])
        #expect(GuideModel(lineup: games, group: nil, focusedChannelID: nil, now: now).selectedGroup == "Favorites")
    }

    @Test func anEmptyFavoritesHasOnePlaceholderRow() {
        let model = GuideModel(lineup: ChannelLineup(channels: channels), group: "Favorites", focusedChannelID: nil,
                               now: now)
        #expect(model.rows == [.favoritesEmpty])
        #expect(model.rows.map(\.kind) == [.favoritesEmpty])
        #expect(model.rows.first?.id == "favoritesEmpty")
        #expect(model.rows.first?.channel == nil)
        #expect(model.focusedRow == .favoritesEmpty)
        #expect(model.focusedChannel == nil)
        #expect(model.channels.isEmpty)
        #expect(model.cells(row: 0, now: now).isEmpty)
        #expect(model.focusedCell(now: now) == nil)
        // With a favorite, the rows are the channels, as before.
        let favorites = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c2"]))
        let filled = GuideModel(lineup: favorites, group: "Favorites", focusedChannelID: nil, now: now)
        #expect(filled.rows.map(\.kind) == [.channel])
        #expect(filled.channels.map(\.id) == ["id:c2"])
    }

    @Test func thePlaceholderRowDoesNothingButMoveAndLeft() {
        var model = GuideModel(lineup: ChannelLineup(channels: channels), group: "Favorites", focusedChannelID: nil,
                               now: now)
        let start = model
        // OK, Menu and Play do nothing: no play, no channel menu, no team picker.
        for command: RemoteCommand in [.select, .menu, .playPause, .up, .down, .channelUp, .channelDown] {
            #expect(model.handle(command, now: now) == .none)
            #expect(model.focusedRow == .favoritesEmpty)
            #expect(model.row == 0)
        }
        #expect(model == start)
        // Right has no programmes to move to.
        #expect(model.handle(.right, now: now) == .none)
        #expect(model.focus == .grid)
        #expect(model.handle(.select, now: now) == .none)
        // Left opens the group list, on Favorites.
        #expect(model.handle(.left, now: now) == .none)
        #expect(model.focus == .groups(0))
        #expect(model.groups[0] == "Favorites")
        // Back closes the list, then (in the watch guide) closes the guide, as on any row.
        #expect(model.handle(.back, now: now) == .none)
        #expect(model.focus == .grid)
        #expect(model.handle(.back, now: now) == .close)
    }

    @Test func thePlaceholderGoesOnceAFavoriteIsAddedAndComesBackWhenItIsRemoved() {
        var model = GuideModel(lineup: ChannelLineup(channels: channels), group: "Favorites", focusedChannelID: nil,
                               now: now)
        #expect(model.rows == [.favoritesEmpty])
        model.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c4", "id:c2"])))
        #expect(model.selectedGroup == "Favorites")
        #expect(model.rows.map(\.kind) == [.channel, .channel])
        #expect(model.row == 0)
        #expect(model.focusedChannel?.id == "id:c4")
        #expect(model.handle(.select, now: now) == .play("id:c4"))
        // The last favorite removed: Favorites stays listed and selected, with the placeholder.
        model.setLineup(ChannelLineup(channels: channels))
        #expect(model.selectedGroup == "Favorites")
        #expect(model.rows == [.favoritesEmpty])
        #expect(model.row == 0)
        #expect(model.focusedChannel == nil)
    }
}
