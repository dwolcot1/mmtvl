import SwiftUI

/// M7g L4: a row's capsule. One-line rows are full pills; rows with a second line are rounded rectangles
/// (`Theme.settingsRowCornerRadius`), so the pill doesn't squeeze the text.
nonisolated struct SettingsRowShape: InsettableShape {
    /// Nil: a capsule.
    var cornerRadius: CGFloat?
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = cornerRadius.map { max(0, $0 - insetAmount) } ?? min(rect.width, rect.height) / 2
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }

    func inset(by amount: CGFloat) -> SettingsRowShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// One Settings row (M7g L4), its own glass capsule. The focused (or lifted) row turns white with dark text, as on
/// tvOS; with a highlight namespace (L5) the white fill slides between the column's rows instead of fading. A focused
/// info row only gets a white ring: the white fill isn't drawn on it, so it fades out (and back in on the next action
/// row) rather than sliding onto it.
struct SettingsRowView: View {
    enum Style {
        /// The current column's focused row.
        case focused
        /// The row in the parent column that opened the current page.
        case selected
        case normal
    }

    let row: SettingsRow
    let style: Style
    /// L5: the column's namespace for the sliding highlight; nil with Reduce Motion (the fill crossfades per row).
    var highlightNamespace: Namespace.ID? = nil
    let launcher: AppLauncher
    var tileArt: TileArtStore? = nil
    let onHover: () -> Void
    let onActivate: () -> Void

    /// Info rows never get the white highlight: a focused one gets a ring instead (`isInfoFocused`).
    private var isHighlighted: Bool { (style == .focused || row.isLifted) && row.action != nil }
    private var isMarkedSelected: Bool { style == .selected && !isHighlighted }
    private var isInfo: Bool { row.action == nil }
    /// A focused info row: its quiet fill and colours, plus a white ring; no scale, no shadow.
    private var isInfoFocused: Bool { style == .focused && isInfo }
    private var primary: Color { isHighlighted ? Theme.focusedRowText : Theme.primaryText }
    private var secondary: Color { isHighlighted ? Theme.focusedRowSecondaryText : Theme.secondaryText }
    private var shape: SettingsRowShape {
        SettingsRowShape(cornerRadius: row.detail == nil ? nil : Theme.settingsRowCornerRadius)
    }

    private var scale: CGFloat { isHighlighted ? Theme.settingsRowFocusScale : 1 }

    /// The glass is never scaled (so it doesn't reach its neighbours); the fill over it and the content scale
    /// each on their own. The white fill isn't under a per-row transform: `matchedGeometryEffect` misplaces it
    /// inside one. The glass is the surface of the row's views, which keeps it behind them in the glass container.
    var body: some View {
        ZStack {
            fill
            content
                .scaleEffect(scale)
        }
        // Selected ↔ focused (a category open, Back onto the opening row) flips at once: crossfading the text from
        // white to black over the gray-to-white fill left the capsule blank for a couple of frames. Normal ↔
        // focused still animates, and so does the column's dimming.
        .animation(nil, value: style == .selected)
        .frame(maxWidth: .infinity, minHeight: Theme.settingsRowMinHeight)
        .modifier(SettingsRowSurface(shape: shape, isInfo: isInfo))
        .overlay {
            if isInfoFocused {
                shape.strokeBorder(Theme.focusedRowFill, lineWidth: Theme.settingsInfoRowFocusRingWidth)
            }
        }
        .contentShape(shape)
        .opacity(row.isDimmed && !isHighlighted ? Theme.unavailableOpacity : 1)
        // No `zIndex` for the focused row: changing it makes the glass container rebuild the row's glass, which
        // shrinks and regrows it.
        .animation(Theme.focusAnimation, value: isHighlighted)
        .animation(Theme.focusAnimation, value: isInfoFocused)
        .onHover { hovering in
            if hovering { onHover() }
        }
        .onTapGesture(perform: onActivate)
    }

