import Foundation
import Sparkle

/// What `SoftwareUpdater` needs from Sparkle (M15). `SparkleEngine` is the real one; `FakeUpdaterEngine`
/// (`UpdatePreview.swift`, Debug) stands in for tests and `-updatePreview`. No Sparkle type crosses this protocol.
protocol UpdaterEngine: AnyObject {
    /// Where Sparkle's callbacks go, as `UpdateEvent`s. Held weakly; set by `SoftwareUpdater.start` before `start()`.
    var events: (any UpdateEventSink)? { get set }
    func start() throws
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sessionInProgress: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    /// User-initiated: the user driver path.
    func checkForUpdates()
    /// A probe, no UI.
    func checkForUpdateInformation()
}

/// `SPUUpdater` behind `UpdaterEngine`. One of only two files that import Sparkle (the other is `SparkleBridge.swift`).
/// The updater holds its delegate weakly, so the bridge (user driver and delegate) is kept here, strongly.
final class SparkleEngine: UpdaterEngine {
    private let bridge: SparkleBridge
    private let updater: SPUUpdater

    init() {
        let bridge = SparkleBridge()
        self.bridge = bridge
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: bridge, delegate: bridge)
    }

    var events: (any UpdateEventSink)? {
        get { bridge.events }
        set { bridge.events = newValue }
    }

    func start() throws {
        try updater.start()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var sessionInProgress: Bool { updater.sessionInProgress }
    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func checkForUpdateInformation() {
        updater.checkForUpdateInformation()
    }
}
