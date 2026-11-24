import Foundation
import Testing
@testable import MMTVL

/// A manual clock for `SoftwareUpdater.Schedule`: nothing runs until `advance(by:)` reaches it.
final class ManualUpdateClock {
    private struct Item {
        let id: Int
        let due: Duration
        let work: () -> Void
    }

    private(set) var now: Duration = .zero
    private var items: [Item] = []
    private var nextID = 0

    var schedule: SoftwareUpdater.Schedule {
        { [self] delay, work in
            nextID += 1
            let id = nextID
            items.append(Item(id: id, due: now + delay, work: work))
            return { [weak self] in self?.items.removeAll { $0.id == id } }
        }
    }

    /// Runs everything due by `now + duration`, in order (work scheduled meanwhile too).
    func advance(by duration: Duration) {
        let target = now + duration
        while let next = items.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            items.removeAll { $0.id == next.id }
            now = next.due
            next.work()
        }
        now = target
    }
}

/// Everything the updater did to the app, in order.
final class UpdaterLog {
    var events: [String] = []
    var toasts: [String] = []
    var snapshot = SoftwareUpdater.notIdle
}

/// M15 step 7: `SoftwareUpdater` on a `FakeUpdaterEngine`; the tests send the events `SparkleBridge` would.
struct SoftwareUpdaterTests {
    let log = UpdaterLog()
    let clock = ManualUpdateClock()
    let engine = FakeUpdaterEngine()
    let update = AvailableUpdate(version: "1.5.0", build: "50")
    static let checked = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeUpdater(checks: Bool = true, mode: AutomaticUpdates = .off) -> SoftwareUpdater {
        let log = log
        let hooks = SoftwareUpdater.Hooks(
            allowQuit: { log.events.append("allowQuit") },
            revokeQuit: { log.events.append("revokeQuit") },
            snapshot: { log.snapshot },
            writeMarker: { log.events.append("marker") },
            deleteMarker: { log.events.append("deleteMarker") },
            showToast: { log.toasts.append($0) },
            now: { Self.checked },
            schedule: clock.schedule
        )
        let updater = SoftwareUpdater(engine: engine, feed: UpdateFeed(userDefaultsValue: nil, infoPlistValue: Self.feedURL),
                                      installed: AppVersion(version: "1.4.0", build: "46"), hooks: hooks)
        updater.start(checks: checks, mode: mode)
        return updater
    }

    static let feedURL = "https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml"

    private var poweredOff: UpdateIdleSnapshot {
        var snapshot = SoftwareUpdater.notIdle
        snapshot.mmtvlFrontmost = true
        snapshot.poweredOffByMMTVL = true
        return snapshot
    }

    @Test func developmentBuildIsOff() {
        #expect(SoftwareUpdater.offReason(debugBuild: true, windowed: false) == .developmentBuild)
        #expect(SoftwareUpdater.offReason(debugBuild: true, windowed: true) == .developmentBuild)
        #expect(SoftwareUpdater.offReason(debugBuild: false, windowed: true) == .windowed)
        #expect(SoftwareUpdater.offReason(debugBuild: false, windowed: false) == nil)
        // The test host is a Debug build.
        #expect(SoftwareUpdater.isDebugBuild)

        let updater = SoftwareUpdater(off: .developmentBuild)
        updater.start(checks: true, mode: .whenIdle)
        updater.apply(checks: true, mode: .atNight)
        updater.checkNow()
        updater.install()
        #expect(!updater.installStagedForRelaunch())
        #expect(!updater.handle(.staged(update, installNow: {})))
        #expect(updater.status == .off(.developmentBuild))
        #expect(updater.homeLabel == nil)
        #expect(updater.feedHost == nil)
        #expect(!updater.isTestFeed)
    }

