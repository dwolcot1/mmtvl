import Foundation
import Sparkle

/// M15: Sparkle's user driver and updater delegate. Every callback goes to `SoftwareUpdater` (the `events` sink) as an
/// `UpdateEvent` or one of its answer methods, and `UpdateChoice` comes back as `SPUUserUpdateChoice`. Draws nothing:
/// MMTVL's Settings and home screen show the state. The other file that imports Sparkle (with `UpdaterEngine.swift`).
/// Kept alive by `SparkleEngine`, since `SPUUpdater` holds its delegate weakly.
final class SparkleBridge: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    weak var events: (any UpdateEventSink)?

    /// The download's expected length and what has arrived (`showDownloadDidReceive…`), for the fraction.
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0
    /// The last whole percent sent, so the status changes at most 100 times per download.
    private var lastPercent: Int?

    private static func update(_ item: SUAppcastItem) -> AvailableUpdate {
        AvailableUpdate(version: item.displayVersionString, build: item.versionString)
    }

    private static func choice(_ choice: UpdateChoice) -> SPUUserUpdateChoice {
        switch choice {
        case .install: .install
        case .dismiss: .dismiss
        }
    }

    private func failed(_ error: any Error) {
        if let event = SoftwareUpdater.failureEvent(for: error) { events?.handle(event) }
    }

    // MARK: SPUUserDriver

    /// Not expected (`SUEnableAutomaticChecks` is set); `settings.json` decides (L5). Never sends a system profile.
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: events?.allowsAutomaticChecks ?? false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        events?.handle(.checking)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        guard let events else { return .dismiss }
        return Self.choice(await events.choice(forFound: Self.update(appcastItem), userInitiated: state.userInitiated))
    }

    /// L10: no release notes.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error) async {
        events?.handle(.notFound)
    }

    func showUpdaterError(_ error: any Error) async {
        failed(error)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        lastPercent = nil
        events?.handle(.downloadStarted)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        receivedLength = 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard expectedLength > 0 else { return }
        let fraction = min(1, Double(receivedLength) / Double(expectedLength))
        let percent = Int(fraction * 100)
        guard percent != lastPercent else { return }
        lastPercent = percent
        events?.handle(.downloadProgress(fraction))
    }

    func showDownloadDidStartExtractingUpdate() {
        events?.handle(.extracting)
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        guard let events else { return .dismiss }
        return Self.choice(await events.choiceForReadyToInstall())
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        events?.installingUpdate(applicationTerminated: applicationTerminated, retry: retryTerminatingApplication)
    }

    /// MMTVL has quit by then; nothing to show.
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}

    func dismissUpdateInstallation() {
        events?.handle(.dismissed)
    }

    func showUpdateInFocus() {}

    // MARK: SPUUpdaterDelegate
    // `feedURLString(for:)` is deliberately not implemented: the user-defaults `SUFeedURL` override (step 14's test
    // feed) must keep working, and `SoftwareUpdater` logs its host (N1).

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        events?.handle(.found(Self.update(item), userInitiated: false))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        events?.handle(.notFound)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        events?.handle(.staged(Self.update(item), installNow: immediateInstallHandler)) ?? false
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        events?.handle(.willRelaunch)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        failed(error)
    }
}
