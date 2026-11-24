import Foundation

/// Everything the Settings model does with side effects. The app wires the real thing; tests pass fakes.
struct SettingsEnvironment {
    var isKiosk: Bool
    /// M7c L28: shown in Settings → About.
    var version: AppVersion
    /// Apply live + save `settings.json`.
    var applySettings: (AppSettings) -> Void
    /// `AppRouter.setItems` + save `launch-items.json`.
    var applyItems: ([LaunchItem]) -> Void
    var isAccessibilityTrusted: () -> Bool
    var requestAccessibility: () -> Void
    var loginItemStatus: () -> LoginItemStatus
    var openLoginItemsSettings: () -> Void
    var scanInstalledApps: () async -> [InstalledApp]
    var relaunch: () -> Void
    /// M15 step 1: `PowerController.restartMac()` (Settings → System → Restart Mac mini).
    var restartMac: () -> Void
    var exitToDesktop: () -> Void
    /// `AppLauncher.title(for:)`.
    var tileTitle: (LaunchItem) -> String
    /// `AppLauncher.isInstalled(_:)`.
    var isInstalled: (LaunchItem) -> Bool
    /// A launcher PIN is stored (D20).
    var hasPIN: () -> Bool
    /// `AppRouter.requestPIN(_:)`.
    var startPINFlow: (PINPurpose) -> Void
    /// `YouTubeController.reload()`.
    var reloadYouTube: () -> Void
    /// `YouTubeController.clearData()`, fire and forget.
    var clearYouTubeData: () -> Void
    var iptvStatus: () -> IPTVSettingsStatus
    /// Reads the clipboard. Returns an error message, or nil on success; on success it starts the save + refresh.
    var pasteIPTVURL: (IPTVURLKind) -> String?
    /// `IPTVLibrary.moveGuideSource(_:by:)`, fire and forget.
    var moveGuideSource: (String, Int) -> Void
    /// `IPTVLibrary.removeGuideSource(_:)`, fire and forget.
    var removeGuideSource: (String) -> Void
    /// `IPTVLibrary.setGroupHidden(_:_:)`.
    var setIPTVGroupHidden: (String, Bool) -> Void
    /// `IPTVLibrary.setChannelHidden(id, false)`.
    var unhideIPTVChannel: (String) -> Void
    /// M7f L13: `IPTVLibrary.setTeamPicked(_:_:)`.
    var setTeamPicked: (Team.ID, Bool) -> Void
    var refreshIPTV: () -> Void
    var removeIPTVSource: () -> Void
    /// M7j L14: Find Tuners: `IPTVLibrary.discoverAntenna()` (a search, then the lineups), then
    /// `AntennaSource.findOutcome(found:)`.
    var findAntennaTuners: () async -> AntennaFindOutcome
    /// M7j L14: `IPTVLibrary.setChannelHidden(_:_:)` (Antenna → Channels).
    var setChannelHidden: (Channel.ID, Bool) -> Void
    /// M7j L18: `IPTVLibrary.startAntennaScan()` (the confirm page's Scan) and `stopAntennaScan()` (Stop Scan).
    var startAntennaScan: () -> Void
    var stopAntennaScan: () -> Void
    /// M7j L18: true exactly while Settings → Antenna is the top page (`IPTVLibrary.antennaPageVisible(_:)`).
    var antennaPageVisible: (Bool) -> Void
    var phoneRemoteStatus: () -> PhoneRemoteSettingsStatus
    /// `PhoneRemote.setPairing(_:)`: true while Pair a Phone shows (M5 L3).
    var setPhonePairing: (Bool) -> Void
    var forgetAllPhones: () -> Void
    /// M7: apply to `InputRouter` + save `key-bindings.json`.
    var applyBindings: (KeyBindings) -> Void
    /// M7 L8: non-nil while learning a button (`InputRouter.captureHandler`); nil stops.
    var setButtonLearning: (((InputBinding.Trigger) -> Void)?) -> Void
    /// M7 L3: the tile's custom picture, e.g. "plex.png"; nil when none.
    var tileArtFileName: (String) -> String?
    /// M7 L15: Settings → Plex.
    var plexStatus: () -> PlexSettingsStatus
    /// True exactly while the Plex link page shows (makes and polls a plex.tv/link code).
    var setPlexLinking: (Bool) -> Void
    var choosePlexServer: (String) -> Void
    var signOutOfPlex: () -> Void
    /// L17: opening the Plex page retries a failed connection.
    var refreshPlex: () -> Void
    /// M7 L23: the tile's Chromium web app identity; nil for other tiles.
    var webAppInfo: (LaunchItem) -> WebAppInfo?
    /// Reads the clipboard as a web address (`ClipboardURL.parse`).
    var pasteURL: () -> Result<URL, ClipboardURL.Problem>
    /// M7 L25: pictures in Downloads, Pictures and Desktop (run off the main actor; may ask for folder access).
    var findPictures: () async -> [PictureFile]
    /// Copies a picture into `tile-art/` for the tile. Returns an error message, or nil.
    var setTilePicture: (String, URL) -> String?
    var removeTilePicture: (String) -> Void
    /// M7b L14: Settings → Casting.
    var castingStatus: () -> CastingSettingsStatus
    /// Runs the AirPlay probe; when done, the app calls `refreshStatus()`.
    var refreshCasting: () -> Void
    var openAirPlaySettings: () -> Void
    /// M7h D43: Settings → Siri Remote.
    var siriRemoteStatus: () -> SiriRemoteSettingsStatus
    /// M7h D44: the receiver link, from `ReceiverController`.
    var receiverStatus: () -> ReceiverSettingsStatus
    /// `SerialPort.available()`, read when the Serial Port list opens.
    var serialPorts: () -> [SerialPortInfo]
    /// L12: the chosen brand's read-only queries on the configured link.
    var testReceiver: () async -> ReceiverTestOutcome
    /// L12: each brand's read-only queries on the serial port (nil = Automatic); the brand that answered.
    var findReceiverOnPort: (String?) async -> ReceiverBrand?
    /// L17: SSDP, then each candidate's read-only queries (`receiverNetworkPort` overrides the port).
    var findReceiversOnNetwork: (UInt16?) async -> [FoundReceiver]
    /// L18: read-only; nil when no TV is set up with a usable address.
    var testTV: () async -> TVTestResult?
    /// L18: SSDP for VIERAs.
    var findTVs: () async -> [FoundTV]
    /// Step 9 (reopened): HDMI-CEC's last known tunnel state (`HDMICEC.availability`); nil before the first check.
    var cecAvailability: () -> CECAvailability?
    /// Checks the tunnel (read-only); when done, the app calls `refreshStatus()`.
    var refreshCEC: () -> Void
    /// Test TV with HDMI-CEC: Give Device Power Status; nil = no answer (or the tunnel isn't ready).
    var testCEC: () async -> CECPowerStatus?
    /// Step 9c: the receiver over HDMI-CEC (`CECAudioSystem`).
    var cecReceiverStatus: () -> CECReceiverSettingsStatus
    /// Step 9c: Test Connection with HDMI-CEC, and Find Receiver after the serial brands: Give Device Power Status and
    /// Give OSD Name to the receiver (read-only).
    var testCECReceiver: () async -> CECReceiverTest
    /// Debug builds: the toast panel (L8), for Settings → Siri Remote → Status.
    var showToast: (String) -> Void
}
