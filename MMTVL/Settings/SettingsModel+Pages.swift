import Foundation

/// Builds the sections and rows for each Settings page.
extension SettingsModel {
    /// The top page's sections.
    var sections: [SettingsSection] { sections(for: page) }

    /// The top page's title.
    var pageTitle: String { title(for: page) }

    /// Pure: builders only read model state, so this is safe for pages that aren't on top (M7g).
    func sections(for page: SettingsPage) -> [SettingsSection] {
        switch page {
        case .root: rootSections
        case .homeScreen: homeScreenSections
        case .tile(let id): tileSections(id: id)
        case .addTile: addTileSections
        case .confirmRestoreDefaults: confirmRestoreSections
        case .confirmClearYouTube: confirmClearYouTubeSections
        case .liveTV: liveTVSections
        case .confirmRemoveIPTV: confirmRemoveIPTVSections
        case .guideSource(let id): guideSourceSections(id: id)
        case .iptvGroups: iptvGroupsSections
        case .iptvHiddenChannels: iptvHiddenChannelsSections
        case .iptvTeams: iptvTeamsSections
        case .iptvLeague(let league): iptvLeagueSections(league)
        case .iptvConference(let league, let conference): iptvConferenceSections(league, conference)
        case .phoneRemote: phoneRemoteSections
        case .pairPhone: pairPhoneSections
        case .confirmForgetPhones: confirmForgetPhonesSections
        case .remoteButtons: remoteButtonsSections
        case .remoteCommand(let command): remoteCommandSections(command)
        case .remoteBinding(let command, let trigger): remoteBindingSections(command, trigger)
        case .learnButton(let command): learnButtonSections(command)
        case .confirmLearn(let command, let trigger): confirmLearnSections(command, trigger)
        case .confirmRestoreButtons: confirmRestoreButtonsSections
        case .plex: plexSections
        case .plexLink: plexLinkSections
        case .tileArt(let id): tileArtSections(id: id)
        case .plexServers: plexServersSections
        case .confirmPlexSignOut: confirmPlexSignOutSections
        case .casting: castingSections
        case .youtube: youtubeSections
        case .remoteInput: remoteInputSections
        case .restrictions: restrictionsSections
        case .system: systemSections
        case .about: aboutSections
        case .siriRemote: siriRemoteSections
        case .audioTV: audioTVSections
        case .receiver: receiverSections
        case .tv: tvSections
        case .receiverBrand: receiverBrandSections
        case .receiverPort: receiverPortSections
        case .receiverMaxVolume: receiverMaxVolumeSections
        case .receiverFound: receiverFoundSections
        case .tvBrand: tvBrandSections
        case .receiverConnection: receiverConnectionSections
        case .addressEntry(let field): addressEntrySections(field)
        case .glassStyle: glassStyleSections
        case .antenna: antennaSections
        case .antennaChannels: antennaChannelsSections
        case .confirmAntennaScan: confirmAntennaScanSections
        case .confirmRestartMac: confirmRestartMacSections
        case .licenses: licensesSections
        case .license(let id): licenseSections(id: id)
        }
    }

    func title(for page: SettingsPage) -> String {
        switch page {
        case .root: "Settings"
        case .homeScreen: "Home Screen"
        case .tile(let id): item(id: id).map(environment.tileTitle) ?? "Tile"
        case .addTile: "Add Tile"
        case .confirmRestoreDefaults: "Restore Default Tiles?"
        case .confirmClearYouTube: "Sign Out of YouTube?"
        case .liveTV: "Live TV"
        case .confirmRemoveIPTV: "Remove Live TV Source?"
        case .guideSource(let id): guideSource(id: id)?.label ?? "Guide"
        case .iptvGroups: "Groups"
        case .iptvHiddenChannels: "Hidden Channels"
        case .iptvTeams: "My Teams"
        case .iptvLeague(let league): league.title
        case .iptvConference(_, let conference): conference
        case .phoneRemote: "Phone Remote"
        case .pairPhone: "Pair a Phone"
        case .confirmForgetPhones: "Forget All Phones?"
        case .remoteButtons: "Remote Buttons"
        case .remoteCommand(let command): command.title
        case .remoteBinding(_, let trigger): TriggerName.describe(trigger)
        case .learnButton: "Press a Button"
        case .confirmLearn(let command, let trigger): "Use \(TriggerName.describe(trigger)) for \(command.title)?"
        case .confirmRestoreButtons: "Restore Default Buttons?"
        case .plex: "Plex"
        case .plexLink: "Sign In to Plex"
        case .tileArt: "Tile Art"
        case .plexServers: "Plex Server"
        case .confirmPlexSignOut: "Sign Out of Plex?"
        case .casting: "Casting"
        case .youtube: "YouTube"
        case .remoteInput: "Remote & Input"
        case .restrictions: "Restrictions"
        case .system: "System"
        case .about: "About"
        case .siriRemote: "Siri Remote"
        case .audioTV: "Audio & TV"
        case .receiver: "Receiver"
        case .tv: "TV"
        case .receiverBrand: "Brand"
        case .receiverPort: "Serial Port"
        case .receiverMaxVolume: "Maximum Volume"
        case .receiverFound: "Receivers Found"
        case .tvBrand: "Brand"
        case .receiverConnection: "Connection"
        case .addressEntry(.receiver): "Receiver Address"
        case .addressEntry(.tv): "TV Address"
        case .glassStyle: "Glass"
        case .antenna: "Antenna"
        case .antennaChannels: "Channels"
        case .confirmAntennaScan: "Scan for Channels?"
        case .confirmRestartMac: "Restart Mac mini?"
        case .licenses: "Licenses"
        case .license(let id): ThirdPartyLicenses.component(id: id)?.name ?? "License"
        }
    }

    /// M7g L2: the working visual that replaces the parent column; nil for every other page.
    func accessory(for page: SettingsPage) -> RowImage? {
        switch page {
        case .pairPhone: phoneRemote.pairingURL.map(RowImage.qrCode) ?? .symbol("iphone")
        case .plexLink: plex.linkURL.map(RowImage.qrCode) ?? .symbol("play.square.stack")
        case .tileArt(let id): .tileArt(itemID: id, tileArtPreviewChoice)
        case .tile(let id): .tileArt(itemID: id, .current)
        case .learnButton: .symbol("hand.point.up.left")
        // MR step 4: the component's source and license, to scan with a phone.
        case .license(let id): ThirdPartyLicenses.component(id: id).map { RowImage.qrCode($0.url) }
        default: nil
        }
    }

    /// The band for a focused info row that has no description of its own.
    static let infoRowBandText = "Information only: nothing to change here."

    /// M7g L3: the description band: the mode hint, else the focused row's description (an info row without one:
    /// `infoRowBandText`), else nothing.
    var bandText: String? {
        if movingTileID != nil { return "Up/Down: move · Select or Back: done" }
        if case .learnButton = page { return "Waiting for a button…" }
        if case .addressEntry(let field) = page, isKeyboardFocused {
            let example = field == .tv ? "192.168.1.40 or tv.local" : "192.168.1.50 or receiver.local"
            let modeKey = keyboard.mode == .letters ? "123 switches to numbers" : "abc switches to letters"
            return "Type an address like \(example). \(modeKey), Play/Pause deletes, Down goes to Save."
        }
        guard let id = focusedRowID, let focused = row(id: id) else { return nil }
        if let description = focused.description { return description }
        return focused.action == nil ? Self.infoRowBandText : nil
    }

    private static func onOff(_ value: Bool) -> String { value ? "On" : "Off" }

    private static let kioskOnly = "Applies in kiosk mode only"

    /// M7g L6: categories only; each opens its page.
    private var rootSections: [SettingsSection] {
        [
            SettingsSection(id: "categories", rows: [
                SettingsRow(id: "homeScreen", title: "Home Screen", showsDisclosure: true, action: .push(.homeScreen),
                            description: "Arrange, hide and add tiles, and choose each tile's art and the tile MMTVL opens on."),
                SettingsRow(id: "liveTV", title: "Live TV",
                            // M7j: a tuner that was found counts as set up; its channels count too.
                            value: iptv.hasLiveSource ? Self.channelCount(iptv.channelCount + iptv.antennaChannels.count)
                                : "Not Set Up",
                            showsDisclosure: true, action: .push(.liveTV),
                            description: "The playlist, antenna and guides, channel groups, hidden channels, teams and the Home screen preview."),
                SettingsRow(id: "plex", title: "Plex", value: plex.isSignedIn ? "Signed In" : "Not Signed In",
                            showsDisclosure: true, action: .push(.plex),
                            description: "Continue Watching from your Plex server on the Home screen."),
                SettingsRow(id: "youtube", title: "YouTube", showsDisclosure: true, action: .push(.youtube),
                            description: "Reload YouTube, or sign every account out of it."),
                SettingsRow(id: "casting", title: "Casting", showsDisclosure: true, action: .push(.casting),
                            description: "Casting from the YouTube app, AirPlay from iPhones, Android mirroring through Reflector, and Plex HTPC."),
                SettingsRow(id: "audioTV", title: "Audio & TV", showsDisclosure: true, action: .push(.audioTV),
                            description: "The AV receiver for volume and power, the TV's power, and the volume display."),
                SettingsRow(id: "remoteInput", title: "Remote & Input", showsDisclosure: true,
                            action: .push(.remoteInput),
                            description: "The Siri Remote, remote buttons, game controllers, the pointer and the phone remote."),
                SettingsRow(id: "restrictions", title: "Restrictions", value: hasPIN ? "PIN On" : "PIN Off",
                            showsDisclosure: true, action: .push(.restrictions),
                            description: "The PIN, and keeping other apps from taking over the TV."),
                SettingsRow(id: "system", title: "System", showsDisclosure: true, action: .push(.system),
                            description: "Accessibility access, starting at login, glass, relaunching MMTVL, restarting the Mac and leaving to the desktop."),
                SettingsRow(id: "about", title: "About", value: environment.version.version, showsDisclosure: true,
                            action: .push(.about), description: "The version and build of MMTVL."),
                SettingsRow(id: "licenses", title: "Licenses", showsDisclosure: true, action: .push(.licenses),
                            description: "The licenses of MMTVL and the open-source software it includes."),
            ]),
        ]
    }

