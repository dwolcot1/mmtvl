import Foundation
@testable import MMTVL

/// Records what the Settings model asks the app to do, and serves fake status.
final class SettingsRecorder {
    var appliedSettings: [AppSettings] = []
    var appliedItems: [[LaunchItem]] = []
    var accessibilityRequests = 0
    var loginItemsOpened = 0
    var relaunches = 0
    /// M15 step 1: Restart Mac mini.
    var restarts = 0
    /// M15 step 8: Software Update.
    var updateStatus = UpdateStatus.idle(lastChecked: nil)
    var lastUpdateCheck: Date?
    var updateTestFeedHost: String?
    var updateChecks = 0
    var updateInstalls = 0
    var exits = 0
    var trusted: Bool
    var loginStatus: LoginItemStatus
    var installedApps: [InstalledApp] = []
    var hasPIN = false
    /// Step 13e: how often the PIN (Keychain) and the login item (SMAppService) were read.
    var pinReads = 0
    var loginItemReads = 0
    var pinFlows: [PINPurpose] = []
    var youtubeReloads = 0
    var youtubeClears = 0
    var iptv = IPTVSettingsStatus()
    var pasteResult: String? = nil
    var pastes: [IPTVURLKind] = []
    var iptvRefreshes = 0
    var iptvRemovals = 0
    var guideMoves: [GuideMove] = []
    var guideRemovals: [String] = []
    var groupHides: [GroupHide] = []
    var teamPicks: [TeamPick] = []
    var unhiddenChannels: [String] = []
    /// M7j L14: Find Tuners answers at once with this.
    var antennaFindResult = AntennaFindOutcome.noneFound
    var antennaFinds = 0
    var channelHides: [ChannelHide] = []
    /// M7j L18: the channel scan's start and stop, and each Antenna page visibility change.
    var antennaScanStarts = 0
    var antennaScanStops = 0
    var antennaPageVisibility: [Bool] = []
    var phoneRemote = PhoneRemoteSettingsStatus()
    var pairingCalls: [Bool] = []
    var forgets = 0
    var appliedBindings: [KeyBindings] = []
    /// The capture handler while Settings learns a button (M7 L8).
    var learningHandler: ((InputBinding.Trigger) -> Void)?
    var learningCalls: [Bool] = []
    /// Tile id → custom picture name (M7 L3).
    var tileArtNames: [String: String] = [:]
    /// M7 Settings → Plex.
    var plex = PlexSettingsStatus()
    var plexLinkingCalls: [Bool] = []
    var chosenPlexServers: [String] = []
    var plexSignOuts = 0
    var plexRefreshes = 0
    /// M7 L23: web app identity per tile id, and what the clipboard holds.
    var webApps: [String: WebAppInfo] = [:]
    var clipboard: String?
    /// M7 L25.
    var pictures: [PictureFile] = []
    var pictureSets: [String] = []
    var pictureSetResult: String?
    var pictureRemovals: [String] = []
    /// M7b Settings → Casting.
    var casting = CastingSettingsStatus()
    var castingRefreshes = 0
    var airPlaySettingsOpened = 0
    /// M7h step 11: Siri Remote, and Audio & TV's Receiver and TV (13c). The async checks answer at once with these.
    var siriRemote = SiriRemoteSettingsStatus()
    var receiver = ReceiverSettingsStatus()
    var serialPorts: [SerialPortInfo] = []
    var serialPortReads = 0
    var receiverTestOutcome = ReceiverTestOutcome()
    var receiverTests = 0
    var serialFindResult: ReceiverBrand?
    var serialFinds: [String?] = []
    var networkFindResult: [FoundReceiver] = []
    var networkFinds: [UInt16?] = []
    var tvTestResult: TVTestResult?
    var tvTests = 0
    var tvFindResult: [FoundTV] = []
    var tvFinds = 0
    /// Step 9 (reopened): HDMI-CEC.
    var cec: CECAvailability?
    var cecRefreshes = 0
    var cecTestResult: CECPowerStatus?
    var cecTests = 0
    /// Step 9c: the receiver over HDMI-CEC.
    var cecReceiver = CECReceiverSettingsStatus()
    var cecReceiverTestResult = CECReceiverTest()
    var cecReceiverTests = 0
    var toasts: [String] = []

    init(trusted: Bool, loginStatus: LoginItemStatus) {
        self.trusted = trusted
        self.loginStatus = loginStatus
    }
}

struct GuideMove: Equatable {
    var id: String
    var step: Int
}

struct TeamPick: Equatable {
    var id: String
    var picked: Bool
}

struct ChannelHide: Equatable {
    var id: String
    var hidden: Bool
}

struct GroupHide: Equatable {
    var name: String
    var hidden: Bool
}

