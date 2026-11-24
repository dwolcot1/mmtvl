/// `settings.json` (D16). Every key is optional in the file; missing keys fall back to defaults.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    static let fileName = "settings.json"

    /// Event tap (global Home, media keys). Ignored in `-windowed` mode.
    var globalInputEnabled = true
    var controllersEnabled = true
    var cursorAutoHide = true
    /// Kiosk mode only.
    var launchAtLogin = false
    /// Hand-edited override of the YouTube TV user agent (L6, M3). nil = `YouTubeConfig.defaultUserAgent`.
    var youtubeUserAgent: String?
    /// Phone remote server (M5 L10), in kiosk and -windowed mode alike.
    var phoneRemoteEnabled = true
    /// Hand-edited. HTTP port; the WebSocket uses port + 1. Values outside 1024…65534 fall back to 8765.
    var phoneRemotePort = 8765
    /// Hand-edited "auto" | "receiver" | "tv" | "keys" | "system" | "app" (M5 L8; M7h D44 adds "receiver", step 9c
    /// "tv"). A String, so a typo can't fail the whole file.
    var phoneRemoteVolume = "auto"
    /// M7 L7: which default bindings `key-bindings.json` has seen. A file without the key is revision 1.
    var keyBindingsRevision = KeyBindings.currentRevision
    /// M7 L22: Channel Up zaps up the list like the Up arrow; false = the higher channel number.
    var channelUpMovesUpList = true
    /// M7b L5: answer YouTube DIAL casts (Settings → Casting).
    var youtubeCastEnabled = true
    /// M7b L3: the DIAL device uuid, made once at launch.
    var castDeviceID: String?
    /// M7b L18: keep Reflector 4 running hidden (Settings → Casting → Android).
    var reflectorAutoStart = true
    /// M7c L6 (D36): kiosk mode keeps other apps out (⌘Tab, ⌘Q, the Dock); Settings root → Keep Other Apps Out.
    var kioskLock = true
    /// M7c L15 (D37): the Live TV tile plays the last channel, muted, behind the home screen (Settings → Live TV).
    var homeLivePreview = true
    /// M7c L28: "Version 1.1.0 Build 2" under the home screen's clock while testing (Settings root → About).
    var showVersionOnHome = true
    /// M7c L32: the tile focused when MMTVL opens (a `launch-items.json` id; Settings → a tile → Start Here).
    /// Missing or hidden: the first tile.
    var homeStartTile = "plex"
    /// M7f L4: use the guide the playlist names instead of the pasted guides (kept in the Keychain).
    /// Settings → Live TV → Guide Source; only offered when the playlist names a guide.
    var usePlaylistGuide = false
    /// M7h D43: read the Siri Remote directly (seized; Settings → Remote & Input → Siri Remote), in kiosk and
    /// -windowed mode alike.
    var siriRemoteEnabled = true
    /// M7h step 13e (user decision 2026-11-08): swipes on the Siri Remote's touch surface move focus, like an Apple TV
    /// (Settings → Remote & Input → Siri Remote → Swipes). Off: touches do nothing outside trackpad mode.
    var siriRemoteSwipes = false
    /// M7h D44, L11: the receiver's brand; `none` = no receiver control (no port is opened). Unknown values read as
    /// `none`.
    var receiverBrand = ReceiverBrand.none
    /// M7h D44: `serial` | `network` | (step 9c) `cec`, a receiver over HDMI-CEC. Unknown values read as `serial`.
    var receiverConnection = ReceiverConnection.serial
    /// M7h L11: a `/dev/cu.*` path; nil = the first USB serial port found.
    var receiverSerialPort: String?
    /// M7h L17: the receiver's IP address or host name (network connection). It must be, or resolve to, a LAN
    /// address (`LANAddress`).
    var receiverHost: String?
    /// M7h L17: overrides the brand's control port; outside 1…65535, or not a number, it's ignored.
    var receiverNetworkPort: Int?
    /// M7h step 10 (user decision): the loudest MMTVL's volume buttons set the receiver, in dB. A value that isn't a
    /// number within `ReceiverLine.plausibleDB` reads as the default.
    var receiverMaxDB = 0.0
    /// M7h L18: the TV's brand; `none` = no TV control, `cec` = HDMI-CEC through the Mac's HDMI (step 9, reopened).
    /// Unknown values read as `none`.
    var tvBrand = TVBrand.none
    /// M7h L18: the TV's IP address or host name; like `receiverHost`, it must be, or resolve to, a LAN address.
    /// Never committed or logged beyond the host.
    var tvHost: String?
    /// M7h L18: the TV's wired MAC for Wake-on-LAN (from Find TV). Never committed or logged.
    var tvMAC: String?
    /// M7h step 13b (user request): the volume toast for the Siri Remote's and the keyboard's volume presses
    /// (Settings → Audio & TV → Show Volume). Off hides the level and Muted toasts; the
    /// `.unavailable` error toasts still show.
    var volumeToast = true
    /// M7h step 9c (user decision 2026-11-08): with no receiver ready, the volume buttons change the TV's own volume
    /// (HDMI-CEC or a network VIERA; Settings → Audio & TV → TV → Volume Buttons Change TV Volume).
    var tvVolumeEnabled = false
    /// M7l L2 (D46): how see-through every glass panel and tile rim is (Settings → System → Glass). Unknown values
    /// read as `clear`.
    var glassStyle = GlassStyle.clear
    /// M7m L29: initials ("ULM", "BUF") count as team names in programmes and game entries (Settings → Live TV →
    /// My Teams → Match Initials).
    var teamMatchInitials = false
    /// M7m L29: a programme naming only a nickname ("The Cougars meet the Bearcats") counts for the teams with it
    /// (Settings → Live TV → My Teams → Match Nicknames Alone).
    var teamMatchNicknames = false
    /// M7j L14: find HDHomeRun tuners on the network and add their channels to Live TV (Settings → Live TV →
    /// Antenna → Use Antenna). Off: no discovery, no lineup, no antenna channels.
    var antennaEnabled = true
    /// M7j L10, L11: antenna channels' guide from SiliconDust (Settings → Live TV → Antenna → Guide from SiliconDust).
    /// Off: they're matched against the pasted guides.
    var antennaGuide = true
    /// M15 L5: check GitHub for new versions once a day and show a notice on the home screen (Settings → System →
    /// Software Update → Check for Updates). Check Now works either way.
    var updateChecks = true
    /// M15 L5, L7: `off` | `whenIdle` | `atNight` (Settings → System → Software Update → Automatic Updates). Unknown
    /// values read as `off`.
    var automaticUpdates = AutomaticUpdates.off

    /// M7m L29: the matcher's options from the two switches (`IPTVLibrary.teamMatchOptions`).
    var teamMatchOptions: TeamMatchOptions { TeamMatchOptions(initials: teamMatchInitials, nicknames: teamMatchNicknames) }
    var volumeMode: VolumeMode { VolumeMode(rawValue: phoneRemoteVolume) ?? .auto }
    /// Step 9c (build 25 security L2): a receiver is set up in Settings (a brand, or HDMI-CEC), whether or not its
    /// connection is usable (a network receiver without a usable `receiverHost` counts). The TV gets the volume
    /// buttons only when this is false (`VolumeController.receiverSetUp`).
    var receiverIsSetUp: Bool { receiverBrand != .none || receiverConnection == .cec }
    var validatedPhoneRemotePort: Int { (1024...65534).contains(phoneRemotePort) ? phoneRemotePort : 8765 }
    /// `receiverNetworkPort` when it's a TCP port, else nil (the brand's ports).
    var validatedReceiverNetworkPort: UInt16? {
        receiverNetworkPort.flatMap { (1...65535).contains($0) ? UInt16($0) : nil }
    }

    /// `receiverMaxDB` when it's within `ReceiverLine.plausibleDB`, else the default (0 dB).
    var validatedReceiverMaxDB: Double {
        ReceiverLine.plausibleDB.contains(receiverMaxDB) ? receiverMaxDB : AppSettings().receiverMaxDB
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        globalInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalInputEnabled) ?? defaults.globalInputEnabled
        controllersEnabled = try container.decodeIfPresent(Bool.self, forKey: .controllersEnabled) ?? defaults.controllersEnabled
        cursorAutoHide = try container.decodeIfPresent(Bool.self, forKey: .cursorAutoHide) ?? defaults.cursorAutoHide
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        youtubeUserAgent = try container.decodeIfPresent(String.self, forKey: .youtubeUserAgent)
        phoneRemoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .phoneRemoteEnabled) ?? defaults.phoneRemoteEnabled
        phoneRemotePort = try container.decodeIfPresent(Int.self, forKey: .phoneRemotePort) ?? defaults.phoneRemotePort
        phoneRemoteVolume = try container.decodeIfPresent(String.self, forKey: .phoneRemoteVolume) ?? defaults.phoneRemoteVolume
        keyBindingsRevision = try container.decodeIfPresent(Int.self, forKey: .keyBindingsRevision) ?? 1
        channelUpMovesUpList = try container.decodeIfPresent(Bool.self, forKey: .channelUpMovesUpList)
            ?? defaults.channelUpMovesUpList
        youtubeCastEnabled = try container.decodeIfPresent(Bool.self, forKey: .youtubeCastEnabled)
            ?? defaults.youtubeCastEnabled
        castDeviceID = try container.decodeIfPresent(String.self, forKey: .castDeviceID)
        reflectorAutoStart = try container.decodeIfPresent(Bool.self, forKey: .reflectorAutoStart)
            ?? defaults.reflectorAutoStart
        kioskLock = try container.decodeIfPresent(Bool.self, forKey: .kioskLock) ?? defaults.kioskLock
        homeLivePreview = try container.decodeIfPresent(Bool.self, forKey: .homeLivePreview) ?? defaults.homeLivePreview
        showVersionOnHome = try container.decodeIfPresent(Bool.self, forKey: .showVersionOnHome)
            ?? defaults.showVersionOnHome
        homeStartTile = try container.decodeIfPresent(String.self, forKey: .homeStartTile) ?? defaults.homeStartTile
        usePlaylistGuide = try container.decodeIfPresent(Bool.self, forKey: .usePlaylistGuide) ?? defaults.usePlaylistGuide
        siriRemoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriRemoteEnabled) ?? defaults.siriRemoteEnabled
        // Strings, so an unknown or misspelled brand can't fail the whole file; read with `try?`, so a value of
        // another type (`"receiverHost": 12`) reads as the default instead of sending the file to `.bak` (step 9b S6).
        receiverBrand = ((try? container.decodeIfPresent(String.self, forKey: .receiverBrand)) ?? nil)
            .flatMap(ReceiverBrand.init(rawValue:)) ?? defaults.receiverBrand
        receiverConnection = ((try? container.decodeIfPresent(String.self, forKey: .receiverConnection)) ?? nil)
            .flatMap(ReceiverConnection.init(rawValue:)) ?? defaults.receiverConnection
        receiverSerialPort = (try? container.decodeIfPresent(String.self, forKey: .receiverSerialPort)) ?? nil
        receiverHost = (try? container.decodeIfPresent(String.self, forKey: .receiverHost)) ?? nil
        // Hand-edited: a string or a fraction reads as nil instead of failing the whole file.
        receiverNetworkPort = (try? container.decodeIfPresent(Int.self, forKey: .receiverNetworkPort)) ?? nil
        // Hand-edited: another type, or a value out of range, reads as the default (S6).
        receiverMaxDB = ((try? container.decodeIfPresent(Double.self, forKey: .receiverMaxDB)) ?? nil)
            .flatMap { ReceiverLine.plausibleDB.contains($0) ? $0 : nil } ?? defaults.receiverMaxDB
        // Hand-edited: a value of another type reads as the default instead of failing the whole file (S6).
        tvBrand = ((try? container.decodeIfPresent(String.self, forKey: .tvBrand)) ?? nil)
            .flatMap(TVBrand.init(rawValue:)) ?? defaults.tvBrand
        tvHost = (try? container.decodeIfPresent(String.self, forKey: .tvHost)) ?? nil
        tvMAC = (try? container.decodeIfPresent(String.self, forKey: .tvMAC)) ?? nil
        // Step 13b: a value of another type reads as the default instead of failing the whole file (S6).
        volumeToast = ((try? container.decodeIfPresent(Bool.self, forKey: .volumeToast)) ?? nil) ?? defaults.volumeToast
        // Step 9c: likewise.
        tvVolumeEnabled = ((try? container.decodeIfPresent(Bool.self, forKey: .tvVolumeEnabled)) ?? nil)
            ?? defaults.tvVolumeEnabled
        // Step 13e: likewise.
        siriRemoteSwipes = ((try? container.decodeIfPresent(Bool.self, forKey: .siriRemoteSwipes)) ?? nil)
            ?? defaults.siriRemoteSwipes
        // M7l step 2: like `receiverBrand`, an unknown step or a value of another type reads as the default (S6).
        glassStyle = ((try? container.decodeIfPresent(String.self, forKey: .glassStyle)) ?? nil)
            .flatMap(GlassStyle.init(rawValue:)) ?? defaults.glassStyle
        // M7m L29: like `siriRemoteSwipes`, a value of another type reads as the default (S6).
        teamMatchInitials = ((try? container.decodeIfPresent(Bool.self, forKey: .teamMatchInitials)) ?? nil)
            ?? defaults.teamMatchInitials
        teamMatchNicknames = ((try? container.decodeIfPresent(Bool.self, forKey: .teamMatchNicknames)) ?? nil)
            ?? defaults.teamMatchNicknames
        // M7j L14: likewise.
        antennaEnabled = ((try? container.decodeIfPresent(Bool.self, forKey: .antennaEnabled)) ?? nil)
            ?? defaults.antennaEnabled
        antennaGuide = ((try? container.decodeIfPresent(Bool.self, forKey: .antennaGuide)) ?? nil)
            ?? defaults.antennaGuide
        // M15 L5: like `antennaGuide` and `glassStyle`, a value of another type, or an unknown mode, reads as the
        // default (S6).
        updateChecks = ((try? container.decodeIfPresent(Bool.self, forKey: .updateChecks)) ?? nil)
            ?? defaults.updateChecks
        automaticUpdates = ((try? container.decodeIfPresent(String.self, forKey: .automaticUpdates)) ?? nil)
            .flatMap(AutomaticUpdates.init(rawValue:)) ?? defaults.automaticUpdates
    }
}
