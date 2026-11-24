import Foundation

/// An update the feed offers (M15): its marketing version and build number, from the appcast item.
nonisolated struct AvailableUpdate: Equatable, Sendable {
    var version: String
    var build: String
}

/// Why an update check or install failed (M15 L12). Carries no URL and no error text: Sparkle's
/// `localizedDescription` can contain the feed URL, so Settings shows only these titles.
nonisolated enum UpdateFailure: Equatable, Sendable {
    case checkFailed
    case installFailed

    /// The Software Update page's status row.
    var title: String {
        switch self {
        case .checkFailed: "Couldn't Check"
        case .installFailed: "Couldn't Install the Update"
        }
    }

    var detail: String? {
        switch self {
        case .checkFailed: "Check your network connection and try again."
        case .installFailed: nil
        }
    }
}

/// What `SoftwareUpdater` knows (M15). Pure; Settings and the home screen read it.
nonisolated enum UpdateStatus: Equatable, Sendable {
    /// M15 L4: the updater runs only in Release builds in kiosk mode.
    nonisolated enum OffReason: Equatable, Sendable {
        case developmentBuild, windowed

        /// The status row's detail under "Updates Are Off".
        var detail: String {
            switch self {
            case .developmentBuild: "Development builds don't update."
            case .windowed: "MMTVL is in a window."
            }
        }
    }

    case off(OffReason)
    /// Checks on or off, nothing known.
    case idle(lastChecked: Date?)
    case checking
    case upToDate(lastChecked: Date)
    /// Found, not downloaded (Off mode, or Check Now).
    case available(AvailableUpdate)
    case downloading(AvailableUpdate, fraction: Double?)
    /// Extracting or quitting.
    case installing(AvailableUpdate)
    /// Downloaded and staged (When Idle / At Night): the install block is held.
    case ready(AvailableUpdate)
    case failed(UpdateFailure)

    /// The update this status is about, if any.
    var update: AvailableUpdate? {
        switch self {
        case .available(let update), .downloading(let update, _), .installing(let update), .ready(let update): update
        case .off, .idle, .checking, .upToDate, .failed: nil
        }
    }

    /// L11: "Update Available: 1.4.0"; with the same marketing version as the installed one (test builds),
    /// "Update Available: 1.4.0 (Build 46)". nil unless an update is available, downloading, installing or ready.
    func homeLabel(installed: AppVersion) -> String? {
        guard let update else { return nil }
        let label = "Update Available: \(update.version)"
        return update.version == installed.version ? "\(label) (Build \(update.build))" : label
    }
}
