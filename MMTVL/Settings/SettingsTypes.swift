import Foundation

nonisolated enum SettingsPage: Hashable, Sendable {
    case root, homeScreen, tile(id: String), addTile, confirmRestoreDefaults, confirmClearYouTube
    case liveTV, confirmRemoveIPTV, guideSource(id: String), iptvGroups, iptvHiddenChannels
    /// M7f L13: Settings → Live TV → Teams, and one league's teams (a pro league) or conferences (a college league).
    case iptvTeams, iptvLeague(TeamLeague)
    /// M7l L13: one college conference's teams.
    case iptvConference(TeamLeague, String)
    case phoneRemote, pairPhone, confirmForgetPhones
    /// M7: Settings → Remote Buttons (D27).
    case remoteButtons, remoteCommand(RemoteCommand), remoteBinding(RemoteCommand, InputBinding.Trigger)
    case learnButton(RemoteCommand), confirmLearn(RemoteCommand, InputBinding.Trigger), confirmRestoreButtons
    /// M7: Settings → Plex (D28, L15).
    case plex, plexLink, plexServers, confirmPlexSignOut
    /// M7 L25: Settings → a tile → Tile Art.
    case tileArt(id: String)
    /// M7b L14: Settings → Casting.
    case casting
    /// M7g L6: root categories.
    case youtube, remoteInput, restrictions, system, about
    /// M7h step 11: Remote & Input → Siri Remote, and the receiver's and TV's lists.
    case siriRemote, receiver, receiverBrand, receiverPort, receiverMaxVolume, receiverFound, tvBrand
    /// M7h step 9c: the receiver's Serial / Network / HDMI-CEC list.
    case receiverConnection
    /// M7h step 13c: the Audio & TV category, and its TV page (the receiver's is `receiver`).
    case audioTV, tv
    /// M7h step 11 (D41): an address typed with the on-screen keyboard.
    case addressEntry(AddressField)
    /// M7l L3: System → Glass, the five glass steps.
    case glassStyle
    /// M7j L14: Live TV → Antenna, and its Channels list.
    case antenna, antennaChannels
    /// M7j L18: Antenna → Scan for Channels' confirm page.
    case confirmAntennaScan
    /// M15 step 1: System → Restart Mac mini's confirm page.
    case confirmRestartMac
    /// M15 step 8: System → Software Update, and its Automatic Updates choice.
    case softwareUpdate, automaticUpdates
    /// MR step 4: Settings → Licenses (every shipped component), and one component's page with its QR code.
    case licenses, license(id: String)
}

/// M7h step 11: which address the keyboard page edits.
nonisolated enum AddressField: Hashable, Sendable {
    /// `receiverHost`.
    case receiver
    /// `tvHost`.
    case tv
}

/// M7h step 11: Settings' read-only checks; each runs in the background while its row says "Testing…" or
/// "Searching…", then shows the result.
nonisolated enum SettingsProbe: Hashable, Sendable {
    case testReceiver, findReceiver, testTV, findTV
    /// M7j L14: Live TV → Antenna → Find Tuners (a UDP search on the LAN, then the lineups).
    case findAntennaTuners
}

/// What Settings → Siri Remote shows (M7h D43). Built by the app from `SiriRemoteInput` and `RemoteBattery`.
nonisolated struct SiriRemoteSettingsStatus: Equatable, Sendable {
    var isConnected = false
    /// 0…100; nil when unknown.
    var batteryLevel: Int?
    /// MultitouchSupport loaded, and (when connected) the remote's touch surface delivers frames.
    var isTouchAvailable = false
}

/// What Settings → Audio & TV → Receiver shows about the receiver link (M7h D44). Never an address or a device path.
nonisolated struct ReceiverSettingsStatus: Equatable, Sendable {
    /// The last known power, volume and mute.
    var state = ReceiverState()
    var isConnected = false
    var isAnswering = false
    /// `ReceiverController.lastConnectError`.
    var lastError: String?
}

/// M7h step 9c: what Settings → Audio & TV → Receiver shows about a receiver over HDMI-CEC (`CECAudioSystem`).
nonisolated struct CECReceiverSettingsStatus: Equatable, Sendable {
    /// The tunnel's state at the last check; nil before one.
    var availability: CECAvailability?
    /// The last power status answer; nil: none yet, or no answer.
    var power: CECPowerStatus?
    /// The OSD name ("VSX-01TXH").
    var name: String?
    var isAnswering = false
}

