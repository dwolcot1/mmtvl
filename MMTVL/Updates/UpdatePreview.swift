#if DEBUG
import Foundation
import os

/// M15 L13 (Debug builds only): `-updatePreview available|downloading|ready|checking|failed|upToDate` puts a
/// `FakeUpdaterEngine` behind `SoftwareUpdater` in that state, in `-windowed` mode too, so Settings → Software Update
/// and the home notice can be seen without Sparkle. Nothing is downloaded, installed or requested.
enum UpdatePreview {
    enum State: String, CaseIterable, Sendable {
        case available, downloading, ready, checking, failed, upToDate
    }

    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Updater")
    /// The update the preview offers.
    static let update = AvailableUpdate(version: "1.5.0", build: "60")

    /// The `-updatePreview` argument, if it names a state.
    static var requested: State? {
        UserDefaults.standard.string(forKey: "updatePreview").flatMap(State.init(rawValue:))
    }
}

/// Stands in for Sparkle (Debug builds): records what `SoftwareUpdater` asks of it (tests drive the updater's events
/// themselves), and with a preview state replays that state's events after `start()` and each Check Now.
final class FakeUpdaterEngine: UpdaterEngine {
    weak var events: (any UpdateEventSink)?
    /// "checks=true", "downloads=false", "start", "checkForUpdates", "checkForUpdateInformation", in order.
    private(set) var calls: [String] = []
    var startError: (any Error)?
    var sessionInProgress = false
    var lastUpdateCheckDate: Date?
    let preview: UpdatePreview.State?

    var automaticallyChecksForUpdates = false {
        didSet { calls.append("checks=\(automaticallyChecksForUpdates)") }
    }

    var automaticallyDownloadsUpdates = false {
        didSet { calls.append("downloads=\(automaticallyDownloadsUpdates)") }
    }

    init(preview: UpdatePreview.State? = nil) {
        self.preview = preview
        // An automatic download under way: Install does nothing (`SoftwareUpdater.install`).
        sessionInProgress = preview == .downloading
        if preview == .upToDate { lastUpdateCheckDate = Date(timeIntervalSinceNow: -2 * 3600) }
    }

    func start() throws {
        calls.append("start")
        if let startError { throw startError }
        guard preview != nil else { return }
        Task { [weak self] in self?.replay() }
    }

    func checkForUpdates() {
        calls.append("checkForUpdates")
        guard preview != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.replay()
        }
    }

    func checkForUpdateInformation() {
        calls.append("checkForUpdateInformation")
    }

    private func replay() {
        guard let preview, let events else { return }
        UpdatePreview.logger.notice("Preview: \(preview.rawValue, privacy: .public)")
        let update = UpdatePreview.update
        switch preview {
        case .available:
            events.handle(.found(update, userInitiated: false))
        case .downloading:
            events.handle(.found(update, userInitiated: false))
            events.handle(.downloadStarted)
            events.handle(.downloadProgress(0.45))
        case .ready:
            events.handle(.staged(update, installNow: {
                UpdatePreview.logger.notice("Preview: install (not run)")
            }))
        case .checking:
            events.handle(.checking)
        case .failed:
            events.handle(.failed(.checkFailed, UpdateErrorCode(domain: SoftwareUpdater.sparkleErrorDomain, code: 1002)))
        case .upToDate:
            events.handle(.notFound)
        }
    }
}
#endif
