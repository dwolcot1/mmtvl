import Foundation
import Testing
@testable import MMTVL

/// M15 L11: the home screen's update notice.
struct UpdateStatusTests {
    private let installed = AppVersion(version: "1.4.0", build: "46")

    @Test func homeLabelForAvailable() {
        let update = AvailableUpdate(version: "1.5.0", build: "50")
        #expect(UpdateStatus.available(update).homeLabel(installed: installed) == "Update Available: 1.5.0")
        #expect(UpdateStatus.downloading(update, fraction: 0.45).homeLabel(installed: installed)
            == "Update Available: 1.5.0")
        #expect(UpdateStatus.downloading(update, fraction: nil).homeLabel(installed: installed)
            == "Update Available: 1.5.0")
        #expect(UpdateStatus.installing(update).homeLabel(installed: installed) == "Update Available: 1.5.0")
    }

    @Test func homeLabelSameVersionAddsBuild() {
        let update = AvailableUpdate(version: "1.4.0", build: "47")
        #expect(UpdateStatus.available(update).homeLabel(installed: installed) == "Update Available: 1.4.0 (Build 47)")
        #expect(UpdateStatus.ready(update).homeLabel(installed: installed) == "Update Available: 1.4.0 (Build 47)")
    }

    @Test func homeLabelNilWhenUpToDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let none: [UpdateStatus] = [
            .upToDate(lastChecked: date), .idle(lastChecked: nil), .idle(lastChecked: date), .checking,
            .off(.developmentBuild), .off(.windowed), .failed(.checkFailed), .failed(.installFailed),
        ]
        for status in none {
            #expect(status.homeLabel(installed: installed) == nil, "\(status)")
        }
    }

    @Test func homeLabelForReady() {
        let update = AvailableUpdate(version: "1.5.0", build: "50")
        #expect(UpdateStatus.ready(update).homeLabel(installed: installed) == "Update Available: 1.5.0")
    }
}