/// M7h L12: Test Connection's replies, or why there were none.
nonisolated struct ReceiverTestOutcome: Equatable, Sendable {
    var replies = ReceiverState()
    /// "Connection refused", "No serial port found"…; nil = use "No answer" when nothing replied.
    var error: String?
}

/// Which Live TV address a paste row fills (M4 L2).
nonisolated enum IPTVURLKind: Hashable, Sendable {
    case playlist, guide
}

/// What the Live TV rows show. Built by the app from `IPTVLibrary`; hosts only, never full URLs (L2).
nonisolated struct IPTVSettingsStatus: Equatable, Sendable {
    var hasPlaylist = false
    /// url.host()
    var playlistHost: String?
    var channelCount = 0
    /// "Loading…", "Updated 10:42 PM", "Failed: Server error (HTTP 403)"
    var playlistLine: String = ""
    /// The guides in use, in priority order (M6b L1), then the pasted guides not in use (M7f L4).
    var guideSources: [GuideSourceStatus] = []
    /// M7f L4: the playlist's header names a guide, so Settings offers Guide Source.
    var playlistNamesGuide = false
    /// Pasted guides; the add row disappears at `IPTVLibrary.maxGuideSources`.
    var customGuideCount = 0
    /// Playlist channels with guide data.
    var matchedChannelCount = 0
    /// Playlist groups, in playlist order (M6b L5).
    var groups: [GroupStatus] = []
    /// Hidden playlist channels, in playlist order.
    var hiddenChannels: [HiddenChannelStatus] = []
    /// M7f L13: picked team ids, in the order added.
    var teams: [String] = []
    /// M7j L14: the antenna is on (`AntennaSource.isEnabled`).
    var antennaEnabled = false
    /// M7j: a search for tuners is running, or none has finished since the antenna was turned on.
    var antennaSearching = false
    /// The tuners found, in DeviceID order. Never a DeviceID, address or token.
    var antennaTuners: [AntennaTunerStatus] = []
    /// The antenna channels, in GuideNumber order.
    var antennaChannels: [AntennaChannelStatus] = []
    /// Protected (DRM) channels left out of the lineup.
    var antennaLeftOut = 0
    /// The lineup's status when it failed: why it can't be read ("The antenna tuner isn't answering"); nil otherwise
    /// (the last channels are kept meanwhile, L5).
    var antennaLineupLine: String?
    /// The antenna guide (`AntennaGuide.sourceID`): "Updated Nov 15, 9:12 AM · 1,234 programmes · 150 of 185 channels",
    /// "Loading…", "Failed: …", "Not loaded yet".
    var antennaGuideLine = ""
    /// M7j L18: the last channel scan (`AntennaSource.scan`); nil when none shows.
    var antennaScan: AntennaScanState?
    /// M7j L18: some tuner may start a scan (`AntennaSource.canScan`); false dims Scan for Channels.
    var antennaCanScan = true

    /// M7j L18: a scan is running (Select on its row is Stop Scan).
    var antennaIsScanning: Bool {
        if case .running = antennaScan { return true }
        return false
    }

    /// L13: Live TV has something to show: a playlist, or a tuner that was found.
    var hasLiveSource: Bool { hasPlaylist || !antennaTuners.isEmpty }

    struct GuideSourceStatus: Identifiable, Equatable, Sendable {
        /// GuideSource.id.
        var id: String
        /// GuideSource.label: host, plus the file name when it looks like a guide file (M6b L2).
        var label: String
        /// "1,234 programmes · 40 channels · Updated 10:43 PM", "Loading…", "Failed: …", "Not loaded yet"
        var line: String
        var isFromPlaylist: Bool
        /// M7f L4: false for a pasted guide kept while the playlist's guide is used.
        var isInUse = true
    }

    struct GroupStatus: Identifiable, Equatable, Sendable {
        var name: String
        var channelCount: Int
        var isHidden: Bool
        var id: String { name }
    }

    struct HiddenChannelStatus: Identifiable, Equatable, Sendable {
        /// Channel.ID.
        var id: String
        var number: Int
        var name: String
        var group: String
        /// M7j: an antenna channel's GuideNumber ("5.1"); nil for playlist channels.
        var guideNumber: String? = nil

        /// What the row shows: `Channel.displayNumber`.
        var displayNumber: String { guideNumber ?? "\(number)" }
    }

    /// M7j L14: one HDHomeRun tuner. No DeviceID, address or DeviceAuth: only what Settings shows.
    struct AntennaTunerStatus: Equatable, Sendable {
        /// FriendlyName ("HDHomeRun FLEX 4K").
        var name: String
        /// ModelNumber ("HDFX-4K").
        var model: String
        var tunerCount: Int
        /// Its channels in Live TV.
        var channelCount: Int
    }

    /// M7j L14: one antenna channel on Settings → Live TV → Antenna → Channels.
    struct AntennaChannelStatus: Identifiable, Equatable, Sendable {
        /// Channel.ID (`antenna:5.1`).
        var id: String
        /// `Channel.displayNumber`: the GuideNumber ("5.1").
        var displayNumber: String
        var name: String
        var isHD = false
        /// The lineup's SignalQuality, 0…100; nil when the tuner doesn't say.
        var signalQuality: Int?
        var isHidden = false
    }
}

