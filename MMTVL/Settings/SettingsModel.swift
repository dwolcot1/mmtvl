import AppKit
import Observation

/// The Settings screen (D19): a navigation stack of pages built from data (L4), driven by `RemoteCommand`s.
@Observable
final class SettingsModel {
    struct PageState: Equatable {
        var page: SettingsPage
        var focusedRowID: String?
    }

    /// M7g L1: one column of the sliding track; the view draws `columns` left to right.
    struct Column: Identifiable, Equatable {
        enum Role: Equatable {
            /// The page below the top one: dimmed, its opening row selected (or the top page's accessory).
            case parent
            /// The top page, with focus.
            case current
            /// The empty slot to the right of the current page (at the root, off to the right of the centered list).
            case empty
            /// Older pages, off screen to the left.
            case hidden
        }

        let index: Int
        /// nil for `.empty`.
        let page: SettingsPage?
        let role: Role
        var id: Int { index }
    }

    private(set) var settings: AppSettings
    /// All tiles in stored order, hidden ones included.
    private(set) var items: [LaunchItem]
    /// Never empty.
    private(set) var stack: [PageState] = [PageState(page: .root, focusedRowID: nil)]
    /// Move mode on the homeScreen page.
    private(set) var movingTileID: String?
    private(set) var isAccessibilityTrusted: Bool
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var hasPIN: Bool
    /// nil = loading (addTile page).
    private(set) var installedApps: [InstalledApp]?
    private(set) var iptv: IPTVSettingsStatus
    /// The last paste error; the paste row's detail. Cleared on any push/pop and on a successful paste.
    private(set) var pasteMessage: String?
    /// Which paste row `pasteMessage` belongs to.
    private(set) var pasteMessageKind: IPTVURLKind?
    private(set) var phoneRemote: PhoneRemoteSettingsStatus
    /// M7: Settings → Plex.
    private(set) var plex: PlexSettingsStatus
    /// M7b: Settings → Casting.
    private(set) var casting: CastingSettingsStatus
    /// M7: `key-bindings.json`, edited on the Remote Buttons pages.
    private(set) var bindings: KeyBindings
    /// M7 L25: pictures for the Tile Art page; nil while looking.
    private(set) var pictures: [PictureFile]?
    /// M7 L25: a failed copy; the page's message until the next push/pop.
    private(set) var tileArtMessage: String?
    /// M7 L23: the last start page paste error; the Start Page row's detail until the next push/pop.
    private(set) var startURLMessage: String?
    /// M7 L8: "No button pressed" after learning timed out; the Add a Button row's detail until the next push/pop.
    private(set) var learnMessage: String?
    /// M7h: Settings → Siri Remote.
    private(set) var siriRemote: SiriRemoteSettingsStatus
    /// M7h: Settings → Audio & TV → Receiver, the receiver link.
    private(set) var receiver: ReceiverSettingsStatus
    /// M7h: the Serial Port list, read when it opens.
    private(set) var serialPorts: [SerialPortInfo] = []
    /// M7h L17: Find on Network's answers, for its chooser.
    private(set) var foundReceivers: [FoundReceiver] = []
    /// M7h: each check's row detail: "Testing…" / "Searching…", then its result. Cleared when the receiver's (or the
    /// TV's) settings change, and when Receiver (or TV) opens.
    private(set) var probeLines: [SettingsProbe: String] = [:]
    /// Step 9 (reopened): Audio & TV → TV → Status with HDMI-CEC; nil before the first check.
    private(set) var cec: CECAvailability?
    /// Step 9c: Audio & TV → Receiver with Connection HDMI-CEC.
    private(set) var cecReceiver: CECReceiverSettingsStatus
    /// M7h D41: the address page's keyboard, and whether it has focus (else the rows below it).
    private(set) var keyboard = OnScreenKeyboard()
    private(set) var isKeyboardFocused = true
    /// M7h: the address page's error ("Use a LAN address…") until the next push/pop.
    private(set) var addressMessage: String?
    /// M15 step 8: Settings → System → Software Update (`SoftwareUpdater`).
    private(set) var updates: UpdateStatus
    private(set) var lastUpdateCheck: Date?
    /// N1: the test feed's host; nil when the feed is Info.plist's.
    private(set) var updateTestFeedHost: String?
    /// How long `.learnButton` waits for a press (L8).
    @ObservationIgnored var learnTimeout: Duration = .seconds(10)
    /// Injectable clock (the confirm page's Select delay, the column click guard).
    @ObservationIgnored var now: () -> Date = Date.init
    /// The system's double-click interval, read at each click; injectable for tests.
    @ObservationIgnored var doubleClickInterval: () -> TimeInterval = { NSEvent.doubleClickInterval }
    /// When a click on the parent column last changed the page (the row click guard).
    @ObservationIgnored private var columnClickedAt: Date?
    /// The running learn timeout; tests await it.
    @ObservationIgnored private(set) var learnTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isLearning = false
    /// The plex.tv/link code is made and polled while the Plex link page shows (M7 L15).
    @ObservationIgnored private var isPlexLinking = false
    /// M7j L18: Settings → Antenna is the top page (told to the environment on each change).
    @ObservationIgnored private var isAntennaPageVisible = false
    @ObservationIgnored private var learnConfirmShownAt: Date?
    /// M7h: the running checks; tests await them. A check whose token was dropped (settings changed) is ignored.
    @ObservationIgnored private(set) var probeTasks: [SettingsProbe: Task<Void, Never>] = [:]
    @ObservationIgnored private var probeTokens: [SettingsProbe: Int] = [:]
    @ObservationIgnored private var nextProbeToken = 0
    @ObservationIgnored let environment: SettingsEnvironment
    /// Channel Up/Down move focus by this many rows (M7 L5).
    static let pageRows = 8
    /// The phone pairing code is valid while Pair a Phone shows (M5 L3).
    @ObservationIgnored private var isPairing = false
    /// L8: a held key's auto-repeat mustn't confirm a learned button by itself.
    static let learnConfirmDelay: TimeInterval = 0.6

