import SwiftUI

/// tvOS-style design tokens, in points on a 1920×1080 canvas.
/// The root view lays out on that canvas and scales it to the screen with `scaleEffect`.
enum Theme {
    // MARK: Canvas

    static let canvasSize = CGSize(width: 1920, height: 1080)

    static func scale(for size: CGSize) -> CGFloat {
        size.width / canvasSize.width
    }

    // MARK: Colors

    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), .black],
        startPoint: .top,
        endPoint: .bottom
    )
    /// The top of `backgroundGradient` fading to clear: keeps the clock legible over scrolled tiles (M7 L21).
    static let backgroundTopFade = LinearGradient(
        colors: [Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let tileFill = Color.white.opacity(0.12)
    static let focusHighlight = Color.white.opacity(0.3)
    static let focusHighlightWidth: CGFloat = 2

    // MARK: Typography

    static let clockFont = Font.title2
    /// M7f L7: the home clock (and the remote battery beside it), readable across the room.
    static let homeClockFont = Font.system(size: 38, weight: .medium)
    static let homeClockPadding = CGSize(width: 24, height: 10)
    /// The top of the home clock stack.
    static let homeClockTop: CGFloat = 60
    /// M7f L8: between the clock and the battery capsule.
    static let homeBatterySpacing: CGFloat = 12
    /// Below this percent the battery shows red and pulses.
    static let batteryLowThreshold = 15
    static let batteryLowColor = Color.red
    static let batteryPulseOpacity: Double = 0.35
    static let batteryPulseAnimation = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    /// M7c L28: between the clock and the version capsule under it.
    static let homeClockStackSpacing: CGFloat = 12
    static let tileTitleFont = Font.title3.weight(.medium)
    static let tileCaptionFont = Font.callout
    static let tileSymbolSize: CGFloat = 72

    // MARK: Layout

    // M7c L19 (D38): the tvOS 26 dock: six tiles in a row low on the screen, the next row peeking.
    static let tileSize = CGSize(width: 270, height: 162)   // 5:3
    static let tileCornerRadius: CGFloat = 16
    static let tileIconFraction: CGFloat = 0.6               // icon height / tile height
    static let tileSpacing: CGFloat = 36
    static let rowSpacing: CGFloat = 16
    static let sideMargin: CGFloat = 120
    /// The rows' side margin (six tiles fill the width).
    static let homeRowMargin: CGFloat = 60
    static let tilesPerRow = 6
    /// Row 0's top on the canvas; row 1 then peeks at the bottom edge.
    static let homeFirstRowTop: CGFloat = 800
    /// M7 L21: the tile title has a fixed height (hidden when unfocused), so every row has the same pitch.
    static let tileTitleHeight: CGFloat = 36
    /// Below the dock panel.
    static let tileTitleSpacing: CGFloat = 30
    /// Distance from one row's top to the next one's.
    static var tileRowPitch: CGFloat { tileSize.height + tileTitleSpacing + tileTitleHeight + rowSpacing }
    /// The glass dock behind row 0: inset from the screen edges, padding around the tiles, corner radius.
    static let homeDockInset: CGFloat = 30
    static let homeDockPadding: CGFloat = 20
    static let homeDockCornerRadius: CGFloat = 40
    /// With a later row focused, that row's top sits here (a grid; the row above stays visible).
    static let homeGridFocusTop: CGFloat = 520
    /// The hero (backdrop, preview video) dims to this in the grid.
    static let homeGridHeroOpacity: Double = 0.3
    /// Precise (trackpad) scroll distance that moves focus one row.
    static let homeScrollStep: CGFloat = 40
    static let homeClockFadeHeight: CGFloat = 200

    // MARK: Tile art (M7 L3, L4)

    static let youtubeArtTop = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
    static let youtubeArtBottom = Color(red: 0xB3 / 255, green: 0x00 / 255, blue: 0x1B / 255)
    static let liveTVArtTop = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
    static let liveTVArtBottom = Color(red: 0x00 / 255, green: 0x3A / 255, blue: 0x8C / 255)
    static let settingsArtTop = Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x66 / 255)
    static let settingsArtBottom = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    /// Exit to Desktop, `.url` tiles and apps without an icon.
    static let neutralArtTop = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
    static let neutralArtBottom = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    /// The white symbol on gradient art, as a fraction of the art's height.
    static let tileArtSymbolFraction: CGFloat = 0.45
    /// M7c step 16: a custom picture that isn't 5:3 shows whole over a blurred, dimmed copy of itself.
    static let tileArtFitBlur: CGFloat = 40
    static let tileArtFitDim: Double = 0.25
    /// The app icon on designed art (M7 L24), as a fraction of the art's height.
    static let designedArtIconFraction: CGFloat = 0.62
    /// M7c L33: glyph art draws the whole icon at this fraction of the art's height, then fades out its shape's
    /// edge (the rim, corners and shadow), so the glyph sits on the icon's own background filling the tile.
    static let glyphArtIconFraction: CGFloat = 0.95
    /// The kept part of the icon: a rounded square inset by this fraction of the icon's side on each side,
    /// with this corner radius and edge blur (fractions of the side). macOS 26 icon shapes fill about 10…90 %;
    /// some (Plex) have a rim reaching 14 %.
    static let glyphArtMaskInset: CGFloat = 0.15
    static let glyphArtMaskCornerRadius: CGFloat = 0.14
    static let glyphArtMaskBlur: CGFloat = 0.02
    /// Glyph art's icon is rasterized at this many pixels (the tile shows it at about 350 on a 4K TV).
    static let glyphArtIconPixels = 512
    /// M7c L33: a logo picture (transparent or plain edges) is inset by these fractions of the tile's width and height
    /// on each side, like tvOS's logo tiles.
    static let tileLogoInset = CGSize(width: 0.18, height: 0.2)
    /// Behind a transparent logo: dark for a light logo, light for a dark one.
    static let tileLogoDarkBackdrop = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let tileLogoLightBackdrop = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
    static let tileIconBackdropBlur: CGFloat = 40
    /// The icon backdrop's size as a multiple of the tile width.
    static let tileIconBackdropScale: CGFloat = 2.2
    static let tileIconBackdropDim: Double = 0.35
    /// Custom pictures are downsampled to this many pixels on the long side.
    static let tileArtMaxPixels = 1500
    /// Settings → Tile Art previews (M7 L25).
    static let tileArtPreviewPixels = 600
    static let settingsArtPreviewSize = CGSize(width: 500, height: 300)
    static let settingsRowThumbnailSize = CGSize(width: 80, height: 48)

    // MARK: Top shelf (M7 L12)

    static let shelfHeight: CGFloat = 440
    /// M7c L14: the Plex carousel advances this often (the router's default).
    static let carouselInterval: Duration = .seconds(8)
    static let carouselCrossfade = Animation.easeInOut(duration: 1.2)
    static let carouselIntervalSeconds = Double(carouselInterval.components.seconds)
    static let carouselZoom: CGFloat = 1.05
    static let carouselTitleFont = Font.system(size: 64, weight: .bold)
    static let carouselSubtitleFont = Font.system(size: 26)
    static let carouselLogoMaxSize = CGSize(width: 640, height: 200)
    static let carouselProgressWidth: CGFloat = 360
    static let carouselDotSize: CGFloat = 10
    static let carouselInfoMaxWidth: CGFloat = 900
    /// Backdrops and logos are decoded at up to this width (`ShelfImageLoader`'s large store).
    static let carouselImagePixelWidth = 1920
    /// M7c L20: the hero's text block, top-left; a scrim behind it; channel logos on Live TV pages; the page dots
    /// this far above the dock.
    static let carouselInfoOrigin = CGPoint(x: 120, y: 80)
    static let shelfInfoScrimOpacity: Double = 0.45
    static let shelfInfoScrimRadius: CGFloat = 1000
    static let carouselChannelLogoMaxSize = CGSize(width: 160, height: 80)
    static let carouselDotsAboveDock: CGFloat = 28
    /// M7c L22, L23: Select on live content animates the home UI away (the dock and rows slide down and fade, the
    /// text fades), then opens it; coming back, the dock slides up.
    static let homeExitDuration: Duration = .milliseconds(450)
    static let homeExitAnimation = Animation.easeIn(duration: 0.45)
    static let homeReturnAnimation = Animation.easeOut(duration: 0.35)
    static let homeExitSlide: CGFloat = 240
    /// L23: after an app launch the home UI comes back by itself if MMTVL is still active this long after.
    static let homeExitAppFallback: Duration = .seconds(3)
    /// M7c L15: the Live TV preview starts after this much focus; its video is revealed with this fade.
    static let previewDelay: Duration = .milliseconds(800)
    static let previewRevealAnimation = Animation.easeInOut(duration: 0.5)
    /// L16: no remote input for this long stops the preview.
    static let previewIdleTimeout: Duration = .seconds(600)
    /// M7m L18 (D51, burn-in): a still screen (home, Settings, the PIN screen, the power menu, Live TV with nothing
    /// moving) dims this long after the later of the last press and the screen becoming still...
    static let stillScreenDimAfter: Duration = .seconds(300)
    /// ...and asks for macOS's screen saver this long after dimming.
    static let screenSaverAfterDim: Duration = .seconds(300)
    /// M7m L20: how long `ScreenSaver.end()` waits for the declared user activity before terminating the engine.
    static let screenSaverEndCheckDelay: Duration = .seconds(1)
    /// M7m L19, L20: after a screen saver that no press ended stops (macOS ended it on a touch), the next press within
    /// this time is still swallowed: it's the press that woke the screen.
    static let screenSaverWakeGrace: Duration = .seconds(1)
    /// The dimmer: black at this opacity over everything, faded in and out with `idleDimAnimation`.
    static let idleDimOpacity: Double = 0.8
    static let idleDimAnimation = Animation.easeInOut(duration: 2)
    static let shelfCardSize = CGSize(width: 352, height: 198)
    static let shelfCardSpacing: CGFloat = 40
    static let shelfCardCornerRadius: CGFloat = 12
    static let shelfCardFill = Color.white.opacity(0.08)
    static let shelfTitleFont = Font.system(size: 30, weight: .semibold)
    static let shelfCaptionFont = Font.system(size: 24, weight: .medium)
    static let shelfDetailFont = Font.system(size: 20)
    static let shelfProgressHeight: CGFloat = 4
    static let shelfProgressFill = Color.white
    static let shelfProgressTrack = Color.white.opacity(0.25)
    /// The cards' title sits at this y; the cards at `shelfCardsTop`.
    static let shelfTitleTop: CGFloat = 96
    static let shelfCardsTop: CGFloat = 140
    static let shelfBannerBlur: CGFloat = 30
    static let shelfBannerDim: Double = 0.25
    static let shelfCrossfade = Animation.easeInOut(duration: 0.25)

    // MARK: Glass (M7 L26)

    static let glassCornerRadius: CGFloat = 28
    /// M7f L9: panels are clearer than `.regular`; the tint keeps text readable.
    /// Hard to read on the TV: raise the tint before going back to `.regular`.
    static let panelGlass = Glass.clear.tint(.black.opacity(0.22))
    static let glassRimWidth: CGFloat = 2
    static let glassRimTop: Double = 0.70
    static let glassRimMiddle: Double = 0.08
    static let glassRimBottom: Double = 0.32
    static let glassRimTopFocused: Double = 1.0
    static let glassRimBottomFocused: Double = 0.5
    static let glassSheen: Double = 0.14
    static let glassSheenFocused: Double = 0.24
    /// Reduce Transparency: panels without see-through.
    static let solidPanelFill = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255).opacity(0.92)

    // MARK: Glass steps (M7l L2, D46)

    // Settings → System → Glass. Clear is `panelGlass` and the rim tokens above, unscaled.
    // Solid has no panel glass (`solidPanelFill`); its scales are for tile rims.
    // Tuned on the TV: change the numbers, never the steps.
    static let glassLightTint: Double = 0.35
    static let glassLightPanel = Glass.clear.tint(.black.opacity(glassLightTint))
    static let glassLightRimScale: Double = 0.8
    static let glassLightSheenScale: Double = 0.7
    static let glassFrostedTint: Double = 0.22
    static let glassFrostedPanel = Glass.regular.tint(.black.opacity(glassFrostedTint))
    static let glassFrostedRimScale: Double = 0.6
    static let glassFrostedSheenScale: Double = 0.5
    static let glassDarkFrostedTint: Double = 0.45
    static let glassDarkFrostedPanel = Glass.regular.tint(.black.opacity(glassDarkFrostedTint))
    static let glassDarkFrostedRimScale: Double = 0.4
    static let glassDarkFrostedSheenScale: Double = 0.0
    static let glassSolidRimScale: Double = 0.3
    static let glassSolidSheenScale: Double = 0.0

    // MARK: Banner glass (M7l L1)

    /// The player's overlays (banner + timeshift bar, behind-live badge, error panel) sit over moving video:
    /// frosted and darker with a faint rim, never less so than Dark Frosted (tint ≥ `glassDarkFrostedTint`,
    /// rim ≤ `glassDarkFrostedRimScale`). Tuned on the TV (M7l step 8).
    static let bannerGlassTint: Double = 0.45
    static let bannerPanelGlass = Glass.regular.tint(.black.opacity(bannerGlassTint))
    static let bannerRimScale: Double = 0.4
    static let bannerSheenScale: Double = 0.0

    // MARK: Full-screen top shelf (M7 L27)

    /// The scrim over the art: transparent until this fraction of the height, then down to `shelfScrimOpacity`.
    static let shelfScrimStart: CGFloat = 0.45
    static let shelfScrimOpacity: Double = 0.75
    /// Darkens the art behind the clock.
    static let shelfClockScrimOpacity: Double = 0.35
    /// M7c L13: the designed art's accent glow (the backdrop no longer draws the app icon).
    static let shelfBackdropGlowRadius: CGFloat = 420
    static let shelfBackdropGlowCenter = CGPoint(x: 1440, y: 300)
    static let shelfBackdropCrossfade = Animation.easeInOut(duration: 0.35)
    /// Extra darkening of the art while cards show.
    static let shelfCardsDim: Double = 0.35

    // MARK: Focus

    static let focusScale: CGFloat = 1.1
    static let focusShadowRadius: CGFloat = 30
    static let focusShadowYOffset: CGFloat = 20
    static let focusShadowOpacity: Double = 0.5
    static let unavailableOpacity: Double = 0.4
    static let shakeDistance: CGFloat = 12

    // MARK: Move mode (M7m L8)

    /// The moving tile lifts this much above a focused one (1.1 × 1.06 ≈ 1.17).
    static let tileMoveLiftScale: CGFloat = 1.06
    /// Its wiggle: ± this many degrees, one full back-and-forth per `tileJiggleDuration`; none with Reduce Motion.
    static let tileJiggleAngle: Double = 1.5
    static let tileJiggleDuration: TimeInterval = 0.25
    /// "Arrows: move · Select: done", a glass capsule centered at the canvas's bottom edge, below row 0's titles.
    static let homeMoveHintFont = Font.system(size: 22, weight: .medium)
    static let homeMoveHintPadding = CGSize(width: 24, height: 8)
    static let homeMoveHintBottom: CGFloat = 10

    // MARK: Parallax (M7 L1)

    static let parallaxMaxDegrees: Double = 7
    /// The art's foreground layer moves this far at full tilt.
    static let parallaxLayerOffset: CGFloat = 8
    /// The tilt a tile starts with when focus arrives by an arrow (toward the side it came from).
    static let parallaxNudgeAmount: CGFloat = 0.6
    static let parallaxSpring = Animation.spring(response: 0.45, dampingFraction: 0.55)
    /// `parallaxSpring` for keyframes.
    static let parallaxKeyframeSpring = Spring(response: 0.45, dampingRatio: 0.55)
    static let parallaxPerspective: CGFloat = 0.6
    static let specularOpacity: Double = 0.35
    /// The specular radius as a fraction of the tile width.
    static let specularRadiusFraction: CGFloat = 0.9
    static let pressScale: CGFloat = 0.95

    // MARK: Settings

    // Literal sizes on purpose: the semantic macOS fonts are too small on the 1920-point TV canvas.
    static let settingsTitleFont = Font.system(size: 48, weight: .semibold)
    /// M7g L4: uppercase section headers, as on tvOS 27.
    static let settingsSectionFont = Font.system(size: 22, weight: .bold)
    static let settingsRowFont = Font.system(size: 30, weight: .medium)
    /// The PIN screen, YouTube and the Live TV menu (Settings' own rows use `settingsRowDetailFont`).
    static let settingsDetailFont = Font.system(size: 22)
    static let settingsHintFont = Font.system(size: 22)
    /// M7g: a Settings row's second line, its badges and chevron, and section footers.
    static let settingsRowDetailFont = Font.system(size: 24)

    /// M7g L3: the focused row's description in the band at the bottom.
    static let settingsDescriptionFont = Font.system(size: 28)

    /// M7g L1: the sliding column track. Two columns and the gap fill the canvas between the side margins.
    static let settingsColumnWidth: CGFloat = 840
    static let settingsColumnGap: CGFloat = 80
    static let settingsSideMargin: CGFloat = (canvasSize.width - 2 * settingsColumnWidth - settingsColumnGap) / 2
    /// M7g L1: the track's offset at the root, so the root column is centered on the canvas with nothing beside it.
    static let settingsRootColumnLeading: CGFloat = (canvasSize.width - settingsColumnWidth) / 2
    /// M7g L3: the band's reserved height, so the columns never move.
    static let settingsBandHeight: CGFloat = 104
    static let settingsBandMaxWidth: CGFloat = 1400
    /// M7g: the parent column (its opening row selected).
    static let settingsDimmedColumnOpacity: Double = 0.55
    /// M7g: the parent column's "you came from here" row.
    static let settingsSelectedRowFill = Color.white.opacity(0.4)
    /// M7g: under an action row's content, over its glass, so unfocused rows read as translucent gray, not black.
    static let settingsRowCapsuleFill = Color.white.opacity(0.075)
    /// M7g L4: info rows (no action) on a quiet fill instead of glass.
    static let settingsInfoRowFill = Color.white.opacity(0.05)
    /// A focused info row keeps its quiet fill and its colours and gets this white ring (`focusedRowFill`), never
    /// the action rows' white highlight, so it reads as information, not something to select.
    static let settingsInfoRowFocusRingWidth: CGFloat = 3
    /// M7g L2: a symbol accessory in the parent column (the learn prompt, or while a QR code loads).
    static let settingsAccessorySymbolSize: CGFloat = 240
    /// M7g L1: the track's slide when going deeper or back. Critically damped: it settles without overshoot.
    static let settingsPageAnimation = Animation.spring(response: 0.4, dampingFraction: 1)
    /// M7g: a column dimming or brightening when its role changes.
    static let settingsFadeAnimation = Animation.easeInOut(duration: 0.25)
    /// M7g step 7: replaced text and lists fade through (out quickly, then in), so the old and new never sit on
    /// top of each other: the title, the band, a replaced or previewed page.
    static let settingsFadeOutAnimation = Animation.easeOut(duration: 0.12)
    static let settingsFadeInAnimation = Animation.easeOut(duration: 0.22).delay(0.06)
    static let settingsFadeThrough = AnyTransition.asymmetric(
        insertion: .opacity.animation(settingsFadeInAnimation),
        removal: .opacity.animation(settingsFadeOutAnimation)
    )
    /// M7g step 7: a page leaving the screen with the slide (pushed off to the left, or popped off to the right)
    /// fades over most of the slide instead of vanishing as it starts to move.
    static let settingsLeaveFadeAnimation = Animation.easeIn(duration: 0.35)

    static let settingsRowMinHeight: CGFloat = 72
    /// M7g L4: rows with a second line; one-line rows are capsules.
    static let settingsRowCornerRadius: CGFloat = 40
    /// M7g: the list's top and bottom padding (room for the focused row's scale and shadow); the scrolled
    /// list fades out over it at the top and bottom.
    static let settingsListVerticalPadding: CGFloat = 32
    /// M7g L4: the row text's distance from the capsule's edge; section headers and footers line up with it.
    static let settingsRowTextInset: CGFloat = 32
    static let settingsRowSpacing: CGFloat = 8
    static let settingsSectionSpacing: CGFloat = 40
    static let settingsRowIconSize: CGFloat = 48
    /// The phone pairing QR code (M5); fits the side column and reads from the couch.
    static let settingsQRCodeSize: CGFloat = 440

    static let settingsRowFocusScale: CGFloat = 1.03
    static let focusedRowFill = Color.white
    static let focusedRowText = Color.black
    static let focusedRowSecondaryText = Color.black.opacity(0.6)

    // MARK: PIN (D20; layout after Google TV's privacy keypad)

    static let pinTitleFont = Font.system(size: 56, weight: .semibold)
    static let pinLabelFont = Font.system(size: 20, weight: .semibold)
    static let pinSlotWidth: CGFloat = 90
    static let pinSlotSpacing: CGFloat = 18
    static let pinSlotHeight: CGFloat = 4
    static let pinActiveSlotHeight: CGFloat = 6
    static let pinDialSize: CGFloat = 340
    static let pinDialDigitFont = Font.system(size: 48, weight: .regular)
    static let pinDialFill = Color.white
    static let pinDialText = Color.black.opacity(0.6)
    static let pinKeypadFont = Font.system(size: 30, weight: .semibold)
    static let pinKeypadColumnSpacing: CGFloat = 20
    static let pinKeypadRowSpacing: CGFloat = 24
    static let pinColumnSpacing: CGFloat = 80

    // MARK: Live TV player (M4)

    static let liveBannerTitleFont = Font.system(size: 40, weight: .semibold)
    static let liveBannerProgrammeFont = Font.system(size: 30, weight: .medium)
    static let liveBannerDetailFont = Font.system(size: 22)
    static let liveBannerLogoSize: CGFloat = 96
    static let liveBarHeight: CGFloat = 8
    static let liveOverlayGradient = LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)

    // MARK: Live TV guide (M4)

    static let guidePreviewRect = CGRect(x: 1160, y: 60, width: 640, height: 360)
    static let guideInfoRect = CGRect(x: 120, y: 60, width: 980, height: 360)
    static let guideGridTop: CGFloat = 460
    static let guideTimeHeaderHeight: CGFloat = 48
    static let guideRowHeight: CGFloat = 80
    /// Gap between cells and rows.
    static let guideCellSpacing: CGFloat = 4
    static let guideChannelColumnWidth: CGFloat = 340
    static let guideGridLeading: CGFloat = 472
    static let guideGridWidth: CGFloat = 1328
    static let guideGroupPanelWidth: CGFloat = 420
    static let guideInfoTitleFont = Font.system(size: 44, weight: .semibold)
    static let guideInfoDetailFont = Font.system(size: 24)
    static let guideCellFont = Font.system(size: 24, weight: .medium)
    static let guideCellTimeFont = Font.system(size: 18)
    static let guideChannelFont = Font.system(size: 24, weight: .medium)
    static let guideCellCornerRadius: CGFloat = 10
    static let guideNowLine = Color(red: 1, green: 0.27, blue: 0.23)
    static let guideLogoSize: CGFloat = 48
    /// The star after a favorite's name in the channel cell (M6b).
    static let guideFavoriteSymbolSize: CGFloat = 20
    /// M7l 8c: the channel number's slot in the channel cell; the Choose Teams row puts its symbol after it, where
    /// channel logos sit, so its title lines up with the channel names. M7j: 52 fits an antenna GuideNumber up to
    /// "99.99" (48.3 pt at `guideCellTimeFont` with tabular digits) and a four-digit playlist number (43.5 pt).
    static let guideChannelNumberWidth: CGFloat = 52
    /// M7j: a number wider than the slot (a five-digit playlist number, a three-digit minor) shrinks to this
    /// much at most, so it never truncates or pushes the name.
    static let guideChannelNumberMinimumScale: CGFloat = 0.8
    /// M7l 8c: the day and time slot that starts an upcoming game's cell ("Wed 12:30 PM" at `guideCellFont`).
    static let guideUpcomingTimeWidth: CGFloat = 220
    /// M7l 8c: the symbols in My Teams' Choose Teams and upcoming rows.
    static let guideRowSymbolSize: CGFloat = 26
    /// M7m L16 (D51, burn-in): no input in Live TV for this long closes its menus and search and takes the guide
    /// back to the playing channel (the picker back to Multiview); nothing happens while nothing plays.
    static let guideIdleReturn: Duration = .seconds(180)

    // MARK: Multiview (M6)

    static let multiviewGap = MultiviewLayout.gap
    static let multiviewDiagramSize = CGSize(width: 96, height: 54)
    /// The bold outline on the focused window, shown for `multiviewHighlightDuration` after each press (M7m L12).
    static let multiviewFocusBorder = Color.white
    static let multiviewFocusBorderWidth: CGFloat = 6
    /// M7m L12 (D51, burn-in): the bold outline (and the empty and failed windows' text, L14) fades this long after
    /// the last Multiview press, and when Multiview opens.
    static let multiviewHighlightDuration: Duration = .seconds(5)
    static let multiviewHighlightFade = Animation.easeOut(duration: 0.6)
    /// M7m L12, L13: the thin, faint outline that always marks the window with sound once the bold one is gone
    /// (replaces M6's speaker badge).
    static let multiviewRestingBorder = Color.white.opacity(0.4)
    static let multiviewRestingBorderWidth: CGFloat = 2
    /// M7m L15: while paused, the timeshift bar, the behind-live badge and Multiview's pause symbol hide this long
    /// after the last press.
    static let pausedOverlayDuration: Duration = .seconds(15)
    static let multiviewEmptySymbolSize: CGFloat = 48
    static let multiviewChipFont = Font.system(size: 26, weight: .semibold)
    static let multiviewChipDetailFont = Font.system(size: 20)

    // MARK: Live TV menus (M6)

    static let liveMenuWidth: CGFloat = 720
    /// Match Guide (M6b L10).
    static let liveMenuWideWidth: CGFloat = 1040
    static let liveMenuTitleFont = Font.system(size: 34, weight: .semibold)
    static let liveMenuRowHeight: CGFloat = 72
    static let liveMenuRowCornerRadius: CGFloat = 12
    /// The menu panel's padding, the space under its title and above its hint, and its rows' side padding
    /// (Live TV menus and the power menu, M7h L15).
    static let menuPanelPadding: CGFloat = 32
    static let menuTitleSpacing: CGFloat = 16
    static let menuRowPadding: CGFloat = 20
    /// Behind a menu: the screen dims (Live TV menus and the power menu).
    static let menuDim = Color.black.opacity(0.4)
    static let menuFadeAnimation = Animation.easeInOut(duration: 0.2)

    // MARK: On-screen keyboard (M7f L11)

    static let keyboardWidth: CGFloat = 600
    static let keyboardKeySpacing: CGFloat = 8
    static let keyboardKeyHeight: CGFloat = 64
    static let keyboardKeyCornerRadius: CGFloat = 12
    static let keyboardKeyFill = Color.white.opacity(0.08)
    static let keyboardKeyFont = Font.system(size: 30, weight: .medium)
    static let keyboardWideKeyFont = Font.system(size: 22, weight: .semibold)
    static let keyboardFocusedScale: CGFloat = 1.08
    static let keyboardFieldHeight: CGFloat = 72
    static let keyboardFieldFont = Font.system(size: 32, weight: .medium)
    static let keyboardFieldSpacing: CGFloat = 24

    // MARK: Live TV search (M7f L12)

    static let searchDim = Color.black.opacity(0.78)
    static let searchKeyboardOrigin = CGPoint(x: 120, y: 200)
    static let searchResultsRect = CGRect(x: 800, y: 200, width: 1000, height: 780)
    static let searchTitleTop: CGFloat = 80
    static let searchRowHeight: CGFloat = 84
    static let searchRowTitleFont = Font.system(size: 26, weight: .medium)
    static let searchRowDetailFont = Font.system(size: 20)

    // MARK: Toast (M7h L8)

    /// "Trackpad On", "Volume −20 dB": a glass capsule top-centre of the screen, over any app.
    static let toastFont = Font.system(size: 30, weight: .semibold)
    static let toastSymbolFont = Font.system(size: 30, weight: .semibold)
    static let toastSpacing: CGFloat = 16
    static let toastPadding = CGSize(width: 36, height: 20)
    /// The capsule's top on the canvas (level with the home clock).
    static let toastTop: CGFloat = 60
    /// The panel's height on the canvas: the capsule and room for its shadow.
    static let toastBandHeight: CGFloat = 200
    /// Inside the glass: the toast floats over any app, often a white web page, where `panelGlass` alone leaves
    /// white text at about 2.3:1; this brings it to about 4.5:1 and barely changes it over dark video.
    static let toastScrim = Color.black.opacity(0.3)
    static let toastShadowRadius: CGFloat = 24
    static let toastShadowOpacity: Double = 0.35
    static let toastDuration: Duration = .seconds(2)
    static let toastFadeInSeconds: TimeInterval = 0.2
    static let toastFadeOutSeconds: TimeInterval = 0.5
    /// A replacing message's text and symbol cross-fade.
    static let toastContentAnimation = Animation.easeInOut(duration: 0.15)

    // MARK: Animation

    static let focusAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// M7n L4: the guide's rows slide a row (or a page) per press; no bounce, and a spring picks up from where a held
    /// key's previous slide is, so fast repeats never lag behind the focus.
    static let guideScrollAnimation = Animation.spring(response: 0.22, dampingFraction: 1)
}