/// What the Phone Remote rows show (M5). Built by the app from `RemoteServer` and `PhoneRemote`.
nonisolated struct PhoneRemoteSettingsStatus: Equatable, Sendable {
    var isRunning = false
    /// "Port 8765 is in use", "No network connection", "Starting…"; nil when fine.
    var problem: String?
    /// "http://192.168.1.20:8765"; nil without a LAN address.
    var address: String?
    /// While Pair a Phone shows.
    var pairingCode: String?
    /// address + "/#pair=" + the pairing's secret (`PairingCode.secret`).
    var pairingURL: String?
    /// Pairing expired; Pair a Phone must be opened again.
    var pairingEnded = false
    /// Re-review L1: too many wrong codes; the typed code is off, the QR code still pairs.
    var pairingCodeLocked = false
    var lastPairedName: String?
    var pairedCount = 0
    var connectedCount = 0
    /// SyntheticInput.canPost.
    var canControlOtherApps = false
}

/// What Settings → Plex shows (M7 L15). Built by the app from `PlexAccount`; never tokens.
nonisolated struct PlexSettingsStatus: Equatable, Sendable {
    struct Server: Identifiable, Equatable, Sendable {
        /// The server's machine identifier.
        var id: String
        var name: String
        /// "Yours", "Shared with you".
        var detail: String
    }

    var isSignedIn = false
    /// While the link page shows.
    var linkCode: String?
    /// `PlexAPI.linkURL(code:)` for the QR code.
    var linkURL: String?
    /// The chosen server.
    var serverName: String?
    /// The account's servers (after sign-in).
    var servers: [Server] = []
    /// "Connected · 7 items", "Can't reach the server", "Sign in again"…
    var statusLine = ""
    var itemCount = 0
    /// Signed in, but the account has no server.
    var hasNoServer = false
    /// Signed in with several servers and none chosen yet.
    var needsServerChoice = false
}

/// What Settings → Casting shows (M7b L14). Built by the app from `CastReceiver`, the AirPlay probe and
/// the installed/running apps.
nonisolated struct CastingSettingsStatus: Equatable, Sendable {
    enum YouTube: Equatable, Sendable { case off, starting, ready, failed(String) }
    enum PlexHTPC: Equatable, Sendable { case notInstalled, notRunning, running }
    enum Reflector: Equatable, Sendable { case notInstalled, notRunning, ready, mirroring }

    var youtube: YouTube = .off
    var airPlay: AirPlayReceiverState = .unknown
    var reflector: Reflector = .notInstalled
    var plexHTPC: PlexHTPC = .notInstalled
}