    private var remoteInputSections: [SettingsSection] {
        var globalInputDetail: String?
        if !environment.isKiosk {
            globalInputDetail = Self.kioskOnly
        } else if settings.globalInputEnabled && !isAccessibilityTrusted {
            globalInputDetail = "Needs Accessibility access"
        }
        return [
            SettingsSection(id: "input", rows: [
                SettingsRow(id: "globalInput", title: "Global Home & Media Keys",
                            value: Self.onOff(settings.globalInputEnabled), detail: globalInputDetail,
                            action: .toggle(.globalInputEnabled),
                            description: "Home and the media keys also work while another app is in front. Needs Accessibility access."),
                SettingsRow(id: "controllers", title: "Game Controllers",
                            value: Self.onOff(settings.controllersEnabled), action: .toggle(.controllersEnabled),
                            description: "Use game controllers as remotes."),
                SettingsRow(id: "siriRemote", title: "Siri Remote", value: siriRemoteValue, showsDisclosure: true,
                            action: .push(.siriRemote),
                            description: "MMTVL reads the Siri Remote itself: its buttons, swipes and trackpad mode."),
                SettingsRow(id: "remoteButtons", title: "Remote Buttons", showsDisclosure: true,
                            action: .push(.remoteButtons),
                            description: "See which buttons do what, and teach MMTVL the buttons of a new remote."),
                SettingsRow(id: "channelUp", title: "Channel Up",
                            value: settings.channelUpMovesUpList ? "Up the List" : "Higher Number",
                            action: .toggle(.channelUpMovesUpList),
                            description: "Changes channel in Live TV. Up the List moves up the list like the Up arrow; Higher Number goes to the next number."),
                SettingsRow(id: "cursorAutoHide", title: "Hide Pointer During Remote Use",
                            value: Self.onOff(settings.cursorAutoHide), action: .toggle(.cursorAutoHide),
                            description: "Hides the pointer while you use the remote. It comes back when the mouse moves."),
                SettingsRow(id: "phoneRemote", title: "Phone Remote", value: Self.onOff(settings.phoneRemoteEnabled),
                            showsDisclosure: true, action: .push(.phoneRemote),
                            description: "Control MMTVL and other apps from a phone's browser, with typing and a trackpad."),
            ]),
        ]
    }

    private var youtubeSections: [SettingsSection] {
        [
            SettingsSection(id: "youtube", rows: [
                SettingsRow(id: "youtube.reload", title: "Reload YouTube", action: .reloadYouTube,
                            description: "Reloads the YouTube page. Try this if YouTube stops responding."),
                SettingsRow(id: "youtube.clear", title: "Sign Out & Clear YouTube Data", showsDisclosure: true,
                            action: .push(.confirmClearYouTube),
                            description: "Signs every account out of YouTube on this Mac and deletes its watch data."),
            ], footer: "To keep kids in their own profile, set a Parent code in YouTube → Settings → Parent code."),
        ]
    }

    private var restrictionsSections: [SettingsSection] {
        [
            pinSection,
            SettingsSection(id: "otherApps", title: "Other Apps", rows: [
                SettingsRow(id: "kioskLock", title: "Keep Other Apps Out", value: Self.onOff(settings.kioskLock),
                            action: .toggle(.kioskLock),
                            description: "⌘Tab, Force Quit and other apps can't take over the TV, and ⌘Q asks for the PIN when one is set. Exit to Desktop is the way out."),
            ]),
        ]
    }

    private var systemSections: [SettingsSection] {
        let kiosk = environment.isKiosk
        var launchAtLoginDetail: String?
        if !kiosk {
            launchAtLoginDetail = Self.kioskOnly
        } else if settings.launchAtLogin && loginItemStatus == .requiresApproval {
            launchAtLoginDetail = "Waiting for approval in System Settings → General → Login Items"
        }

        var startupRows = [
            SettingsRow(id: "launchAtLogin", title: "Launch at Login", value: Self.onOff(settings.launchAtLogin),
                        detail: launchAtLoginDetail, action: .toggle(.launchAtLogin),
                        description: "Opens MMTVL when this Mac starts up."),
        ]
        if kiosk && settings.launchAtLogin && loginItemStatus == .requiresApproval {
            startupRows.append(SettingsRow(id: "approveLoginItem", title: "Open Login Items Settings",
                                           action: .openLoginItemsSettings,
                                           description: "macOS asks you to allow MMTVL in System Settings → General → Login Items."))
        }

        return [
            SettingsSection(id: "permissions", title: "Permissions", rows: [
                SettingsRow(id: "accessibility", title: "Accessibility",
                            value: isAccessibilityTrusted ? "Allowed" : "Not Allowed",
                            action: .requestAccessibility,
                            description: "Needed for Home in other apps, the media keys, full-screen apps and the phone remote in other apps."),
            ]),
            SettingsSection(id: "startup", title: "Startup", rows: startupRows),
            // M7l L3: app-wide, so on System rather than one screen's page.
            SettingsSection(id: "appearance", title: "Appearance", rows: [
                SettingsRow(id: "glass", title: "Glass", value: settings.glassStyle.title, showsDisclosure: true,
                            action: .push(.glassStyle),
                            description: "How see-through MMTVL's glass panels are."),
            ]),
            SettingsSection(id: "mmtvl", title: "MMTVL", rows: [
                SettingsRow(id: "relaunch", title: "Relaunch MMTVL", action: .relaunch,
                            description: "Quits and reopens MMTVL. Picks up changes made by hand to its settings files."),
                // M15 L17: worded like the power menu's, whatever the Mac is.
                SettingsRow(id: "restartMac", title: "Restart Mac mini", showsDisclosure: true,
                            action: .push(.confirmRestartMac),
                            description: "Restarts the Mac mini. Asks first."),
                SettingsRow(id: "exit", title: "Exit to Desktop", action: .exitToDesktop,
                            description: "Leaves MMTVL for the macOS desktop. Home brings MMTVL back."),
            ]),
        ]
    }

    /// M7c L28.
    private var aboutSections: [SettingsSection] {
        [
            SettingsSection(id: "about", rows: [
                SettingsRow(id: "about.version", title: "Version", value: environment.version.version),
                SettingsRow(id: "about.build", title: "Build", value: environment.version.build),
                SettingsRow(id: "about.showOnHome", title: "Show Version on Home",
                            value: Self.onOff(settings.showVersionOnHome), action: .toggle(.showVersionOnHome),
                            description: "Shows the version and build under the clock, for testing builds."),
            ], footer: "Settings are saved in ~/Library/Application Support/MMTVL"),
        ]
    }

    /// MR step 4: MMTVL first, then every shipped component by name.
    private var licensesSections: [SettingsSection] {
        let rows = ThirdPartyLicenses.all.map { component in
            SettingsRow(id: "license.\(component.id)", title: component.name, value: component.license,
                        detail: "Version \(component.version)", showsDisclosure: true,
                        action: .push(.license(id: component.id)))
        }
        return [SettingsSection(id: "licenses", rows: rows,
                                footer: "Full license texts and source links are in THIRD_PARTY_NOTICES.md inside MMTVL.app and at github.com/dwolcot1/mmtvl.")]
    }

    /// MR step 4: one component; its URL is the QR code beside the list. An unknown id shows only Done.
    private func licenseSections(id: String) -> [SettingsSection] {
        let done = SettingsRow(id: "license.done", title: "Done", action: .pop)
        guard let component = ThirdPartyLicenses.component(id: id) else {
            return [SettingsSection(id: "license", rows: [done])]
        }
        let source = component.url.hasPrefix("https://") ? String(component.url.dropFirst("https://".count))
            : component.url
        return [
            SettingsSection(id: "license", rows: [
                SettingsRow(id: "license.version", title: "Version", value: component.version),
                SettingsRow(id: "license.license", title: "License", value: component.license),
                SettingsRow(id: "license.copyright", title: component.copyright),
                SettingsRow(id: "license.source", title: "Source", value: source),
                done,
            ], footer: "Scan the code with a phone's camera to read the license and source."),
        ]
    }

    /// D20.
    private var pinSection: SettingsSection {
        let rows = hasPIN
            ? [
                SettingsRow(id: "pin.change", title: "Change PIN", action: .startPIN(.change),
                            description: "Choose a new PIN. You'll enter the current one first."),
                SettingsRow(id: "pin.off", title: "Turn Off PIN", action: .startPIN(.turnOff),
                            description: "Removes the PIN. Settings, Exit to Desktop and protected tiles open without it."),
            ]
            : [
                SettingsRow(id: "pin.set", title: "Set PIN", action: .startPIN(.setNew),
                            description: "A 4-digit PIN that guards Settings, Exit to Desktop and tiles set to Require PIN."),
            ]
        return SettingsSection(id: "pin", title: "PIN", rows: rows)
    }

    private var homeScreenSections: [SettingsSection] {
        let tileRows = items.map { item in
            var detail = item.kindDescription
            if !environment.isInstalled(item) { detail += " · Not installed" }
            if item.id == startTileID { detail += " · Start tile" }
            return SettingsRow(
                id: Self.tileRowID(item.id),
                title: environment.tileTitle(item),
                value: item.isVisible ? nil : "Hidden",
                detail: detail,
                image: .item(item),
                showsDisclosure: true,
                isDimmed: !item.isVisible,
                isLifted: movingTileID == item.id,
                action: .push(.tile(id: item.id))
            )
        }
        return [
            SettingsSection(id: "tiles", title: "Tiles", rows: tileRows,
                            footer: "Hidden tiles stay here but don't show on the Home screen."),
            SettingsSection(id: "manage", rows: [
                SettingsRow(id: "addTile", title: "Add Tile", showsDisclosure: true, action: .push(.addTile)),
                SettingsRow(id: "restoreDefaults", title: "Restore Default Tiles", showsDisclosure: true,
                            action: .push(.confirmRestoreDefaults)),
            ]),
        ]
    }

