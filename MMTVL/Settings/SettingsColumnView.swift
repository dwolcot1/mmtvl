import SwiftUI

/// M7g L1: one column of the Settings track. The current page has focus; the parent page is dimmed with its
/// opening row selected, or shows the current page's accessory instead (L2). Empty and hidden columns hold their slot
/// so the track never reflows.
struct SettingsColumnView: View {
    let model: SettingsModel
    let column: SettingsModel.Column
    let launcher: AppLauncher
    let tileArt: TileArtStore
    /// A row's id and its column's page; the model ignores rows that aren't on the current page.
    let onHoverRow: (String, SettingsPage) -> Void
    let onActivateRow: (String, SettingsPage) -> Void
    let onActivateParent: () -> Void

    /// What the column draws; a change crossfades (replaced, pushed and popped pages).
    private enum Content: Hashable {
        case none
        case list(SettingsPage)
        /// The accessory of this (current) page, in the parent column.
        case accessory(SettingsPage)
    }

    private var content: Content {
        switch column.role {
        case .current:
            return column.page.map(Content.list) ?? .none
        case .parent:
            if model.accessory(for: model.page) != nil { return .accessory(model.page) }
            return column.page.map(Content.list) ?? .none
        case .empty, .hidden:
            return .none
        }
    }

    /// The accessory stays at full strength: a QR code must scan and tile art shows its real colors. A hidden
    /// column keeps the parent's dimming, so the page pushed off to the left doesn't brighten as it fades.
    private var opacity: Double {
        switch (column.role, content) {
        case (.parent, .list), (.hidden, _): Theme.settingsDimmedColumnOpacity
        default: 1
        }
    }

    private var onClick: (() -> Void)? {
        column.role == .parent ? onActivateParent : nil
    }

    /// The column is leaving the screen with the slide (pushed off to the left, or popped off to the right).
    private var isLeaving: Bool { column.role == .hidden || column.role == .empty }

    /// How the old content fades out. Column 1 is only `.empty` at the root, so this is the category page on a
    /// return to the root: it moves only 460 pt and stays half on screen, so it fades faster than the slide.
    private var removalAnimation: Animation {
        if column.role == .empty && column.index == 1 { return Theme.settingsFadeAnimation }
        return isLeaving ? Theme.settingsLeaveFadeAnimation : Theme.settingsFadeOutAnimation
    }