    init(settings: AppSettings, items: [LaunchItem], environment: SettingsEnvironment, bindings: KeyBindings = .defaults) {
        self.settings = settings
        self.items = items
        self.bindings = bindings
        self.environment = environment
        isAccessibilityTrusted = environment.isAccessibilityTrusted()
        loginItemStatus = environment.loginItemStatus()
        hasPIN = environment.hasPIN()
        iptv = environment.iptvStatus()
        phoneRemote = environment.phoneRemoteStatus()
        plex = environment.plexStatus()
        casting = environment.castingStatus()
        siriRemote = environment.siriRemoteStatus()
        receiver = environment.receiverStatus()
        cec = environment.cecAvailability()
        cecReceiver = environment.cecReceiverStatus()
        updates = environment.updateStatus()
        lastUpdateCheck = environment.lastUpdateCheck()
        updateTestFeedHost = environment.updateTestFeedHost()
    }

    var page: SettingsPage { stack[stack.count - 1].page }

    /// Every row, info rows included, in display order: Up/Down and Channel Up/Down walk them all (info rows take
    /// focus so a page of mostly info rows doesn't feel stuck; Select on one does nothing).
    var focusableRowIDs: [String] {
        sections.flatMap(\.rows).map(\.id)
    }

    /// Rows with an action, in display order.
    var actionRowIDs: [String] {
        sections.flatMap(\.rows).filter { $0.action != nil }.map(\.id)
    }

    var focusedRowID: String? {
        if isKeyboardActive { return nil }
        return Self.resolveFocus(rows: sections.flatMap(\.rows), current: stack[stack.count - 1].focusedRowID)
    }

    /// `current` if it's one of `rows`, else (a page just opened, or the focused row went away) the first action
    /// row, else the first row: a page opens where it always did, and Up reaches the info rows above it.
    nonisolated static func resolveFocus(rows: [SettingsRow], current: String?) -> String? {
        if let current, rows.contains(where: { $0.id == current }) { return current }
        return rows.first { $0.action != nil }?.id ?? rows.first?.id
    }