    private func tileSections(id: String) -> [SettingsSection] {
        guard let item = item(id: id) else { return [] }
        if item.isSettingsTile {
            return [SettingsSection(id: "options", rows: [
                startHereRow(item),
                tileArtRow(id: id),
                tileMoveRow(id: id),
            ], footer: "Settings is always on the Home screen and asks for the PIN when one is set.")]
        }
        var rows = [
            SettingsRow(id: "tile.visible", title: "Show on Home Screen", value: Self.onOff(item.isVisible),
                        action: .toggleTileVisible(id: id), description: "Show this tile on the Home screen."),
        ]
        if item.supportsFullScreen {
            rows.append(SettingsRow(id: "tile.fullScreen", title: "Open Full Screen",
                                    value: Self.onOff(item.wantsFullScreen),
                                    detail: isAccessibilityTrusted ? nil : "Needs Accessibility access",
                                    action: .toggleTileFullScreen(id: id), description: "Open the app full screen."))
        }
        if environment.webAppInfo(item) != nil {
            rows.append(contentsOf: startURLRows(item))
        }
        if !item.isExitToDesktop {
            rows.append(SettingsRow(id: "tile.requiresPIN", title: "Require PIN",
                                    value: Self.onOff(item.requiresPIN == true),
                                    detail: hasPIN ? nil : "Set a PIN in Settings first",
                                    action: .toggleTileRequiresPIN(id: id),
                                    description: "Ask for the PIN before opening."))
        }
        if !item.isExitToDesktop {
            rows.append(startHereRow(item))
        }
        rows.append(tileArtRow(id: id))
        rows.append(tileMoveRow(id: id))
        rows.append(SettingsRow(id: "tile.remove", title: "Remove from Home Screen", action: .removeTile(id: id),
                                description: "Removes the tile. Built-in tiles can be added back from Add Tile."))
        let footer = item.isExitToDesktop ? "Exit to Desktop always asks for the PIN when one is set." : nil
        return [SettingsSection(id: "options", rows: rows, footer: footer)]
    }

    /// M7c L32: the tile focused when MMTVL opens; a hidden start tile falls back to the first tile.
    var startTileID: String? {
        let visible = items.visible
        return visible.contains { $0.id == settings.homeStartTile } ? settings.homeStartTile : visible.first?.id
    }

    /// M7c L32.
    private func startHereRow(_ item: LaunchItem) -> SettingsRow {
        let isStart = item.id == startTileID
        return SettingsRow(id: "tile.start", title: "Start Here", value: isStart ? "On" : "Off",
                           detail: item.isVisible ? nil : "Show it on the Home screen first",
                           action: .setStartTile(id: item.id),
                           description: "MMTVL opens on this tile, and Home returns to it.")
    }

    private func tileMoveRow(id: String) -> SettingsRow {
        SettingsRow(id: "tile.move", title: "Move", action: .startMove(id: id),
                    description: "Move the tile with Up and Down.")
    }

    /// M7 L23: web app tiles only.
    private func startURLRows(_ item: LaunchItem) -> [SettingsRow] {
        var rows = [SettingsRow(id: "tile.startURL", title: "Start Page",
                                value: item.startURL.map(Self.startURLLabel) ?? "App's Own",
                                detail: startURLMessage ?? "Copy a page address on this Mac or your iPhone, then select",
                                action: .pasteTileStartURL(id: item.id))]
        if item.startURL != nil {
            rows.append(SettingsRow(id: "tile.startURL.clear", title: "Use the App's Own Start Page",
                                    action: .clearTileStartURL(id: item.id)))
        }
        return rows
    }

    /// Host + path (+ "?" + query), cut to 48 characters.
    static func startURLLabel(_ url: URL) -> String {
        var label = (url.host() ?? "") + url.path()
        if let query = url.query(), !query.isEmpty { label += "?" + query }
        return label.count > 48 ? String(label.prefix(47)) + "…" : label
    }

    /// M7 L3, L25: opens the Tile Art page.
    private func tileArtRow(id: String) -> SettingsRow {
        let value = environment.tileArtFileName(id)
            ?? (item(id: id)?.tileArtStyle == .icon ? "App Icon" : "Designed")
        return SettingsRow(id: "tile.art", title: "Tile Art", value: value, showsDisclosure: true,
                           action: .push(.tileArt(id: id)),
                           description: "Designed art, the app icon, or your own picture.")
    }

    /// L25: the style for apps; only designed art for built-ins and web addresses.
    private func offersIconStyle(_ item: LaunchItem) -> Bool {
        switch item.kind {
        case .application, .defaultBrowser: true
        case .url, .internalDestination, .system: false
        }
    }

    private func tileArtSections(id: String) -> [SettingsSection] {
        guard let item = item(id: id) else { return [] }
        let custom = environment.tileArtFileName(id)
        // M7c L33: choosing a style removes the picture, so no style shows as selected while one is in use.
        let styleDetail = custom == nil ? nil : "Removes your picture"
        let current = custom == nil ? item.tileArtStyle : nil
        var styleRows = [SettingsRow(id: "art.designed", title: "Designed",
                                     value: current == .designed ? "Selected" : nil, detail: styleDetail,
                                     action: .setTileArtStyle(id: id, .designed))]
        if offersIconStyle(item) {
            styleRows.append(SettingsRow(id: "art.icon", title: "App Icon",
                                         value: current == .icon ? "Selected" : nil, detail: styleDetail,
                                         action: .setTileArtStyle(id: id, .icon)))
        }
        var sections = [SettingsSection(id: "style", title: "Style", rows: styleRows)]
        if let custom {
            sections.append(SettingsSection(id: "custom", title: "Your Picture", rows: [
                SettingsRow(id: "art.custom", title: custom, value: "In Use"),
                SettingsRow(id: "art.removeCustom", title: "Remove Picture", action: .removeTileArtPicture(id: id)),
            ]))
        }
        var pictureRows: [SettingsRow]
        if let pictures {
            pictureRows = pictures.enumerated().map { index, file in
                SettingsRow(id: "art.file.\(index)", title: file.name, detail: PictureFinder.detail(file),
                            image: .picture(file.url), action: .useTileArtPicture(id: id, file.url))
            }
            if pictureRows.isEmpty {
                pictureRows.append(SettingsRow(id: "art.file.none", title: "No pictures in Downloads, Pictures or Desktop"))
            }
        } else {
            pictureRows = [SettingsRow(id: "art.file.loading", title: "Looking for pictures…")]
        }
        if let tileArtMessage {
            pictureRows.insert(SettingsRow(id: "art.message", title: tileArtMessage), at: 0)
        }
        sections.append(SettingsSection(id: "pictures", title: "Pictures on This Mac", rows: pictureRows,
                                        footer: "Logos on a plain or transparent background get padding and a matching color. "
                                            + "You can also put a picture named \(id).png in …/MMTVL/tile-art."))
        return sections
    }

    /// L25: the side column previews the focused option.
    private var tileArtPreviewChoice: TileArtChoice {
        guard let id = focusedRowID, let action = row(id: id)?.action else { return .current }
        switch action {
        case .setTileArtStyle(_, let style): return .style(style)
        case .useTileArtPicture(_, let url): return .file(url)
        default: return .current
        }
    }