/// The `settings.json` toggles.
nonisolated enum SettingKey: String, CaseIterable, Sendable {
    case globalInputEnabled, controllersEnabled, cursorAutoHide, launchAtLogin, phoneRemoteEnabled
    /// M7 L22: its row shows "Up the List" / "Higher Number" instead of On/Off.
    case channelUpMovesUpList
    /// M7b L5.
    case youtubeCastEnabled
    /// M7b L18.
    case reflectorAutoStart
    /// M7c L6.
    case kioskLock
    /// M7c L15.
    case homeLivePreview
    /// M7c L28.
    case showVersionOnHome
    /// M7f L4: its row shows "Playlist" / "Pasted Guides".
    case usePlaylistGuide
    /// M7h D43.
    case siriRemoteEnabled
    /// M7h step 13b.
    case volumeToast
    /// M7h step 9c.
    case tvVolumeEnabled
    /// M7h step 13e.
    case siriRemoteSwipes
    /// M7m L29: Settings → Live TV → My Teams → Matching.
    case teamMatchInitials, teamMatchNicknames
    /// M7j L14: Settings → Live TV → Antenna.
    case antennaEnabled, antennaGuide
    /// M15 step 8: Settings → System → Software Update → Check for Updates.
    case updateChecks

    var keyPath: WritableKeyPath<AppSettings, Bool> {
        switch self {
        case .globalInputEnabled: \.globalInputEnabled
        case .controllersEnabled: \.controllersEnabled
        case .cursorAutoHide: \.cursorAutoHide
        case .launchAtLogin: \.launchAtLogin
        case .phoneRemoteEnabled: \.phoneRemoteEnabled
        case .channelUpMovesUpList: \.channelUpMovesUpList
        case .youtubeCastEnabled: \.youtubeCastEnabled
        case .reflectorAutoStart: \.reflectorAutoStart
        case .kioskLock: \.kioskLock
        case .homeLivePreview: \.homeLivePreview
        case .showVersionOnHome: \.showVersionOnHome
        case .usePlaylistGuide: \.usePlaylistGuide
        case .siriRemoteEnabled: \.siriRemoteEnabled
        case .volumeToast: \.volumeToast
        case .tvVolumeEnabled: \.tvVolumeEnabled
        case .siriRemoteSwipes: \.siriRemoteSwipes
        case .teamMatchInitials: \.teamMatchInitials
        case .teamMatchNicknames: \.teamMatchNicknames
        case .antennaEnabled: \.antennaEnabled
        case .antennaGuide: \.antennaGuide
        case .updateChecks: \.updateChecks
        }
    }
}

/// What Select does on a row (L4). Data, not closures, so pages are Equatable and testable.
nonisolated enum SettingsAction: Hashable, Sendable {
    case toggle(SettingKey)
    case requestAccessibility
    case openLoginItemsSettings
    case push(SettingsPage)
    case relaunch
    /// M15 step 1: the confirm page's Restart (`PowerController.restartMac()`).
    case restartMac
    /// M15 step 8: Settings → System → Software Update's Check Now and Install (`SoftwareUpdater`).
    case checkForUpdates, installUpdate
    /// M15 step 8: Software Update → Automatic Updates (`settings.json` `automaticUpdates`).
    case setAutomaticUpdates(AutomaticUpdates)
    case exitToDesktop
    case toggleTileVisible(id: String)
    case toggleTileFullScreen(id: String)
    case startMove(id: String)
    case removeTile(id: String)
    case addDefaultTile(id: String)
    case addApp(InstalledApp)
    case restoreDefaults
    case pop
    /// D20: the router shows the PIN screen and returns to this page.
    case startPIN(PINPurpose)
    case toggleTileRequiresPIN(id: String)
    case reloadYouTube
    case clearYouTubeData
    case pasteIPTVURL(IPTVURLKind)
    case moveGuideSource(id: String, by: Int)
    case removeGuideSource(id: String)
    case toggleIPTVGroupHidden(String)
    case unhideIPTVChannel(id: String)
    /// M7f L13.
    case toggleTeam(id: String)
    case refreshIPTV
    case removeIPTVSource
    case forgetAllPhones
    /// M7 L8: pushes `.learnButton`, or replaces `.confirmLearn` with it (Try Again).
    case startLearning(RemoteCommand)
    case useLearned(RemoteCommand, InputBinding.Trigger)
    case removeBinding(InputBinding.Trigger)
    case toggleBindingGlobal(InputBinding.Trigger)
    case restoreDefaultButtons
    case choosePlexServer(id: String)
    case signOutOfPlex
    /// M7 L23: a web app tile's start page from the clipboard, or back to the app's own.
    case pasteTileStartURL(id: String)
    case clearTileStartURL(id: String)
    /// M7 L25.
    case setTileArtStyle(id: String, TileArtStyle)
    case useTileArtPicture(id: String, URL)
    case removeTileArtPicture(id: String)
    /// M7b L14: System Settings → General → AirDrop & Handoff.
    case openAirPlaySettings
    /// M7c L32: the tile MMTVL opens on (`settings.json` `homeStartTile`).
    case setStartTile(id: String)
    /// M7h step 11: Settings → Audio & TV → Receiver.
    case setReceiverBrand(ReceiverBrand)
    case setReceiverConnection(ReceiverConnection)
    /// nil = Automatic (the first USB serial port).
    case setReceiverPort(String?)
    case setReceiverMaxDB(Double)
    /// M7l L3: System → Glass (`settings.json` `glassStyle`).
    case setGlassStyle(GlassStyle)
    /// Find on Network's choice: brand, network, host, and the port when it isn't the brand's own.
    case useFoundReceiver(FoundReceiver)
    case setTVBrand(TVBrand)
    /// Read-only checks (L12, L17, L18); never a command that changes anything.
    case testReceiver, findReceiver, testTV, findTV
    /// M7j L14: Live TV → Antenna → Find Tuners.
    case findAntennaTuners
    /// M7j L14: Live TV → Antenna → Channels: hides a shown channel, shows a hidden one.
    case toggleChannelHidden(id: String)
    /// M7j L18: the confirm page's Scan, and Stop Scan on the running scan's row.
    case startAntennaScan, stopAntennaScan
    /// The address page: save the typed address (empty clears it), or clear the field.
    case saveAddress(AddressField)
    case clearAddress
    /// Debug builds: Settings → Siri Remote → Status shows the "Trackpad On" toast (step 6).
    case showToastDemo
}