func makeSettingsModel(
    kiosk: Bool = true,
    trusted: Bool = true,
    loginStatus: LoginItemStatus = .notRegistered,
    settings: AppSettings = AppSettings(),
    items: [LaunchItem] = LaunchItem.defaults,
    hasPIN: Bool = false,
    bindings: KeyBindings = .defaults
) -> (SettingsModel, SettingsRecorder) {
    let recorder = SettingsRecorder(trusted: trusted, loginStatus: loginStatus)
    recorder.hasPIN = hasPIN
    let environment = SettingsEnvironment(
        isKiosk: kiosk,
        version: AppVersion(version: "1.1.0", build: "7"),
        applySettings: { recorder.appliedSettings.append($0) },
        applyItems: { recorder.appliedItems.append($0) },
        isAccessibilityTrusted: { recorder.trusted },
        requestAccessibility: { recorder.accessibilityRequests += 1 },
        loginItemStatus: {
            recorder.loginItemReads += 1
            return recorder.loginStatus
        },
        openLoginItemsSettings: { recorder.loginItemsOpened += 1 },
        scanInstalledApps: { recorder.installedApps },
        relaunch: { recorder.relaunches += 1 },
        restartMac: { recorder.restarts += 1 },
        updateStatus: { recorder.updateStatus },
        lastUpdateCheck: { recorder.lastUpdateCheck },
        updateTestFeedHost: { recorder.updateTestFeedHost },
        // Like `SoftwareUpdater.checkNow()`: the status goes to checking.
        checkForUpdates: {
            recorder.updateChecks += 1
            recorder.updateStatus = .checking
        },
        installUpdate: { recorder.updateInstalls += 1 },
        exitToDesktop: { recorder.exits += 1 },
        tileTitle: { $0.title },
        isInstalled: { _ in true },
        hasPIN: {
            recorder.pinReads += 1
            return recorder.hasPIN
        },
        startPINFlow: { recorder.pinFlows.append($0) },
        reloadYouTube: { recorder.youtubeReloads += 1 },
        clearYouTubeData: { recorder.youtubeClears += 1 },
        iptvStatus: { recorder.iptv },
        pasteIPTVURL: { kind in
            recorder.pastes.append(kind)
            return recorder.pasteResult
        },
        moveGuideSource: { recorder.guideMoves.append(GuideMove(id: $0, step: $1)) },
        removeGuideSource: { recorder.guideRemovals.append($0) },
        setIPTVGroupHidden: { recorder.groupHides.append(GroupHide(name: $0, hidden: $1)) },
        unhideIPTVChannel: { recorder.unhiddenChannels.append($0) },
        setTeamPicked: { recorder.teamPicks.append(TeamPick(id: $0, picked: $1)) },
        refreshIPTV: { recorder.iptvRefreshes += 1 },
        removeIPTVSource: { recorder.iptvRemovals += 1 },
        findAntennaTuners: {
            recorder.antennaFinds += 1
            return recorder.antennaFindResult
        },
        setChannelHidden: { recorder.channelHides.append(ChannelHide(id: $0, hidden: $1)) },
        startAntennaScan: { recorder.antennaScanStarts += 1 },
        stopAntennaScan: { recorder.antennaScanStops += 1 },
        antennaPageVisible: { recorder.antennaPageVisibility.append($0) },
        phoneRemoteStatus: { recorder.phoneRemote },
        setPhonePairing: { recorder.pairingCalls.append($0) },
        forgetAllPhones: { recorder.forgets += 1 },
        applyBindings: { recorder.appliedBindings.append($0) },
        setButtonLearning: { handler in
            recorder.learningHandler = handler
            recorder.learningCalls.append(handler != nil)
        },
        tileArtFileName: { recorder.tileArtNames[$0] },
        plexStatus: { recorder.plex },
        setPlexLinking: { recorder.plexLinkingCalls.append($0) },
        choosePlexServer: { recorder.chosenPlexServers.append($0) },
        signOutOfPlex: { recorder.plexSignOuts += 1 },
        refreshPlex: { recorder.plexRefreshes += 1 },
        webAppInfo: { recorder.webApps[$0.id] },
        pasteURL: { ClipboardURL.parse(recorder.clipboard) },
        findPictures: { recorder.pictures },
        setTilePicture: { id, url in
            recorder.pictureSets.append("\(id) ← \(url.lastPathComponent)")
            if recorder.pictureSetResult == nil { recorder.tileArtNames[id] = "\(id).\(url.pathExtension.lowercased())" }
            return recorder.pictureSetResult
        },
        removeTilePicture: { id in
            recorder.pictureRemovals.append(id)
            recorder.tileArtNames[id] = nil
        },
        castingStatus: { recorder.casting },
        refreshCasting: { recorder.castingRefreshes += 1 },
        openAirPlaySettings: { recorder.airPlaySettingsOpened += 1 },
        siriRemoteStatus: { recorder.siriRemote },
        receiverStatus: { recorder.receiver },
        serialPorts: {
            recorder.serialPortReads += 1
            return recorder.serialPorts
        },
        testReceiver: {
            recorder.receiverTests += 1
            return recorder.receiverTestOutcome
        },
        findReceiverOnPort: { path in
            recorder.serialFinds.append(path)
            return recorder.serialFindResult
        },
        findReceiversOnNetwork: { port in
            recorder.networkFinds.append(port)
            return recorder.networkFindResult
        },
        testTV: {
            recorder.tvTests += 1
            return recorder.tvTestResult
        },
        findTVs: {
            recorder.tvFinds += 1
            return recorder.tvFindResult
        },
        cecAvailability: { recorder.cec },
        refreshCEC: { recorder.cecRefreshes += 1 },
        testCEC: {
            recorder.cecTests += 1
            return recorder.cecTestResult
        },
        cecReceiverStatus: { recorder.cecReceiver },
        testCECReceiver: {
            recorder.cecReceiverTests += 1
            return recorder.cecReceiverTestResult
        },
        showToast: { recorder.toasts.append($0) }
    )
    return (SettingsModel(settings: settings, items: items, environment: environment, bindings: bindings), recorder)
}

extension SettingsModel {
    /// Sends commands like a remote would.
    func press(_ commands: RemoteCommand...) {
        for command in commands { _ = handle(command) }
    }

    /// M7g L6: opens a root category (or any page) like selecting its row.
    func open(_ page: SettingsPage) {
        perform(.push(page))
    }
}

/// A tile art store on an empty temporary folder, so tests never read the real one (M7 L3).
func makeTestTileArt() -> TileArtStore {
    TileArtStore(directory: FileManager.default.temporaryDirectory.appending(path: "mmtvl-tile-art-\(UUID().uuidString)"))
}