    var body: some View {
        ZStack {
            contentView
                .id(content)
                .transition(.asymmetric(insertion: .opacity.animation(Theme.settingsFadeInAnimation),
                                        removal: .opacity))
        }
        // The old content fades out quickly when replaced in place (then the new one fades in), or over most of
        // the slide when the column leaves the screen.
        .animation(removalAnimation, value: content)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dimming and brightening on role changes, scoped to the opacity alone.
        .animation(Theme.settingsFadeAnimation) { $0.opacity(opacity) }
        .overlay {
            // Parent: a click anywhere goes back. Covers the rows, so they get no hover or clicks of their own.
            if let onClick {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClick)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .none:
            Color.clear
        case .list(let page):
            if case .addressEntry = page, column.role == .current {
                // M7h D41: the on-screen keyboard, with the page's rows (Save, Clear, Cancel) below it.
                VStack(alignment: .leading, spacing: 0) {
                    OnScreenKeyboardView(keyboard: model.keyboard, placeholder: "Address",
                                         isFocused: model.isKeyboardFocused)
                        .padding(.top, Theme.settingsListVerticalPadding)
                        .padding(.horizontal, 24)
                    pageList(page)
                }
            } else {
                pageList(page)
            }
        case .accessory(let page):
            if let image = model.accessory(for: page) {
                RowImageView(image: image, launcher: launcher, size: Theme.settingsAccessorySymbolSize,
                             tileArt: tileArt, items: model.items)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pageList(_ page: SettingsPage) -> some View {
        SettingsPageList(
            page: page,
            sections: model.sections(for: page),
            role: column.role,
            markedRowID: markedRowID,
            launcher: launcher,
            tileArt: tileArt,
            onHoverRow: onHoverRow,
            onActivateRow: onActivateRow
        )
    }

    /// The focused row (current), the opening row (parent), or nothing.
    private var markedRowID: String? {
        switch column.role {
        case .current: model.focusedRowID
        case .parent: model.parentSelectionRowID
        default: nil
        }
    }
}

/// A page's sections in one column, with its own scroll position: the current column centers its focused row,
/// the parent its selected row. M7g L4: every row is its own glass capsule, in one
/// glass container per column. L5: one white highlight per column slides between the rows.
private struct SettingsPageList: View {
    let page: SettingsPage
    let sections: [SettingsSection]
    let role: SettingsModel.Column.Role
    let markedRowID: String?
    let launcher: AppLauncher
    let tileArt: TileArtStore
    let onHoverRow: (String, SettingsPage) -> Void
    let onActivateRow: (String, SettingsPage) -> Void

    /// The padded content, for scrolling to the list's top (the first row, or the first action row) or its end (the
    /// last row, or the last action row).
    private static let topID = "settings.list.top"

    @Namespace private var highlightNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCurrent: Bool { role == .current }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                GlassEffectContainer(spacing: Theme.settingsRowSpacing) {
                    VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
                        ForEach(sections) { section in
                            sectionView(section)
                        }
                    }
                }
                // Room for the focused row's scale and shadow.
                .padding(.vertical, Theme.settingsListVerticalPadding)
                .padding(.horizontal, 24)
                .id(Self.topID)
                // L5: the highlight slides to the newly focused row (with Reduce Motion each row fades its own).
                .animation(Theme.focusAnimation, value: isCurrent ? markedRowID : nil)
            }
            .scrollIndicators(.never)
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: markedRowID) { scroll(proxy, animated: true) }
            .onChange(of: role) { scroll(proxy, animated: true) }
        }
        // Scrolled rows fade out at the top and bottom instead of being cut, and never draw over the page title or
        // the band. Only vertical: the focused row's scale and shadow reach past the list at the sides.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.settingsListVerticalPadding)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.settingsListVerticalPadding)
            }
            .padding(.horizontal, -Theme.settingsColumnGap / 2)
        }
    }

    /// Centers the marked row. On the first row or the first action row the list shows its top, and on the last row
    /// or the last action row its end, so headers, info rows and footers at either end stay in view (the first
    /// check wins on a page with one action row). Other rows, info rows included, are centered.
    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let markedRowID else { return }
        let rows = sections.flatMap(\.rows)
        let actionIDs = rows.filter { $0.action != nil }.map(\.id)
        let target: (id: String, anchor: UnitPoint) =
            if markedRowID == rows.first?.id || markedRowID == actionIDs.first { (Self.topID, .top) }
            else if markedRowID == rows.last?.id || markedRowID == actionIDs.last { (Self.topID, .bottom) }
            else { (markedRowID, .center) }
        if animated {
            withAnimation(Theme.focusAnimation) { proxy.scrollTo(target.id, anchor: target.anchor) }
        } else {
            proxy.scrollTo(target.id, anchor: target.anchor)
        }
    }

    private func style(of row: SettingsRow) -> SettingsRowView.Style {
        guard row.id == markedRowID else { return .normal }
        switch role {
        case .current: return .focused
        case .parent: return .selected
        default: return .normal
        }
    }

    private func sectionView(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
            if let title = section.title {
                Text(title.uppercased())
                    .font(Theme.settingsSectionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, Theme.settingsRowTextInset)
            }
            ForEach(section.rows) { row in
                SettingsRowView(
                    row: row,
                    style: style(of: row),
                    highlightNamespace: reduceMotion || !isCurrent ? nil : highlightNamespace,
                    launcher: launcher,
                    tileArt: tileArt,
                    // The model ignores rows not on the current page: the parent column (also covered by its
                    // click layer) and a page still fading out after a pop or a replace, whose view keeps
                    // its last role.
                    onHover: { onHoverRow(row.id, page) },
                    onActivate: { onActivateRow(row.id, page) }
                )
                .id(row.id)
            }
            if let footer = section.footer {
                Text(footer)
                    .font(Theme.settingsRowDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, Theme.settingsRowTextInset)
            }
        }
    }
}
