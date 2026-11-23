import SwiftUI

/// The grid guide on the 1920×1080 canvas (L12): info panel, preview frame (the video sits under it, L16),
/// time header, channel rows, now line and group panel.
struct GuideView: View {
    let model: GuideModel
    let currentChannel: Channel?
    let phase: PlayerState.Phase
    /// The Multiview picker guide (M6 L11): Select puts the channel in a window.
    var isPicking = false
    /// Starred in the channel cell (M6b).
    var favoriteIDs: Set<Channel.ID> = []
    /// M7m L4: Back in the watch guide returns to a channel (`LiveTVModel.canReturnToChannel`); the hint says so.
    var hasChannel = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// M7n L4: the position the scrolling stack shows; follows the model's (animated for short moves,
    /// `scroll(from:to:)`). Nil until the first scroll.
    @State private var displayed: ScrollPosition?
    /// The group panel's position, as `displayed` is the rows'.
    @State private var displayedGroups: ScrollPosition?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                infoPanel(now: now)
                    .frame(width: Theme.guideInfoRect.width, height: Theme.guideInfoRect.height, alignment: .topLeading)
                    .offset(x: Theme.guideInfoRect.minX, y: Theme.guideInfoRect.minY)
                previewFrame
                    .frame(width: Theme.guidePreviewRect.width, height: Theme.guidePreviewRect.height)
                    .offset(x: Theme.guidePreviewRect.minX, y: Theme.guidePreviewRect.minY)
                timeHeader
                    .offset(x: Theme.guideGridLeading, y: Theme.guideGridTop)
                rows(now: now)
                    .offset(x: Theme.sideMargin, y: Theme.guideGridTop + Theme.guideTimeHeaderHeight)
                nowLine(now: now)
                switch model.focus {
                case .groups, .search:
                    groupPanel(focus: model.focus)
                        .offset(x: Theme.sideMargin, y: Theme.guideGridTop)
                case .grid, .channel:
                    EmptyView()
                }
                Text(Self.hint(focus: model.focus, isPicking: isPicking, row: model.focusedRow?.kind ?? .channel,
                               hasChannel: hasChannel))
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Theme.canvasSize.width)
                    .offset(y: Theme.canvasSize.height - 64)
            }
            .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        }
        .onChange(of: scrollPosition) { old, new in
            scroll(from: old, to: new)
        }
        .onChange(of: groupScrollPosition) { old, new in
            scrollGroups(from: old, to: new)
        }
    }

    /// M7n L4: what a scroll compares: a new group or a loop is never animated.
    nonisolated struct ScrollPosition: Equatable {
        var group: String?
        var first: Int
        /// `GuideModel.wrapCount`: a loop to the other end never slides, however short the list.
        var wraps: Int
    }

    private var scrollPosition: ScrollPosition {
        ScrollPosition(group: model.selectedGroup, first: model.firstVisibleRow, wraps: model.wrapCount)
    }

    /// M7n L4: a move of up to a page in the same group slides; a longer jump, a loop (any list), a search result in
    /// another group or a new group is in place at once, never a fast scroll through rows; Reduce Motion never slides.
    nonisolated static func slides(from old: ScrollPosition, to new: ScrollPosition, reduceMotion: Bool) -> Bool {
        !reduceMotion && old.group == new.group && old.wraps == new.wraps
            && abs(new.first - old.first) <= GuideModel.visibleRows
    }

    /// M7n L4 (QA minor 1): the first row to draw. Before `onChange` catches up, a move that will slide still draws
    /// the old position (the slide starts from it); any other change draws the model's position at once, so a jump
    /// never shows a stale or blank window for a frame.
    nonisolated static func drawnFirst(displayed: ScrollPosition?, current: ScrollPosition, reduceMotion: Bool) -> Int {
        guard let displayed, slides(from: displayed, to: current, reduceMotion: reduceMotion) else { return current.first }
        return displayed.first
    }

    private func scroll(from old: ScrollPosition, to new: ScrollPosition) {
        let slides = Self.slides(from: old, to: new, reduceMotion: reduceMotion)
        var transaction = Transaction(animation: slides ? Theme.guideScrollAnimation : nil)
        transaction.disablesAnimations = !slides
        withTransaction(transaction) { displayed = new }
    }

    /// M7n L5: the focus fill and text colours fade to the newly focused cell; with Reduce Motion they change at once.
    private var focusAnimation: Animation? { reduceMotion ? nil : Theme.focusAnimation }

    /// The bottom hint per focus and purpose (M6), (M7l 8c) My Teams' Choose Teams and upcoming rows, and an empty
    /// Favorites' row (nothing to select there).
    /// M7m L4: in the watch guide Back goes back to the channel (`hasChannel`); with no channel it does nothing.
    nonisolated static func hint(focus: GuideModel.Focus, isPicking: Bool, row: GuideModel.Row.Kind = .channel,
                                 hasChannel: Bool = false) -> String {
        let back = hasChannel ? " · Back: back to the channel" : ""
        switch (focus, row, isPicking) {
        case (.grid, .chooseTeams, false), (.channel, .chooseTeams, false):
            return "Select: choose your teams · Left: groups" + back
        case (.grid, .chooseTeams, true), (.channel, .chooseTeams, true):
            return "Select: choose your teams · Left: groups · Back: cancel"
        case (.grid, .upcoming, false), (.channel, .upcoming, false):
            return "Select: watch this channel · Left: groups" + back
        case (.grid, .upcoming, true), (.channel, .upcoming, true):
            return "Select: show this channel in window · Left: groups · Back: cancel"
        case (.grid, .favoritesEmpty, false), (.channel, .favoritesEmpty, false):
            return "Left: groups" + back
        case (.grid, .favoritesEmpty, true), (.channel, .favoritesEmpty, true):
            return "Left: groups · Back: cancel"
        default:
            break
        }
        return switch (focus, isPicking) {
        case (.grid, false): "Select: watch · Left at now: channel options" + back
        case (.grid, true): "Select: show in window · Left at now: channel · Back: cancel"
        case (.channel, false): "Select: options · Left: groups · Right: programmes" + back
        case (.channel, true): "Select: show in window · Left: groups · Right: programmes · Back: cancel"
        case (.groups, _): "Select: show group · Back: close list"
        case (.search, _): "Select: search channels and programmes · Back: close list"
        }
    }

    // MARK: Info panel

    @ViewBuilder
    private func infoPanel(now: Date) -> some View {
        switch model.focusedRow {
        case .chooseTeams?: chooseTeamsInfo
        case .upcoming(let game)?: upcomingInfo(game)
        case .favoritesEmpty?: favoritesEmptyInfo
        case .channel?, nil: channelInfo(now: now)
        }
    }

    /// An empty Favorites group's only row.
    private var favoritesEmptyInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.favoritesEmptyTitle)
                .font(Theme.guideInfoTitleFont)
                .foregroundStyle(Theme.primaryText)
            Text("Press Menu on any channel and choose Add to Favorites. Your teams' live games show here too.")
                .font(Theme.guideInfoDetailFont)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(4)
        }
    }

    private static let favoritesEmptyTitle = "No favorites yet"

    /// M7l 8c: My Teams' Choose Teams row.
    private var chooseTeamsInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TeamPicker.title)
                .font(Theme.guideInfoTitleFont)
                .foregroundStyle(Theme.primaryText)
            Text("Pick pro and college teams. Their live games show here, then their games in the next 3 days.")
                .font(Theme.guideInfoDetailFont)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(4)
        }
    }

    /// M7l 8c: an upcoming game: its programme, the channel and the day. The time is "Wed 10:00 PM – 1:00 AM", not
    /// `LiveBannerView.timeRange`, whose interval format spells out both dates when a game ends after midnight.
    private func upcomingInfo(_ game: UpcomingTeamGame) -> some View {
        let programme = game.programme
        let when = game.dayTime + " – " + programme.stop.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 16) {
            Text(programme.title)
                .font(Theme.guideInfoTitleFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            Text(([game.channel.name, when] + [programme.subtitle, programme.category].compactMap { $0 })
                .joined(separator: " · "))
                .font(Theme.guideInfoDetailFont)
                .foregroundStyle(Theme.primaryText)
            if let summary = programme.summary {
                Text(summary)
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private func channelInfo(now: Date) -> some View {
        let cell = model.focusedCell(now: now)
        let channelName = model.focusedChannel?.name ?? ""
        VStack(alignment: .leading, spacing: 16) {
            if let programme = cell?.programme {
                Text(programme.title)
                    .font(Theme.guideInfoTitleFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Text(([channelName, LiveBannerView.timeRange(programme)] + [programme.episode, programme.category].compactMap { $0 })
                    .joined(separator: " · "))
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.primaryText)
                if let summary = programme.summary {
                    Text(summary)
                        .font(Theme.guideInfoDetailFont)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(4)
                }
            } else {
                Text(channelName)
                    .font(Theme.guideInfoTitleFont)
                    .foregroundStyle(Theme.primaryText)
                Text("No programme information")
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Preview

    private var previewFrame: some View {
        ZStack {
            if phase == .idle || phase == .failed {
                Text(phase == .failed ? "Can't play this channel" : "Nothing playing")
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
            RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius)
                .strokeBorder(Theme.focusHighlight, lineWidth: Theme.focusHighlightWidth)
        }
    }

    // MARK: Grid

    private var timeHeader: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.timeline.ticks(width: Theme.guideGridWidth), id: \.date) { tick in
                Text(tick.date.formatted(date: .omitted, time: .shortened))
                    .font(Theme.guideCellTimeFont)
                    .foregroundStyle(Theme.secondaryText)
                    .offset(x: tick.x + 8)
            }
        }
        .frame(width: Theme.guideGridWidth, height: Theme.guideTimeHeaderHeight, alignment: .topLeading)
    }

    /// The channel column and the grid, as wide as a row.
    private static let rowsWidth = Theme.guideGridLeading - Theme.sideMargin + Theme.guideGridWidth
    private static let rowsWindowHeight = CGFloat(GuideModel.visibleRows) * Theme.guideRowHeight

    /// M7n L4: a window `visibleRows` rows high. Inside it the rows of a buffer (a page above and two below the
    /// first row shown) sit at their index's place, keyed by their id, and the stack moves by `drawnFirst`, so a
    /// scroll slides the rows instead of swapping what six fixed slots show. Each channel row carries its piece of
    /// the now line. The window clips only top and bottom.
    private func rows(now: Date) -> some View {
        let first = Self.drawnFirst(displayed: displayed, current: scrollPosition, reduceMotion: reduceMotion)
        let nowX = model.timeline.span(start: now, stop: now + 1, width: Theme.guideGridWidth)?.x
        return ZStack(alignment: .topLeading) {
            ForEach(Self.bufferedRows(model.rows, first: first), id: \.key) { item in
                rowView(item.index, now: now)
                    .frame(width: Self.rowsWidth, height: Theme.guideRowHeight, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        if let nowX, model.rows[item.index].kind == .channel {
                            Rectangle()
                                .fill(Theme.guideNowLine)
                                .frame(width: 2, height: Theme.guideRowHeight)
                                .offset(x: Theme.guideGridLeading - Theme.sideMargin + nowX)
                        }
                    }
                    .offset(y: CGFloat(item.index) * Theme.guideRowHeight)
            }
        }
        .offset(y: -CGFloat(first) * Theme.guideRowHeight)
        .frame(width: Self.rowsWidth, height: Self.rowsWindowHeight, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: Self.rowsWidth + 2 * Theme.sideMargin, height: Self.rowsWindowHeight)
                .offset(x: -Theme.sideMargin)
        }
    }

    /// M7n L4: the rows drawn around `first` (`first - visibleRows ..< first + 2 × visibleRows`, within the rows),
    /// keyed by `Row.id`; a repeated id (never expected) gets its index added so every key is unique.
    nonisolated static func bufferedRows(_ rows: [GuideModel.Row], first: Int) -> [BufferedRow] {
        let upper = max(0, min(rows.count, first + 2 * GuideModel.visibleRows))
        let lower = min(max(0, first - GuideModel.visibleRows), upper)
        var seen = Set<String>()
        return (lower..<upper).map { index in
            let id = rows[index].id
            return BufferedRow(index: index, key: seen.insert(id).inserted ? id : "\(id)#\(index)")
        }
    }

    nonisolated struct BufferedRow: Equatable, Sendable {
        var index: Int
        var key: String
    }

    @ViewBuilder
    private func rowView(_ row: Int, now: Date) -> some View {
        switch model.rows[row] {
        case .channel(let channel): channelRow(row, channel, now: now)
        case .chooseTeams: chooseTeamsRow(row)
        case .upcoming(let game): upcomingRow(row, game)
        case .favoritesEmpty: favoritesEmptyRow(row)
        }
    }

    private func channelRow(_ row: Int, _ channel: Channel, now: Date) -> some View {
        let focusedCell = row == model.row && model.focus == .grid ? model.focusedCell(now: now) : nil
        let isChannelFocused = row == model.row && model.focus == .channel
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            channelCell(channel, isFocused: isChannelFocused)
                .padding(.horizontal, 8)
                .frame(width: Theme.guideChannelColumnWidth, height: Theme.guideRowHeight - Theme.guideCellSpacing,
                       alignment: .leading)
                .focusFill(isChannelFocused ? Theme.focusedRowFill : Color.clear, focusAnimation)
                .frame(height: Theme.guideRowHeight, alignment: .top)
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.cells(row: row, now: now).enumerated()), id: \.offset) { _, cell in
                    if let span = model.timeline.span(start: cell.start, stop: cell.stop, width: Theme.guideGridWidth) {
                        programmeCell(cell, isFocused: cell == focusedCell)
                            .frame(width: max(0, span.width - Theme.guideCellSpacing),
                                   height: Theme.guideRowHeight - Theme.guideCellSpacing)
                            .offset(x: span.x)
                    }
                }
            }
            .frame(width: Theme.guideGridWidth, height: Theme.guideRowHeight, alignment: .topLeading)
            .clipped()
        }
    }

    /// M7l 8c: whether My Teams' Choose Teams or upcoming row `row` is focused. They have no programme cells to
    /// move between, so the channel column and the grid both focus the whole row.
    private func isActionRowFocused(_ row: Int) -> Bool {
        row == model.row && (model.focus == .grid || model.focus == .channel)
    }

    /// M7l 8c: My Teams' first row, an action rather than a channel: one button across the channel column and the
    /// grid (no channel number, no programme cells), its symbol where channel logos sit and its title in line with
    /// the channel names, the description in line with the programme titles, and a chevron for "opens a page".
    private func chooseTeamsRow(_ row: Int) -> some View {
        let isFocused = isActionRowFocused(row)
        let columnGap = Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth
        return HStack(spacing: columnGap) {
            HStack(spacing: 12) {
                Color.clear.frame(width: Theme.guideChannelNumberWidth, height: 1)
                Image(systemName: "sportscourt")
                    .font(.system(size: Theme.guideRowSymbolSize, weight: .medium))
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
                Text(TeamPicker.title + "…")
                    .font(Theme.guideChannelFont)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: Theme.guideChannelColumnWidth, alignment: .leading)
            HStack(spacing: 16) {
                Text("Add or remove pro and college teams")
                    .font(Theme.guideCellFont)
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.guideRowSymbolSize, weight: .semibold))
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
            }
            .padding(.horizontal, 16)
        }
        .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
        .frame(width: Theme.guideGridLeading - Theme.sideMargin + Theme.guideGridWidth - Theme.guideCellSpacing,
               height: Theme.guideRowHeight - Theme.guideCellSpacing, alignment: .leading)
        .focusFill(isFocused ? Theme.focusedRowFill : Theme.tileFill, focusAnimation)
        .frame(height: Theme.guideRowHeight, alignment: .top)
    }

    /// M7l 8c: an upcoming game: the channel column as on every guide row, then one cell across the grid (it isn't
    /// on the timeline, so the now line skips it) led by its day and time, then the game ("Tampa Bay Buccaneers at
    /// Chicago Bears") over the programme's title ("NFL Football") when the game came from the subtitle.
    private func upcomingRow(_ row: Int, _ game: UpcomingTeamGame) -> some View {
        let isFocused = isActionRowFocused(row)
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            channelCell(game.channel, isFocused: isFocused)
                .padding(.horizontal, 8)
                .frame(width: Theme.guideChannelColumnWidth, height: Theme.guideRowHeight - Theme.guideCellSpacing,
                       alignment: .leading)
                .focusFill(isFocused ? Theme.focusedRowFill : Color.clear, focusAnimation)
                .frame(height: Theme.guideRowHeight, alignment: .top)
            upcomingCell(game, isFocused: isFocused)
                .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
                .padding(.horizontal, 16)
                .frame(width: Theme.guideGridWidth - Theme.guideCellSpacing,
                       height: Theme.guideRowHeight - Theme.guideCellSpacing, alignment: .leading)
                .focusFill(isFocused ? Theme.focusedRowFill : Theme.tileFill, focusAnimation)
                .frame(width: Theme.guideGridWidth, height: Theme.guideRowHeight, alignment: .topLeading)
        }
    }

    /// An empty Favorites group's only row, laid out like a channel row: "No favorites yet" in the channel column (a
    /// star where channel logos sit, its text in line with the channel names), then one cell across the grid saying
    /// how to add one. It isn't on the timeline, so the now line skips it; it's focused as a whole.
    private func favoritesEmptyRow(_ row: Int) -> some View {
        let isFocused = isActionRowFocused(row)
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            HStack(spacing: 12) {
                Color.clear.frame(width: Theme.guideChannelNumberWidth, height: 1)
                Image(systemName: "star")
                    .font(.system(size: Theme.guideRowSymbolSize, weight: .medium))
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
                Text(Self.favoritesEmptyTitle)
                    .font(Theme.guideChannelFont)
                    .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: Theme.guideChannelColumnWidth, height: Theme.guideRowHeight - Theme.guideCellSpacing,
                   alignment: .leading)
            .focusFill(isFocused ? Theme.focusedRowFill : Color.clear, focusAnimation)
            .frame(height: Theme.guideRowHeight, alignment: .top)
            Text("Press Menu on a channel, then choose Add to Favorites")
                .font(Theme.guideCellFont)
                .lineLimit(1)
                .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
                .padding(.horizontal, 16)
                .frame(width: Theme.guideGridWidth - Theme.guideCellSpacing,
                       height: Theme.guideRowHeight - Theme.guideCellSpacing, alignment: .leading)
                .focusFill(isFocused ? Theme.focusedRowFill : Theme.tileFill, focusAnimation)
                .frame(width: Theme.guideGridWidth, height: Theme.guideRowHeight, alignment: .topLeading)
        }
    }

    /// "[calendar] Sun 1:00 PM | Tampa Bay Buccaneers at Chicago Bears / NFL Football".
    private func upcomingCell(_ game: UpcomingTeamGame, isFocused: Bool) -> some View {
        let secondary = isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText
        let title = game.programme.title
        return HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: Theme.guideRowSymbolSize))
                    .focusForeground(secondary, focusAnimation)
                Text(game.dayTime)
                    .font(Theme.guideCellFont)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: Theme.guideUpcomingTimeWidth, alignment: .leading)
            Rectangle()
                .focusForeground(secondary, focusAnimation)
                .frame(width: 2, height: Theme.guideLogoSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.label)
                    .font(Theme.guideCellFont)
                    .lineLimit(1)
                if game.label != title {
                    Text(title)
                        .font(Theme.guideCellTimeFont)
                        .focusForeground(secondary, focusAnimation)
                        .lineLimit(1)
                }
            }
        }
    }

    private func channelCell(_ channel: Channel, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            // M7j: "5.1" for antenna channels. Tabular digits keep the column's right edge even; the fixed slot keeps
            // the names in line, and a number wider than "26.12" shrinks rather than truncating.
            Text(channel.displayNumber)
                .font(Theme.guideCellTimeFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(Theme.guideChannelNumberMinimumScale)
                .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
                .frame(width: Theme.guideChannelNumberWidth, alignment: .trailing)
            if let logo = channel.logoURL {
                ChannelLogoView(url: logo)
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
            }
            Text(channel.name)
                .font(Theme.guideChannelFont)
                .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
                .lineLimit(1)
            if favoriteIDs.contains(channel.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: Theme.guideFavoriteSymbolSize))
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
            }
            if channel.id == currentChannel?.id {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.guideCellTimeFont)
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
            }
        }
    }

    private func programmeCell(_ cell: GuideModel.Cell, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.programme?.title ?? "No information")
                .font(Theme.guideCellFont)
                .lineLimit(1)
            if let programme = cell.programme {
                Text(programme.start.formatted(date: .omitted, time: .shortened))
                    .font(Theme.guideCellTimeFont)
                    .focusForeground(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText, focusAnimation)
            }
        }
        .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .focusFill(isFocused ? Theme.focusedRowFill : Theme.tileFill, focusAnimation)
    }

    /// The now line's piece through the time header. M7n L4: the channel rows carry their own pieces (`rows(now:)`),
    /// so they slide with the rows; My Teams' Choose Teams and upcoming rows (M7l 8c) aren't on the timeline and
    /// have none.
    @ViewBuilder
    private func nowLine(now: Date) -> some View {
        if let span = model.timeline.span(start: now, stop: now + 1, width: Theme.guideGridWidth) {
            Rectangle()
                .fill(Theme.guideNowLine)
                .frame(width: 2, height: Theme.guideTimeHeaderHeight)
                .offset(x: Theme.guideGridLeading + span.x, y: Theme.guideGridTop)
        }
    }

    // MARK: Groups

    private static let groupPanelHeight = Theme.guideTimeHeaderHeight + CGFloat(GuideModel.visibleRows) * Theme.guideRowHeight
    private static let groupPanelPadding: CGFloat = 16
    private static let groupRowHeight = Theme.guideRowHeight - 16
    /// A group row and the gap below it.
    private static let groupRowPitch = groupRowHeight + Theme.settingsRowSpacing
    /// The clipped window inside the panel's padding: exactly `GuideModel.visibleGroupRows` rows.
    static let groupWindowHeight = groupPanelHeight - 2 * groupPanelPadding

    /// What the group panel's slide compares. `group` is "" while the panel is open and nil while it's closed, so
    /// opening it puts the rows in place; a loop or a jump of more than a page doesn't slide either (`slides`).
    private var groupScrollPosition: ScrollPosition {
        ScrollPosition(group: model.groupPanelRow == nil ? nil : "", first: model.firstVisibleGroupRow,
                       wraps: model.groupWrapCount)
    }

    private func scrollGroups(from old: ScrollPosition, to new: ScrollPosition) {
        let slides = Self.slides(from: old, to: new, reduceMotion: reduceMotion)
        var transaction = Transaction(animation: slides ? Theme.guideScrollAnimation : nil)
        transaction.disablesAnimations = !slides
        withTransaction(transaction) { displayedGroups = new }
    }

    /// The Search row (M7f L12) above the groups. (M7l 8c: Choose Teams is My Teams' first row.)
    /// Like the channel rows (M7n L4, L5): each row sits at its place in a clipped window and the stack slides by
    /// `firstVisibleGroupRow`, so moving the focus past the window's edge slides the list; the highlight fades.
    private func groupPanel(focus: GuideModel.Focus) -> some View {
        let first = Self.drawnFirst(displayed: displayedGroups, current: groupScrollPosition, reduceMotion: reduceMotion)
        return ZStack(alignment: .topLeading) {
            groupRow(Label("Search", systemImage: "magnifyingglass"), isFocused: focus == .search)
            ForEach(Array(model.groups.enumerated()), id: \.offset) { index, group in
                groupRow(Text(group), isFocused: focus == .groups(index))
                    .offset(y: CGFloat(index + 1) * Self.groupRowPitch)
            }
        }
        .offset(y: -CGFloat(first) * Self.groupRowPitch)
        .frame(width: Theme.guideGroupPanelWidth - 40, height: Self.groupWindowHeight, alignment: .topLeading)
        .clipped()
        .padding(.horizontal, 20)
        .padding(.vertical, Self.groupPanelPadding)
        .frame(width: Theme.guideGroupPanelWidth, height: Self.groupPanelHeight, alignment: .topLeading)
        .glassPanel()
    }

    private func groupRow(_ label: some View, isFocused: Bool) -> some View {
        label
            .font(Theme.guideChannelFont)
            .focusForeground(isFocused ? Theme.focusedRowText : Theme.primaryText, focusAnimation)
            .padding(.horizontal, 20)
            .frame(width: Theme.guideGroupPanelWidth - 40, height: Self.groupRowHeight, alignment: .leading)
            .focusFill(isFocused ? Theme.focusedRowFill : Color.clear, focusAnimation)
    }
}

private extension View {
    /// M7n L5: a focus change fades this foreground colour with `animation` (nil: at once); nothing else in the view
    /// animates with it, so a cell's frame and offset still change in place.
    func focusForeground(_ style: Color, _ animation: Animation?) -> some View {
        self.animation(animation) { $0.foregroundStyle(style) }
    }

    /// M7n L5: a guide cell's fill, fading with `animation` when the focus moves (nil: at once).
    func focusFill(_ fill: Color, _ animation: Animation?) -> some View {
        self.animation(animation) {
            $0.background(fill, in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
        }
    }
}
