import Foundation

/// Guide focus and navigation (M4 L9, L12; M6 L8 channel cell). Pure: `LiveTVModel` feeds it commands and programmes.
nonisolated struct GuideModel: Equatable, Sendable {
    static let visibleRows = 6
    /// The group panel's rows (Search, then the groups) that fit in it (`GuideView.groupWindowHeight`).
    static let visibleGroupRows = 7

    /// `.channel`: the channel cell of the focused row (M6 L8), between the grid and the groups.
    /// `.search` (M7f L12): the Search row above the groups. On a row that isn't a channel's (M7l 8c), `.grid` and
    /// `.channel` both mean the whole row.
    enum Focus: Equatable, Sendable { case grid, channel, groups(Int), search }
    enum Action: Equatable, Sendable {
        case none, play(Channel.ID), close, groupChanged(String), channelMenu(Channel.ID)
        /// M7f L12: Select on the Search row.
        case openSearch
        /// M7l L12, 8c: Select on My Teams' Choose Teams row.
        case openTeamPicker
    }
    /// One row of the selected group. M7l 8c: My Teams has Choose Teams first, then its live channels, then the
    /// upcoming games. An empty Favorites group (no favorites, no live team game) has one `favoritesEmpty` row that
    /// says how to add one.
    enum Row: Equatable, Sendable {
        case channel(Channel)
        case chooseTeams
        case upcoming(UpcomingTeamGame)
        case favoritesEmpty

        enum Kind: Equatable, Sendable { case channel, chooseTeams, upcoming, favoritesEmpty }

        var kind: Kind {
            switch self {
            case .channel: .channel
            case .chooseTeams: .chooseTeams
            case .upcoming: .upcoming
            case .favoritesEmpty: .favoritesEmpty
            }
        }

        /// What Select plays: the row's channel, or an upcoming game's.
        var channel: Channel? {
            switch self {
            case .channel(let channel): channel
            case .chooseTeams, .favoritesEmpty: nil
            case .upcoming(let game): game.channel
            }
        }

        /// Kept across lineup changes (`setLineup`).
        var id: String {
            switch self {
            case .channel(let channel): "channel.\(channel.id)"
            case .chooseTeams: "chooseTeams"
            case .favoritesEmpty: "favoritesEmpty"
            case .upcoming(let game): "upcoming.\(game.channel.id).\(game.programme.start.timeIntervalSinceReferenceDate)"
            }
        }
    }
    /// One focusable cell: a programme, or a placeholder spanning the window when a row has no data.
    struct Cell: Equatable, Sendable {
        var programme: Programme?
        var start: Date
        var stop: Date
    }

    private(set) var groups: [String]
    private(set) var groupIndex: Int
    /// The selected group's rows.
    private(set) var rows: [Row]
    /// Set by LiveTVModel after loading.
    var programmes: [Channel.ID: [Programme]] = [:]
    private(set) var focus: Focus = .grid {
        didSet { keepGroupVisible() }
    }
    private(set) var row = 0
    /// The time the focus aims at (≥ now).
    private(set) var focusTime: Date
    private(set) var firstVisibleRow = 0
    /// M7n L4: bumped each time `moveRow` loops past an end, so the view puts the rows in place instead of sliding.
    private(set) var wrapCount = 0
    /// The group panel's first row shown (0: Search, 1…: the groups), kept so the focused one is in view.
    private(set) var firstVisibleGroupRow = 0
    /// Bumped each time the group panel loops past an end, so the view puts its rows in place instead of sliding.
    private(set) var groupWrapCount = 0
    private(set) var timeline: GuideTimeline
    private var lineup: ChannelLineup

    /// The default group (no remembered one) is the first: Favorites when it has channels (M6b L11; listed even when
    /// empty, but then skipped). M7l 8c: never My Teams (always there), unless it's the only group. M7j L3: nor
    /// Antenna, unless it's the only other group.
    init(lineup: ChannelLineup, group: String?, focusedChannelID: Channel.ID?, now: Date) {
        self.lineup = lineup
        let groups = lineup.groups
        self.groups = groups
        groupIndex = lineup.resolvedGroup(group).flatMap { groups.firstIndex(of: $0) } ?? Self.defaultGroupIndex(lineup)
        rows = []
        focusTime = now
        timeline = GuideTimeline(now: now)
        rows = rowsOfSelectedGroup()
        if let focusedChannelID, Self.channelRowIndex(of: focusedChannelID, in: rows) == nil {
            // Show the focused channel: All Channels if there is one, else its own group.
            let channelGroup = lineup.visibleChannels.first { $0.id == focusedChannelID }?.group
            if let index = groups.firstIndex(of: ChannelList.allChannelsGroup)
                ?? channelGroup.flatMap({ groups.firstIndex(of: $0) }) {
                groupIndex = index
                rows = rowsOfSelectedGroup()
            }
        }
        row = focusedChannelID.flatMap { Self.channelRowIndex(of: $0, in: rows) } ?? 0
        firstVisibleRow = min(row, max(0, rows.count - Self.visibleRows))
    }

    var selectedGroup: String? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }

    /// The selected group's channel rows, in order (not Choose Teams or the upcoming games, M7l 8c).
    var channels: [Channel] {
        rows.compactMap { if case .channel(let channel) = $0 { channel } else { nil } }
    }

    var focusedRow: Row? { rows.indices.contains(row) ? rows[row] : nil }

    /// The focused row's channel: a channel row's, or an upcoming game's (M7l 8c); nil on Choose Teams.
    var focusedChannel: Channel? { focusedRow?.channel }

    /// Cells of `row` overlapping [now, now + horizon), sorted; one placeholder cell [now, now + horizon) when none.
    /// [] for a row that isn't a channel's (M7l 8c).
    func cells(row: Int, now: Date) -> [Cell] {
        let end = now + GuideTimeline.horizon
        guard rows.indices.contains(row), case .channel(let channel) = rows[row] else { return [] }
        let cells = (programmes[channel.id] ?? [])
            .filter { $0.start < end && $0.stop > now }
            .sorted { $0.start < $1.start }
            .map { Cell(programme: $0, start: $0.start, stop: $0.stop) }
        return cells.isEmpty ? [Cell(programme: nil, start: now, stop: end)] : cells
    }

    /// The cell containing focusTime, else the first after it, else the last.
    func focusedCell(now: Date) -> Cell? {
        let cells = cells(row: row, now: now)
        return focusedCellIndex(in: cells).map { cells[$0] }
    }

    mutating func handle(_ command: RemoteCommand, now: Date) -> Action {
        switch focus {
        case .grid, .channel:
            if let focusedRow, focusedRow.kind != .channel { return handleActionRow(command, focusedRow) }
            return focus == .grid ? handleGrid(command, now: now) : handleChannel(command)
        case .groups(let index): return handleGroups(command, index: index, now: now)
        case .search: return handleSearchRow(command)
        }
    }

    /// M7f L12: a search result for a later programme. Focus goes to `channelID` (All Channels if it isn't in the
    /// selected group, else its own group) at `date`. False when the channel isn't in the lineup.
    @discardableResult
    mutating func focus(channelID: Channel.ID, at date: Date, now: Date) -> Bool {
        if Self.channelRowIndex(of: channelID, in: rows) == nil {
            guard lineup.visibleChannels.contains(where: { $0.id == channelID }) else { return false }
            let channelGroup = lineup.visibleChannels.first { $0.id == channelID }?.group
            let candidates = [ChannelList.allChannelsGroup] + [channelGroup].compactMap { $0 }
            let groups = groups, lineup = lineup
            guard let index = candidates.compactMap({ groups.firstIndex(of: $0) })
                .first(where: { lineup.channels(in: groups[$0]).contains { $0.id == channelID } })
            else { return false }
            groupIndex = index
            rows = rowsOfSelectedGroup()
            firstVisibleRow = 0
        }
        guard let index = Self.channelRowIndex(of: channelID, in: rows) else { return false }
        row = index
        keepRowVisible()
        focus = .grid
        focusTime = max(date, now)
        timeline = GuideTimeline(now: now)
        timeline.reveal(focusTime, now: now)
        return true
    }

    /// Tests and callers without preferences.
    init(allChannels: [Channel], group: String?, focusedChannelID: Channel.ID?, now: Date) {
        self.init(lineup: ChannelLineup(channels: allChannels), group: group, focusedChannelID: focusedChannelID, now: now)
    }

    mutating func setChannels(allChannels: [Channel]) {
        setLineup(ChannelLineup(channels: allChannels))
    }

    /// After a playlist refresh or a favorites/hiding change: keep group/row by id where possible, else the row index.
    /// M7l 8c: a focused group-list row keeps its group (by name) when groups appear or go above it.
    mutating func setLineup(_ lineup: ChannelLineup) {
        let focusedRowID = focusedRow?.id
        let focusedChannelID = focusedRow.flatMap { if case .channel(let channel) = $0 { channel.id } else { nil } }
        let group = selectedGroup
        let focusedGroup: String? = if case .groups(let index) = focus, groups.indices.contains(index) {
            groups[index]
        } else {
            nil
        }
        self.lineup = lineup
        groups = lineup.groups
        groupIndex = group.flatMap { groups.firstIndex(of: $0) } ?? Self.defaultGroupIndex(lineup)
        rows = rowsOfSelectedGroup()
        row = focusedRowID.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? focusedChannelID.flatMap { Self.channelRowIndex(of: $0, in: rows) }
            ?? min(row, max(0, rows.count - 1))
        firstVisibleRow = min(firstVisibleRow, max(0, rows.count - Self.visibleRows))
        keepRowVisible()
        if case .groups(let index) = focus {
            focus = .groups(focusedGroup.flatMap { groups.firstIndex(of: $0) } ?? min(index, max(0, groups.count - 1)))
        }
        keepGroupVisible()
    }

    /// The focused row of the group panel: 0 is Search, 1… the groups; nil when the panel isn't focused.
    var groupPanelRow: Int? {
        switch focus {
        case .search: 0
        case .groups(let index): index + 1
        case .grid, .channel: nil
        }
    }

    // MARK: - Private

    /// M7l 8c: the first group that isn't My Teams; M7j L3: nor Antenna, else Antenna, else 0. Nor an empty
    /// Favorites, so a first launch with no favorites opens where it did before Favorites was always listed.
    private static func defaultGroupIndex(_ lineup: ChannelLineup) -> Int {
        let groups = lineup.groups
        let favoritesEmpty = lineup.favoritesGroupChannels.isEmpty
        return groups.firstIndex {
            $0 != ChannelLineup.teamsGroup && $0 != AntennaLineup.group
                && !(favoritesEmpty && $0 == ChannelLineup.favoritesGroup)
        } ?? groups.firstIndex(of: AntennaLineup.group) ?? 0
    }

    private static func channelRowIndex(of id: Channel.ID, in rows: [Row]) -> Int? {
        rows.firstIndex { if case .channel(let channel) = $0 { channel.id == id } else { false } }
    }

    private func rowsOfSelectedGroup() -> [Row] {
        guard let group = selectedGroup else { return [] }
        let channels = lineup.channels(in: group).map(Row.channel)
        if group == ChannelLineup.favoritesGroup, channels.isEmpty { return [.favoritesEmpty] }
        guard group == ChannelLineup.teamsGroup else { return channels }
        return [.chooseTeams] + channels + lineup.upcomingTeamGames.map(Row.upcoming)
    }

    private func focusedCellIndex(in cells: [Cell]) -> Int? {
        guard !cells.isEmpty else { return nil }
        if let index = cells.firstIndex(where: { $0.start <= focusTime && focusTime < $0.stop }) { return index }
        if let index = cells.firstIndex(where: { $0.start > focusTime }) { return index }
        return cells.count - 1
    }

    private mutating func handleGrid(_ command: RemoteCommand, now: Date) -> Action {
        switch command {
        case .up, .down:
            moveRow(command)
            return .none
        case .right, .fastForward:
            let cells = cells(row: row, now: now)
            guard let index = focusedCellIndex(in: cells), index + 1 < cells.count else { return .none }
            moveFocus(to: cells[index + 1], now: now)
            return .none
        case .left, .rewind:
            let cells = cells(row: row, now: now)
            guard let index = focusedCellIndex(in: cells) else { return .none }
            if index == 0 {
                focus = .channel
            } else {
                moveFocus(to: cells[index - 1], now: now)
            }
            return .none
        case .select:
            return focusedChannel.map { .play($0.id) } ?? .none
        case .back:
            return .close
        case .menu:
            // M7 L5: the channel menu, as Select on the channel cell.
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .channelUp, .channelDown:
            moveRow(by: command == .channelUp ? -Self.visibleRows : Self.visibleRows)
            return .none
        case .playPause, .home, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    private mutating func handleChannel(_ command: RemoteCommand) -> Action {
        switch command {
        case .up, .down:
            moveRow(command)
            return .none
        case .right, .fastForward:
            focus = .grid
            return .none
        case .left, .rewind:
            focus = .groups(groupIndex)
            return .none
        case .select:
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .back:
            return .close
        case .menu:
            // M7 L5: the channel menu, as Select on the channel cell.
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .channelUp, .channelDown:
            moveRow(by: command == .channelUp ? -Self.visibleRows : Self.visibleRows)
            return .none
        case .playPause, .home, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    private mutating func handleGroups(_ command: RemoteCommand, index: Int, now: Date) -> Action {
        switch command {
        case .up, .down:
            // M7f L12: the Search row sits above the first group; the list loops.
            moveInGroupPanel(by: command == .up ? -1 : 1)
            return .none
        case .select, .right:
            guard groups.indices.contains(index) else { return .none }
            groupIndex = index
            rows = rowsOfSelectedGroup()
            row = 0
            firstVisibleRow = 0
            focusTime = now
            timeline = GuideTimeline(now: now)
            focus = .grid
            return .groupChanged(groups[index])
        case .back, .left:
            focus = .grid
            return .none
        case .channelUp, .channelDown:
            moveInGroupPanel(by: command == .channelUp ? -Self.visibleGroupRows : Self.visibleGroupRows)
            return .none
        case .playPause, .home, .fastForward, .rewind, .menu, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    /// M7f L12: the Search row; Down goes to the first group.
    private mutating func handleSearchRow(_ command: RemoteCommand) -> Action {
        switch command {
        case .select, .right:
            // Focus stays here, so closing search comes back to the Search row.
            return .openSearch
        case .up, .down:
            // Up loops to the last group.
            moveInGroupPanel(by: command == .up ? -1 : 1)
            return .none
        case .channelUp, .channelDown:
            moveInGroupPanel(by: command == .channelUp ? -Self.visibleGroupRows : Self.visibleGroupRows)
            return .none
        case .back, .left:
            focus = .grid
            return .none
        case .playPause, .home, .fastForward, .rewind, .menu, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    /// M7l 8c: My Teams' Choose Teams and upcoming rows, and an empty Favorites' row, focused as a whole (no channel
    /// cell, no programmes). Select opens the picker (focus stays, so closing it comes back here) or plays the game's
    /// channel, and does nothing on the empty Favorites row; Left goes to the groups; Menu does nothing.
    private mutating func handleActionRow(_ command: RemoteCommand, _ focusedRow: Row) -> Action {
        switch command {
        case .up, .down:
            moveRow(command)
            return .none
        case .select:
            switch focusedRow {
            case .upcoming(let game): return .play(game.channel.id)
            case .chooseTeams: return .openTeamPicker
            case .channel, .favoritesEmpty: return .none
            }
        case .left, .rewind:
            focus = .groups(groupIndex)
            return .none
        case .right, .fastForward:
            focus = .grid
            return .none
        case .back:
            return .close
        case .channelUp, .channelDown:
            moveRow(by: command == .channelUp ? -Self.visibleRows : Self.visibleRows)
            return .none
        case .menu, .playPause, .home, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    private mutating func moveRow(_ command: RemoteCommand) {
        moveRow(by: command == .up ? -1 : 1)
    }

    /// M7n L3: a step (±1) past either end wraps to the other end. A page (M7 L5, Channel Up/Down) stops at the
    /// first or last row and wraps only from it, so paging never skips past an end unseen. A one-row list stays.
    private mutating func moveRow(by step: Int) {
        guard rows.count > 1 else { return }
        let last = rows.count - 1
        let target = row + step
        let before = row
        if abs(step) == 1 {
            row = (target + rows.count) % rows.count
        } else if target < 0 {
            row = row == 0 ? last : 0
        } else if target > last {
            row = row == last ? 0 : last
        } else {
            row = target
        }
        if (step > 0 && row < before) || (step < 0 && row > before) { wrapCount &+= 1 }
        keepRowVisible()
    }

    private mutating func moveFocus(to cell: Cell, now: Date) {
        focusTime = max(cell.start, now)
        timeline.reveal(focusTime, now: now)
    }

    /// The group panel loops like the channel list (M7n L3): a step (±1) past either end wraps to the other end; a
    /// page stops at Search or the last group and wraps only from it. Without groups the Search row stays.
    private mutating func moveInGroupPanel(by step: Int) {
        guard let position = groupPanelRow, !groups.isEmpty else { return }
        let last = groups.count
        let target = position + step
        let new = if abs(step) == 1 {
            (target + last + 1) % (last + 1)
        } else if target < 0 {
            position == 0 ? last : 0
        } else if target > last {
            position == last ? 0 : last
        } else {
            target
        }
        if (step > 0 && new < position) || (step < 0 && new > position) { groupWrapCount &+= 1 }
        focus = new == 0 ? .search : .groups(new - 1)
    }

    private mutating func keepGroupVisible() {
        if let position = groupPanelRow {
            if position < firstVisibleGroupRow {
                firstVisibleGroupRow = position
            } else if position >= firstVisibleGroupRow + Self.visibleGroupRows {
                firstVisibleGroupRow = position - Self.visibleGroupRows + 1
            }
        }
        firstVisibleGroupRow = min(firstVisibleGroupRow, max(0, groups.count + 1 - Self.visibleGroupRows))
    }

    private mutating func keepRowVisible() {
        if row < firstVisibleRow {
            firstVisibleRow = row
        } else if row >= firstVisibleRow + Self.visibleRows {
            firstVisibleRow = row - Self.visibleRows + 1
        }
    }
}