    private var content: some View {
        HStack(spacing: 24) {
            if let image = row.image {
                RowImageView(image: image, launcher: launcher, size: Theme.settingsRowIconSize, foreground: primary,
                             tileArt: tileArt)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(primary)
                if let detail = row.detail {
                    Text(detail)
                        .font(Theme.settingsRowDetailFont)
                        .foregroundStyle(secondary)
                }
            }
            Spacer(minLength: 16)
            if row.needsRelaunch {
                Text("Relaunch needed")
                    .font(Theme.settingsRowDetailFont)
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().strokeBorder(secondary))
            }
            if let value = row.value {
                Text(value)
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(secondary)
            }
            if row.isLifted {
                Image(systemName: "arrow.up.arrow.down")
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(secondary)
            }
            if row.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(Theme.settingsRowDetailFont.weight(.semibold))
                    .foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, Theme.settingsRowTextInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.settingsRowMinHeight, alignment: .leading)
    }

    /// The white highlight (L5: sliding with a namespace, else fading in place), scaled and shadowed with the
    /// content, or the parent's selected fill. It sits over the row's glass, so the glass never tints it.
    @ViewBuilder
    private var fill: some View {
        if isHighlighted {
            let highlight = shape.fill(Theme.focusedRowFill)
                .scaleEffect(scale)
                .shadow(color: .black.opacity(Theme.focusShadowOpacity), radius: Theme.focusShadowRadius,
                        y: Theme.focusShadowYOffset)
            if let highlightNamespace, style == .focused {
                highlight.matchedGeometryEffect(id: "focus", in: highlightNamespace)
            } else {
                highlight
            }
        } else if isMarkedSelected {
            shape.fill(Theme.settingsSelectedRowFill)
        } else if !isInfo {
            shape.fill(Theme.settingsRowCapsuleFill)
        }
    }
}

/// L4: action rows on glass (solid with Reduce Transparency, through `glassPanel`); info rows on a quiet fill.
private struct SettingsRowSurface: ViewModifier {
    let shape: SettingsRowShape
    let isInfo: Bool

    func body(content: Content) -> some View {
        if isInfo {
            content.background(Theme.settingsInfoRowFill, in: shape)
        } else {
            content.glassPanel(in: shape)
        }
    }
}

/// An SF Symbol or app icon for a row, or the page's accessory in the parent column (M7g L2).
struct RowImageView: View {
    let image: RowImage
    let launcher: AppLauncher
    let size: CGFloat
    var foreground: Color = Theme.primaryText
    /// M7 L25: for `.tileArt` and `.picture`.
    var tileArt: TileArtStore? = nil
    var items: [LaunchItem] = []

    var body: some View {
        switch image {
        case .picture(let url):
            if let preview = tileArt?.preview(of: url) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Theme.settingsRowThumbnailSize.width, height: Theme.settingsRowThumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                symbol("photo")
            }
        case .tileArt(let itemID, let choice):
            if let art = tileArtPreview(itemID: itemID, choice) {
                let radius = Theme.tileCornerRadius * Theme.settingsArtPreviewSize.width / Theme.tileSize.width
                TileArtView(art: art, size: Theme.settingsArtPreviewSize, cornerRadius: radius)
                    .glassRim(cornerRadius: radius)
            } else {
                symbol("photo")
            }
        case .symbol(let name):
            symbol(name)
        case .item(let item):
            if let icon = launcher.icon(for: item) {
                iconImage(icon)
            } else {
                symbol(item.iconSymbol ?? "app.dashed")
            }
        case .app(let url):
            iconImage(launcher.icon(forApplicationAt: url))
        case .qrCode(let string):
            if let qrCode = QRCodeImage.make(string) {
                qrCodeImage(qrCode)
            } else {
                symbol("qrcode")
            }
        }
    }

    private func tileArtPreview(itemID: String, _ choice: TileArtChoice) -> TileArt? {
        guard let tileArt, let item = items.first(where: { $0.id == itemID }) else { return nil }
        let icon = launcher.icon(for: item)
        let bundleID = launcher.bundleID(for: item)
        switch choice {
        case .current: return tileArt.art(for: item, icon: icon, bundleID: bundleID)
        case .style(let style): return tileArt.styledArt(for: item, icon: icon, bundleID: bundleID, style: style)
        case .file(let url): return tileArt.previewArt(of: url)
        }
    }

    /// Ignores `size`. White padding keeps the quiet zone the QR spec asks for.
    private func qrCodeImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(Theme.settingsQRCodeSize * 0.08)
            .frame(width: Theme.settingsQRCodeSize, height: Theme.settingsQRCodeSize)
            .background(RoundedRectangle(cornerRadius: 24).fill(.white))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
    }

    private func iconImage(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