nonisolated enum RowImage: Hashable, Sendable {
    /// SF Symbol.
    case symbol(String)
    /// App icon via `AppLauncher.icon(for:)`, else the item's `iconSymbol`, else "app.dashed".
    case item(LaunchItem)
    /// `AppLauncher.icon(forApplicationAt:)`.
    case app(URL)
    /// A QR code for the string (M5 pairing), drawn at `Theme.settingsQRCodeSize`.
    case qrCode(String)
    /// M7 L25: a tile's art as it would look with this choice, at preview size.
    case tileArt(itemID: String, TileArtChoice)
    /// M7 L25: a small thumbnail of a picture file.
    case picture(URL)
}

/// What Settings → Tile Art previews (M7 L25).
nonisolated enum TileArtChoice: Hashable, Sendable {
    /// What the tile shows now.
    case current
    case style(TileArtStyle)
    case file(URL)
}

nonisolated struct SettingsRow: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// Right-aligned: "On", "Off", "Allowed", "Hidden"…
    var value: String? = nil
    /// Second line, smaller.
    var detail: String? = nil
    var image: RowImage? = nil
    var showsDisclosure = false
    /// Hidden tiles.
    var isDimmed = false
    /// The tile being moved.
    var isLifted = false
    /// D19 "Relaunch needed" badge; no M2b row sets it (L3).
    var needsRelaunch = false
    /// nil = info row: it takes focus (a ring, not the white highlight), but Select does nothing.
    var action: SettingsAction? = nil
    /// M7g L3, L8: the band's text when focused; an explanation, while `detail` holds status and messages.
    var description: String? = nil
}

nonisolated struct SettingsSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String? = nil
    var rows: [SettingsRow]
    var footer: String? = nil
}

/// Vertical list focus by row id; ids stay stable when rows appear, disappear or move.
nonisolated enum ListFocus {
    /// `current` if it's in `ids`, else the first id, else nil.
    static func resolve(ids: [String], current: String?) -> String? {
        if let current, ids.contains(current) { return current }
        return ids.first
    }

    /// The id `step` positions from the resolved current one, clamped to the ends.
    static func move(ids: [String], current: String?, by step: Int) -> String? {
        guard let resolved = resolve(ids: ids, current: current),
              let index = ids.firstIndex(of: resolved)
        else { return nil }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }
}