    @Test func applySetsChecksBeforeDownloads() {
        let updater = makeUpdater(checks: true, mode: .whenIdle)
        #expect(engine.calls == ["checks=true", "downloads=true", "start"])

        updater.apply(checks: false, mode: .whenIdle)
        updater.apply(checks: true, mode: .off)
        updater.apply(checks: true, mode: .atNight)
        #expect(engine.calls == ["checks=true", "downloads=true", "start",
                                 "checks=false", "downloads=false",
                                 "checks=true", "downloads=false",
                                 "checks=true", "downloads=true"])
        #expect(updater.allowsAutomaticChecks)
    }

    @Test func offModeScheduledFindIsDismissedAndAvailable() async {
        let updater = makeUpdater(mode: .off)
        #expect(await updater.choice(forFound: update, userInitiated: false) == .dismiss)
        #expect(updater.status == .available(update))
        // Sparkle ends the session; the notice stays.
        updater.handle(.dismissed)
        #expect(updater.status == .available(update))
        #expect(!engine.calls.contains("checkForUpdates"))
    }

    @Test func checkNowReportsAvailable() async {
        let updater = makeUpdater()
        updater.checkNow()
        #expect(engine.calls.last == "checkForUpdates")
        #expect(updater.status == .checking)
        updater.handle(.checking)
        #expect(await updater.choice(forFound: update, userInitiated: true) == .dismiss)
        #expect(updater.status == .available(update))
    }

    @Test func checkNowUpToDate() {
        engine.lastUpdateCheckDate = Self.checked
        let updater = makeUpdater()
        updater.checkNow()
        updater.handle(.notFound)
        #expect(updater.status == .upToDate(lastChecked: Self.checked))
        #expect(updater.homeLabel == nil)
    }

    @Test func installStartsUserCheckAndAnswersInstall() async {
        let updater = makeUpdater()
        _ = await updater.choice(forFound: update, userInitiated: false)
        updater.install()
        #expect(engine.calls.last == "checkForUpdates")
        updater.handle(.checking)
        #expect(updater.status == .available(update))
        #expect(await updater.choice(forFound: update, userInitiated: true) == .install)
        updater.handle(.downloadStarted)
        #expect(updater.status == .downloading(update, fraction: nil))
        updater.handle(.downloadProgress(0.45))
        #expect(updater.status == .downloading(update, fraction: 0.45))
        updater.handle(.extracting)
        #expect(updater.status == .installing(update))
    }

    @Test func installDoesNothingWhileSparklesSessionRuns() {
        let updater = makeUpdater(mode: .whenIdle)
        engine.sessionInProgress = true
        updater.install()
        updater.checkNow()
        #expect(!engine.calls.contains("checkForUpdates"))
        #expect(log.events.isEmpty)
    }

    @Test func readyToInstallAllowsQuitFirst() async {
        let updater = makeUpdater()
        updater.install()
        _ = await updater.choice(forFound: update, userInitiated: true)
        updater.handle(.downloadStarted)
        updater.handle(.extracting)
        #expect(log.events.isEmpty)
        let choice = await updater.choiceForReadyToInstall()
        log.events.append("answer.\(choice)")
        #expect(log.events == ["allowQuit", "answer.install"])
        #expect(updater.status == .installing(update))

        // Sparkle's termination didn't go through yet: the quit stays allowed, and it retries once.
        var retries = 0
        updater.installingUpdate(applicationTerminated: false, retry: { retries += 1 })
        updater.installingUpdate(applicationTerminated: false, retry: { retries += 1 })
        #expect(retries == 1)
        #expect(log.events == ["allowQuit", "answer.install", "allowQuit", "allowQuit"])
        updater.handle(.willRelaunch)
        #expect(log.events.last == "allowQuit")
    }

    @Test func readyToInstallWithoutAnInstallPressIsDismissed() async {
        let updater = makeUpdater()
        #expect(await updater.choiceForReadyToInstall() == .dismiss)
        #expect(log.events.isEmpty)
    }

    @Test func stagedBlockHeldInAutomaticModes() {
        for mode in [AutomaticUpdates.whenIdle, .atNight] {
            let updater = makeUpdater(mode: mode)
            #expect(updater.handle(.staged(update, installNow: {})))
            #expect(updater.status == .ready(update))
            #expect(updater.homeLabel == "Update Available: 1.5.0")
        }
    }

    @Test func stagedRefusedInOffMode() {
        let updater = makeUpdater(mode: .off)
        var installs = 0
        #expect(!updater.handle(.staged(update, installNow: { installs += 1 })))
        #expect(updater.status != .ready(update))
        #expect(!updater.installStagedForRelaunch())
        clock.advance(by: .seconds(600))
        #expect(installs == 0)
    }

    @Test func installWithStagedCallsBlock() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        updater.install()
        #expect(log.events == ["allowQuit", "block"])
        #expect(!engine.calls.contains("checkForUpdates"))
        #expect(updater.status == .installing(update))
    }

    @Test func idleTickInstallsWhenPolicyAllows() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        log.snapshot = poweredOff
        clock.advance(by: .seconds(59))
        #expect(log.events.isEmpty)
        clock.advance(by: .seconds(1))
        #expect(log.events == ["marker", "allowQuit", "block"])
        // One attempt: no more ticks while it's under way.
        clock.advance(by: .seconds(59))
        #expect(log.events == ["marker", "allowQuit", "block"])
        #expect(updater.status == .installing(update))
    }

    @Test func idleTickWaitsOtherwise() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        var other = poweredOff
        other.mmtvlFrontmost = false   // another app in front
        log.snapshot = other
        clock.advance(by: .seconds(180))
        #expect(log.events.isEmpty)
        #expect(updater.status == .ready(update))
        log.snapshot = poweredOff
        clock.advance(by: .seconds(60))
        #expect(log.events == ["marker", "allowQuit", "block"])
    }

    @Test func markerWrittenOnlyWhenPoweredOff() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        var saver = SoftwareUpdater.notIdle
        saver.mmtvlFrontmost = true
        saver.screenSaverOurs = true
        log.snapshot = saver
        clock.advance(by: .seconds(60))
        #expect(log.events == ["allowQuit", "block"])
        #expect(updater.status == .installing(update))

        // Check Now and Install with a staged update never write it either.
        let other = SoftwareUpdaterTests()
        let second = other.makeUpdater(mode: .whenIdle)
        second.handle(.staged(update, installNow: {}))
        #expect(second.installStagedForRelaunch())
        #expect(!other.log.events.contains("marker"))
    }

    @Test func quitRevokedAfter60s() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        updater.install()
        clock.advance(by: .seconds(59))
        #expect(log.events == ["allowQuit", "block"])
        #expect(updater.status == .installing(update))
        clock.advance(by: .seconds(1))
        #expect(log.events == ["allowQuit", "block", "revokeQuit"])
        #expect(log.toasts == ["Couldn't Install the Update"])
        // Nothing else fires while the idle policy doesn't allow a retry.
        clock.advance(by: .seconds(600))
        #expect(log.events == ["allowQuit", "block", "revokeQuit"])
    }

    /// A user-driver install (no held block) that doesn't finish: failed at once, nothing to retry.
    @Test func unheldInstallTimeoutFails() async {
        let updater = makeUpdater()
        updater.install()
        _ = await updater.choice(forFound: update, userInitiated: true)
        _ = await updater.choiceForReadyToInstall()
        clock.advance(by: .seconds(60))
        #expect(log.events == ["allowQuit", "revokeQuit"])
        #expect(updater.status == .failed(.installFailed))
        #expect(log.toasts == ["Couldn't Install the Update"])
    }

    /// QA major (item 1): one call of the block per attempt; Relaunch during it still says it's handled.
    @Test func heldBlockCalledOncePerAttempt() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        updater.install()
        updater.install()
        #expect(updater.installStagedForRelaunch())
        clock.advance(by: .seconds(30))
        #expect(updater.installStagedForRelaunch())
        #expect(log.events.filter { $0 == "block" }.count == 1)

        let other = SoftwareUpdaterTests()
        let second = other.makeUpdater(mode: .atNight)
        second.handle(.staged(update, installNow: { [log = other.log] in log.events.append("block") }))
        #expect(second.installStagedForRelaunch())
        #expect(second.installStagedForRelaunch())
        second.install()
        #expect(other.log.events.filter { $0 == "block" }.count == 1)
    }

    /// QA major, security L-a (item 2): the first attempt that doesn't finish leaves the update ready, and the next
    /// allowed idle tick tries once more.
    @Test func installRetriedOnceAfterTimeout() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        updater.install()
        clock.advance(by: .seconds(60))
        #expect(updater.status == .ready(update))
        #expect(log.toasts == ["Couldn't Install the Update"])
        #expect(log.events == ["allowQuit", "block", "revokeQuit"])

        log.snapshot = poweredOff
        clock.advance(by: .seconds(60))
        #expect(log.events == ["allowQuit", "block", "revokeQuit", "marker", "allowQuit", "block"])
        #expect(updater.status == .installing(update))
        // Install and Relaunch can retry too (once the first attempt's 60 s are over).
        let other = SoftwareUpdaterTests()
        let second = other.makeUpdater(mode: .whenIdle)
        second.handle(.staged(update, installNow: { [log = other.log] in log.events.append("block") }))
        #expect(second.installStagedForRelaunch())
        other.clock.advance(by: .seconds(60))
        #expect(second.installStagedForRelaunch())
        #expect(other.log.events.filter { $0 == "block" }.count == 2)
    }

    /// Item 2: after the second attempt that doesn't finish the block is dropped: Relaunch is a plain relaunch and
    /// Check Now works.
    @Test func secondTimeoutDropsHeldBlock() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        #expect(updater.installStagedForRelaunch())
        clock.advance(by: .seconds(60))
        #expect(updater.installStagedForRelaunch())
        clock.advance(by: .seconds(60))
        #expect(updater.status == .failed(.installFailed))
        #expect(log.toasts == ["Couldn't Install the Update", "Couldn't Install the Update"])
        #expect(log.events.filter { $0 == "block" }.count == 2)
        #expect(log.events.last == "revokeQuit")

        #expect(!updater.installStagedForRelaunch())
        updater.install()
        #expect(log.events.filter { $0 == "block" }.count == 2)
        updater.checkNow()
        #expect(engine.calls.contains("checkForUpdates"))
        #expect(updater.status == .checking)
        // No idle attempts either.
        log.snapshot = poweredOff
        clock.advance(by: .seconds(600))
        #expect(log.events.filter { $0 == "block" }.count == 2)
    }

    /// QA minor (item 3): a check failure while an update is staged keeps it.
    @Test func checkFailureKeepsStagedUpdate() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        updater.handle(.failed(.checkFailed, UpdateErrorCode(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        #expect(updater.status == .ready(update))
        updater.install()
        #expect(log.events == ["allowQuit", "block"])

        // An install failure drops it.
        let other = SoftwareUpdaterTests()
        let second = other.makeUpdater(mode: .whenIdle)
        second.handle(.staged(update, installNow: { [log = other.log] in log.events.append("block") }))
        second.handle(.failed(.installFailed, UpdateErrorCode(domain: SoftwareUpdater.sparkleErrorDomain, code: 4005)))
        #expect(second.status == .failed(.installFailed))
        #expect(!second.installStagedForRelaunch())
        #expect(!other.log.events.contains("block"))
    }

    /// QA minor, security L-c (item 5): the marker doesn't outlive an install that didn't happen.
    @Test func markerDeletedWhenInstallDoesntFinish() {
        let updater = makeUpdater(mode: .whenIdle)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        log.snapshot = poweredOff
        clock.advance(by: .seconds(60))
        #expect(log.events == ["marker", "allowQuit", "block"])
        clock.advance(by: .seconds(60))
        #expect(log.events == ["marker", "allowQuit", "block", "revokeQuit", "deleteMarker"])
        // The retry writes it again; the second timeout deletes it again.
        clock.advance(by: .seconds(60))
        clock.advance(by: .seconds(60))
        #expect(log.events.filter { $0 == "marker" }.count == 2)
        #expect(log.events.filter { $0 == "deleteMarker" }.count == 2)
        #expect(log.events.last == "deleteMarker")
        #expect(updater.status == .failed(.installFailed))

        // An install failure while it exists deletes it; without a marker nothing is deleted.
        let other = SoftwareUpdaterTests()
        other.log.snapshot = poweredOff
        let second = other.makeUpdater(mode: .whenIdle)
        second.handle(.staged(update, installNow: {}))
        other.clock.advance(by: .seconds(60))
        second.handle(.failed(.installFailed, UpdateErrorCode(domain: SoftwareUpdater.sparkleErrorDomain, code: 4005)))
        #expect(other.log.events == ["marker", "allowQuit", "revokeQuit", "deleteMarker"])
        second.handle(.dismissed)
        #expect(other.log.events.filter { $0 == "deleteMarker" }.count == 1)
    }

    /// Security L-b (item 4): the updater's permission is its own; the decision lets a quit through on either.
    @Test func updaterQuitPermissionIsItsOwn() {
        #expect(AppDelegate.quitSkipsPIN(allowsTermination: false, updateQuitAllowed: true, lockEffective: true))
        #expect(AppDelegate.quitSkipsPIN(allowsTermination: true, updateQuitAllowed: false, lockEffective: true))
        #expect(AppDelegate.quitSkipsPIN(allowsTermination: false, updateQuitAllowed: false, lockEffective: false))
        #expect(!AppDelegate.quitSkipsPIN(allowsTermination: false, updateQuitAllowed: false, lockEffective: true))
    }

    @Test func dismissedInstallTakesTheQuitBack() async {
        let updater = makeUpdater()
        updater.install()
        _ = await updater.choice(forFound: update, userInitiated: true)
        updater.handle(.downloadStarted)
        _ = await updater.choiceForReadyToInstall()
        updater.handle(.dismissed)
        #expect(log.events == ["allowQuit", "revokeQuit"])
        #expect(updater.status == .available(update))
        clock.advance(by: .seconds(120))
        #expect(log.events == ["allowQuit", "revokeQuit"])
        #expect(log.toasts.isEmpty)
    }

    @Test func relaunchWithStagedInstalls() {
        let updater = makeUpdater(mode: .atNight)
        updater.handle(.staged(update, installNow: { [log] in log.events.append("block") }))
        #expect(updater.installStagedForRelaunch())
        #expect(log.events == ["allowQuit", "block"])
    }

    @Test func relaunchWithoutStagedReturnsFalse() async {
        let updater = makeUpdater(mode: .whenIdle)
        _ = await updater.choice(forFound: update, userInitiated: false)
        #expect(!updater.installStagedForRelaunch())
        #expect(log.events.isEmpty)
    }

    @Test func errorsCarryNoURL() throws {
        let url = Self.feedURL
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "A server with the specified hostname could not be found: \(url)",
            NSURLErrorFailingURLStringErrorKey: url,
        ])
        let event = try #require(SoftwareUpdater.failureEvent(for: error))
        guard case .failed(let failure, let code) = event else {
            Issue.record("not a failure")
            return
        }
        #expect(failure == .checkFailed)
        #expect(SoftwareUpdater.logLine(for: failure, code) == "Couldn't check: NSURLErrorDomain -1003")

        let updater = makeUpdater()
        updater.checkNow()
        updater.handle(event)
        #expect(updater.status == .failed(.checkFailed))
        let texts = [failure.title, failure.detail ?? "", SoftwareUpdater.logLine(for: failure, code),
                     updater.homeLabel ?? "", String(describing: updater.status)]
        for text in texts { #expect(!text.contains("http")) }

        // Sparkle's own codes: no update isn't a failure; download, extraction and install ones are install failures.
        let sparkle = SoftwareUpdater.sparkleErrorDomain
        #expect(SoftwareUpdater.failureEvent(for: NSError(domain: sparkle, code: 1001)) == nil)
        #expect(SoftwareUpdater.failureEvent(for: NSError(domain: sparkle, code: 4008)) == nil)
        if case .failed(let downloadFailure, _) = SoftwareUpdater.failureEvent(for: NSError(domain: sparkle, code: 2001)) {
            #expect(downloadFailure == .installFailed)
        } else {
            Issue.record("a download error is a failure")
        }
        if case .failed(let keyFailure, _) = SoftwareUpdater.failureEvent(for: NSError(domain: sparkle, code: 1)) {
            #expect(keyFailure == .checkFailed)
        } else {
            Issue.record("a missing key is a failure")
        }
    }

    @Test func startErrorIsCheckFailed() {
        engine.startError = NSError(domain: SoftwareUpdater.sparkleErrorDomain, code: 1)
        let updater = makeUpdater()
        #expect(updater.status == .failed(.checkFailed))
        // No probe after a failed start.
        clock.advance(by: .seconds(60))
        #expect(!engine.calls.contains("checkForUpdateInformation"))
        #expect(updater.status == .failed(.checkFailed))
    }

    @Test func offModeProbesOnce30sAfterStart() {
        // The scheduled work holds the updater weakly, as in the app (AppDelegate keeps it).
        let updater = makeUpdater(checks: true, mode: .off)
        clock.advance(by: .seconds(29))
        #expect(!engine.calls.contains("checkForUpdateInformation"))
        clock.advance(by: .seconds(1))
        #expect(engine.calls.filter { $0 == "checkForUpdateInformation" }.count == 1)
        clock.advance(by: .seconds(600))
        #expect(engine.calls.filter { $0 == "checkForUpdateInformation" }.count == 1)

        let other = SoftwareUpdaterTests()
        let checksOff = other.makeUpdater(checks: false, mode: .off)
        other.clock.advance(by: .seconds(60))
        #expect(!other.engine.calls.contains("checkForUpdateInformation"))
        withExtendedLifetime((updater, checksOff)) {}
    }

    @Test func homeLabelPublished() async {
        let updater = makeUpdater()
        var published: [UpdateStatus] = []
        updater.onStatusChange = { published.append($0) }
        _ = await updater.choice(forFound: update, userInitiated: false)
        #expect(published == [.available(update)])
        #expect(updater.homeLabel == "Update Available: 1.5.0")
        // Checks off: no notice.
        updater.apply(checks: false, mode: .off)
        #expect(published.last == .idle(lastChecked: nil))
        #expect(updater.homeLabel == nil)
    }

    @Test func feedHostAndTestFeedFlag() {
        let plist = Self.feedURL
        let normal = UpdateFeed(userDefaultsValue: nil, infoPlistValue: plist)
        #expect(normal.host == "github.com")
        #expect(!normal.isTestFeed)
        #expect(normal.logLine == "Feed: github.com")

        // The same URL in user defaults (or quoted, as Sparkle strips quotes) isn't a test feed.
        #expect(!UpdateFeed(userDefaultsValue: plist, infoPlistValue: plist).isTestFeed)
        #expect(!UpdateFeed(userDefaultsValue: "\"\(plist)\"", infoPlistValue: plist).isTestFeed)

        let test = UpdateFeed(userDefaultsValue: "https://Feed.Example/mmtvl/appcast.xml?token=x", infoPlistValue: plist)
        #expect(test.host == "feed.example")
        #expect(test.isTestFeed)
        #expect(test.logLine == "Feed: feed.example (test feed)")
        for line in [normal.logLine, test.logLine] {
            #expect(!line.contains("http"))
            #expect(!line.contains("/"))
            #expect(!line.contains("token"))
        }

        #expect(UpdateFeed(userDefaultsValue: nil, infoPlistValue: nil).host == "none")
        #expect(UpdateFeed(userDefaultsValue: "not a url", infoPlistValue: plist).host == "none")

        let updater = makeUpdater()
        #expect(updater.feedHost == "github.com")
        #expect(!updater.isTestFeed)
    }
}