    func row(id: String) -> SettingsRow? {
        sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    /// M7g L1: every stack page, then one empty column (the slot a pushed page slides into).
    var columns: [Column] {
        let top = stack.count - 1
        var columns = stack.indices.map { index in
            Column(index: index, page: stack[index].page,
                   role: index == top ? .current : index == top - 1 ? .parent : .hidden)
        }
        columns.append(Column(index: stack.count, page: nil, role: .empty))
        return columns
    }

    /// M7g L1: the row in the parent column that opened the current page; nil at the root.
    var parentSelectionRowID: String? {
        guard stack.count > 1 else { return nil }
        let parent = stack[stack.count - 2]
        let ids = sections(for: parent.page).flatMap(\.rows).filter { $0.action != nil }.map(\.id)
        return ListFocus.resolve(ids: ids, current: parent.focusedRowID)
    }

    /// M7g: a click on the parent column goes back a page, like Back (move mode ends first).
    func activateParentColumn() {
        if movingTileID != nil {
            movingTileID = nil
            return
        }
        guard stack.count > 1 else { return }
        pop()
        columnClickedAt = now()
    }

    func reset() {
        stack = [PageState(page: .root, focusedRowID: nil)]
        movingTileID = nil
        refreshStatus()
        syncPairing()
        syncLearning()
        syncPlexLink()
        syncAntennaPage()
    }

    /// M7m L10 (D50): Settings opened on a tile's page from the home tile menu: root (on Home Screen) → Home Screen
    /// (on the tile's row) → the tile, so Back walks out as if it had been opened by hand. An unknown tile: the root.
    func openTile(_ id: String) {
        reset()
        guard item(id: id) != nil else { return }
        setFocus("homeScreen")
        push(.homeScreen)
        setFocus(Self.tileRowID(id))
        push(.tile(id: id))
    }

    /// Settings closed (the router went home): ends phone pairing, button learning and the Plex link code.
    func screenDidClose() {
        syncLearning(closed: true)
        syncPlexLink(closed: true)
        syncAntennaPage(closed: true)
        guard isPairing else { return }
        isPairing = false
        environment.setPhonePairing(false)
        refreshStatus()
    }

    /// L10: re-read on open, after toggles, after a PIN flow and when the app becomes active.
    func refreshStatus() {
        isAccessibilityTrusted = environment.isAccessibilityTrusted()
        loginItemStatus = environment.loginItemStatus()
        hasPIN = environment.hasPIN()
        iptv = environment.iptvStatus()
        phoneRemote = environment.phoneRemoteStatus()
        plex = environment.plexStatus()
        casting = environment.castingStatus()
        siriRemote = environment.siriRemoteStatus()
        receiver = environment.receiverStatus()
        cec = environment.cecAvailability()
        cecReceiver = environment.cecReceiverStatus()
        refreshUpdates()
        followPlexSignIn()
    }

    /// M7h step 13e: the status a device change touches, for `refreshStatus(_:)`.
    struct StatusParts: OptionSet {
        let rawValue: Int
        /// The receiver over serial or the network (`receiverStatus`).
        static let receiver = StatusParts(rawValue: 1 << 0)
        /// HDMI-CEC: the TV's tunnel (`cecAvailability`) and the receiver over HDMI-CEC (`cecReceiverStatus`).
        static let cec = StatusParts(rawValue: 1 << 1)
        /// The Siri Remote's connection, touch surface and battery (`siriRemoteStatus`).
        static let siriRemote = StatusParts(rawValue: 1 << 2)
        /// The phone remote's server, pairing and phones (`phoneRemoteStatus`).
        static let phoneRemote = StatusParts(rawValue: 1 << 3)
        /// Live TV's playlist and guides (`iptvStatus`).
        static let iptv = StatusParts(rawValue: 1 << 4)
        /// Plex's sign-in, server and link code (`plexStatus`; the link page follows a sign-in).
        static let plex = StatusParts(rawValue: 1 << 5)
        /// Casting: YouTube, AirPlay, Reflector, Plex HTPC (`castingStatus`).
        static let casting = StatusParts(rawValue: 1 << 6)
        /// M15 step 8: the updater's status, last check and feed (`updateStatus`, `lastUpdateCheck`).
        static let updates = StatusParts(rawValue: 1 << 7)
    }

    /// M7h step 13e: whether the Settings screen shows (`AppRouter` sets it). Off screen, the status refreshes below
    /// do nothing: opening Settings (or coming back to it) re-reads everything (`reset`, `AppRouter.returnToSettings`).
    @ObservationIgnored var isShowing: () -> Bool = { true }

    /// M7h step 13e: re-reads only `parts`, and only while Settings shows (a volume press or a receiver line must not
    /// read the Keychain, the login item or any other status on the main actor). Unchanged values aren't assigned, so
    /// the page isn't redrawn for them.
    func refreshStatus(_ parts: StatusParts) {
        guard isShowing() else { return }
        if parts.contains(.receiver) { update(\.receiver, to: environment.receiverStatus()) }
        if parts.contains(.cec) {
            update(\.cec, to: environment.cecAvailability())
            update(\.cecReceiver, to: environment.cecReceiverStatus())
        }
        if parts.contains(.siriRemote) { update(\.siriRemote, to: environment.siriRemoteStatus()) }
        if parts.contains(.phoneRemote) { phoneRemote = environment.phoneRemoteStatus() }
        if parts.contains(.iptv) { iptv = environment.iptvStatus() }
        if parts.contains(.casting) { casting = environment.castingStatus() }
        if parts.contains(.updates) { refreshUpdates() }
        if parts.contains(.plex) {
            plex = environment.plexStatus()
            followPlexSignIn()
        }
    }

    /// M7h step 13e: the full `refreshStatus()`, only while Settings shows (becoming active, Accessibility granted).
    func refreshStatusIfShowing() {
        guard isShowing() else { return }
        refreshStatus()
    }

    /// M15 step 8: unchanged values aren't assigned (a download's progress redraws only when it moves).
    private func refreshUpdates() {
        update(\.updates, to: environment.updateStatus())
        update(\.lastUpdateCheck, to: environment.lastUpdateCheck())
        update(\.updateTestFeedHost, to: environment.updateTestFeedHost())
    }

    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Returns false only for commands it doesn't use, and for Back on the root page (the router then goes home).
    /// `isRepeat`: a held key's or button's auto-repeat. Only a fresh Left or Right changes page; their repeats
    /// are swallowed (so holding Left doesn't run back to the root, nor Right down a chain of pages).
    func handle(_ command: RemoteCommand, isRepeat: Bool = false) -> Bool {
        if isKeyboardActive, let handled = handleKeyboard(command) { return handled }
        switch command {
        case .up, .down:
            let step = command == .up ? -1 : 1
            if case .addressEntry = page, command == .up, focusedRowID == focusableRowIDs.first {
                // M7h: Up from the first row goes back to the keyboard above it.
                isKeyboardFocused = true
                return true
            }
            if let movingTileID, page == .homeScreen {
                updateItems(items.movingItem(id: movingTileID, by: step))
            } else {
                setFocus(ListFocus.move(ids: focusableRowIDs, current: focusedRowID, by: step))
            }
            return true
        case .right:
            // M7g L7 (replaces M2b L13): Right opens a disclosure row; values still don't cycle.
            if !isRepeat, movingTileID == nil, let id = focusedRowID, let action = row(id: id)?.action, case .push = action {
                perform(action)
            }
            return true
        case .left:
            // M7g L7: Left goes back a page, except on the root and while learning a button.
            if case .learnButton = page { return true }
            if !isRepeat, movingTileID == nil, stack.count > 1 { pop() }
            return true
        case .select:
            if case .confirmLearn = page, let shownAt = learnConfirmShownAt,
               now().timeIntervalSince(shownAt) < Self.learnConfirmDelay {
                return true
            }
            if movingTileID != nil {
                movingTileID = nil
            } else if let id = focusedRowID, let action = row(id: id)?.action {
                perform(action)
            }
            return true
        case .back:
            if movingTileID != nil {
                movingTileID = nil
                return true
            }
            guard stack.count > 1 else { return false }
            pop()
            return true
        case .channelUp, .channelDown:
            // M7 L5: a page of rows.
            guard movingTileID == nil else { return true }
            let step = command == .channelUp ? -Self.pageRows : Self.pageRows
            setFocus(ListFocus.move(ids: focusableRowIDs, current: focusedRowID, by: step))
            return true
        case .home, .playPause, .fastForward, .rewind, .menu, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return false
        }
    }

    /// Mouse hover on a row of the current page.
    func focus(rowID: String) {
        focus(rowID: rowID, on: page)
    }

    /// Mouse hover on a row of `page`; ignored unless `page` is the current page (a parent or closing column's
    /// rows never take focus).
    func focus(rowID: String, on page: SettingsPage) {
        guard page == self.page, movingTileID == nil, focusableRowIDs.contains(rowID) else { return }
        isKeyboardFocused = false
        setFocus(rowID)
    }

    /// Mouse click on a row of the current page.
    func activate(rowID: String) {
        activate(rowID: rowID, on: page)
    }

    /// Mouse click on a row of `page`; ignored unless `page` is the current page (a page fading out after a pop or
    /// a replace can still be under the pointer), and within a double-click interval of a column click (its second
    /// click would land on a row of the page the first one opened).
    func activate(rowID: String, on page: SettingsPage) {
        guard page == self.page else { return }
        if let columnClickedAt, now().timeIntervalSince(columnClickedAt) < doubleClickInterval() { return }
        if movingTileID != nil {
            movingTileID = nil
            return
        }
        guard let action = row(id: rowID)?.action else { return }
        isKeyboardFocused = false
        setFocus(rowID)
        perform(action)
    }

    func perform(_ action: SettingsAction) {
        switch action {
        case .toggle(let key):
            var new = settings
            new[keyPath: key.keyPath].toggle()
            settings = new
            environment.applySettings(new)
            // M7j: Find Tuners' last result is about the antenna as it was.
            if key == .antennaEnabled { dropProbes([.findAntennaTuners]) }
            refreshStatus()
        case .setStartTile(let id):
            guard settings.homeStartTile != id, item(id: id)?.isVisible == true else { return }
            var new = settings
            new.homeStartTile = id
            settings = new
            environment.applySettings(new)
        case .requestAccessibility:
            environment.requestAccessibility()
        case .openLoginItemsSettings:
            environment.openLoginItemsSettings()
        case .push(let page):
            push(page)
        case .pop:
            pop()
        case .relaunch:
            environment.relaunch()
        case .restartMac:
            // M15 step 1: `PowerController.restartMac()` toasts when loginwindow refuses.
            environment.restartMac()
            pop()
        case .checkForUpdates:
            environment.checkForUpdates()
            refreshStatus(.updates)
        case .installUpdate:
            environment.installUpdate()
            refreshStatus(.updates)
        case .setAutomaticUpdates(let mode):
            // Like Glass: saved and applied at once (`SoftwareUpdater.apply(checks:mode:)`), then back.
            if settings.automaticUpdates != mode {
                var new = settings
                new.automaticUpdates = mode
                settings = new
                environment.applySettings(new)
            }
            if page == .automaticUpdates { pop() }
        case .exitToDesktop:
            environment.exitToDesktop()
        case .toggleTileVisible(let id):
            guard let item = item(id: id), !item.isSettingsTile else { return }
            updateItems(items.settingHidden(item.isVisible, id: id))
        case .toggleTileFullScreen(let id):
            guard let item = item(id: id) else { return }
            updateItems(items.settingFullScreen(!item.wantsFullScreen, id: id))
        case .startMove(let id):
            pop()
            movingTileID = id
            setFocus(Self.tileRowID(id))
        case .removeTile(let id):
            guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isSettingsTile else { return }
            let neighbor = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            updateItems(items.removingItem(id: id))
            pop()
            setFocus(neighbor.map { Self.tileRowID($0.id) })
        case .addDefaultTile(let id):
            guard let item = LaunchItem.defaults.first(where: { $0.id == id }) else { return }
            addTile(item)
        case .addApp(let app):
            addTile(LaunchItem(id: "app.\(app.bundleID)", title: app.name, kind: .application(bundleID: app.bundleID)))
        case .restoreDefaults:
            updateItems(LaunchItem.defaults)
            pop()
        case .startPIN(let purpose):
            environment.startPINFlow(purpose)
        case .toggleTileRequiresPIN(let id):
            guard let item = item(id: id), !item.isSettingsTile, !item.isExitToDesktop else { return }
            updateItems(items.settingRequiresPIN(item.requiresPIN != true, id: id))
        case .reloadYouTube:
            environment.reloadYouTube()
        case .clearYouTubeData:
            environment.clearYouTubeData()
            pop()
        case .pasteIPTVURL(let kind):
            pasteMessage = environment.pasteIPTVURL(kind)
            pasteMessageKind = pasteMessage == nil ? nil : kind
            refreshStatus()
        case .moveGuideSource(let id, let step):
            environment.moveGuideSource(id, step)
            refreshStatus()
        case .removeGuideSource(let id):
            environment.removeGuideSource(id)
            pop()
            refreshStatus()
        case .toggleIPTVGroupHidden(let name):
            environment.setIPTVGroupHidden(name, !(iptv.groups.first { $0.name == name }?.isHidden ?? false))
            refreshStatus()
        case .unhideIPTVChannel(let id):
            environment.unhideIPTVChannel(id)
            refreshStatus()
        case .toggleChannelHidden(let id):
            guard let channel = iptv.antennaChannels.first(where: { $0.id == id }) else { return }
            environment.setChannelHidden(id, !channel.isHidden)
            refreshStatus()
        case .toggleTeam(let id):
            environment.setTeamPicked(id, !iptv.teams.contains(id))
            refreshStatus()
        case .refreshIPTV:
            environment.refreshIPTV()
        case .removeIPTVSource:
            environment.removeIPTVSource()
            pop()
        case .startAntennaScan:
            // M7j L18: back on the Antenna page, whose Scan row now reads Stop Scan.
            environment.startAntennaScan()
            pop()
            refreshStatus(.iptv)
        case .stopAntennaScan:
            environment.stopAntennaScan()
            refreshStatus(.iptv)
        case .forgetAllPhones:
            environment.forgetAllPhones()
            refreshStatus()
            pop()
        case .startLearning(let command):
            if case .confirmLearn = page { pop() }
            push(.learnButton(command))
        case .useLearned(let command, let trigger):
            applyBindings(bindings.adding(trigger, for: command))
            pop()
            setFocus("binding.\(bindings.bindings(for: command).count - 1)")
        case .removeBinding(let trigger):
            guard bindings.canRemove(trigger) else { return }
            applyBindings(bindings.removing(trigger))
            pop()
        case .toggleBindingGlobal(let trigger):
            guard let binding = bindings.binding(matching: trigger) else { return }
            applyBindings(bindings.settingGlobal(!binding.isGlobal, for: trigger))
        case .restoreDefaultButtons:
            applyBindings(.defaults)
            pop()
        case .choosePlexServer(let id):
            environment.choosePlexServer(id)
            if page == .plexServers { pop() }
            refreshStatus()
        case .openAirPlaySettings:
            environment.openAirPlaySettings()
        case .signOutOfPlex:
            environment.signOutOfPlex()
            pop()
            refreshStatus()
        case .pasteTileStartURL(let id):
            pasteStartURL(id: id)
        case .clearTileStartURL(let id):
            startURLMessage = nil
            updateItems(items.settingStartURL(nil, id: id))
            setFocus("tile.startURL")
        case .setTileArtStyle(let id, let style):
            // M7c L33: a style replaces the tile's picture.
            if environment.tileArtFileName(id) != nil {
                environment.removeTilePicture(id)
                refreshStatus()
            }
            updateItems(items.settingArtStyle(style, id: id))
        case .useTileArtPicture(let id, let url):
            tileArtMessage = environment.setTilePicture(id, url)
            refreshStatus()
        case .removeTileArtPicture(let id):
            environment.removeTilePicture(id)
            setFocus("art.designed")
            refreshStatus()
        case .setReceiverBrand(let brand):
            updateReceiverSettings { $0.receiverBrand = brand }
            if page == .receiverBrand { pop() }
        case .setReceiverConnection(let connection):
            updateReceiverSettings { $0.receiverConnection = connection }
            if page == .receiverConnection { pop() }
        case .setReceiverPort(let path):
            updateReceiverSettings { $0.receiverSerialPort = path }
            if page == .receiverPort { pop() }
        case .setReceiverMaxDB(let dB):
            if settings.receiverMaxDB != dB {
                var new = settings
                new.receiverMaxDB = dB
                settings = new
                environment.applySettings(new)
            }
            if page == .receiverMaxVolume { pop() }
        case .setGlassStyle(let style):
            // M7l L3: saved and applied at once; Settings is glass, so the change shows here too.
            if settings.glassStyle != style {
                var new = settings
                new.glassStyle = style
                settings = new
                environment.applySettings(new)
            }
            if page == .glassStyle { pop() }
        case .useFoundReceiver(let found):
            useFoundReceiver(found)
        case .setTVBrand(let brand):
            updateTVSettings { $0.tvBrand = brand }
            if brand == .cec { environment.refreshCEC() }
            if page == .tvBrand { pop() }
        case .testReceiver:
            runProbe(.testReceiver)
        case .findReceiver:
            runProbe(.findReceiver)
        case .testTV:
            runProbe(.testTV)
        case .findTV:
            runProbe(.findTV)
        case .findAntennaTuners:
            runProbe(.findAntennaTuners)
        case .saveAddress(let field):
            saveAddress(field)
        case .clearAddress:
            keyboard.clear()
            addressMessage = nil
        case .showToastDemo:
            environment.showToast("Trackpad On")
        }
    }

    // MARK: - Receiver and TV (M7h step 11; Audio & TV from step 13c)

    /// M7h D41: the address page's keyboard has focus.
    var isKeyboardActive: Bool {
        guard case .addressEntry = page else { return false }
        return isKeyboardFocused
    }

    /// The keyboard's commands; nil for those the page handles as usual (Home and the like return false there).
    private func handleKeyboard(_ command: RemoteCommand) -> Bool? {
        switch command {
        case .back:
            pop()
            return true
        case .down where keyboard.focus.row == keyboard.rows.count - 1:
            // Down from the bottom row: the rows below the keyboard (Save first).
            isKeyboardFocused = false
            setFocus(actionRowIDs.first)
            return true
        case .up, .down, .left, .right, .select, .playPause:
            if keyboard.handle(command) == .changed { addressMessage = nil }
            return true
        case .channelUp, .channelDown:
            return true
        case .home, .fastForward, .rewind, .menu, .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return nil
        }
    }

    /// The address as it would be saved: nil for an empty field, else `LANAddress.normalized`.
    private var typedAddress: String? {
        LANAddress.normalized(keyboard.text)
    }

    /// Saves `receiverHost` or `tvHost` (an empty field clears it) and goes back; an address MMTVL won't connect
    /// to stays on the page with a message. The controllers check the rest when they connect (step 8b, 9b).
    private func saveAddress(_ field: AddressField) {
        let host = typedAddress
        if let host {
            let allowed = switch field {
            case .receiver: LANAddress.isAllowedReceiverHost(host)
            // L18: IPv4 only.
            case .tv: LANAddress.isAllowedReceiverHost(host) && !host.contains(":")
            }
            guard allowed else {
                addressMessage = field == .tv
                    ? "Use the TV's IPv4 address, like 192.168.1.40, or its name"
                    : "Use a LAN address, like 192.168.1.50, or a name"
                return
            }
        }
        switch field {
        case .receiver: updateReceiverSettings { $0.receiverHost = host }
        case .tv: updateTVSettings { $0.tvHost = host }
        }
        pop()
    }

    /// L17: Find on Network's choice: its brand over the network at its address, and its port only when it isn't
    /// one of the brand's own.
    private func useFoundReceiver(_ found: FoundReceiver) {
        let ownPorts = found.brand.codec?.networkPorts(override: nil) ?? []
        updateReceiverSettings {
            $0.receiverBrand = found.brand
            $0.receiverConnection = .network
            $0.receiverHost = found.host
            $0.receiverNetworkPort = ownPorts.contains(found.port) ? nil : Int(found.port)
        }
        if page == .receiverFound { pop() }
    }

    /// Saves a receiver setting (the app reconfigures the receiver at once) and drops the checks' old results.
    private func updateReceiverSettings(_ change: (inout AppSettings) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        settings = new
        environment.applySettings(new)
        dropProbes([.testReceiver, .findReceiver])
        refreshStatus()
    }

    private func updateTVSettings(_ change: (inout AppSettings) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        settings = new
        environment.applySettings(new)
        dropProbes([.testTV, .findTV])
    }

    /// Forgets the checks' results; ones still running are ignored when they finish.
    private func dropProbes(_ probes: [SettingsProbe]) {
        for probe in probes {
            probeLines[probe] = nil
            probeTokens[probe] = nil
        }
        if probes.contains(.findReceiver) { foundReceivers = [] }
    }

    func isProbeRunning(_ probe: SettingsProbe) -> Bool {
        probeTokens[probe] != nil
    }

    /// L12, L17, L18: runs a read-only check in the background; its row shows "Testing…" or "Searching…" meanwhile.
    /// A second Select while it runs does nothing.
    private func runProbe(_ probe: SettingsProbe) {
        guard probeTokens[probe] == nil else { return }
        nextProbeToken += 1
        let token = nextProbeToken
        probeTokens[probe] = token
        probeLines[probe] = probe == .testReceiver || probe == .testTV ? "Testing…" : "Searching…"
        let environment = environment
        let settings = settings
        probeTasks[probe] = Task { [weak self] in
            switch probe {
            case .testReceiver where settings.receiverConnection == .cec:
                let result = await environment.testCECReceiver()
                self?.finishProbe(probe, token: token) { _ in result.line }
            case .testReceiver:
                let outcome = await environment.testReceiver()
                self?.finishProbe(probe, token: token) { _ in Self.receiverTestLine(outcome) }
            case .findReceiver:
                if settings.receiverConnection == .network {
                    let found = await environment.findReceiversOnNetwork(settings.validatedReceiverNetworkPort)
                    self?.finishProbe(probe, token: token) { $0.foundNetworkReceivers(found) }
                } else {
                    // Step 9c: the serial brands first (a match gives dB and the volume cap), then HDMI-CEC.
                    let brand = await environment.findReceiverOnPort(settings.receiverSerialPort)
                    let cec = brand == nil ? await environment.testCECReceiver() : nil
                    self?.finishProbe(probe, token: token) { $0.foundSerialReceiver(brand, cec: cec) }
                }
            case .testTV where settings.tvBrand == .cec:
                let status = await environment.testCEC()
                self?.finishProbe(probe, token: token) { _ in Self.cecTestLine(status) }
            case .testTV:
                let result = await environment.testTV()
                self?.finishProbe(probe, token: token) { _ in Self.tvTestLine(result) }
            case .findTV:
                let found = await environment.findTVs()
                self?.finishProbe(probe, token: token) { $0.foundTVs(found) }
            case .findAntennaTuners:
                let found = await environment.findAntennaTuners()
                self?.finishProbe(probe, token: token) { _ in Self.antennaFindLine(found) }
            }
        }
    }

    /// M7j L14: Find Tuners' result.
    static func antennaFindLine(_ outcome: AntennaFindOutcome) -> String {
        switch outcome {
        case .found(1): "Found 1 tuner"
        case .found(let count): "Found \(count) tuners"
        case .noneFound: "No HDHomeRun found on this network"
        case .noneAnswered: "No HDHomeRun answered"
        }
    }

    /// Applies a finished check's result, unless it was dropped meanwhile.
    private func finishProbe(_ probe: SettingsProbe, token: Int, _ result: (SettingsModel) -> String) {
        guard probeTokens[probe] == token else { return }
        probeTokens[probe] = nil
        probeTasks[probe] = nil
        let line = result(self)
        probeLines[probe] = line
        refreshStatus()
    }

    /// L17: the chooser when any answered (if Receiver is still the page), else "No receivers found".
    private func foundNetworkReceivers(_ found: [FoundReceiver]) -> String {
        foundReceivers = found
        guard !found.isEmpty else { return "No receivers found" }
        if page == .receiver { push(.receiverFound) }
        return found.count == 1 ? "1 receiver found" : "\(found.count) receivers found"
    }

    /// L12: the brand that answered on the serial port becomes the receiver's brand (over the serial connection).
    /// Step 9c: else a receiver that answered over HDMI-CEC makes the connection HDMI-CEC.
    private func foundSerialReceiver(_ brand: ReceiverBrand?, cec: CECReceiverTest?) -> String {
        if let brand {
            updateReceiverSettings {
                $0.receiverBrand = brand
                $0.receiverConnection = .serial
            }
            return "Found \(brand.settingsTitle)"
        }
        guard let cec, cec.answered else { return "No receiver answered" }
        updateReceiverSettings { $0.receiverConnection = .cec }
        return cec.name.map { "Found \($0) over HDMI-CEC" } ?? "Found a receiver over HDMI-CEC"
    }

    /// L18: the first TV with a MAC (else the first) fills Address and the MAC. A TV without one keeps the MAC
    /// already set for the same address; otherwise MMTVL can't turn it on, and says so.
    private func foundTVs(_ found: [FoundTV]) -> String {
        guard let tv = found.first(where: { $0.mac != nil }) ?? found.first else { return "No TV found" }
        let sameHost = settings.tvHost.flatMap(LANAddress.normalized) == tv.host
        updateTVSettings {
            $0.tvHost = tv.host
            $0.tvMAC = tv.mac?.description ?? (sameHost ? $0.tvMAC : nil)
        }
        let name = tv.name ?? tv.host
        return settings.tvMAC == nil ? "Found \(name); MMTVL can't turn this TV on" : "Found \(name)"
    }

    /// L12: "On · −20 dB · Not muted", else why nothing answered.
    static func receiverTestLine(_ outcome: ReceiverTestOutcome) -> String {
        receiverStatusLine(outcome.replies) ?? outcome.error ?? "No answer"
    }

    /// "On · −20 dB · Not muted" ("Standby", "Volume 45" without dB, "Volume Min"); nil when nothing is known.
    static func receiverStatusLine(_ state: ReceiverState) -> String? {
        var parts: [String] = []
        if let power = state.power { parts.append(power ? "On" : "Standby") }
        if let volume = state.volume {
            if let dB = volume.dB {
                parts.append(dB.isFinite ? VolumeToast.format(dB: dB) : "Volume Min")
            } else {
                parts.append("Volume \(volume.raw)")
            }
        }
        if let muted = state.muted { parts.append(muted ? "Muted" : "Not muted") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// L18: "On · Volume 12 · Not muted", "Off or not answering".
    static func tvTestLine(_ result: TVTestResult?) -> String {
        guard let result else { return "Set the TV's address first" }
        guard result.isOn else { return "Off or not answering" }
        var parts = ["On"]
        if let volume = result.volume { parts.append("Volume \(volume)") }
        if let muted = result.isMuted { parts.append(muted ? "Muted" : "Not muted") }
        return parts.joined(separator: " · ")
    }

    /// Step 9 (reopened): Test TV over HDMI-CEC.
    static func cecTestLine(_ status: CECPowerStatus?) -> String {
        guard let status else { return "No answer" }
        return status.isOn ? "On" : "Standby"
    }

    /// Step 9 (reopened): the TV page's Status row with HDMI-CEC.
    static func cecStatusLine(_ availability: CECAvailability?) -> String {
        switch availability {
        case .ready: "Ready"
        case .notAvailable: "HDMI-CEC not available on this display"
        case .noDisplay: "No HDMI display"
        case nil: "Checking…"
        }
    }

    /// L15: once the link page's code is used, the page leaves: to the server list when there are several
    /// servers, else back to the Plex page (with no server, it stays and says so).
    private func followPlexSignIn() {
        guard page == .plexLink, plex.isSignedIn else { return }
        if plex.needsServerChoice {
            pop()
            push(.plexServers)
        } else if plex.serverName != nil {
            pop()
        }
    }

    /// L23: an http(s) page on the web app's own site (else it would open in a browser tab).
    private func pasteStartURL(id: String) {
        guard let item = item(id: id), let webApp = environment.webAppInfo(item) else { return }
        switch environment.pasteURL() {
        case .failure(let problem):
            startURLMessage = ClipboardURL.message(for: problem)
        case .success(let url):
            if let host = webApp.startURL?.host(), url.host()?.lowercased() != host.lowercased() {
                startURLMessage = "Use a page on \(host)"
                return
            }
            startURLMessage = nil
            updateItems(items.settingStartURL(url, id: id))
        }
    }

    private func applyBindings(_ new: KeyBindings) {
        bindings = new
        environment.applyBindings(new)
    }

    /// L8: the handler's capture. Replaces the learn page with the confirm page; ignored when not learning.
    private func learned(_ trigger: InputBinding.Trigger) {
        guard case .learnButton(let command) = page else { return }
        pop()
        push(.confirmLearn(command, trigger))
        learnConfirmShownAt = now()
    }

    /// L8: no press within `learnTimeout`.
    private func learnTimedOut() {
        guard case .learnButton = page else { return }
        pop()
        learnMessage = "No button pressed"
    }

    func loadPictures() async {
        pictures = await environment.findPictures()
    }

    func loadInstalledApps() async {
        installedApps = await environment.scanInstalledApps()
    }

    static func tileRowID(_ itemID: String) -> String { "tile.\(itemID)" }

    func item(id: String) -> LaunchItem? {
        items.first { $0.id == id }
    }

    /// L2: inserted before Exit to Desktop; back on the tile list with the new tile focused.
    private func addTile(_ item: LaunchItem) {
        updateItems(items.insertingTile(item))
        pop()
        setFocus(Self.tileRowID(item.id))
    }

    private func push(_ page: SettingsPage) {
        pasteMessage = nil
        pasteMessageKind = nil
        learnMessage = nil
        startURLMessage = nil
        tileArtMessage = nil
        addressMessage = nil
        stack.append(PageState(page: page, focusedRowID: nil))
        switch page {
        case .receiver:
            // M7h: a fresh visit starts without old results (checks still running are ignored).
            dropProbes([.testReceiver, .findReceiver])
        case .tv:
            dropProbes([.testTV, .findTV])
            if settings.tvBrand == .cec { environment.refreshCEC() }
        case .antenna:
            dropProbes([.findAntennaTuners])
        case .receiverPort:
            serialPorts = environment.serialPorts()
        case .addressEntry(let field):
            let text = (field == .receiver ? settings.receiverHost : settings.tvHost) ?? ""
            // Addresses are mostly digits: start there unless a name is set.
            let isNumeric = text.allSatisfy { $0.isNumber || $0 == "." }
            keyboard = OnScreenKeyboard(text: text, mode: isNumeric ? .digits : .letters)
            isKeyboardFocused = true
        default:
            break
        }
        if page == .addTile {
            installedApps = nil
            Task { await loadInstalledApps() }
        }
        if case .tileArt = page {
            pictures = nil
            Task { await loadPictures() }
        }
        syncPairing()
        syncLearning()
        syncPlexLink()
        syncAntennaPage()
        if page == .plex { environment.refreshPlex() }
        if page == .casting { environment.refreshCasting() }
    }

    private func pop() {
        guard stack.count > 1 else { return }
        pasteMessage = nil
        pasteMessageKind = nil
        learnMessage = nil
        startURLMessage = nil
        tileArtMessage = nil
        addressMessage = nil
        stack.removeLast()
        syncPairing()
        syncLearning()
        syncPlexLink()
        syncAntennaPage()
    }

    /// M7j L18: a running channel scan is polled every second exactly while Settings → Antenna is the top page (and
    /// Settings is open); each time it opens, the tuners are asked whether they can scan.
    private func syncAntennaPage(closed: Bool = false) {
        let visible = !closed && page == .antenna
        guard visible != isAntennaPageVisible else { return }
        isAntennaPageVisible = visible
        environment.antennaPageVisible(visible)
    }

    /// M7 L15: the link code is made and polled exactly while the Plex link page shows.
    private func syncPlexLink(closed: Bool = false) {
        let active = !closed && page == .plexLink
        guard active != isPlexLinking else { return }
        isPlexLinking = active
        environment.setPlexLinking(active)
    }

    /// M7 L8: the capture handler is set exactly while the learn page shows (and Settings is open).
    private func syncLearning(closed: Bool = false) {
        var active = false
        if !closed, case .learnButton = page { active = true }
        guard active != isLearning else { return }
        isLearning = active
        learnTimeoutTask?.cancel()
        learnTimeoutTask = nil
        if active {
            environment.setButtonLearning { [weak self] trigger in self?.learned(trigger) }
            let timeout = learnTimeout
            learnTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.learnTimedOut()
            }
        } else {
            environment.setButtonLearning(nil)
        }
    }

    /// M5 L3: pairing is active exactly while the Pair a Phone page shows.
    private func syncPairing() {
        let active = page == .pairPhone
        guard active != isPairing else { return }
        isPairing = active
        environment.setPhonePairing(active)
        refreshStatus()
    }

    private func setFocus(_ id: String?) {
        stack[stack.count - 1].focusedRowID = id
    }

    /// M7m L8: the home screen's move mode, one step at a time; saved and given to the router like any tile edit
    /// (`applyItems`). Never touches the Settings stack or Settings' own move mode.
    func moveTile(id: String, toVisibleIndex index: Int) {
        let new = items.movingVisibleItem(id: id, toVisibleIndex: index)
        guard new != items else { return }
        updateItems(new)
    }

    private func updateItems(_ new: [LaunchItem]) {
        items = new
        environment.applyItems(new)
    }
}