    private var confirmRestoreSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.restore", title: "Restore Defaults", action: .restoreDefaults),
            ], footer: "Replaces every tile with the defaults. Added apps, hidden tiles and the order are reset."),
        ]
    }

    private var confirmClearYouTubeSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.clearYouTube", title: "Sign Out & Clear", action: .clearYouTubeData),
            ], footer: "Signs every account out of YouTube on this Mac and deletes its watch data. YouTube's Parent code may be removed too."),
        ]
    }

    /// "1 Channel", "185 Channels".
    private static func channelCount(_ count: Int) -> String {
        count == 1 ? "1 Channel" : "\(count.formatted()) Channels"
    }

    /// M4: the playlist and guide addresses come from the clipboard (L2).
    private var liveTVSections: [SettingsSection] {
        var playlistRows: [SettingsRow] = []
        if iptv.hasPlaylist {
            playlistRows.append(SettingsRow(id: "iptv.playlist.info", title: iptv.playlistHost ?? "Playlist",
                                            value: Self.channelCount(iptv.channelCount), detail: iptv.playlistLine))
        }
        playlistRows.append(SettingsRow(id: "iptv.playlist.paste",
                                        title: iptv.hasPlaylist ? "Replace with Clipboard URL" : "Paste Playlist URL",
                                        detail: pasteMessage(for: .playlist) ?? "Copy the M3U address on this Mac or your iPhone first",
                                        action: .pasteIPTVURL(.playlist)))
        var sections = [SettingsSection(id: "playlist", title: "Playlist", rows: playlistRows)]
        // M7j L13, L14: the antenna alone. The Antenna row always shows, so the antenna can be turned back on.
        guard iptv.hasLiveSource || settings.antennaEnabled else {
            sections.append(SettingsSection(id: "channels", title: "Channels", rows: [antennaRow]))
            return sections
        }
        // The antenna on, no playlist and no tuner found yet: the Channels section only.
        guard iptv.hasLiveSource else {
            sections.append(channelsSection)
            return sections
        }

        // M7j L11, L13: the guides, the preview and Refresh Now with a tuner alone too; only Remove is the playlist's.
        sections.append(guidesSection)
        sections.append(channelsSection)
        sections.append(SettingsSection(id: "homePreview", rows: [
            SettingsRow(id: "iptv.homePreview", title: "Preview on Home", value: Self.onOff(settings.homeLivePreview),
                        action: .toggle(.homeLivePreview),
                        description: "Loads the channel, muted, while the Home screen shows; you see it when Live TV is focused."),
        ]))
        var manageRows = [
            SettingsRow(id: "iptv.refresh", title: "Refresh Now", action: .refreshIPTV,
                        description: iptv.hasPlaylist ? "Downloads the playlist and the guides again now."
                            : "Reads the tuner's channels and downloads the guides again now."),
        ]
        if iptv.hasPlaylist {
            manageRows.append(SettingsRow(id: "iptv.remove", title: "Remove Live TV Source", showsDisclosure: true,
                                          action: .push(.confirmRemoveIPTV)))
        }
        sections.append(SettingsSection(id: "manage", rows: manageRows,
                                        footer: "Addresses are kept in the Keychain. The first paste may ask for permission; choose Allow."))
        return sections
    }

    private func pasteMessage(for kind: IPTVURLKind) -> String? {
        pasteMessageKind == kind ? pasteMessage : nil
    }

    private func guideSource(id: String) -> IPTVSettingsStatus.GuideSourceStatus? {
        iptv.guideSources.first { $0.id == id }
    }

    /// M6b L1: the guides in priority order; pasted ones open their own page.
    private var guidesSection: SettingsSection {
        var rows: [SettingsRow] = []
        // M7f L4: a choice only when the playlist names a guide and one is pasted.
        if iptv.playlistNamesGuide && iptv.customGuideCount > 0 {
            rows.append(SettingsRow(id: "iptv.guideSource", title: "Guide Source",
                                    value: settings.usePlaylistGuide ? "Playlist" : "Pasted Guides",
                                    action: .toggle(.usePlaylistGuide),
                                    description: "Use the guide the playlist names, or your pasted guides. Your pasted guides are kept either way."))
        }
        rows += iptv.guideSources.enumerated().map { index, source in
            SettingsRow(id: "iptv.guide.\(source.id)", title: source.label,
                        value: source.isFromPlaylist ? "From Playlist" : source.isInUse ? "\(index + 1)" : "Off",
                        detail: source.line, showsDisclosure: !source.isFromPlaylist, isDimmed: !source.isInUse,
                        action: source.isFromPlaylist ? nil : .push(.guideSource(id: source.id)))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "iptv.guide.none", title: "No guide",
                                    detail: "Copy an XMLTV guide address, then add it below"))
        }
        if iptv.customGuideCount < IPTVLibrary.maxGuideSources {
            rows.append(SettingsRow(id: "iptv.guide.add", title: "Add Guide from Clipboard",
                                    detail: pasteMessage(for: .guide) ?? "Copy an XMLTV address on this Mac or your iPhone first",
                                    action: .pasteIPTVURL(.guide)))
        }
        // M7j: the count is the playlist's (step 8); a tuner alone has its own guide line on the Antenna page.
        let count = iptv.hasPlaylist ? "Guide data for \(iptv.matchedChannelCount) of \(iptv.channelCount) channels. " : ""
        return SettingsSection(id: "guides", title: "Guides", rows: rows,
                               footer: count + "A channel uses the first guide in this list that has it.")
    }

    /// M6b L5: groups and hidden channels; favorites and single channels are managed from the guide.
    private var channelsSection: SettingsSection {
        let hiddenGroups = iptv.groups.filter(\.isHidden).count
        return SettingsSection(id: "channels", title: "Channels", rows: [
            antennaRow,
            SettingsRow(id: "iptv.groups", title: "Groups", value: hiddenGroups == 0 ? "All Shown" : "\(hiddenGroups) Hidden",
                        showsDisclosure: true, action: .push(.iptvGroups), description: "Which groups show in the guide."),
            SettingsRow(id: "iptv.hiddenChannels", title: "Hidden Channels",
                        value: iptv.hiddenChannels.isEmpty ? "None" : "\(iptv.hiddenChannels.count)",
                        showsDisclosure: true, action: .push(.iptvHiddenChannels),
                        description: "Channels hidden from the guide."),
            SettingsRow(id: "iptv.teams", title: "My Teams", value: Self.teamCountLabel(iptv.teams.count),
                        showsDisclosure: true, action: .push(.iptvTeams),
                        description: "Your teams' live and upcoming games, pro and college, in the guide's My Teams group."),
        ], footer: "To favorite, hide or match one channel: in the guide, press Left on the programme airing now, then Select.")
    }

    // MARK: - Antenna (M7j L14)

    /// Live TV → Antenna: "1 Tuner · 185 Channels", "Searching…", "No Tuner Found", "Off".
    private var antennaRow: SettingsRow {
        let value: String
        if !settings.antennaEnabled {
            value = "Off"
        } else if !iptv.antennaTuners.isEmpty {
            let tuners = iptv.antennaTuners.count
            value = "\(tuners) \(tuners == 1 ? "Tuner" : "Tuners") · \(Self.channelCount(iptv.antennaChannels.count))"
        } else if iptv.antennaSearching {
            value = "Searching…"
        } else {
            value = "No Tuner Found"
        }
        return SettingsRow(id: "iptv.antenna", title: "Antenna", value: value, showsDisclosure: true,
                           action: .push(.antenna), description: "Channels from an HDHomeRun tuner on your network.")
    }

    /// The tuners, Find Tuners, the antenna guide and the channels; only the switch while the antenna is off. Never a
    /// DeviceID, address or token: the status has none.
    private var antennaSections: [SettingsSection] {
        var sections = [SettingsSection(id: "antenna", title: "Antenna", rows: [
            SettingsRow(id: "antenna.enabled", title: "Use Antenna", value: Self.onOff(settings.antennaEnabled),
                        action: .toggle(.antennaEnabled),
                        description: "Finds HDHomeRun tuners on your network and adds their channels to Live TV's Antenna group."),
        ])]
        guard settings.antennaEnabled else { return sections }

        var tunerRows = iptv.antennaTuners.enumerated().map { index, tuner in
            SettingsRow(id: "antenna.tuner.\(index)", title: tuner.name,
                        value: tuner.tunerCount == 1 ? "1 tuner" : "\(tuner.tunerCount) tuners",
                        detail: "\(tuner.model) · \(iptv.antennaLineupLine ?? Self.antennaChannelCount(tuner.channelCount))")
        }
        let searchLine = iptv.antennaTuners.isEmpty
            ? (iptv.antennaSearching ? "Searching…" : SettingsModel.antennaFindLine(.noneFound)) : nil
        tunerRows.append(SettingsRow(id: "antenna.find", title: "Find Tuners",
                                     detail: probeLines[.findAntennaTuners] ?? searchLine, action: .findAntennaTuners,
                                     description: "Looks for HDHomeRun tuners on your network again."))
        if !iptv.antennaTuners.isEmpty { tunerRows.append(antennaScanRow) }
        sections.append(SettingsSection(id: "antennaTuners", title: "Tuners", rows: tunerRows))

        sections.append(SettingsSection(id: "antennaGuide", title: "Guide", rows: [
            SettingsRow(id: "antenna.guide", title: "Guide from SiliconDust", value: Self.onOff(settings.antennaGuide),
                        action: .toggle(.antennaGuide),
                        description: "Downloads 2 days of listings from SiliconDust (api.hdhomerun.com) about once a day, signed in with your tuner. Off: antenna channels use your pasted guides."),
            SettingsRow(id: "antenna.guide.status", title: "Status",
                        detail: settings.antennaGuide ? iptv.antennaGuideLine : "Off"),
        ]))

        let hidden = iptv.antennaChannels.count(where: \.isHidden)
        var footer = "Channels come from the tuner's lineup. After moving the antenna, Scan for Channels finds them again."
        switch iptv.antennaLeftOut {
        case 0: break
        case 1: footer += " 1 protected channel can't play and is left out."
        case let count: footer += " \(count) protected channels can't play and are left out."
        }
        sections.append(SettingsSection(id: "antennaChannels", title: "Channels", rows: [
            SettingsRow(id: "antenna.channels", title: "Channels",
                        value: hidden == 0 ? "\(iptv.antennaChannels.count) Shown" : "\(hidden) Hidden",
                        showsDisclosure: true, action: .push(.antennaChannels),
                        description: "Show or hide each antenna channel."),
        ], footer: footer))
        return sections
    }

    /// M7j L18: Scan for Channels (the confirm page), or Stop Scan while a scan runs ("45 %", "Scanning… 120 found").
    /// Dimmed with "The tuner can't scan now" when no tuner can: then an info row, Select does nothing (security L2).
    private var antennaScanRow: SettingsRow {
        if case .running(let progress, let found) = iptv.antennaScan {
            return SettingsRow(id: "antenna.scan", title: "Stop Scan", value: "\(progress) %",
                               detail: "Scanning… \(found.formatted()) found", action: .stopAntennaScan,
                               description: "Stops the tuner's channel scan now.")
        }
        return SettingsRow(id: "antenna.scan", title: "Scan for Channels",
                           detail: Self.antennaScanLine(iptv.antennaScan, canScan: iptv.antennaCanScan),
                           showsDisclosure: iptv.antennaCanScan, isDimmed: !iptv.antennaCanScan,
                           action: iptv.antennaCanScan ? .push(.confirmAntennaScan) : nil,
                           description: "Has the tuner look for channels again, for a few minutes.")
    }

    /// M7j L18: the Scan for Channels row's detail when no scan runs.
    static func antennaScanLine(_ scan: AntennaScanState?, canScan: Bool) -> String? {
        if !canScan { return "The tuner can't scan now" }
        switch scan {
        case .finished(let found, let added, let removed):
            let channels = found == 1 ? "1 channel" : "\(found.formatted()) channels"
            return "Found \(channels): \(added.formatted()) new, \(removed.formatted()) gone"
        case .stopped: return "Scan stopped"
        case .failed: return "Scan failed"
        case .running, nil: return nil
        }
    }

    /// M7j L18: like Remove Live TV Source, Cancel first.
    private var confirmAntennaScanSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.scan", title: "Scan", action: .startAntennaScan),
            ], footer: "The tuner looks for channels for a few minutes. Antenna channels can't play meanwhile, here or on other devices. Channels it doesn't find are removed from the tuner's lineup."),
        ]
    }

    /// M15 step 1: like Scan for Channels, Cancel first. No second PIN: Settings is already behind it.
    private var confirmRestartMacSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.restartMac", title: "Restart Mac mini", action: .restartMac),
            ], footer: "Other apps are asked to quit first. With Launch at Login on, MMTVL opens again after the restart."),
        ]
    }

    /// "1 channel", "185 channels".
    private static func antennaChannelCount(_ count: Int) -> String {
        count == 1 ? "1 channel" : "\(count.formatted()) channels"
    }

    /// One row per antenna channel: "5.1  WAGA-HD", Shown or Hidden, "HD · Signal 100 %" (the parts the tuner gives).
    private var antennaChannelsSections: [SettingsSection] {
        var rows = iptv.antennaChannels.map { channel in
            let parts = [channel.isHD ? "HD" : nil, channel.signalQuality.map { "Signal \($0) %" }].compactMap { $0 }
            return SettingsRow(id: "antennaChannel.\(channel.id)", title: "\(channel.displayNumber)  \(channel.name)",
                               value: channel.isHidden ? "Hidden" : "Shown",
                               detail: parts.isEmpty ? nil : parts.joined(separator: " · "), isDimmed: channel.isHidden,
                               action: .toggleChannelHidden(id: channel.id))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "antennaChannel.none", title: "No antenna channels"))
        }
        // QA 3: each row keeps its own Shown/Hidden; the footer says the whole group is hidden.
        let groupHidden = iptv.groups.contains { $0.name == AntennaLineup.group && $0.isHidden }
        return [SettingsSection(id: "antennaChannelList", rows: rows,
                                footer: groupHidden ? "The Antenna group is hidden in Live TV → Groups, so none of these channels show." : nil)]
    }

    private var iptvGroupsSections: [SettingsSection] {
        let rows = iptv.groups.map { group in
            SettingsRow(id: "group.\(group.name)", title: group.name, value: group.isHidden ? "Hidden" : "Shown",
                        detail: "\(group.channelCount) channels", isDimmed: group.isHidden,
                        action: .toggleIPTVGroupHidden(group.name))
        }
        return [SettingsSection(id: "groups", rows: rows,
                                footer: "Hidden groups and their channels don't show in the guide or when changing channels.")]
    }

    /// M7f L13: "None", "1 Team", "3 Teams".
    static func teamCountLabel(_ count: Int) -> String {
        switch count {
        case 0: "None"
        case 1: "1 Team"
        default: "\(count) Teams"
        }
    }

    /// M7f L13, M7l L13: Pro and College sections, one row per league, with how many of its teams are picked.
    private var iptvTeamsSections: [SettingsSection] {
        let picked = Set(iptv.teams)
        func rows(_ leagues: [TeamLeague]) -> [SettingsRow] {
            leagues.map { league in
                let count = TeamCatalog.teams(in: league).count { picked.contains($0.id) }
                return SettingsRow(id: "league.\(league.rawValue)", title: league.title, value: Self.onCountLabel(count),
                                   showsDisclosure: true, action: .push(.iptvLeague(league)))
            }
        }
        return [
            SettingsSection(id: "leagues.pro", title: "Pro", rows: rows(TeamLeague.allCases.filter { !$0.isCollege })),
            SettingsSection(id: "leagues.college", title: "College", rows: rows(TeamLeague.allCases.filter(\.isCollege)),
                            footer: "The guide's My Teams group shows your teams' live games, the channels showing them now, and their games in the next 3 days."),
            // M7m L29.
            SettingsSection(id: "matching", title: "Matching", rows: [
                SettingsRow(id: "teams.matchInitials", title: "Match Initials", value: Self.onOff(settings.teamMatchInitials),
                            action: .toggle(.teamMatchInitials),
                            description: "Games named with initials, such as ULM or BYU, count for your teams. Some initials are also pro teams' (BUF, MIA), so other games may show."),
                SettingsRow(id: "teams.matchNicknames", title: "Match Nicknames Alone",
                            value: Self.onOff(settings.teamMatchNicknames), action: .toggle(.teamMatchNicknames),
                            description: "A game that names only a nickname, such as \"The Cougars meet the Bearcats\", counts for your teams with that nickname, narrowed by the school or conference when the guide names one."),
            ], footer: "Spelled-out names, such as Louisiana-Monroe or Brigham Young, always count."),
        ]
    }

    /// M7l L13: "3 On" when any are picked, else nothing.
    static func onCountLabel(_ count: Int) -> String? {
        count == 0 ? nil : "\(count) On"
    }

    /// A pro league's teams; a college league's conferences (M7l L13).
    private func iptvLeagueSections(_ league: TeamLeague) -> [SettingsSection] {
        let picked = Set(iptv.teams)
        guard league.isCollege else {
            return [SettingsSection(id: "teams", rows: teamRows(TeamCatalog.teams(in: league), picked: picked),
                                    footer: "Select a team to add or remove it.")]
        }
        let rows = TeamCatalog.conferences(in: league).map { conference in
            let count = TeamCatalog.teams(in: league, conference: conference).count { picked.contains($0.id) }
            return SettingsRow(id: "conference.\(league.rawValue).\(conference)", title: conference,
                               value: Self.onCountLabel(count), showsDisclosure: true,
                               action: .push(.iptvConference(league, conference)))
        }
        return [SettingsSection(id: "conferences", rows: rows)]
    }

    /// M7l L13: one college conference's teams.
    private func iptvConferenceSections(_ league: TeamLeague, _ conference: String) -> [SettingsSection] {
        let teams = TeamCatalog.teams(in: league, conference: conference)
        return [SettingsSection(id: "teams", rows: teamRows(teams, picked: Set(iptv.teams)),
                                footer: "Select a team to add or remove it.")]
    }

    private func teamRows(_ teams: [Team], picked: Set<Team.ID>) -> [SettingsRow] {
        teams.map { team in
            SettingsRow(id: "team.\(team.id)", title: team.name, value: picked.contains(team.id) ? "On" : nil,
                        action: .toggleTeam(id: team.id))
        }
    }

    private var iptvHiddenChannelsSections: [SettingsSection] {
        var rows = iptv.hiddenChannels.map { channel in
            SettingsRow(id: "hidden.\(channel.id)", title: "\(channel.displayNumber)  \(channel.name)", value: "Show",
                        detail: channel.group, action: .unhideIPTVChannel(id: channel.id))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "hidden.none", title: "No hidden channels"))
        }
        return [SettingsSection(id: "hiddenChannels", rows: rows, footer: "Select a channel to show it again.")]
    }

    /// M6b: one pasted guide.
    private func guideSourceSections(id: String) -> [SettingsSection] {
        let pasted = iptv.guideSources.filter { !$0.isFromPlaylist }
        guard let index = pasted.firstIndex(where: { $0.id == id }) else { return [] }
        var rows = [SettingsRow(id: "guideSource.status", title: "Status", detail: pasted[index].line)]
        if index > 0 {
            rows.append(SettingsRow(id: "guideSource.moveUp", title: "Move Up", action: .moveGuideSource(id: id, by: -1)))
        }
        if index < pasted.count - 1 {
            rows.append(SettingsRow(id: "guideSource.moveDown", title: "Move Down", action: .moveGuideSource(id: id, by: 1)))
        }
        rows.append(SettingsRow(id: "guideSource.remove", title: "Remove Guide", action: .removeGuideSource(id: id)))
        return [SettingsSection(id: "guideSource", rows: rows,
                                footer: "When two guides have the same channel, the higher one wins.")]
    }

    private var confirmRemoveIPTVSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.removeIPTV", title: "Remove", action: .removeIPTVSource),
            ], footer: "Forgets the playlist and guide addresses and deletes the downloaded guide."),
        ]
    }

    /// M5.
    private var phoneRemoteSections: [SettingsSection] {
        var serverRows = [
            SettingsRow(id: "phone.enabled", title: "Phone Remote", value: Self.onOff(settings.phoneRemoteEnabled),
                        detail: phoneRemote.problem, action: .toggle(.phoneRemoteEnabled),
                        description: "Serves the phone remote's page on this Mac's network address."),
        ]
        if settings.phoneRemoteEnabled {
            serverRows.append(SettingsRow(id: "phone.address", title: "Address",
                                          value: phoneRemote.address ?? "No network connection"))
            if phoneRemote.isRunning {
                serverRows.append(SettingsRow(id: "phone.pair", title: "Pair a Phone", showsDisclosure: true,
                                              action: .push(.pairPhone)))
            }
        }

        var phoneRows = [
            SettingsRow(id: "phone.count", title: "Paired Phones", value: "\(phoneRemote.pairedCount)",
                        detail: phoneRemote.connectedCount > 0 ? "\(phoneRemote.connectedCount) connected now" : nil),
        ]
        if phoneRemote.pairedCount > 0 {
            phoneRows.append(SettingsRow(id: "phone.forget", title: "Forget All Phones", showsDisclosure: true,
                                         action: .push(.confirmForgetPhones)))
        }

        return [
            SettingsSection(id: "phone.server", rows: serverRows,
                            footer: "Open the address in the phone's browser. The phone must be on the same network as this Mac."),
            SettingsSection(id: "phone.phones", title: "Phones", rows: phoneRows),
            SettingsSection(id: "phone.access", title: "Typing & Other Apps", rows: [
                SettingsRow(id: "phone.accessibility", title: "Accessibility",
                            value: phoneRemote.canControlOtherApps ? "Allowed" : "Not Allowed",
                            action: .requestAccessibility,
                            description: "Needed to type from the phone and to control Plex, Prime Video and the browser."),
            ], footer: "Volume buttons use SoundSource when it's running, else the Mac's volume when the output allows it, else MMTVL's own volume."),
        ]
    }

    /// M5 L3: the code is valid while this page shows.
    private var pairPhoneSections: [SettingsSection] {
        if phoneRemote.pairingEnded {
            return [
                SettingsSection(id: "pair", rows: [
                    SettingsRow(id: "pair.ended", title: "Pairing Ended", detail: "Pairing timed out",
                                image: .symbol("exclamationmark.triangle")),
                    SettingsRow(id: "pair.close", title: "Done", action: .pop),
                ], footer: "To pair a phone, go back and open Pair a Phone again."),
            ]
        }
        var rows: [SettingsRow]
        if phoneRemote.pairingCodeLocked {
            // Re-review L1: too many wrong codes turn the typed code off; the QR code (the secret) still pairs.
            rows = [
                SettingsRow(id: "pair.locked", title: "Pairing Code Off",
                            detail: "Too many wrong codes were entered. Scan the QR code with the phone's camera",
                            image: .symbol("exclamationmark.triangle")),
            ]
        } else {
            rows = [
                SettingsRow(id: "pair.code", title: "Pairing Code", value: phoneRemote.pairingCode ?? "—"),
                SettingsRow(id: "pair.address", title: phoneRemote.address ?? "No network connection",
                            detail: "Or open this address on the phone and enter the code"),
            ]
        }
        if let name = phoneRemote.lastPairedName {
            rows.append(SettingsRow(id: "pair.done", title: "Paired \"\(name)\"", image: .symbol("checkmark.circle")))
        }
        rows.append(SettingsRow(id: "pair.close", title: "Done", action: .pop))
        return [
            SettingsSection(id: "pair", rows: rows,
                            footer: "Scan the code with the phone's camera. Pairing ends when you leave this page."),
        ]
    }

    private var confirmForgetPhonesSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.forget", title: "Forget All Phones", action: .forgetAllPhones),
            ], footer: "Every phone will need to pair again."),
        ]
    }

    private var addTileSections: [SettingsSection] {
        var sections: [SettingsSection] = []
        let missing = items.missingDefaults
        if !missing.isEmpty {
            sections.append(SettingsSection(id: "builtIn", title: "MMTVL", rows: missing.map { item in
                SettingsRow(id: "add.default.\(item.id)", title: environment.tileTitle(item), image: .item(item),
                            action: .addDefaultTile(id: item.id))
            }))
        }

        let appRows: [SettingsRow]
        if let installedApps {
            let taken = items.applicationBundleIDs.union(missing.applicationBundleIDs)
            let rows = installedApps.filter { !taken.contains($0.bundleID) }.map { app in
                SettingsRow(id: "add.app.\(app.bundleID)", title: app.name, image: .app(app.url), action: .addApp(app))
            }
            appRows = rows.isEmpty ? [SettingsRow(id: "apps.none", title: "No other apps found")] : rows
        } else {
            appRows = [SettingsRow(id: "apps.loading", title: "Loading…")]
        }
        sections.append(SettingsSection(id: "apps", title: "Applications", rows: appRows))
        return sections
    }

    // MARK: - Remote Buttons (M7, D27)

    private var remoteButtonsSections: [SettingsSection] {
        // M7h (user decision U2, 2026-11-06): Power Menu can have buttons too; holding the Siri Remote's Power button
        // opens it whatever they are.
        let rows = Self.listedCommands.map { command in
            let names = bindings.bindings(for: command).map { TriggerName.describe($0.trigger) }
            var value = names.prefix(2).joined(separator: " · ")
            if names.count > 2 { value += " +\(names.count - 2)" }
            return SettingsRow(id: "command.\(command.rawValue)", title: command.title, value: names.isEmpty ? "None" : value,
                               showsDisclosure: true, action: .push(.remoteCommand(command)))
        }
        return [
            SettingsSection(id: "commands", title: "Commands", rows: rows,
                            footer: "Holding the Siri Remote's Power button also opens the power menu, and holding its centre opens the menu (a right click in trackpad mode)."),
            SettingsSection(id: "manage", rows: [
                SettingsRow(id: "restoreButtons", title: "Restore Default Buttons", showsDisclosure: true,
                            action: .push(.confirmRestoreButtons)),
            ], footer: "Buttons apply at once. Phone remote buttons can't be changed."),
        ]
    }

    /// The Remote Buttons rows: every command (M7h U2: Power Menu again, step 11 had left it out).
    static let listedCommands = RemoteCommand.allCases

    private func remoteCommandSections(_ command: RemoteCommand) -> [SettingsSection] {
        var rows = bindings.bindings(for: command).enumerated().map { index, binding in
            var detail = TriggerName.kind(binding.trigger)
            if binding.isGlobal { detail += " · Works in other apps" }
            return SettingsRow(id: "binding.\(index)", title: TriggerName.describe(binding.trigger), detail: detail,
                               showsDisclosure: true, action: .push(.remoteBinding(command, binding.trigger)))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "binding.none", title: "No buttons"))
        }
        rows.append(SettingsRow(id: "learn", title: "Add a Button", detail: learnMessage, action: .startLearning(command)))
        var footer: String?
        if command == .home {
            footer = "Home buttons can work in other apps too (needs Accessibility)."
        } else if KeyBindings.essentialCommands.contains(command) {
            footer = "Keep at least one button for \(command.title)."
        } else if command == .power {
            footer = "Power buttons can work in other apps too (needs Accessibility)."
        } else if command == .powerMenu {
            footer = "Power Menu buttons can work in other apps too (needs Accessibility). Holding the Siri Remote's Power button opens the power menu too, whatever buttons are here."
        }
        return [SettingsSection(id: "buttons", title: "Buttons", rows: rows, footer: footer)]
    }

    private func remoteBindingSections(_ command: RemoteCommand, _ trigger: InputBinding.Trigger) -> [SettingsSection] {
        var rows: [SettingsRow] = []
        // M7h L2: Siri Remote buttons always work in other apps, so they have no row. M7h step 12 (follow-up to U2):
        // Power and Power Menu buttons can work in other apps too, so the power menu opens over Plex.
        if let description = Self.globalDescription(command), !trigger.isSiriRemote {
            if KeyBindings.canSetGlobal(trigger) {
                let isGlobal = bindings.binding(matching: trigger)?.isGlobal == true
                rows.append(SettingsRow(id: "binding.global", title: "Works in Other Apps", value: Self.onOff(isGlobal),
                                        detail: isAccessibilityTrusted ? nil : "Needs Accessibility access",
                                        action: .toggleBindingGlobal(trigger),
                                        description: description))
            } else {
                // M7h L9: a plain letter or digit typed in other apps would bring MMTVL back.
                rows.append(SettingsRow(id: "binding.global", title: "Works in Other Apps", value: "Off",
                                        detail: "Letter and number keys only work in MMTVL"))
            }
        }
        if bindings.canRemove(trigger) {
            rows.append(SettingsRow(id: "binding.remove", title: "Remove Button", action: .removeBinding(trigger)))
        } else {
            rows.append(SettingsRow(id: "binding.cantRemove", title: "The last button for \(command.title) can't be removed"))
        }
        return [SettingsSection(id: "binding", rows: rows)]
    }

    /// The Works in Other Apps row's description, for the commands that may be global (Home, Power, Power Menu);
    /// nil for the others.
    static func globalDescription(_ command: RemoteCommand) -> String? {
        switch command {
        case .home: "This button also brings MMTVL back while another app is in front. Needs Accessibility access."
        case .power: "This button also turns the TV and receiver off or on while another app is in front. Needs Accessibility access."
        case .powerMenu: "This button also opens the power menu over another app. Needs Accessibility access."
        default: nil
        }
    }

    private func learnButtonSections(_ command: RemoteCommand) -> [SettingsSection] {
        [SettingsSection(id: "learn", rows: [
            SettingsRow(id: "learn.prompt", title: "Press the button to use for \(command.title)",
                        detail: "On the remote, a keyboard or a game controller. Waits 10 seconds."),
            SettingsRow(id: "learn.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private func confirmLearnSections(_ command: RemoteCommand, _ trigger: InputBinding.Trigger) -> [SettingsSection] {
        var detail: String?
        if let existing = bindings.binding(matching: trigger) {
            detail = existing.command == command
                ? "Already used for \(command.title)"
                : "Now used for \(existing.command.title); it moves to \(command.title)"
        }
        return [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.use", title: "Use This Button", detail: detail, action: .useLearned(command, trigger)),
            SettingsRow(id: "confirm.retry", title: "Try Again", action: .startLearning(command)),
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private var confirmRestoreButtonsSections: [SettingsSection] {
        [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
            SettingsRow(id: "confirm.restoreButtons", title: "Restore Defaults", action: .restoreDefaultButtons),
        ], footer: "Replaces every button with the defaults.")]
    }

    // MARK: - Plex (M7 D28, L15)

    private var plexSections: [SettingsSection] {
        guard plex.isSignedIn else {
            return [SettingsSection(id: "plex", rows: [
                SettingsRow(id: "plex.signIn", title: "Sign In", showsDisclosure: true, action: .push(.plexLink),
                            description: "Shows Continue Watching on the Home screen. Uses a code at plex.tv/link; no password is typed here."),
            ])]
        }
        let canChoose = plex.servers.count > 1
        return [SettingsSection(id: "plex", rows: [
            SettingsRow(id: "plex.server", title: "Server", value: plex.serverName ?? "None",
                        showsDisclosure: canChoose, action: canChoose ? .push(.plexServers) : nil),
            SettingsRow(id: "plex.status", title: "Status", value: plex.statusLine),
            SettingsRow(id: "plex.signOut", title: "Sign Out", showsDisclosure: true, action: .push(.confirmPlexSignOut)),
        ], footer: "Selecting a Continue Watching item opens Plex.")]
    }

    private var plexLinkSections: [SettingsSection] {
        if plex.isSignedIn && plex.hasNoServer {
            return [SettingsSection(id: "link", rows: [
                SettingsRow(id: "plexLink.noServer", title: "No Plex Media Server on this account"),
                SettingsRow(id: "plexLink.cancel", title: "Done", action: .pop),
            ])]
        }
        return [SettingsSection(id: "link", rows: [
            SettingsRow(id: "plexLink.code", title: "Code", value: plex.linkCode ?? "…"),
            SettingsRow(id: "plexLink.where", title: "plex.tv/link",
                        detail: "On a phone or computer, open plex.tv/link and enter the code, or scan the QR code"),
            SettingsRow(id: "plexLink.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private var plexServersSections: [SettingsSection] {
        let rows = plex.servers.map { server in
            SettingsRow(id: "plexServer.\(server.id)", title: server.name,
                        value: server.name == plex.serverName ? "Selected" : nil, detail: server.detail,
                        action: .choosePlexServer(id: server.id))
        }
        return [SettingsSection(id: "servers", rows: rows, footer: "Continue Watching comes from this server.")]
    }

    private var confirmPlexSignOutSections: [SettingsSection] {
        [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
            SettingsRow(id: "confirm.signOutOfPlex", title: "Sign Out", action: .signOutOfPlex),
        ], footer: "Removes this Mac from your Plex account's sign-in here. Plex HTPC stays signed in.")]
    }

    // MARK: - Casting (M7b L14)

    private var castingSections: [SettingsSection] {
        let youtubeDetail: String? = switch casting.youtube {
        case .ready: "Phones on this network list \"MMTVL\""
        case .starting: "Starting…"
        case .failed(let message): message
        case .off: nil
        }
        let airPlayValue = switch casting.airPlay {
        case .on: "On"
        case .off: "Off"
        case .unknown: "Unknown"
        }
        let reflectorValue = switch casting.reflector {
        case .notInstalled: "Not Installed"
        case .notRunning: "Not Running"
        case .ready: "Ready"
        case .mirroring: "Mirroring"
        }
        var androidRows = [
            SettingsRow(id: "cast.android.reflector", title: "Reflector", value: reflectorValue,
                        detail: casting.reflector == .notInstalled ? "Install Reflector 4 from airsquirrels.com" : nil),
        ]
        if casting.reflector != .notInstalled {
            androidRows.append(SettingsRow(id: "cast.android.autostart", title: "Start Reflector with MMTVL",
                                           value: Self.onOff(settings.reflectorAutoStart),
                                           action: .toggle(.reflectorAutoStart),
                                           description: "Keeps Reflector running hidden, so Android phones can mirror at any time."))
        }
        let plexValue = switch casting.plexHTPC {
        case .running: "Running"
        case .notRunning: "Not Running"
        case .notInstalled: "Not Installed"
        }
        return [
            SettingsSection(id: "cast.youtube", title: "YouTube", rows: [
                SettingsRow(id: "cast.youtube.enabled", title: "Cast from the YouTube App",
                            value: Self.onOff(settings.youtubeCastEnabled),
                            detail: settings.youtubeCastEnabled ? youtubeDetail : nil,
                            action: .toggle(.youtubeCastEnabled),
                            description: "Phones on this network list MMTVL in the YouTube app's Cast menu."),
            ], footer: "In the YouTube app on a phone, tap Cast and choose MMTVL, or use Link with TV Code in YouTube's settings."),
            SettingsSection(id: "cast.airplay", title: "AirPlay", rows: [
                SettingsRow(id: "cast.airplay.receiver", title: "AirPlay Receiver", value: airPlayValue,
                            action: .openAirPlaySettings,
                            description: "Opens AirDrop & Handoff in System Settings, where AirPlay Receiver is turned on."),
            ], footer: "Turn on AirPlay Receiver and allow AirPlay for \"Anyone on the Same Network\" so iPhones list this Mac under Screen Mirroring."),
            SettingsSection(id: "cast.android", title: "Android", rows: androidRows,
                            footer: "On an Android phone, open Quick Settings → Cast and choose MMTVL Screen Mirroring; Home on the remote ends it."),
            SettingsSection(id: "cast.plex", title: "Plex", rows: [
                SettingsRow(id: "cast.plex.htpc", title: "Plex HTPC", value: plexValue),
            ], footer: "In the Plex app on a phone, tap Cast and choose Plex HTPC; it must be running, so open it once after a restart."),
        ]
    }

    // MARK: - Siri Remote (M7h D43)

    /// "Connected · 78 %", "Connected", "Not Connected", "Off".
    private var siriRemoteValue: String {
        guard settings.siriRemoteEnabled else { return "Off" }
        guard siriRemote.isConnected else { return "Not Connected" }
        return siriRemote.batteryLevel.map { "Connected · \($0) %" } ?? "Connected"
    }

    private var siriRemoteSections: [SettingsSection] {
        var rows = [
            SettingsRow(id: "siri.enabled", title: "Use Siri Remote", value: Self.onOff(settings.siriRemoteEnabled),
                        action: .toggle(.siriRemoteEnabled),
                        description: "Read the Siri Remote directly. Double-press Siri for trackpad mode."),
        ]
        if settings.siriRemoteEnabled {
            // Step 13e: off by default; trackpad mode is the same either way.
            rows.append(SettingsRow(id: "siri.swipes", title: "Swipes", value: Self.onOff(settings.siriRemoteSwipes),
                                    action: .toggle(.siriRemoteSwipes),
                                    description: "Swipe on the remote's touch surface to move around, like an Apple TV. Off: only the clickpad's clicks move."))
            #if DEBUG
            // Step 6: a way to see the toast without the remote.
            let demo: (action: SettingsAction?, description: String?) =
                (.showToastDemo, "Debug builds: Select shows the Trackpad On toast.")
            #else
            let demo: (action: SettingsAction?, description: String?) = (nil, nil)
            #endif
            rows.append(SettingsRow(id: "siri.status", title: "Status", value: siriRemoteValue,
                                    detail: siriRemote.isTouchAvailable ? (siriRemote.isConnected ? "Touch available" : nil)
                                        : "Touch not available",
                                    action: demo.action, description: demo.description))
        }
        return [
            SettingsSection(id: "siri", rows: rows,
                            footer: "How it works: TV goes Home. Press the clickpad's edges to move (or swipe, with Swipes on), press its centre to select. "
                                + "Double-press Siri for trackpad mode: touch moves the pointer and a press clicks. "
                                + "Holding the centre opens the menu (a right click in trackpad mode) and holding Power opens the power menu, "
                                + "even if those buttons are changed in Remote Buttons."),
        ]
    }

    // MARK: - Audio & TV: Receiver and TV (M7h D44, L12, L17, L18; step 13c)

    /// Step 13c: Receiver and TV as their own pages, then the volume display (it applies to every volume route).
    private var audioTVSections: [SettingsSection] {
        [
            SettingsSection(id: "devices", rows: [
                SettingsRow(id: "audioTV.receiver", title: "Receiver", value: audioTVReceiverValue,
                            showsDisclosure: true, action: .push(.receiver),
                            description: "Volume, mute and power through the AV receiver, over a serial cable, the network or HDMI-CEC."),
                SettingsRow(id: "audioTV.tv", title: "TV",
                            value: settings.tvBrand == .none ? "Not Set Up" : settings.tvBrand.shortTitle,
                            showsDisclosure: true, action: .push(.tv),
                            description: "Turning the TV on and off with the remote's Power button, and optionally its volume."),
            ]),
            SettingsSection(id: "volume", title: "Volume", rows: [showVolumeRow]),
        ]
    }

    /// "cu.usbserial-A1B2" for a configured path, "Automatic" for none.
    private static func portTitle(_ path: String?) -> String {
        guard let path else { return "Automatic" }
        return path.hasPrefix("/dev/") ? String(path.dropFirst(5)) : path
    }

    /// Step 9c: Audio & TV's Receiver row: the brand, or over HDMI-CEC the receiver's name ("HDMI-CEC" before it
    /// gave one).
    private var audioTVReceiverValue: String {
        if settings.receiverConnection == .cec { return cecReceiver.name ?? "HDMI-CEC" }
        return settings.receiverBrand == .none ? "Not Set Up" : settings.receiverBrand.shortTitle
    }

    private var connectionRow: SettingsRow {
        SettingsRow(id: "receiver.connection", title: "Connection", value: settings.receiverConnection.settingsTitle,
                    showsDisclosure: true, action: .push(.receiverConnection),
                    description: "Serial: an RS-232 cable from a USB serial adapter. Network: the receiver's address on this network. HDMI-CEC: through the Mac's HDMI, for any receiver that follows HDMI-CEC.")
    }

    private var receiverSections: [SettingsSection] {
        if settings.receiverConnection == .cec { return cecReceiverSections }
        let brand = settings.receiverBrand
        let isNetwork = settings.receiverConnection == .network
        var rows = [
            SettingsRow(id: "receiver.brand", title: "Brand", value: brand.settingsTitle, showsDisclosure: true,
                        action: .push(.receiverBrand),
                        description: "The receiver's maker. MMTVL speaks each brand's own control commands."),
            connectionRow,
        ]
        if isNetwork {
            rows.append(SettingsRow(id: "receiver.address", title: "Address", value: settings.receiverHost ?? "Not Set",
                                    showsDisclosure: true, action: .push(.addressEntry(.receiver)),
                                    description: "The receiver's IP address or name on this network."))
        } else {
            rows.append(SettingsRow(id: "receiver.port", title: "Serial Port", value: Self.portTitle(settings.receiverSerialPort),
                                    showsDisclosure: true, action: .push(.receiverPort),
                                    description: "The USB serial adapter the receiver's cable is on. Automatic uses the first one."))
        }
        if brand != .none {
            rows.append(SettingsRow(id: "receiver.test", title: "Test Connection", detail: probeLines[.testReceiver],
                                    action: .testReceiver,
                                    description: "Asks the receiver for its power, volume and mute. Nothing on the receiver changes."))
        }
        rows.append(SettingsRow(id: "receiver.find", title: isNetwork ? "Find on Network" : "Find Receiver",
                                detail: probeLines[.findReceiver], action: .findReceiver,
                                description: isNetwork
                                    ? "Looks for receivers on this network and lists the ones that answer. Nothing on the receiver changes."
                                    : "Tries each brand on the serial port and picks the one that answers. Nothing on the receiver changes."))
        // QA minor 1: Find on Network's answers stay reachable after leaving the page they opened on.
        if isNetwork, !foundReceivers.isEmpty {
            rows.append(SettingsRow(id: "receiver.found", title: "Receivers Found", value: "\(foundReceivers.count)",
                                    showsDisclosure: true, action: .push(.receiverFound),
                                    description: "The receivers Find on Network found. Choose the one MMTVL controls."))
        }
        if brand != .none {
            rows.append(SettingsRow(id: "receiver.maxVolume", title: "Maximum Volume",
                                    value: VolumeToast.format(dB: settings.validatedReceiverMaxDB),
                                    detail: brand.reportsDB ? nil : "\(brand.shortTitle) receivers don't report dB, so there's no limit",
                                    showsDisclosure: true, action: .push(.receiverMaxVolume),
                                    description: "The loudest MMTVL's volume buttons set the receiver. Its own remote and knob aren't limited."))
            rows.append(SettingsRow(id: "receiver.status", title: "Status", value: receiverStatusValue))
        }

        return [
            SettingsSection(id: "receiver", rows: rows, footer: "Volume buttons go to the receiver while it answers."),
        ]
    }

    /// Step 9c: Connection HDMI-CEC. No brand, port, address or volume limit; Test and Status show the receiver's name.
    private var cecReceiverSections: [SettingsSection] {
        let rows = [
            connectionRow,
            SettingsRow(id: "receiver.test", title: "Test Connection", detail: probeLines[.testReceiver],
                        action: .testReceiver,
                        description: "Asks the receiver over HDMI-CEC whether it's on, and its name. Nothing on the receiver changes."),
            SettingsRow(id: "receiver.find", title: "Find Receiver", detail: probeLines[.findReceiver], action: .findReceiver,
                        description: "Tries each brand on the serial port, then HDMI-CEC, and picks the one that answers. A serial cable gives the volume in dB and the volume limit. Nothing on the receiver changes."),
            SettingsRow(id: "receiver.maxVolume", title: "Maximum Volume", value: "No Limit",
                        detail: "HDMI-CEC receivers can't be limited"),
            SettingsRow(id: "receiver.status", title: "Status", value: cecReceiverStatusValue),
        ]
        return [
            SettingsSection(id: "receiver", rows: rows,
                            footer: "Volume buttons go to the receiver while it's on. MMTVL shares the Mac's HDMI-CEC with macOS."),
        ]
    }

    /// Step 9c: "On · VSX-01TXH", "Standby", "Not answering", or why HDMI-CEC can't be used.
    private var cecReceiverStatusValue: String {
        switch cecReceiver.availability {
        case .notAvailable: return "HDMI-CEC not available on this display"
        case .noDisplay: return "No HDMI display"
        case .ready, nil: break
        }
        guard let power = cecReceiver.power else {
            return cecReceiver.availability == nil ? "Checking…" : "Not answering"
        }
        return CECReceiverTest(power: power, name: cecReceiver.name).line
    }

    /// Step 9c: Serial / Network / HDMI-CEC.
    private var receiverConnectionSections: [SettingsSection] {
        let rows = ReceiverConnection.allCases.map { connection in
            SettingsRow(id: "connection.\(connection.rawValue)", title: connection.settingsTitle,
                        value: connection == settings.receiverConnection ? "Selected" : nil, detail: connection.detail,
                        action: .setReceiverConnection(connection))
        }
        return [SettingsSection(id: "connections", rows: rows,
                                footer: "Serial and Network give the volume in dB and a volume limit. HDMI-CEC works with any receiver that follows it, without a cable or address.")]
    }

    /// Step 9c: Volume Buttons Change TV Volume (`tvVolumeEnabled`), for Panasonic and HDMI-CEC.
    private var tvVolumeRow: SettingsRow {
        SettingsRow(id: "tv.volume", title: "Volume Buttons Change TV Volume", value: Self.onOff(settings.tvVolumeEnabled),
                    action: .toggle(.tvVolumeEnabled),
                    description: "When no receiver is set up, the volume buttons change the TV's own volume. For TVs that play through their own speakers. Some TVs ignore HDMI-CEC volume.")
    }

    /// Step 13b: the volume toast toggle (`volumeToast`); on Audio & TV from step 13c.
    private var showVolumeRow: SettingsRow {
        SettingsRow(id: "receiver.showVolume", title: "Show Volume", value: Self.onOff(settings.volumeToast),
                    action: .toggle(.volumeToast),
                    description: "Shows the volume at the top of the screen when you press a volume button. Messages about volume not working always show.")
    }

    /// The Status row: the last known state, else why there's none.
    private var receiverStatusValue: String {
        if let line = Self.receiverStatusLine(receiver.state) {
            return receiver.isAnswering ? line : line + " · Not answering"
        }
        if let error = receiver.lastError { return error }
        return receiver.isConnected ? "Waiting for an answer" : "Not connected"
    }

    static let vieraTVFooter = "Turn on TV Remote App and Wake on LAN in the TV's Network settings. The TV must be on Ethernet to turn on from MMTVL."

    private var tvSections: [SettingsSection] {
        var rows = [
            SettingsRow(id: "tv.brand", title: "Brand", value: settings.tvBrand.settingsTitle, showsDisclosure: true,
                        action: .push(.tvBrand),
                        description: "A TV MMTVL turns on and off with the Power button, over the network or HDMI-CEC."),
        ]
        // Step 9 (reopened): HDMI-CEC needs no address, Find TV or MAC.
        if settings.tvBrand == .cec {
            rows.append(SettingsRow(id: "tv.test", title: "Test TV", detail: probeLines[.testTV], action: .testTV,
                                    description: "Asks the TV over HDMI-CEC whether it's on. Nothing on the TV changes."))
            rows.append(SettingsRow(id: "tv.status", title: "Status", value: Self.cecStatusLine(cec)))
            rows.append(tvVolumeRow)
            return [
                SettingsSection(id: "tv", rows: rows,
                                footer: "MMTVL shares the Mac's HDMI-CEC with macOS. Turning off also turns off receivers that follow HDMI-CEC."),
            ]
        }
        if settings.tvBrand != .none {
            rows.append(SettingsRow(id: "tv.address", title: "Address", value: settings.tvHost ?? "Not Set",
                                    showsDisclosure: true, action: .push(.addressEntry(.tv)),
                                    description: "The TV's IPv4 address or name on this network. Find TV fills it in."))
            rows.append(SettingsRow(id: "tv.find", title: "Find TV", detail: probeLines[.findTV], action: .findTV,
                                    description: "Looks for the TV on this network and fills in its address and MAC address. The TV must be on."))
            rows.append(SettingsRow(id: "tv.test", title: "Test TV", detail: probeLines[.testTV], action: .testTV,
                                    description: "Asks the TV whether it's on, and its volume and mute. Nothing on the TV changes."))
            rows.append(SettingsRow(id: "tv.mac", title: "MAC Address", value: settings.tvMAC ?? "Not Set",
                                    detail: settings.tvMAC == nil ? "MMTVL can't turn the TV on without it; Find TV fills it in" : nil))
            rows.append(tvVolumeRow)
        }
        // Build 25 QA minor: the VIERA setup footer only for a Panasonic TV; none without a TV.
        return [
            SettingsSection(id: "tv", rows: rows,
                            footer: settings.tvBrand == .panasonic ? Self.vieraTVFooter : nil),
        ]
    }

    private var receiverBrandSections: [SettingsSection] {
        let rows = ReceiverBrand.allCases.map { brand in
            SettingsRow(id: "brand.\(brand.rawValue)", title: brand.settingsTitle,
                        value: brand == settings.receiverBrand ? "Selected" : nil, detail: brand.years,
                        action: .setReceiverBrand(brand))
        }
        return [SettingsSection(id: "brands", rows: rows,
                                footer: "Tested with Pioneer. Serial cables: Pioneer needs a null-modem cable, Denon, Marantz and Onkyo a straight one.")]
    }

    private var receiverPortSections: [SettingsSection] {
        let configured = settings.receiverSerialPort
        var rows = [
            SettingsRow(id: "port.automatic", title: "Automatic", value: configured == nil ? "Selected" : nil,
                        detail: "The first USB serial port", action: .setReceiverPort(nil)),
        ]
        rows += serialPorts.map { port in
            SettingsRow(id: "port.\(port.path)", title: Self.portTitle(port.path),
                        value: port.path == configured ? "Selected" : nil, detail: port.displayName,
                        action: .setReceiverPort(port.path))
        }
        if let configured, !serialPorts.contains(where: { $0.path == configured }) {
            rows.append(SettingsRow(id: "port.\(configured)", title: Self.portTitle(configured), value: "Selected",
                                    detail: "Not connected", action: .setReceiverPort(configured)))
        }
        if serialPorts.isEmpty {
            rows.append(SettingsRow(id: "port.none", title: "No serial ports found",
                                    detail: "Plug in the USB serial adapter, then open this list again"))
        }
        return [SettingsSection(id: "ports", rows: rows)]
    }

    /// −30…+10 dB in 5 dB steps, plus a hand-edited value that isn't one of them.
    static let maxVolumeChoices: [Double] = stride(from: -30.0, through: 10.0, by: 5.0).map { $0 }

    private var receiverMaxVolumeSections: [SettingsSection] {
        let current = settings.validatedReceiverMaxDB
        var choices = Self.maxVolumeChoices
        if !choices.contains(current) { choices = (choices + [current]).sorted() }
        let rows = choices.map { dB in
            SettingsRow(id: "maxVolume.\(dB)", title: VolumeToast.format(dB: dB), value: dB == current ? "Selected" : nil,
                        action: .setReceiverMaxDB(dB))
        }
        var footer = "MMTVL's volume buttons never set the receiver louder than this. Its own remote and knob aren't limited."
        if !settings.receiverBrand.reportsDB {
            footer += " \(settings.receiverBrand.shortTitle) receivers don't report dB, so there's no limit."
        }
        return [SettingsSection(id: "maxVolume", rows: rows, footer: footer)]
    }

    /// M7l L3: the five steps, the current one "Selected" (as Maximum Volume does).
    private var glassStyleSections: [SettingsSection] {
        let current = settings.glassStyle
        let rows = GlassStyle.allCases.map { style in
            SettingsRow(id: "glass.\(style.rawValue)", title: style.title, value: style == current ? "Selected" : nil,
                        action: .setGlassStyle(style))
        }
        return [SettingsSection(id: "glass", rows: rows,
                                footer: "Changes every glass panel in MMTVL. Reduce Transparency in macOS's Accessibility settings always uses Solid.")]
    }

    private var receiverFoundSections: [SettingsSection] {
        let rows = foundReceivers.map { found in
            let ownPorts = found.brand.codec?.networkPorts(override: nil) ?? []
            let address = ownPorts.contains(found.port) ? found.host : LANAddress.display(host: found.host, port: found.port)
            let isChosen = settings.receiverConnection == .network && settings.receiverHost == found.host
                && settings.receiverBrand == found.brand
            return SettingsRow(id: "found.\(found.host):\(found.port)", title: found.name ?? found.model ?? found.brand.settingsTitle,
                               value: isChosen ? "Selected" : nil,
                               detail: "\(found.brand.settingsTitle) · \(address)", action: .useFoundReceiver(found))
        }
        return [SettingsSection(id: "found", rows: rows, footer: "Choose the receiver MMTVL controls.")]
    }

    private var tvBrandSections: [SettingsSection] {
        let rows = TVBrand.allCases.map { brand in
            SettingsRow(id: "tvBrand.\(brand.rawValue)", title: brand.settingsTitle,
                        value: brand == settings.tvBrand ? "Selected" : nil, detail: brand.years,
                        action: .setTVBrand(brand))
        }
        return [SettingsSection(id: "tvBrands", rows: rows,
                                footer: "Newer VIERAs (2019 and later) need a pairing MMTVL doesn't support.")]
    }

    /// D41: the keyboard is drawn above these rows (`SettingsColumnView`).
    private func addressEntrySections(_ field: AddressField) -> [SettingsSection] {
        [SettingsSection(id: "address", rows: [
            SettingsRow(id: "address.save", title: keyboard.text.isEmpty ? "Save Without an Address" : "Save",
                        detail: addressMessage, action: .saveAddress(field)),
            SettingsRow(id: "address.clear", title: "Clear", action: .clearAddress),
            SettingsRow(id: "address.cancel", title: "Cancel", action: .pop),
        ])]
    }
}

/// M7h step 11: how Settings names each brand.
extension ReceiverBrand {
    /// The brand list's titles (*Settings pages*).
    nonisolated var settingsTitle: String {
        switch self {
        case .none: "None"
        case .pioneer: "Pioneer"
        case .onkyo: "Onkyo / Integra / Pioneer"
        case .denon: "Denon / Marantz"
        case .yamaha: "Yamaha"
        case .anthem: "Anthem"
        case .nad: "NAD"
        }
    }

    /// Which models each covers.
    nonisolated var years: String? {
        switch self {
        case .pioneer: "Before 2016"
        case .onkyo: "2016 and later"
        case .denon: "2010 and later"
        case .yamaha: "2010–2020"
        case .none, .anthem, .nad: nil
        }
    }

    /// For "Pioneer · VIERA" and notes.
    nonisolated var shortTitle: String {
        switch self {
        case .none: "None"
        case .pioneer: "Pioneer"
        case .onkyo: "Onkyo"
        case .denon: "Denon"
        case .yamaha: "Yamaha"
        case .anthem: "Anthem"
        case .nad: "NAD"
        }
    }

    /// Step 10: Onkyo reports a level, not dB, so the volume cap can't apply.
    nonisolated var reportsDB: Bool { self != .onkyo }
}

/// Step 9c: how Settings names each receiver connection.
extension ReceiverConnection {
    nonisolated var settingsTitle: String {
        switch self {
        case .serial: "Serial"
        case .network: "Network"
        case .cec: "HDMI-CEC"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .serial: "An RS-232 cable from a USB serial adapter"
        case .network: "The receiver's address on this network"
        case .cec: "Through the Mac's HDMI; no volume in dB"
        }
    }
}

extension TVBrand {
    nonisolated var settingsTitle: String {
        switch self {
        case .none: "None"
        case .panasonic: "Panasonic VIERA"
        case .cec: "HDMI-CEC"
        }
    }

    nonisolated var years: String? {
        switch self {
        case .none: nil
        case .panasonic: "2012–2018, network"
        case .cec: "Any TV, through the Mac's HDMI. Also turns a CEC receiver off and on."
        }
    }

    nonisolated var shortTitle: String {
        switch self {
        case .none: "None"
        case .panasonic: "VIERA"
        case .cec: "HDMI-CEC"
        }
    }
}
