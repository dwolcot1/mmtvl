import Foundation
import Testing
@testable import MMTVL

struct IPTVLibraryTests {
    private let hour: TimeInterval = 3600

    @Test func noPlaylist() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.hasPlaylist == false)
        #expect(library.guideSources.isEmpty)
        await library.refreshAll()
        await library.refreshPlaylistIfStale()
        await library.refreshGuideIfStale()
        #expect(fixture.network.fetchCount == 0)
        #expect(fixture.network.downloadCount == 0)
        #expect(library.playlistStatus == .idle)
        #expect(library.guideStatus == .idle)
    }

    @Test func setPlaylistURLLoadsChannels() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        var statusChanges = 0
        library.onStatusChange = { statusChanges += 1 }

        await library.setPlaylistURL(IPTVFixtures.playlistURL)

        #expect(library.hasPlaylist)
        #expect(fixture.sources.playlistURL() == IPTVFixtures.playlistURL)
        #expect(library.channels.map(\.name) == ["NFL Network", "NBA TV", "Red Zone", "Lakers @ Celtics", "Knicks @ Heat"])
        #expect(library.playlistStatus == .loaded(fixture.clock.now))
        #expect(library.playlistHost == "provider.example")
        #expect(statusChanges >= 2)
        // No guide anywhere: nothing downloaded.
        #expect(library.guideSources.isEmpty)
        #expect(fixture.network.downloadCount == 0)
    }

    @Test func httpFailureKeepsChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.channels.count == 5)

        fixture.network.setError(IPTVNetworkError.http(403), for: IPTVFixtures.playlistURL)
        await library.refreshPlaylist()
        #expect(library.playlistStatus == .failed("Server error (HTTP 403)"))
        #expect(library.channels.count == 5)
    }

    @Test func notAPlaylistMessage() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: "<html><body>Error</body></html>"])
        defer { fixture.cleanUp() }
        await fixture.library.refreshPlaylist()
        #expect(fixture.library.playlistStatus == .failed("The address didn't return a playlist"))
        #expect(fixture.library.channels.isEmpty)
    }

    @Test func refreshPlaylistIfStale() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 1)
        fixture.clock.advance(9 * 60)
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 1)
        fixture.clock.advance(2 * 60)
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 2)
    }

    /// M7f L5: the timer's check. The playlist first (so the guide imports with channels), then the guide.
    @Test func refreshIfStaleFetchesThePlaylistBeforeTheGuide() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 1)
        #expect(fixture.network.downloadCount == 1)
        #expect(!library.channels.isEmpty)
        #expect(library.guideProgrammeCount > 0)

        // Fresh: nothing is fetched.
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 1)
        #expect(fixture.network.downloadCount == 1)

        // 15 minutes later the playlist is stale, the guide isn't.
        fixture.clock.advance(IPTVLibrary.autoRefreshInterval)
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 2)
        #expect(fixture.network.downloadCount == 1)
    }

    @Test func aChangedLineupIsReported() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        var changes = 0
        library.onLineupChange = { changes += 1 }
        await library.refreshPlaylist()
        #expect(changes == 1)
        // The same playlist again: no change.
        await library.refreshPlaylist()
        #expect(changes == 1)
    }

    @Test func playlistGuidesUntilOneIsPasted() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)])
        #expect(fixture.network.downloadCount == 1)
        let playlistID = IPTVLibrary.hash(IPTVFixtures.playlistGuideURL)
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)

        // The first pasted guide replaces the playlist's.
        await library.addGuideURL(IPTVFixtures.customGuideURL)
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.customGuideURL])
        #expect(fixture.network.downloadCount == 2)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [customID])
        #expect(library.state.guideImports.keys.sorted() == [customID])

        // Removing it brings them back (imported again: their rows were pruned).
        await library.removeGuideSource(customID)
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)])
        #expect(fixture.sources.guideURLs().isEmpty)
        #expect(fixture.network.downloadCount == 3)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [playlistID])
        #expect(library.guideStatus == .loaded(fixture.clock.now))
    }

    /// M7f L4: the playlist's guide instead of the pasted one; the pasted URL is kept.
    @Test func usePlaylistGuideKeepsPastedGuides() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let playlistGuide = GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)
        let pastedGuide = GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)
        await library.refreshAll()
        #expect(library.playlistNamesGuide)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 1)

        await library.applyUsePlaylistGuide(true)
        #expect(library.guideSources == [playlistGuide])
        #expect(library.customGuideSources == [pastedGuide])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.customGuideURL])
        #expect(fixture.network.downloadCount == 2)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [playlistGuide.id])
        #expect(library.state.guideImports.keys.sorted() == [playlistGuide.id])

        // Back to the pasted guide: imported again (its rows were pruned).
        await library.applyUsePlaylistGuide(false)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 3)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [pastedGuide.id])
    }

    /// M7f L4: without a playlist guide the setting changes nothing.
    @Test func usePlaylistGuideWithoutOneKeepsPastedGuides() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let pastedGuide = GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)
        await library.refreshAll()
        #expect(library.playlistNamesGuide == false)
        #expect(fixture.network.downloadCount == 1)

        await library.applyUsePlaylistGuide(true)
        #expect(library.usePlaylistGuide)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 1)
    }

    @Test func guideImport() async throws {
        let fixture = try makeLibrary(texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let revisionBefore = library.guideRevision

        await library.setPlaylistURL(IPTVFixtures.playlistURL)

        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideStatus == .loaded(fixture.clock.now))
        #expect(library.guideRevision > revisionBefore)
        #expect(library.guideProgrammeCount == 8)
        #expect(library.state.guideImports == [IPTVLibrary.hash(IPTVFixtures.playlistGuideURL): fixture.clock.now])

        let now = fixture.clock.now
        let result = await library.programmes(for: library.channels, in: DateInterval(start: now, duration: 2 * hour))
        let nfl = try #require(library.channels.first { $0.name == "NFL Network" })
        let nba = try #require(library.channels.first { $0.name == "NBA TV" })
        #expect(result[nfl.id]?.map(\.title) == ["NFL Network HD 1", "NFL Network HD 2"])
        #expect(result[nba.id]?.map(\.title) == ["NBA TV 1", "NBA TV 2"])
        #expect(result.count == 2)
    }

    @Test func refreshGuideIfStale() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(11 * hour)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(2 * hour)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 2)
    }

    @Test func refreshGuideIfStaleRunsWhenTheURLChanged() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let fresh = IPTVState(guideImports: [IPTVLibrary.hash(IPTVFixtures.customGuideURL): now])
        let same = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL], state: fresh, now: now)
        defer { same.cleanUp() }
        await same.library.refreshPlaylist()
        await same.library.refreshGuideIfStale()
        #expect(same.network.downloadCount == 0)

        let changed = IPTVState(guideImports: [IPTVLibrary.hash(IPTVFixtures.playlistGuideURL): now])
        let other = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL], state: changed, now: now)
        defer { other.cleanUp() }
        await other.library.refreshPlaylist()
        await other.library.refreshGuideIfStale()
        #expect(other.network.downloadCount == 1)
    }

    @Test func overridesApplyOnPlaylistRefreshWithoutImport() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        #expect(library.epgMatches[redZone.id] == nil)

        // nbatv.us's programmes were imported (NBA TV matched it), so the mapping applies without a download.
        try fixture.overridesFile.save(["red zone": "NBATV.us"])
        let revision = library.guideRevision
        await library.refreshPlaylist()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.epgMatches[redZone.id]?.epgID == "nbatv.us")
        #expect(library.guideRevision > revision)
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NBA TV 1")
    }

    @Test func overrideTargetsAreImported() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      overrides: ["Red Zone": "NFL.RedZone.HD.us2"])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NFL RedZone 1")
        #expect(library.guideProgrammeCount == 12)
    }

    @Test func removeSource() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      state: IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "Live Channels"))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(try await fixture.store.programmeCount() > 0)

        await library.removeSource()
        #expect(library.hasPlaylist == false)
        #expect(library.channels.isEmpty)
        #expect(library.guideSources.isEmpty)
        #expect(library.guideSourceInfo.isEmpty)
        #expect(fixture.sources.playlistURL() == nil)
        #expect(fixture.sources.guideURLs().isEmpty)
        #expect(try await fixture.store.programmeCount() == 0)
        #expect(library.guideProgrammeCount == 0)
        #expect(library.state == IPTVState())
        #expect(fixture.stateFile.load() == IPTVState())
    }

    // MARK: - Several guides (M6b)

    private var customID: String { IPTVLibrary.hash(IPTVFixtures.customGuideURL) }
    private var secondID: String { IPTVLibrary.hash(IPTVFixtures.secondGuideURL) }

    private func twoGuides() async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        await fixture.library.refreshAll()
        return fixture
    }

    private func channel(_ name: String, in library: IPTVLibrary) throws -> Channel {
        try #require(library.channels.first { $0.name == name })
    }

    @Test func twoGuidesMatchByPriority() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(fixture.network.downloadCount == 2)
        #expect(library.guideSources.map(\.id) == [customID, secondID])
        let matches = library.epgMatches
        #expect(matches[try channel("Red Zone", in: library).id] == EPGRef(sourceID: secondID, epgID: "redzone.alt.us"))
        #expect(matches[try channel("NBA TV", in: library).id] == EPGRef(sourceID: customID, epgID: "nbatv.us"))
        #expect(matches[try channel("NFL Network", in: library).id] == EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2"))
        #expect(library.guideSourceInfo[customID]?.matchedChannels == 2)
        #expect(library.guideSourceInfo[secondID]?.matchedChannels == 1)
        #expect(library.guideSourceInfo[customID]?.status == .loaded(fixture.clock.now))
        #expect(library.matchedChannelCount == 3)
        #expect(Set(library.state.guideImports.keys) == [customID, secondID])
        #expect(library.guideProgrammeCount == (library.guideSourceInfo[customID]?.programmeCount ?? 0)
                + (library.guideSourceInfo[secondID]?.programmeCount ?? 0))
    }

    @Test func moveGuideRematchesWithoutDownload() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.moveGuideSource(secondID, by: -1)
        #expect(library.guideSources.map(\.id) == [secondID, customID])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.secondGuideURL, IPTVFixtures.customGuideURL])
        // Rule 2 (tvg-id) in the lower guide beats rule 3 (name) in the higher one.
        #expect(library.epgMatches[try channel("NBA TV", in: library).id]?.sourceID == customID)
        #expect(fixture.network.downloadCount == 2)
        // Past the end does nothing.
        await library.moveGuideSource(secondID, by: -1)
        #expect(library.guideSources.map(\.id) == [secondID, customID])
    }

    /// M7n step 4b: rematches asked for at once (the matching runs off the main actor) run one at a time: each
    /// finishes and they give the matches a single one does; one asked for while another runs, after a guide is
    /// removed, leaves the current guides' matches.
    @Test func concurrentRematchesRunOneAtATime() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let expected = library.epgMatches
        let revision = library.guideRevision
        async let first: Void = library.rematch()
        async let second: Void = library.rematch()
        async let third: Void = library.rematch()
        _ = await (first, second, third)
        #expect(library.guideRevision == revision + 3)
        #expect(library.epgMatches == expected)

        let running = Task { await library.rematch() }
        await library.removeGuideSource(customID)
        await running.value
        let nba = try channel("NBA TV", in: library)
        #expect(library.epgMatches[nba.id] == EPGRef(sourceID: secondID, epgID: "nba.tv.alt.us"))
        #expect(library.epgMatches.values.allSatisfy { $0.sourceID == secondID })
        #expect(library.guideSourceInfo[secondID]?.matchedChannels == library.matchedChannelCount)
    }

    @Test func removeGuideRematchesWithoutDownload() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.removeGuideSource(customID)
        #expect(fixture.network.downloadCount == 2)
        let nba = try channel("NBA TV", in: library)
        #expect(library.epgMatches[nba.id] == EPGRef(sourceID: secondID, epgID: "nba.tv.alt.us"))
        #expect(library.epgMatches[try channel("Red Zone", in: library).id]?.sourceID == secondID)
        let programmes = await library.programmes(for: [nba], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[nba.id]?.first?.title == "NBA TV alt 1")
        #expect(try await fixture.store.programmeCounts()[customID] == nil)
        #expect(library.guideSourceInfo[customID] == nil)
        #expect(library.state.guideImports[customID] == nil)
    }

    @Test func onlyStaleGuidesDownload() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(13 * hour)
        await library.addGuideURL(IPTVFixtures.secondGuideURL)
        #expect(fixture.network.downloadCount == 2)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 3)    // only custom
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 3)
    }

    @Test func failingGuide() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.network.setError(IPTVNetworkError.http(500), for: IPTVFixtures.secondGuideURL)
        await library.refreshAll()
        #expect(library.guideSourceInfo[secondID]?.status == .failed("Server error (HTTP 500)"))
        #expect(library.guideSourceInfo[customID]?.status == .loaded(fixture.clock.now))
        #expect(library.guideStatus == .loaded(fixture.clock.now))

        fixture.network.setError(IPTVNetworkError.http(404), for: IPTVFixtures.customGuideURL)
        await library.refreshGuide()
        #expect(library.guideStatus == .failed("Server error (HTTP 404)"))
        // The failed guide keeps its rows.
        #expect(library.epgMatches[try channel("NBA TV", in: library).id]?.sourceID == customID)
    }

    @Test func requestsDuringARunJoinIt() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        var runs = 0
        var last = library.guideStatus
        library.onStatusChange = {
            if library.guideStatus == .loading, last != .loading { runs += 1 }
            last = library.guideStatus
        }
        let run = Task { await library.refreshGuide(sourceIDs: [customID]) }
        await Task.yield()
        await library.refreshGuide(sourceIDs: [secondID])    // returns at once: the run picks it up
        await run.value
        #expect(runs == 1)
        #expect(fixture.network.downloadCount == 2)
        #expect(Set(library.state.guideImports.keys) == [customID, secondID])
        #expect(library.guideStatus == .loaded(fixture.clock.now))
    }

    @Test func addGuideProblems() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.guideAddProblem(IPTVFixtures.customGuideURL) == .duplicate)
        #expect(library.guideAddProblem(IPTVFixtures.secondGuideURL) == nil)
        for n in 2...IPTVLibrary.maxGuideSources {
            await library.addGuideURL(URL(string: "https://guide.example/\(n).xml")!)
        }
        #expect(library.customGuideCount == IPTVLibrary.maxGuideSources)
        #expect(library.guideAddProblem(IPTVFixtures.secondGuideURL) == .full)
        #expect(library.guideAddProblem(IPTVFixtures.customGuideURL) == .duplicate)
    }

    // MARK: - Favorites and hiding (M6b L5)

    @Test func favoritesAndHidingSaveAndUpdateTheLineup() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        var statusChanges = 0
        library.onStatusChange = { statusChanges += 1 }

        library.setFavorite("id:nbatv.us", true)
        library.setFavorite("name:red zone", true)
        library.setFavorite("id:nflnetwork.us", true)
        #expect(library.isFavorite("id:nbatv.us"))
        #expect(library.lineup.favorites.map(\.name) == ["NBA TV", "Red Zone", "NFL Network"])
        #expect(fixture.preferencesFile.load().favorites == ["id:nbatv.us", "name:red zone", "id:nflnetwork.us"])
        #expect(statusChanges == 3)

        library.moveFavorite("name:red zone", by: -1)
        #expect(library.lineup.favorites.map(\.name) == ["Red Zone", "NBA TV", "NFL Network"])
        library.moveFavorite("name:red zone", by: -1)    // past the start
        library.moveFavorite("id:nflnetwork.us", by: 1)   // past the end
        #expect(fixture.preferencesFile.load().favorites == ["name:red zone", "id:nbatv.us", "id:nflnetwork.us"])

        library.setFavorite("id:nbatv.us", false)
        #expect(library.lineup.favorites.map(\.name) == ["Red Zone", "NFL Network"])

        library.setChannelHidden("name:red zone", true)
        #expect(!library.lineup.isVisible("name:red zone"))
        #expect(fixture.preferencesFile.load().hiddenChannels == ["name:red zone"])
        library.setGroupHidden("NBA Games", true)
        #expect(library.lineup.groups == ["Favorites", "My Teams", "Live Channels"])
        #expect(fixture.preferencesFile.load().hiddenGroups == ["NBA Games"])
        library.setGroupHidden("NBA Games", false)
        library.setChannelHidden("name:red zone", false)
        #expect(library.lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(fixture.preferencesFile.load() == ChannelPreferences(favorites: ["name:red zone", "id:nflnetwork.us"]))
    }

    @Test func removeSourceKeepsPreferences() async throws {
        let preferences = ChannelPreferences(favorites: ["id:nbatv.us"], hiddenGroups: ["NBA Games"])
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, preferences: preferences)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.lineup.groups == ["Favorites", "My Teams", "Live Channels"])
        await library.removeSource()
        #expect(library.preferences == preferences)
        #expect(fixture.preferencesFile.load() == preferences)
        #expect(library.lineup.groups.isEmpty)
    }

    // MARK: - Match Guide (M6b L6, L9)

    @Test func manualMatchReimportsWhenItsProgrammesWerentKept() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try channel("Red Zone", in: library)
        #expect(library.epgMatches[redZone.id] == nil)

        await library.setGuideMatch(.epg(EPGRef(sourceID: customID, epgID: "nfl.redzone.hd.us2")), for: redZone)
        #expect(fixture.overridesFile.load() == ["Red Zone": "nfl.redzone.hd.us2"])
        #expect(fixture.network.downloadCount == 2)
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NFL RedZone 1")
    }

    @Test func noGuideAndAutomatic() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nba = try channel("NBA TV", in: library)

        await library.setGuideMatch(.none, for: nba)
        #expect(fixture.overridesFile.load() == ["NBA TV": ""])
        #expect(library.epgMatches[nba.id] == nil)
        #expect(await library.guideMatchOptions(for: nba).choice == GuideMatchChoice.none)

        // Automatic removes keys for the name and the tvg-id, in any case. Its programmes are stored: no download.
        try fixture.overridesFile.save(["NBATV.us": "x", "nba tv": ""])
        await library.setGuideMatch(.automatic, for: nba)
        #expect(fixture.overridesFile.load().isEmpty)
        #expect(library.epgMatches[nba.id] == EPGRef(sourceID: customID, epgID: "nbatv.us"))
        #expect(fixture.network.downloadCount == 1)
    }

    @Test func automaticReimportsWhenNoGuideKeptNothing() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      overrides: ["NBA TV": ""])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nba = try channel("NBA TV", in: library)
        #expect(try await fixture.store.programmeCount(for: EPGRef(sourceID: customID, epgID: "nbatv.us")) == 0)

        await library.setGuideMatch(.automatic, for: nba)
        #expect(fixture.network.downloadCount == 2)
        let programmes = await library.programmes(for: [nba], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[nba.id]?.first?.title == "NBA TV 1")
    }

    @Test func matchOptions() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nfl = try channel("NFL Network", in: library)
        let current = EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2")
        #expect(library.guideLabel(for: current) == "custom")

        let options = await library.guideMatchOptions(for: nfl)
        #expect(options.choice == .automatic)
        #expect(options.current == current)
        #expect(options.candidates.first == GuideCandidate(ref: current, name: "NFL Network HD", sourceLabel: "custom"))
        #expect(options.candidates.filter { $0.ref == current }.count == 1)

        await library.setGuideMatch(.epg(current), for: nfl)
        #expect(await library.guideMatchOptions(for: nfl).choice == .epg(current))
    }

    @Test func nowNext() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nfl = try #require(library.channels.first { $0.name == "NFL Network" })
        let result = await library.nowNext(for: nfl, at: fixture.clock.now.addingTimeInterval(10 * 60))
        #expect(result.now?.title == "NFL Network HD 1")
        #expect(result.next?.title == "NFL Network HD 2")

        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        let none = await library.nowNext(for: redZone, at: fixture.clock.now)
        #expect(none.now == nil && none.next == nil)
    }

    @Test func rememberedStateIsSaved() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        fixture.library.rememberChannel("id:nbatv.us")
        fixture.library.rememberGroup("NBA Games")
        #expect(fixture.stateFile.load() == IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "NBA Games",
                                                      recentChannelIDs: ["id:nbatv.us"]))
    }

    // MARK: Recent channels (M7 L13)

    @Test func recentChannelsAreMostRecentFirstAndCapped() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        for n in 1...12 { library.rememberChannel("id:\(n)") }
        #expect(library.state.recentChannelIDs == (3...12).reversed().map { "id:\($0)" })
        library.rememberChannel("id:5")
        #expect(library.state.recentChannelIDs.first == "id:5")
        #expect(library.state.recentChannelIDs.count == 10)
        #expect(library.state.recentChannelIDs.filter { $0 == "id:5" }.count == 1)
        #expect(fixture.stateFile.load().recentChannelIDs == library.state.recentChannelIDs)
    }

    @Test func rememberingTheLastChannelStillMovesItToTheFront() throws {
        let fixture = try makeLibrary(state: IPTVState(lastChannelID: "id:a", recentChannelIDs: ["id:b", "id:a"]))
        defer { fixture.cleanUp() }
        fixture.library.rememberChannel("id:a")
        #expect(fixture.library.state.recentChannelIDs == ["id:a", "id:b"])
        #expect(fixture.stateFile.load().recentChannelIDs == ["id:a", "id:b"])
    }

    @Test func olderStateFilesHaveNoRecents() throws {
        let state = try JSONDecoder().decode(IPTVState.self, from: Data(#"{"lastChannelID": "id:a"}"#.utf8))
        #expect(state.recentChannelIDs.isEmpty)
    }

    @Test func oldGuideKeysLoad() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let json = """
        {"lastChannelID": "id:nbatv.us", "lastGroup": "NBA Games",
         "lastGuideImport": 700000000, "lastGuideSourceHash": "abc"}
        """
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fixture.directory.appending(path: IPTVState.fileName))
        #expect(fixture.stateFile.load() == IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "NBA Games"))
    }

    @Test func multiviewSnapshotRoundTrips() throws {
        let snapshot = MultiviewSnapshot(layout: .grid, slots: ["id:nbatv.us", nil, "id:nflnetwork.us", nil],
                                         focusedSlot: 2, isActive: true)
        let state = IPTVState(lastChannelID: "id:nbatv.us", multiview: snapshot)
        let fixture = try makeLibrary(state: state)
        defer { fixture.cleanUp() }
        #expect(fixture.stateFile.load() == state)
        #expect(fixture.library.state.multiview == snapshot)
    }

    @Test func badMultiviewSnapshotReadsAsNil() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let json = """
        {"lastChannelID": "id:nbatv.us",
         "multiview": {"layout": "bogus", "slots": ["id:nbatv.us"], "focusedSlot": 0, "isActive": true}}
        """
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fixture.directory.appending(path: IPTVState.fileName))
        let state = fixture.stateFile.load()
        #expect(state.multiview == nil)
        #expect(state.lastChannelID == "id:nbatv.us")
    }

    @Test func rememberMultiviewSaves() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: ["id:nbatv.us", nil, nil, nil, nil],
                                         focusedSlot: 0, isActive: false)
        fixture.library.rememberMultiview(snapshot)
        #expect(fixture.stateFile.load().multiview == snapshot)
        fixture.library.rememberMultiview(nil)
        #expect(fixture.stateFile.load().multiview == nil)
    }

    // MARK: M7j step 4: antenna channels in the library

    private static let antennaIDs = ["antenna:2.1", "antenna:5.1", "antenna:11.1"]

    @Test func antennaChannelsJoinThePlaylist() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.playlistChannels.count == 5)
        #expect(library.channels.count == 8)
        #expect(Array(library.channels.suffix(3).map(\.id)) == Self.antennaIDs)
        // L2: numbered after the playlist's.
        #expect(library.channels.map(\.number) == Array(1...8))
        #expect(library.channels.suffix(3).allSatisfy { $0.group == "Antenna" && $0.isDirectStream })
        #expect(library.lineup.groups == ["Favorites", "My Teams", "Antenna", "All Channels", "Live Channels", "NBA Games"])
        #expect(library.antenna.status == .loaded(fixture.clock.now))
        #expect(fixture.tuner?.searchCount == 1)
    }

    @Test func settingAPlaylistKeepsAntennaChannels() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAntenna()
        #expect(library.channels.map(\.id) == Self.antennaIDs)
        #expect(library.channels.map(\.number) == [1, 2, 3])

        await library.setPlaylistURL(IPTVFixtures.playlistURL)
        #expect(library.channels.count == 8)
        #expect(Array(library.channels.suffix(3).map(\.id)) == Self.antennaIDs)
        #expect(Array(library.channels.suffix(3).map(\.number)) == [6, 7, 8])
    }

    @Test func removingTheSourceKeepsAntennaChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.channels.count == 8)

        await library.removeSource()
        #expect(!library.hasPlaylist)
        #expect(library.playlistChannels.isEmpty)
        #expect(library.channels.map(\.id) == Self.antennaIDs)
        #expect(library.channels.map(\.number) == [1, 2, 3])
        #expect(library.lineup.groups == ["Favorites", "My Teams", "Antenna"])
        #expect(library.hasLiveSource)
    }

    @Test func failedLineupKeepsTheLastChannels() async throws {
        let tuner = FakeTuner()
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAntenna()
        #expect(library.channels.count == 3)

        tuner.setLineup(nil, for: AntennaFixtures.device())
        // Fresh: nothing is asked.
        fixture.clock.advance(9 * 60)
        await library.refreshIfStale()
        #expect(tuner.lineupFetchCount == 1)
        fixture.clock.advance(2 * 60)
        await library.refreshIfStale()
        #expect(tuner.lineupFetchCount == 3)
        #expect(library.channels.map(\.id) == Self.antennaIDs)
        #expect(library.antenna.status == .failed("The antenna tuner isn't answering"))
    }

    @Test func failedLineupRediscoversOnce() async throws {
        let tuner = FakeTuner()
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAntenna()
        #expect(tuner.searchCount == 1)
        #expect(tuner.lineupFetchCount == 1)

        // No answer: one more search, the lineup asked once more, then it gives up.
        tuner.setLineup(nil, for: AntennaFixtures.device())
        await library.refreshAntenna()
        #expect(tuner.searchCount == 2)
        #expect(tuner.lineupFetchCount == 3)

        // The tuner moved to another address: the search finds it there and its lineup is read.
        let moved = AntennaFixtures.device(host: "10.0.0.10")
        tuner.setDevices([moved])
        tuner.setLineup(AntennaFixtures.lineupJSON(AntennaFixtures.channels, host: "10.0.0.10"), for: moved)
        await library.refreshAntenna()
        #expect(tuner.searchCount == 3)
        #expect(library.antenna.devices == [moved])
        #expect(library.channels.map(\.streamURL) == AntennaFixtures.channels.map {
            AntennaFixtures.streamURL($0.0, host: "10.0.0.10")
        })
        #expect(library.antenna.status == .loaded(fixture.clock.now))
    }

    @Test func antennaOffRemovesTheChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.channels.count == 8)

        await library.applyAntennaEnabled(false)
        #expect(library.channels.count == 5)
        #expect(!library.channels.contains { $0.isDirectStream })
        #expect(!library.lineup.groups.contains("Antenna"))
        #expect(library.antenna.devices.isEmpty)
        // Off: no search, no lineup.
        fixture.clock.advance(3600)
        await library.refreshIfStale()
        #expect(fixture.tuner?.searchCount == 1)

        await library.applyAntennaEnabled(true)
        #expect(library.channels.count == 8)
        #expect(fixture.tuner?.searchCount == 2)
    }

    @Test func hasLiveSourceWithOnlyATuner() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(!library.hasPlaylist)
        #expect(!library.hasLiveSource)
        #expect(library.canHaveLiveSource)
        await library.discoverAntenna()
        #expect(library.hasLiveSource)

        let none = try makeLibrary(tuner: FakeTuner(devices: []))
        defer { none.cleanUp() }
        #expect(await none.library.discoverAntenna() == 0)
        #expect(!none.library.hasLiveSource)
        #expect(none.library.canHaveLiveSource)
        #expect(none.library.antenna.hasSearched)

        let off = try makeLibrary()
        defer { off.cleanUp() }
        #expect(!off.library.canHaveLiveSource)
    }

    /// QA (step 4) finding 2: the antenna turned off while a search, then a lineup read, is in flight: what they
    /// bring back is dropped.
    @Test func turningTheAntennaOffMidwayDropsWhatComesBack() async throws {
        let tuner = FakeTuner()
        let slowSearch = AntennaSource(find: {
            try? await Task.sleep(for: .milliseconds(100))
            return tuner.search()
        }, http: HDHomeRunHTTP(fetch: { url, _, _ in tuner.fetch(url) }))
        slowSearch.isEnabled = true
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, antenna: slowSearch)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        let search = Task { await library.discoverAntenna() }
        while !library.antenna.isSearching { await Task.yield() }
        await library.applyAntennaEnabled(false)
        _ = await search.value
        #expect(tuner.searchCount == 1)
        #expect(library.antenna.devices.isEmpty)
        #expect(library.antenna.channels.isEmpty)
        #expect(library.channels.count == 5)
        #expect(!library.lineup.groups.contains("Antenna"))

        let slowLineup = AntennaSource(find: { tuner.search() }, http: HDHomeRunHTTP(fetch: { url, _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return tuner.fetch(url)
        }))
        slowLineup.isEnabled = true
        let second = try makeLibrary(playlist: IPTVFixtures.playlistURL, antenna: slowLineup)
        defer { second.cleanUp() }
        await second.library.refreshPlaylist()
        let read = Task { await second.library.discoverAntenna() }
        while second.library.antenna.status != .loading { await Task.yield() }
        await second.library.applyAntennaEnabled(false)
        _ = await read.value
        #expect(tuner.lineupFetchCount == 1)
        #expect(second.library.antenna.devices.isEmpty)
        #expect(second.library.antenna.channels.isEmpty)
        #expect(second.library.antenna.status == .idle)
        #expect(second.library.channels.count == 5)
        #expect(!second.library.lineup.groups.contains("Antenna"))
    }

    /// QA (step 4) finding 3: a playlist fetch tells the router once, and not at all when nothing changed.
    @Test func playlistFetchChangesTheLineupOnce() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        var changes = 0
        library.onLineupChange = { changes += 1 }
        await library.refreshPlaylist()
        #expect(changes == 1)
        await library.refreshPlaylist()
        #expect(changes == 1)
        await library.refreshAntenna()
        #expect(changes == 2)
        #expect(library.channels.count == 8)
    }

    /// Step 2 security L-b: a search asked for while one runs waits for it instead of starting another.
    @Test func antennaSearchesRunOneAtATime() async throws {
        final class Counter { var searches = 0 }
        let counter = Counter()
        let tuner = FakeTuner()
        let source = AntennaSource(find: {
            counter.searches += 1
            try? await Task.sleep(for: .milliseconds(50))
            return [AntennaFixtures.device()]
        }, http: HDHomeRunHTTP(fetch: { url, _, _ in tuner.fetch(url) }))
        source.isEnabled = true
        async let first = source.discover()
        async let second = source.discover()
        #expect(await [first, second] == [1, 1])
        #expect(counter.searches == 1)
        #expect(source.channels.count == 3)
    }

    // MARK: M7n step 1: the antenna and playlist retry after launch and wake (L1, L2)

    /// The retry loop's waits, on the test clock (never in real time); `onWait` runs after the clock moved, with the
    /// wait's number (from 1), before the try that follows it.
    private final class RetryWaits {
        var all: [Duration] = []
        var onWait: ((Int) async -> Void)?
        func wait(_ clock: TestClock, _ delay: Duration) async {
            all.append(delay)
            clock.advance(TimeInterval(delay.components.seconds))
            await onWait?(all.count)
        }
    }

    /// (a) The network isn't up at launch: the first search finds nothing, the retry 5 s later neither, the one 10 s
    /// after that finds the tuner. Its channels merge, the antenna guide follows, and the loop ends.
    @Test func launchRetriesTheAntennaSearchUntilATunerAnswers() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let waits = RetryWaits()
        let tuner = FakeTuner(devices: [])
        tuner.setDiscover(AntennaFixtures.discoverJSON())
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      files: [AntennaFixtures.guideURL: AntennaFixtures.guideXML(now: now)],
                                      tuner: tuner, retryWait: { await waits.wait($0, $1) }, now: now)
        defer { fixture.cleanUp() }
        let library = fixture.library
        library.antennaGuideEnabled = true
        waits.onWait = { number in
            guard number == 2 else { return }
            tuner.setDevices([AntennaFixtures.device()])
            tuner.setLineup(AntennaFixtures.lineupJSON(AntennaFixtures.channels), for: AntennaFixtures.device())
        }
        await library.refreshAtLaunch()
        #expect(library.channels.count == 5)
        #expect(tuner.searchCount == 1)
        let retry = try #require(library.channelRetryTask)

        await retry.value
        #expect(waits.all == [.seconds(5), .seconds(10)])
        #expect(tuner.searchCount == 3)
        #expect(library.channels.count == 8)
        #expect(Array(library.channels.suffix(3).map(\.id)) == Self.antennaIDs)
        #expect(library.lineup.groups.contains("Antenna"))
        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideSourceInfo[AntennaGuide.sourceID]?.status == .loaded(fixture.clock.now))
        // The playlist was there all along: fetched once.
        #expect(fixture.network.fetchCount == 1)
    }

    /// (b) The playlist failed at launch (offline): it's fetched again, and its guide follows.
    @Test func launchRetriesAFailedPlaylist() async throws {
        let waits = RetryWaits()
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide],
                                      retryWait: { await waits.wait($0, $1) })
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.network.setError(URLError(.notConnectedToInternet), for: IPTVFixtures.playlistURL)
        waits.onWait = { number in
            if number == 2 { fixture.network.setError(nil, for: IPTVFixtures.playlistURL) }
        }
        await library.refreshAtLaunch()
        #expect(library.playlistChannels.isEmpty)
        guard case .failed = library.playlistStatus else {
            Issue.record("the launch fetch should have failed")
            return
        }

        await library.channelRetryTask?.value
        #expect(waits.all == [.seconds(5), .seconds(10)])
        #expect(fixture.network.fetchCount == 3)
        #expect(library.playlistChannels.count == 5)
        #expect(library.playlistStatus == .loaded(fixture.clock.now))
        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideSourceInfo[IPTVLibrary.hash(IPTVFixtures.playlistGuideURL)]?.status
                == .loaded(fixture.clock.now))
    }

    /// (c) No tuner at all: tries at 5, 15, 35, 65, 125, 185 and 245 s; the next (305 s) would be past 5 minutes.
    @Test func retryStopsAfterFiveMinutes() async throws {
        let waits = RetryWaits()
        let tuner = FakeTuner(devices: [])
        let fixture = try makeLibrary(tuner: tuner, retryWait: { await waits.wait($0, $1) })
        defer { fixture.cleanUp() }
        let start = fixture.clock.instant
        await fixture.library.refreshAtLaunch()
        await fixture.library.channelRetryTask?.value
        #expect(waits.all == [.seconds(5), .seconds(10), .seconds(20), .seconds(30), .seconds(60), .seconds(60),
                              .seconds(60)])
        #expect(tuner.searchCount == 8)
        #expect(fixture.clock.instant - start <= IPTVLibrary.channelRetryLimit)
        #expect(fixture.library.isAntennaMissing)
    }

    /// (c) Both sources there at launch: no loop. After wake too.
    @Test func noRetryWhenBothSourcesLoaded() async throws {
        let waits = RetryWaits()
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner(),
                                      retryWait: { await waits.wait($0, $1) })
        defer { fixture.cleanUp() }
        await fixture.library.refreshAtLaunch()
        #expect(fixture.library.channelRetryTask == nil)
        await fixture.library.refreshAfterWake()
        #expect(fixture.library.channelRetryTask == nil)
        #expect(waits.all.isEmpty)
        #expect(fixture.library.channels.count == 8)
    }

    /// (c) The antenna turned off during a wait ends the loop without another search; the playlist was there.
    @Test func turningTheAntennaOffEndsTheRetry() async throws {
        let waits = RetryWaits()
        let tuner = FakeTuner(devices: [])
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: tuner,
                                      retryWait: { await waits.wait($0, $1) })
        defer { fixture.cleanUp() }
        let library = fixture.library
        waits.onWait = { _ in await library.applyAntennaEnabled(false) }
        await library.refreshAtLaunch()
        await library.channelRetryTask?.value
        #expect(waits.all == [.seconds(5)])
        #expect(tuner.searchCount == 1)
        #expect(library.channels.count == 5)
    }

    /// (c) Removing the playlist during a wait ends its part: it isn't fetched again.
    @Test func removingThePlaylistEndsItsRetry() async throws {
        let waits = RetryWaits()
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, retryWait: { await waits.wait($0, $1) })
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.network.setError(URLError(.notConnectedToInternet), for: IPTVFixtures.playlistURL)
        waits.onWait = { _ in await library.removeSource() }
        await library.refreshAtLaunch()
        await library.channelRetryTask?.value
        #expect(waits.all == [.seconds(5)])
        #expect(fixture.network.fetchCount == 1)
    }

    /// One loop at a time: a wake refresh ends the launch's loop and starts its own.
    @Test func aNewerRefreshReplacesTheRetry() async throws {
        let tuner = FakeTuner(devices: [])
        let fixture = try makeLibrary(tuner: tuner)    // the loop's waits are parked
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        let first = try #require(library.channelRetryTask)
        await library.refreshAfterWake()
        await first.value    // cancelled: its parked wait ended
        let second = try #require(library.channelRetryTask)
        #expect(second != first)
        #expect(!second.isCancelled)
        #expect(tuner.searchCount == 2)
    }

    /// (d) L2: with no tuner known, `refreshIfStale` searches again once the last search is more than 30 s old (not
    /// 10 minutes); with a tuner known, the lineup is read again only after the 10-minute staleness.
    @Test func refreshIfStaleSearchesAgainAfterThirtySecondsWithNoTuner() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_791_200_000))
        let tuner = FakeTuner(devices: [])
        let source = AntennaSource.fake(tuner, now: { clock.now })
        #expect(AntennaSource.searchRetryStaleness == 30)
        #expect(await source.discover() == 0)
        #expect(tuner.searchCount == 1)
        clock.advance(30)
        await source.refreshIfStale()
        #expect(tuner.searchCount == 1)
        clock.advance(1)
        await source.refreshIfStale()
        #expect(tuner.searchCount == 2)

        // A tuner known: the lineup's 10 minutes, no search.
        tuner.setDevices([AntennaFixtures.device()])
        tuner.setLineup(AntennaFixtures.lineupJSON(AntennaFixtures.channels), for: AntennaFixtures.device())
        clock.advance(31)
        await source.refreshIfStale()
        #expect(tuner.searchCount == 3)
        #expect(tuner.lineupFetchCount == 1)
        #expect(source.channels.count == 3)
        clock.advance(31)
        await source.refreshIfStale()
        clock.advance(AntennaSource.staleness - 31)
        await source.refreshIfStale()
        #expect(tuner.lineupFetchCount == 1)
        clock.advance(1)
        await source.refreshIfStale()
        #expect(tuner.lineupFetchCount == 2)
        #expect(tuner.searchCount == 3)
    }

    // MARK: M7j step 8: the antenna guide (L10, L11, L12)

    private static let antennaGuideID = AntennaGuide.sourceID

    /// A library with the fake tuner answering `discover.json` with the fake DeviceAuth, SiliconDust's fake guide at
    /// its URL, and the antenna guide on.
    private func antennaGuideLibrary(playlist: URL? = IPTVFixtures.playlistURL, guides: [URL] = [],
                                     files extra: [URL: String] = [:], guideExtra: String = "",
                                     overrides: [String: String]? = nil, preferences: ChannelPreferences? = nil,
                                     guideOn: Bool = true) throws -> LibraryFixture {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let tuner = FakeTuner()
        tuner.setDiscover(AntennaFixtures.discoverJSON())
        var files = [AntennaFixtures.guideURL: AntennaFixtures.guideXML(now: now, extra: guideExtra),
                     IPTVFixtures.customGuideURL: IPTVFixtures.guide(now: now)]
        files.merge(extra) { _, new in new }
        let fixture = try makeLibrary(playlist: playlist, guides: guides, files: files, overrides: overrides,
                                      preferences: preferences, tuner: tuner, now: now)
        fixture.library.antennaGuideEnabled = guideOn
        return fixture
    }

    private func antennaChannel(_ number: String, in library: IPTVLibrary) throws -> Channel {
        try #require(library.channels.first { $0.id == "antenna:\(number)" })
    }

    private func hasProgrammes(_ channel: Channel, in library: IPTVLibrary, at now: Date) async -> Bool {
        let interval = DateInterval(start: now, duration: 3600)
        return !(await library.programmes(for: [channel], in: interval)[channel.id] ?? []).isEmpty
    }

    /// Launch: the tuner's lineup, then the antenna guide (never imported: at once) for the antenna channels only.
    /// The file also lists a playlist channel's id, which isn't matched to it. Next due 20–28 h later.
    @Test func antennaGuideImportsOnlyAntennaChannels() async throws {
        let fixture = try antennaGuideLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        #expect(fixture.tuner?.discoverFetchCount == 1)
        #expect(library.epgMatches[try antennaChannel("2.1", in: library).id]
                == EPGRef(sourceID: Self.antennaGuideID, epgID: "us10001.hdhomerun.com"))
        #expect(library.epgMatches[try antennaChannel("5.1", in: library).id]?.epgID == "us10002.hdhomerun.com")
        #expect(library.epgMatches[try antennaChannel("11.1", in: library).id]?.epgID == "us10003.hdhomerun.com")
        let nba = try channel("NBA TV", in: library)
        #expect(library.epgMatches[nba.id] == nil)
        for number in ["2.1", "5.1", "11.1"] {
            #expect(await hasProgrammes(try antennaChannel(number, in: library), in: library, at: fixture.clock.now))
        }
        // Programmes are kept for the three antenna channels only (4 each), not for nbatv.us.
        #expect(try await fixture.store.programmeCounts()[Self.antennaGuideID] == 12)
        let info = try #require(library.guideSourceInfo[Self.antennaGuideID])
        #expect(info.matchedChannels == 3)
        #expect(info.programmeCount == 12)
        #expect(info.status == .loaded(fixture.clock.now))
        // Not one of the Guides section's guides; the footer counts playlist channels only.
        #expect(!library.guideSources.contains { $0.id == Self.antennaGuideID })
        #expect(library.matchedChannelCount == 0)
        let due = try #require(library.state.antennaGuideDue)
        #expect(due.timeIntervalSince(fixture.clock.now) >= 20 * 3600)
        #expect(due.timeIntervalSince(fixture.clock.now) <= 28 * 3600)
        #expect(library.state.guideImports[Self.antennaGuideID] == fixture.clock.now)
        #expect(library.guideLabel(for: EPGRef(sourceID: Self.antennaGuideID, epgID: "us10001.hdhomerun.com"))
                == "HDHomeRun")

        // Not due again until then.
        fixture.clock.advance(19 * 3600)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(9 * 3600 + 1)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 2)
    }

    /// The token is never in the state file, Settings' status texts or the guide's id.
    @Test func theDeviceAuthIsNeverStored() async throws {
        let fixture = try antennaGuideLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.state.antennaGuideDue != nil)
        let token = AntennaFixtures.fakeDeviceAuth
        let encoded = try #require(AntennaFixtures.guideURL.query(percentEncoded: true))
        let stateJSON = String(decoding: try JSONEncoder().encode(library.state), as: UTF8.self)
        let onDisk = try String(contentsOf: fixture.stateFile.url, encoding: .utf8)
        for text in [stateJSON, onDisk, "\(library.guideSourceInfo)", "\(library.state)", Self.antennaGuideID] {
            #expect(!text.contains(token))
            #expect(!text.contains(encoded))
            #expect(!text.contains("FAKEauth"))
        }
    }

    /// Two tuners: their DeviceAuths are concatenated in DeviceID order, whatever order the search found them in.
    @Test func antennaGuideAuthsAreInDeviceIDOrder() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let first = AntennaFixtures.device(id: "0000000A", host: "10.0.0.20")
        let second = AntennaFixtures.device(id: "0000000B", host: "10.0.0.21")
        let tuner = FakeTuner(devices: [second, first])
        tuner.setDiscover(AntennaFixtures.discoverJSON(device: first, auth: "FirstAuth111"), for: first)
        tuner.setDiscover(AntennaFixtures.discoverJSON(device: second, auth: "SecondAuth22"), for: second)
        let url = try #require(AntennaGuide.url(deviceAuths: ["FirstAuth111", "SecondAuth22"]))
        let fixture = try makeLibrary(files: [url: AntennaFixtures.guideXML(now: now)], tuner: tuner, now: now)
        defer { fixture.cleanUp() }
        let library = fixture.library
        library.antennaGuideEnabled = true
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideSourceInfo[Self.antennaGuideID]?.status == .loaded(now))
    }

    /// Step 2 security L5: a DeviceAuth with characters outside base64, or none, means no download; tried again in an
    /// hour.
    @Test func aBadDeviceAuthMeansNoDownload() async throws {
        let fixture = try antennaGuideLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.tuner?.setDiscover(AntennaFixtures.discoverJSON(auth: "abc&evil=1 2"))
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 0)
        #expect(library.guideSourceInfo[Self.antennaGuideID]?.status == .failed("The tuner didn't give a guide key"))
        #expect(library.state.antennaGuideDue == fixture.clock.now.addingTimeInterval(3600))

        fixture.tuner?.setDiscover(AntennaFixtures.discoverJSON(auth: nil))
        fixture.clock.advance(3601)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 0)

        // Another device's discover.json at that address (a different DeviceID) isn't used either.
        fixture.tuner?.setDiscover(AntennaFixtures.discoverJSON(device: AntennaFixtures.device(id: "99999999")))
        fixture.clock.advance(3601)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 0)
    }

    @Test func antennaGuideIsDueAfterAFailureInAnHour() async throws {
        let fixture = try antennaGuideLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.network.setError(IPTVNetworkError.http(503), for: AntennaFixtures.guideURL)
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideSourceInfo[Self.antennaGuideID]?.status == .failed("Server error (HTTP 503)"))
        #expect(library.state.antennaGuideDue == fixture.clock.now.addingTimeInterval(3600))
        #expect(library.state.guideImports[Self.antennaGuideID] == nil)

        fixture.clock.advance(30 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 1)
        fixture.network.setError(nil, for: AntennaFixtures.guideURL)
        fixture.clock.advance(31 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 2)
        #expect(library.guideSourceInfo[Self.antennaGuideID]?.status == .loaded(fixture.clock.now))
    }

    /// A pasted guide's import prunes guides no longer in use, never the antenna guide.
    @Test func pruneKeepsTheAntennaGuide() async throws {
        let fixture = try antennaGuideLibrary(guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [customID, Self.antennaGuideID].sorted())

        await library.refreshGuide()
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [customID, Self.antennaGuideID].sorted())
        await library.removeGuideSource(customID)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [Self.antennaGuideID])
        #expect(library.state.guideImports[Self.antennaGuideID] != nil)
        #expect(library.state.antennaGuideDue != nil)
        #expect(library.epgMatches[try antennaChannel("5.1", in: library).id]?.sourceID == Self.antennaGuideID)
    }

    /// L11: off, the antenna guide's rows go and antenna channels match the pasted guides by name; SiliconDust isn't
    /// asked. On again: it's due at once.
    @Test func guideOffPrunesItAndMatchesPastedGuidesByName() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let pasted = IPTVFixtures.guide(now: now).replacingOccurrences(
            of: "<channel id=\"Unrelated.us2\"><display-name>Unrelated</display-name>",
            with: "<channel id=\"Unrelated.us2\"><display-name>WAGA</display-name>")
        let fixture = try antennaGuideLibrary(guides: [IPTVFixtures.customGuideURL],
                                              files: [IPTVFixtures.customGuideURL: pasted])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 2)
        let waga = try antennaChannel("5.1", in: library)
        #expect(library.epgMatches[waga.id]?.sourceID == Self.antennaGuideID)

        await library.applyAntennaGuide(false)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [customID])
        #expect(library.guideSourceInfo[Self.antennaGuideID] == nil)
        #expect(library.state.antennaGuideDue == nil)
        #expect(library.state.guideImports[Self.antennaGuideID] == nil)
        // "WAGA-HD" matches "WAGA" by name in the pasted guide, whose programmes were kept for it at import.
        #expect(library.epgMatches[waga.id] == EPGRef(sourceID: customID, epgID: "unrelated.us2"))
        #expect(await hasProgrammes(waga, in: library, at: fixture.clock.now))
        #expect(library.epgMatches[try antennaChannel("2.1", in: library).id] == nil)
        fixture.clock.advance(2 * 24 * 3600)
        await library.refreshIfStale()
        #expect(fixture.tuner?.discoverFetchCount == 1)
        #expect(fixture.network.downloadCount == 3)    // the pasted guide only (stale after 12 h)
        #expect(!(try await fixture.store.programmeCounts().keys.contains(Self.antennaGuideID)))

        await library.applyAntennaGuide(true)
        #expect(fixture.tuner?.discoverFetchCount == 2)
        #expect(library.epgMatches[waga.id]?.sourceID == Self.antennaGuideID)
    }

    /// Refresh Now imports the antenna guide only when its last import is more than an hour old.
    @Test func refreshNowSkipsAFreshAntennaGuide() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(30 * 60)
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(31 * 60)
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 2)
        // Nor does a failed one repeat within the hour.
        fixture.network.setError(IPTVNetworkError.http(500), for: AntennaFixtures.guideURL)
        fixture.clock.advance(61 * 60)
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 3)
        fixture.clock.advance(10 * 60)
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 3)
    }

    /// Step 9: Refresh Now with a tuner alone reads its lineup and the guides; it never fetches a playlist or shows a
    /// playlist error.
    @Test func refreshNowWithoutAPlaylistReadsTheTunerOnly() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(fixture.tuner?.lineupFetchCount == 1)
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(61 * 60)
        await library.refreshAll()
        #expect(fixture.network.fetchCount == 0)
        #expect(library.playlistStatus == .idle)
        #expect(library.guideStatus == .idle)
        #expect(fixture.tuner?.lineupFetchCount == 2)
        #expect(fixture.tuner?.searchCount == 1)
        // L10's 1 h rule: the antenna guide again, since the last import is more than an hour old.
        #expect(fixture.network.downloadCount == 2)
        #expect(library.channels.map(\.id) == Self.antennaIDs)
    }

    /// Step 9 QA 1: Settings is told after the channels and guide matches changed, so its last read sees them.
    @Test func antennaStatusChangeComesAfterTheChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.channels.count == 8)
        var seen: [Int] = []
        library.onStatusChange = { seen.append(library.channels.count) }
        await library.applyAntennaEnabled(false)
        #expect(!seen.isEmpty)
        #expect(seen.last == 5)
        seen = []
        await library.applyAntennaEnabled(true)
        #expect(seen.last == 8)
        // A lineup change (a channel gone) too.
        fixture.tuner?.setLineup(AntennaFixtures.lineupJSON(Array(AntennaFixtures.channels.prefix(2))),
                                 for: AntennaFixtures.device())
        seen = []
        await library.refreshAntenna()
        #expect(seen.last == 7)
    }

    /// Step 9 QA 4: Find Tuners with a known tuner and a search that finds nothing.
    @Test func findOutcomeCountsKeptTunersThatAnswered() async throws {
        let fixture = try makeLibrary(tuner: FakeTuner())
        defer { fixture.cleanUp() }
        let library = fixture.library
        let antenna = library.antenna
        let found = await library.discoverAntenna()
        #expect(antenna.findOutcome(found: found) == .found(1))
        // The search finds nothing; the known tuner is kept and its lineup read.
        fixture.tuner?.setDevices([])
        let none = await library.discoverAntenna()
        #expect(none == 0)
        #expect(antenna.findOutcome(found: none) == .found(1))
        // Kept, but its lineup isn't answering.
        fixture.tuner?.setLineup(nil, for: AntennaFixtures.device())
        let silent = await library.discoverAntenna()
        #expect(antenna.findOutcome(found: silent) == .noneAnswered)
        // Nothing known.
        let fresh = try makeLibrary(tuner: FakeTuner(devices: []))
        defer { fresh.cleanUp() }
        let nothing = await fresh.library.discoverAntenna()
        #expect(fresh.library.antenna.findOutcome(found: nothing) == .noneFound)
    }

    /// Step 9 QA 6: Settings' antenna status: the guide's line and format, and no DeviceID or address anywhere.
    @Test func antennaSettingsStatusHasNoIDOrAddress() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        var status = IPTVSettingsStatus()
        library.fillAntennaSettings(&status)
        #expect(status.antennaEnabled)
        #expect(!status.antennaSearching)
        #expect(status.antennaTuners == [.init(name: "HDHomeRun CONNECT", model: "HDHR4-2US", tunerCount: 2, channelCount: 3)])
        #expect(status.antennaChannels.map(\.id) == Self.antennaIDs)
        #expect(status.antennaChannels.map(\.displayNumber) == ["2.1", "5.1", "11.1"])
        #expect(status.antennaChannels.allSatisfy { $0.isHD && $0.signalQuality == nil && !$0.isHidden })
        #expect(status.antennaLineupLine == nil)
        let date = IPTVLibrary.settingsDate(fixture.clock.now)
        #expect(!date.contains(" at "))
        #expect(date.contains(", "))
        #expect(status.antennaGuideLine == "Updated \(date) · 12 programmes · 3 of 3 channels")

        // The lineup can't be read: the message, still no address.
        fixture.tuner?.setLineup(nil, for: AntennaFixtures.device())
        fixture.tuner?.setDevices([])
        await library.refreshAntenna()
        var failed = IPTVSettingsStatus()
        library.fillAntennaSettings(&failed)
        #expect(failed.antennaLineupLine == AntennaSource.unreachableMessage)

        for status in [status, failed] {
            var texts = [status.antennaGuideLine, status.antennaLineupLine ?? ""]
            texts += status.antennaTuners.flatMap { [$0.name, $0.model] }
            texts += status.antennaChannels.flatMap { [$0.id, $0.displayNumber, $0.name] }
            for text in texts {
                #expect(!text.contains(AntennaFixtures.deviceID))
                #expect(!text.contains(AntennaFixtures.host))
                #expect(!text.contains(AntennaFixtures.fakeDeviceAuth))
            }
        }
    }

    /// Step 10 (security N3): at the caps (16 tuners × 1,000 channels each, all kept) Settings' status is built in
    /// linear time: each tuner's entries are indexed once, not searched per channel. Measured in Debug on the dev
    /// Mac: about 9 ms indexed, about 550 ms with the old search per channel, so the bound sits between them.
    @Test func antennaSettingsStatusAtTheCapsIsFast() async throws {
        let devices = (0..<HDHomeRunDiscovery.maximumDevices).map { index in
            AntennaFixtures.device(id: String(format: "%08X", 0x1000_0000 + index), host: "10.0.1.\(index + 1)")
        }
        let perDevice = AntennaLineup.maximumChannelsPerDevice
        var lineups: [URL: String] = [:]
        for (index, device) in devices.enumerated() {
            let channels = (1...perDevice).map { ("\(index + 1).\($0)", "CH\(index + 1)-\($0)") }
            lineups[device.lineupURL] = AntennaFixtures.lineupJSON(channels, host: "10.0.1.\(index + 1)")
        }
        let fixture = try makeLibrary(tuner: FakeTuner(devices: devices, lineups: lineups))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        #expect(library.antenna.channels.count == devices.count * perDevice)

        var status = IPTVSettingsStatus()
        let clock = ContinuousClock()
        let elapsed = clock.measure { library.fillAntennaSettings(&status) }
        #expect(elapsed < .milliseconds(250))
        #expect(status.antennaTuners.count == devices.count)
        #expect(status.antennaTuners.allSatisfy { $0.channelCount == perDevice })
        #expect(status.antennaChannels.count == devices.count * perDevice)
        // Every channel still finds its own entry (HD 1 in the fixture's lineup).
        #expect(status.antennaChannels.allSatisfy { $0.isHD })
    }

    /// Pre-build QA minor 1: a lineup read that brings a channel the antenna guide lists but kept no programmes for
    /// (it wasn't in the lineup at import) imports the guide again once the hour since the last import is over. The
    /// same lineup again, or one that only drops a channel, downloads nothing.
    @Test func aNewAntennaChannelGetsTheGuideAfterTheHour() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let device = AntennaFixtures.device()
        let one = AntennaFixtures.lineupJSON([("2.1", "WSB-HD")])
        let two = AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("5.1", "WAGA-HD")])
        tuner.setLineup(one, for: device)
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.channels.map(\.id) == ["antenna:2.1"])

        fixture.clock.advance(2 * 3600)
        tuner.setLineup(two, for: device)
        await library.refreshAntenna()
        #expect(fixture.network.downloadCount == 2)
        let wsb = try antennaChannel("2.1", in: library)
        let waga = try antennaChannel("5.1", in: library)
        #expect(library.epgMatches[waga.id]?.epgID == "us10002.hdhomerun.com")
        #expect(await hasProgrammes(waga, in: library, at: fixture.clock.now))
        #expect(await hasProgrammes(wsb, in: library, at: fixture.clock.now))

        // Nothing new: no download, whatever the time.
        fixture.clock.advance(2 * 3600)
        await library.refreshAntenna()
        #expect(fixture.network.downloadCount == 2)
        tuner.setLineup(one, for: device)
        await library.refreshAntenna()
        #expect(library.channels.map(\.id) == ["antenna:2.1"])
        #expect(fixture.network.downloadCount == 2)
    }

    /// Pre-build QA minor 1: within the hour of the last import the 1 h rule holds: no download, but the guide is due
    /// when that hour ends (never later than it was), and the timer's due check then brings 5.1's programmes.
    @Test func aNewAntennaChannelWithinTheHourIsDueWhenTheHourEnds() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let device = AntennaFixtures.device()
        tuner.setLineup(AntennaFixtures.lineupJSON([("2.1", "WSB-HD")]), for: device)
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(30 * 60)
        tuner.setLineup(AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("5.1", "WAGA-HD")]), for: device)
        await library.refreshAntenna()
        let waga = try antennaChannel("5.1", in: library)
        #expect(library.epgMatches[waga.id]?.epgID == "us10002.hdhomerun.com")
        #expect(await !hasProgrammes(waga, in: library, at: fixture.clock.now))
        #expect(fixture.network.downloadCount == 1)
        let imported = try #require(library.state.guideImports[Self.antennaGuideID])
        #expect(library.state.antennaGuideDue == imported.addingTimeInterval(3601))

        // The timer before the hour's end: nothing; after it: the second download, and 5.1 has programmes.
        fixture.clock.advance(15 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(16 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 2)
        #expect(await hasProgrammes(waga, in: library, at: fixture.clock.now))
        // Due again 20–28 h after that import.
        let due = try #require(library.state.antennaGuideDue)
        #expect(due.timeIntervalSince(fixture.clock.now) >= 20 * 3600)
    }

    /// Pre-build QA minor 1: a channel scan that finds a new channel the guide lists imports the guide again (after
    /// the hour), through `antennaScanDidChange`.
    @Test func aScanThatFindsAChannelImportsTheGuideAgain() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let device = AntennaFixtures.device()
        tuner.setLineup(AntennaFixtures.lineupJSON([("2.1", "WSB-HD")]), for: device)
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON()], for: device)
        tuner.setLineupAfterScan(AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("5.1", "WAGA-HD")]), for: device)
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(2 * 3600)
        library.startAntennaScan()
        await awaitScan(library)
        #expect(library.channels.map(\.id) == ["antenna:2.1", "antenna:5.1"])
        #expect(fixture.network.downloadCount == 2)
        #expect(await hasProgrammes(try antennaChannel("5.1", in: library), in: library, at: fixture.clock.now))
    }

    /// Pre-build QA minor 2: two tuners sharing a channel number, read twice, log the notice once (the count is
    /// stored, and the notice is only made when it changes).
    @Test func sharedNumbersNoticeIsLoggedOnce() async throws {
        let first = AntennaFixtures.device()
        let second = AntennaFixtures.device(id: "5678ABCD", host: "10.0.0.10")
        let tuner = FakeTuner(devices: [first, second])   // both carry 2.1, 5.1 and 11.1
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.antenna.loggedSharedNumbers == 0)
        await library.discoverAntenna()
        #expect(library.antenna.loggedSharedNumbers == 3)
        #expect(AntennaSource.sharedNumbersNotice(3, previous: 0) != nil)
        await library.discoverAntenna()
        #expect(library.antenna.loggedSharedNumbers == 3)
        #expect(AntennaSource.sharedNumbersNotice(3, previous: library.antenna.loggedSharedNumbers) == nil)
    }

    /// L17: Remove Live TV Source wipes guide.sqlite; the antenna guide is due again.
    @Test func removingTheSourceMakesTheAntennaGuideDue() async throws {
        let fixture = try antennaGuideLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        await library.removeSource()
        #expect(library.state.antennaGuideDue == nil)    // nil: due at once, but not within an hour of the last try
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(61 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 2)
        #expect(library.epgMatches[try antennaChannel("2.1", in: library).id]?.sourceID == Self.antennaGuideID)
    }

    /// L12: Match Guide on an antenna channel offers the antenna guide's channels first and writes its id key,
    /// removing keys under its id or name.
    @Test func matchGuideOnAnAntennaChannelWritesItsIDKey() async throws {
        let fixture = try antennaGuideLibrary(guides: [IPTVFixtures.customGuideURL],
                                              overrides: ["WSB-HD": "NFL.Network.HD.us2", "NBA TV": "nbatv.us"])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        let wsb = try antennaChannel("2.1", in: library)
        // The name override points at a pasted guide's channel; the antenna guide doesn't have it.
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        #expect(library.epgMatches[wsb.id] == EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2"))
        #expect(await hasProgrammes(wsb, in: library, at: fixture.clock.now))

        let options = await library.guideMatchOptions(for: wsb)
        // The current match first (as for every channel), then the antenna guide's suggestions.
        #expect(options.candidates.first?.ref == EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2"))
        #expect(options.candidates.dropFirst().first?.sourceLabel == "HDHomeRun")
        #expect(options.candidates.dropFirst().first?.ref.epgID == "us10001.hdhomerun.com")

        let target = EPGRef(sourceID: Self.antennaGuideID, epgID: "us10002.hdhomerun.com")
        await library.setGuideMatch(.epg(target), for: wsb)
        let overrides = fixture.overridesFile.load()
        #expect(overrides["antenna:2.1"] == "us10002.hdhomerun.com")
        #expect(overrides["WSB-HD"] == nil)
        #expect(overrides["NBA TV"] == "nbatv.us")
        #expect(library.epgMatches[wsb.id] == target)
        #expect(fixture.network.downloadCount == 2)    // its programmes were kept (5.1 has them): no download

        let chosen = await library.guideMatchOptions(for: wsb)
        #expect(chosen.choice == .epg(target))

        await library.setGuideMatch(.none, for: wsb)
        #expect(fixture.overridesFile.load()["antenna:2.1"] == "")
        #expect(library.epgMatches[wsb.id] == nil)
        await library.setGuideMatch(.automatic, for: wsb)
        #expect(fixture.overridesFile.load()["antenna:2.1"] == nil)
        #expect(library.epgMatches[wsb.id] == EPGRef(sourceID: Self.antennaGuideID, epgID: "us10001.hdhomerun.com"))
    }

    /// An antenna channel whose programme on now names a picked team is in My Teams.
    @Test func antennaTeamGameShowsInMyTeams() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let start = now.addingTimeInterval(-1800)
        let game = "<programme start=\"\(IPTVFixtures.stamp(start))\" stop=\"\(IPTVFixtures.stamp(start + 7200))\" "
            + "channel=\"US10002.hdhomerun.com\"><title>NBA Basketball</title>"
            + "<sub-title>Miami Heat at Los Angeles Lakers</sub-title></programme>\n"
        let fixture = try antennaGuideLibrary(playlist: nil, guideExtra: game,
                                              preferences: ChannelPreferences(teams: ["nba.lal"]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(library.teamChannelIDs == ["antenna:5.1"])
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == ["antenna:5.1"])
    }

    /// Step 4's carry-over: Settings' Guides footer counts playlist channels with guide data against the playlist's
    /// channels, not antenna matches too.
    @Test func guideFooterCountsPlaylistChannelsOnly() async throws {
        let fixture = try antennaGuideLibrary(guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        // NFL Network (by name) and NBA TV (by id) of the playlist's 5; the 3 antenna channels match their own guide.
        #expect(library.epgMatches.count == 5)
        #expect(library.matchedChannelCount == 2)
        #expect(library.playlistChannels.count == 5)
    }

    /// Step 8 (every guide): a pasted guide with one id on two `<channel>` elements imports (the parser merges them).
    @Test func aPastedGuideWithARepeatedChannelIDImports() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let repeated = IPTVFixtures.guide(now: now).replacingOccurrences(
            of: "<channel id=\"Unrelated.us2\">",
            with: "<channel id=\"nbatv.us\"><display-name>NBA TV 2</display-name></channel>\n<channel id=\"Unrelated.us2\">")
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      files: [IPTVFixtures.customGuideURL: repeated], now: now)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        #expect(library.guideSourceInfo[customID]?.status == .loaded(now))
        let stored = try await fixture.store.channelsBySource()[customID] ?? []
        #expect(stored.filter { $0.id == "nbatv.us" }.map(\.names) == [["NBA TV", "NBA TV 2"]])
        #expect(library.epgMatches[try channel("NBA TV", in: library).id]?.epgID == "nbatv.us")
    }

    /// Security L1 / QA minor 1: a launch while the tuner doesn't answer, with a pasted guide refreshed meanwhile,
    /// keeps the antenna guide's rows and due date; the tuner back, nothing is downloaded before the due date and its
    /// channels match the kept rows.
    @Test func aMissingTunerKeepsTheAntennaGuide() async throws {
        let fixture = try antennaGuideLibrary(guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        await fixture.library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 2)
        let due = try #require(fixture.library.state.antennaGuideDue)

        // The next launch, an hour later (the fixture's programmes end 3 h after the first): the same files and guide
        // store, no tuner found.
        fixture.clock.advance(3600)
        let tuner = FakeTuner(devices: [])
        let library = IPTVLibrary(sources: fixture.sources, store: fixture.store, network: .fake(fixture.network),
                                  stateFile: fixture.stateFile, overridesFile: fixture.overridesFile,
                                  preferencesFile: fixture.preferencesFile,
                                  antenna: AntennaSource.fake(tuner, now: { fixture.clock.now }),
                                  now: { fixture.clock.now }, retrySleep: parkedRetrySleep)
        defer { library.channelRetryTask?.cancel() }
        library.antennaGuideEnabled = true
        await library.refreshAtLaunch()
        let hasAntennaChannels = library.channels.contains(where: \.isDirectStream)
        #expect(!hasAntennaChannels)
        await library.refreshGuide()    // a pasted-guide refresh prunes
        #expect(fixture.network.downloadCount == 3)
        #expect(try await fixture.store.programmeCounts()[Self.antennaGuideID] == 12)
        #expect(library.state.antennaGuideDue == due)
        #expect(library.state.guideImports[Self.antennaGuideID] != nil)

        // The tuner is back.
        tuner.setDevices([AntennaFixtures.device()])
        tuner.setLineup(AntennaFixtures.lineupJSON(AntennaFixtures.channels), for: AntennaFixtures.device())
        tuner.setDiscover(AntennaFixtures.discoverJSON())
        await library.discoverAntenna()
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 3)
        #expect(library.epgMatches[try antennaChannel("5.1", in: library).id]
                == EPGRef(sourceID: Self.antennaGuideID, epgID: "us10002.hdhomerun.com"))
        #expect(await hasProgrammes(try antennaChannel("5.1", in: library), in: library, at: fixture.clock.now))
    }

    /// Security L1: turning the guide off and on again and again downloads it once.
    @Test func guideOffAndOnDownloadsOnce() async throws {
        let fixture = try antennaGuideLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAtLaunch()
        #expect(fixture.network.downloadCount == 1)
        for _ in 0..<2 {
            await library.applyAntennaGuide(false)
            fixture.clock.advance(5 * 60)
            await library.applyAntennaGuide(true)
            fixture.clock.advance(5 * 60)
        }
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 1)
        #expect(fixture.tuner?.discoverFetchCount == 1)
        // An hour after the last try, it's due again (its rows went when it was turned off).
        fixture.clock.advance(61 * 60)
        await library.refreshIfStale()
        #expect(fixture.network.downloadCount == 2)
    }

    /// Security L3: a download over its limit is refused and its file deleted; no limit, as for pasted guides, keeps
    /// it.
    @Test func aDownloadOverItsLimitIsRefused() async throws {
        let url = URL(string: "https://guide.example/big.xml")!
        let (network, _) = IPTVNetwork.fake(files: [url: String(repeating: "x", count: 2000)])
        await #expect(throws: IPTVNetworkError.tooLarge) { try await network.download(url, maxBytes: 1000) }
        let kept = try await network.download(url, maxBytes: nil)
        defer { try? FileManager.default.removeItem(at: kept) }
        #expect(try Data(contentsOf: kept).count == 2000)
        #expect(IPTVLibrary.message(for: IPTVNetworkError.tooLarge) == "The guide file is too large")
    }

    // MARK: M7j step 9b: the channel scan (L18). The fake tuner only: no test reaches a real one.

    /// The fake tuner found (2.1, 5.1, 11.1); its `lineup_status.json` answers `statuses` in turn (the last repeats).
    private func scanLibrary(_ statuses: [String], tuner: FakeTuner = FakeTuner(),
                             playlist: URL? = nil) async throws -> LibraryFixture {
        tuner.setLineupStatusSequence(statuses)
        let fixture = try makeLibrary(playlist: playlist, tuner: tuner)
        if playlist != nil {
            await fixture.library.refreshAtLaunch()
        } else {
            await fixture.library.discoverAntenna()
        }
        return fixture
    }

    /// Waits for the scan's task, and the stop's task when the scan was stopped meanwhile.
    private func awaitScan(_ library: IPTVLibrary) async {
        var seen: Task<Void, Never>?
        while let task = library.antenna.scanTask, task != seen {
            seen = task
            await task.value
        }
    }

    private static let startPost = "http://10.0.0.9/lineup.post?scan=start&source=Antenna"
    private static let abortPost = "http://10.0.0.9/lineup.post?scan=abort"

    @Test func scanPollsUntilDoneThenRefreshesTheLineupOnce() async throws {
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(),
            AntennaFixtures.scanningLineupStatusJSON(progress: 10, found: 3),
            AntennaFixtures.scanningLineupStatusJSON(progress: 60, found: 40),
            AntennaFixtures.idleLineupStatusJSON(),
        ])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        var states: [AntennaScanState?] = []
        library.onStatusChange = { states.append(library.antenna.scan) }
        let lineupReads = tuner.lineupFetchCount
        let revision = library.guideRevision
        let started = fixture.clock.now

        library.startAntennaScan()
        #expect(library.antenna.scan == .running(progress: 0, found: 0))
        await awaitScan(library)

        #expect(tuner.posts == [Self.startPost])
        #expect(states.contains(.running(progress: 10, found: 3)))
        #expect(states.contains(.running(progress: 60, found: 40)))
        #expect(library.antenna.scan == .finished(found: 3, added: 0, removed: 0))
        #expect(states.last == .finished(found: 3, added: 0, removed: 0))
        // The lineup once, after the end; the guides rematched once (My Teams with them).
        #expect(tuner.lineupFetchCount == lineupReads + 1)
        #expect(library.guideRevision == revision + 1)
        // Off the Antenna page: every 5 s (three polls).
        #expect(fixture.clock.now.timeIntervalSince(started) == 15)
        #expect(tuner.lineupStatusFetchCount == 4)
        // A second start while none runs is a new scan; while one runs, nothing.
        library.startAntennaScan()
        library.startAntennaScan()
        await awaitScan(library)
        #expect(tuner.posts == [Self.startPost, Self.startPost])
    }

    @Test func scanCountsNewAndGoneChannels() async throws {
        let tuner = FakeTuner()
        tuner.setLineupAfterScan(AntennaFixtures.lineupJSON([("2.1", "WSB-HD"), ("5.1", "WAGA-HD"), ("7.1", "WNEW"),
                                                             ("9.1", "WNEW2")]))
        // The page's own check, then the start's read, a poll still scanning, and the end.
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(), AntennaFixtures.idleLineupStatusJSON(),
            AntennaFixtures.scanningLineupStatusJSON(progress: 50, found: 2), AntennaFixtures.idleLineupStatusJSON(),
        ], tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        try library.setFavorite(antennaChannel("5.1", in: library).id, true)
        // QA minor 4: hidden ids stay hidden, and a gone channel's id is kept (it may come back).
        library.setChannelHidden("antenna:2.1", true)
        library.setChannelHidden("antenna:11.1", true)
        await library.antennaPageVisible(true)
        let started = fixture.clock.now
        library.startAntennaScan()
        await awaitScan(library)

        #expect(library.antenna.scan == .finished(found: 4, added: 2, removed: 1))
        #expect(library.channels.filter(\.isDirectStream).map(\.id)
            == ["antenna:2.1", "antenna:5.1", "antenna:7.1", "antenna:9.1"])
        #expect(library.lineup.channels(in: "Antenna").map(\.id) == ["antenna:5.1", "antenna:7.1", "antenna:9.1"])
        // Ids are GuideNumbers: a channel that stays keeps its favorite and its hiding.
        #expect(library.preferences.favorites == ["antenna:5.1"])
        #expect(Set(library.preferences.hiddenChannels) == ["antenna:2.1", "antenna:11.1"])
        // On the Antenna page: every second (two polls).
        #expect(fixture.clock.now.timeIntervalSince(started) == 2)
    }

    @Test func stopSendsAbortAndSaysStopped() async throws {
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(), AntennaFixtures.scanningLineupStatusJSON(progress: 20, found: 10),
        ])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let lineupReads = tuner.lineupFetchCount
        // Stop Scan as soon as the row shows progress.
        library.onStatusChange = {
            if library.antenna.scan == .running(progress: 20, found: 10) { library.stopAntennaScan() }
        }
        library.startAntennaScan()
        await awaitScan(library)

        #expect(tuner.posts == [Self.startPost, Self.abortPost])
        #expect(library.antenna.scan == .stopped)
        #expect(!library.antenna.isScanning)
        // The lineup is read again (what the tuner kept), once.
        #expect(tuner.lineupFetchCount == lineupReads + 1)
        // Stop with no scan running sends nothing.
        library.stopAntennaScan()
        #expect(tuner.posts.count == 2)
    }

    @Test func scanGivesUpPollingAfter15Minutes() async throws {
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(), AntennaFixtures.scanningLineupStatusJSON(progress: 50, found: 5),
        ])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let lineupReads = tuner.lineupFetchCount
        let started = fixture.clock.now
        library.startAntennaScan()
        await awaitScan(library)

        #expect(fixture.clock.now.timeIntervalSince(started) == AntennaSource.scanTimeLimit)
        // The start's read, then one every 5 s for 15 minutes.
        #expect(tuner.lineupStatusFetchCount == 1 + 180)
        #expect(tuner.posts == [Self.startPost])
        #expect(tuner.lineupFetchCount == lineupReads + 1)
        #expect(library.antenna.scan == .finished(found: 3, added: 0, removed: 0))
    }

    @Test func scanStartedElsewhereShowsAsRunning() async throws {
        let fixture = try await scanLibrary([AntennaFixtures.scanningLineupStatusJSON(progress: 30, found: 7)])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        await library.antennaPageVisible(true)
        #expect(library.antenna.scan == .running(progress: 30, found: 7))
        // A scanning tuner says nothing about the next scan: once it ends, the row isn't "can't scan".
        #expect(library.antenna.scanPossible.isEmpty)
        #expect(library.antenna.canScan)
        var status = IPTVSettingsStatus()
        library.fillAntennaSettings(&status)
        #expect(status.antennaIsScanning)
        // MMTVL didn't start it, and doesn't start another; Stop Scan stops it.
        library.startAntennaScan()
        #expect(tuner.posts.isEmpty)
        library.stopAntennaScan()
        await awaitScan(library)
        #expect(tuner.posts == [Self.abortPost])
        #expect(library.antenna.scan == .stopped)

        // Opening the page again (QA major): the last line stays, and an idle tuner shows nothing running.
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON()])
        await library.antennaPageVisible(true)
        #expect(library.antenna.scan == .stopped)
        #expect(library.antenna.canScan)
    }

    @Test func scanSkipsDevicesThatCantScan() async throws {
        let first = AntennaFixtures.device()
        let second = AntennaFixtures.device(id: "5678ABCD", host: "10.0.0.10")
        let tuner = FakeTuner(devices: [first, second])
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON()], for: first)
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(scanPossible: false)], for: second)
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        library.startAntennaScan()
        // Step 10 (security N1): until the tuners' statuses are read, any of them may be started, so all count.
        #expect(library.antenna.isScanning(deviceID: first.id))
        #expect(library.antenna.isScanning(deviceID: second.id))
        await awaitScan(library)
        #expect(!library.antenna.isScanning(deviceID: first.id))
        #expect(tuner.posts == [Self.startPost])
        #expect(library.antenna.scanPossible == ["1234ABCD": true, "5678ABCD": false])
        #expect(library.antenna.canScan)

        // No tuner can: nothing is sent and Settings dims the row. An odd current source counts as can't.
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(scanPossible: false)], for: first)
        tuner.setLineupStatusSequence([#"{"ScanInProgress":0,"ScanPossible":1,"Source":"Antenna&scan=abort","SourceList":["Antenna&scan=abort"]}"#],
                                      for: second)
        library.startAntennaScan()
        await awaitScan(library)
        #expect(tuner.posts == [Self.startPost])
        #expect(library.antenna.scan == nil)
        #expect(!library.antenna.canScan)
        var status = IPTVSettingsStatus()
        library.fillAntennaSettings(&status)
        #expect(!status.antennaCanScan)
        #expect(status.antennaScan == nil)

        // A refused start: failed, with nothing to stop.
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON()], for: first)
        tuner.setPostStatus(403)
        library.startAntennaScan()
        await awaitScan(library)
        #expect(library.antenna.scan == .failed)
        #expect(tuner.posts.count == 2)
    }

    /// The home preview on an antenna channel stops before the scan's POST; a playlist channel's preview doesn't stop.
    @Test func scanStopsMMTVLsOwnAntennaStreams() async throws {
        let fixture = try await scanLibrary([AntennaFixtures.idleLineupStatusJSON()], playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: library)
        // As AppDelegate wires it.
        var postsWhenStopped: Int?
        library.stopAntennaStreams = { [weak model] in
            postsWhenStopped = tuner.posts.count
            model?.stopAntennaStreams()
        }

        model.startPreview(channelID: "id:nbatv.us")
        model.stopAntennaStreams()
        #expect(model.previewChannelID == "id:nbatv.us")
        #expect(player.stops == 0)

        model.startPreview(channelID: "antenna:5.1")
        player.state.phase = .playing
        let stops = player.stops
        library.startAntennaScan()
        #expect(model.previewChannelID == nil)
        #expect(player.stops == stops + 1)
        #expect(postsWhenStopped == 0)
        await awaitScan(library)
        #expect(tuner.posts == [Self.startPost])
    }

    // MARK: Step 9b review fixes

    /// Security M1: two devices reporting Found = Int.max don't trap when the page opens or on a poll.
    @Test func hugeFoundFromTwoDevicesDoesntTrap() async throws {
        let first = AntennaFixtures.device()
        let second = AntennaFixtures.device(id: "5678ABCD", host: "10.0.0.10")
        let tuner = FakeTuner(devices: [first, second])
        for device in [first, second] {
            tuner.setLineupStatusSequence([AntennaFixtures.scanningLineupStatusJSON(progress: 10, found: Int.max),
                                           AntennaFixtures.scanningLineupStatusJSON(progress: 20, found: Int.max)],
                                          for: device)
        }
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        var states: [AntennaScanState?] = []
        library.onStatusChange = {
            states.append(library.antenna.scan)
            if library.antenna.scan == .running(progress: 20, found: 200_000) { library.stopAntennaScan() }
        }
        await library.antennaPageVisible(true)
        #expect(library.antenna.scan == .running(progress: 10, found: 200_000))
        await awaitScan(library)
        #expect(states.contains(.running(progress: 20, found: 200_000)))
        #expect(library.antenna.scan == .stopped)
    }

    /// QA major: a scan that ended while the page wasn't on screen keeps its line when the page opens again (the
    /// tuners are still asked); a scan started elsewhere then replaces it.
    @Test func finishedLineStaysWhenThePageOpensAgain() async throws {
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(), AntennaFixtures.scanningLineupStatusJSON(progress: 50, found: 2),
            AntennaFixtures.idleLineupStatusJSON(),
        ])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        library.startAntennaScan()
        await awaitScan(library)
        #expect(library.antenna.scan == .finished(found: 3, added: 0, removed: 0))
        let reads = tuner.lineupStatusFetchCount
        await library.antennaPageVisible(true)
        await library.antennaPageVisible(false)
        await library.antennaPageVisible(true)
        #expect(library.antenna.scan == .finished(found: 3, added: 0, removed: 0))
        #expect(tuner.lineupStatusFetchCount == reads + 2)
        var status = IPTVSettingsStatus()
        library.fillAntennaSettings(&status)
        #expect(status.antennaScan == .finished(found: 3, added: 0, removed: 0))

        tuner.setLineupStatusSequence([AntennaFixtures.scanningLineupStatusJSON(progress: 5, found: 1)])
        await library.antennaPageVisible(false)
        await library.antennaPageVisible(true)
        #expect(library.antenna.scan == .running(progress: 5, found: 1))
        library.stopAntennaScan()
        await awaitScan(library)
        // Turning the antenna off forgets it.
        library.antenna.isEnabled = false
        #expect(library.antenna.scan == nil)
    }

    /// QA minors 2 and 4: two tuners scanning show the lowest progress and the sum found; one that finishes isn't
    /// aborted by Stop, and its Found still counts.
    @Test func stopAbortsOnlyTunersStillScanning() async throws {
        let first = AntennaFixtures.device()
        let second = AntennaFixtures.device(id: "5678ABCD", host: "10.0.0.10")
        let tuner = FakeTuner(devices: [first, second])
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 40, found: 10),
                                       AntennaFixtures.idleLineupStatusJSON()], for: first)
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 20, found: 5),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 30, found: 6)], for: second)
        let fixture = try makeLibrary(tuner: tuner)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        var states: [AntennaScanState?] = []
        library.onStatusChange = {
            states.append(library.antenna.scan)
            if library.antenna.scan == .running(progress: 30, found: 16) { library.stopAntennaScan() }
        }
        library.startAntennaScan()
        await awaitScan(library)
        #expect(states.contains(.running(progress: 20, found: 15)))
        #expect(states.contains(.running(progress: 30, found: 16)))
        #expect(tuner.posts == ["http://10.0.0.9/lineup.post?scan=start&source=Antenna",
                                "http://10.0.0.10/lineup.post?scan=start&source=Antenna",
                                "http://10.0.0.10/lineup.post?scan=abort"])
        #expect(library.antenna.scan == .stopped)
    }

    /// QA minor 4: the antenna turned off mid-scan stops the polling and posts nothing more.
    @Test func antennaOffMidScanStopsPolling() async throws {
        let fixture = try await scanLibrary([
            AntennaFixtures.idleLineupStatusJSON(), AntennaFixtures.scanningLineupStatusJSON(progress: 20, found: 10),
        ])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let tuner = try #require(fixture.tuner)
        library.onStatusChange = {
            if library.antenna.scan == .running(progress: 20, found: 10) { library.antenna.isEnabled = false }
        }
        library.startAntennaScan()
        await awaitScan(library)
        let reads = tuner.lineupStatusFetchCount
        #expect(reads == 2)
        // Any poll still waiting ends without reading.
        for _ in 0..<10 { await Task.yield() }
        #expect(tuner.lineupStatusFetchCount == reads)
        #expect(tuner.posts == [Self.startPost])
        #expect(library.antenna.scan == nil)
        #expect(!library.antenna.isScanning)
    }

    /// Security L1: a Stop while the start POST is in flight sends the abort only after the start has gone out.
    @Test func stopWaitsForTheStartPostBeforeTheAbort() async throws {
        nonisolated final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var _order: [String] = []
            private var _startEntered = false
            private var _released = false
            var order: [String] { lock.withLock { _order } }
            var startEntered: Bool { lock.withLock { _startEntered } }
            func release() { lock.withLock { _released = true } }
            func post(_ url: URL) async -> Int? {
                if url.query()?.hasPrefix("scan=start") == true {
                    lock.withLock { _startEntered = true }
                    while !lock.withLock({ _released }) { try? await Task.sleep(for: .milliseconds(5)) }
                    lock.withLock { _order.append("start") }
                } else {
                    lock.withLock { _order.append("abort") }
                }
                return 200
            }
        }
        let gate = Gate()
        let tuner = FakeTuner()
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 1, found: 0)])
        let clock = TestClock(Date(timeIntervalSince1970: 1_791_200_000))
        let antenna = AntennaSource.fake(tuner, now: { clock.now }, sleep: { clock.advance(TimeInterval($0.components.seconds)) },
                                         scanClock: { clock.instant }, post: { url, _ in await gate.post(url) })
        let fixture = try makeLibrary(antenna: antenna)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        library.startAntennaScan()
        while !gate.startEntered { try await Task.sleep(for: .milliseconds(5)) }
        library.stopAntennaScan()
        // The stop's task runs, and waits.
        try await Task.sleep(for: .milliseconds(50))
        #expect(gate.order.isEmpty)
        gate.release()
        await awaitScan(library)
        #expect(gate.order == ["start", "abort"])
        #expect(library.antenna.scan == .stopped)
    }

    /// QA minor 3: the page opening mid-scan polls at once, then every second.
    @Test func pageOpeningMidScanPollsAtOnce() async throws {
        nonisolated final class Waits: @unchecked Sendable {
            private let lock = NSLock()
            private var _durations: [Duration] = []
            var durations: [Duration] { lock.withLock { _durations } }
            func add(_ duration: Duration) { lock.withLock { _durations.append(duration) } }
        }
        let waits = Waits()
        let tuner = FakeTuner()
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 1, found: 0)])
        // Each wait lasts an hour unless it's cut short.
        let antenna = AntennaSource.fake(tuner, sleep: { duration in
            waits.add(duration)
            try? await Task.sleep(for: .seconds(3600))
        })
        let fixture = try makeLibrary(antenna: antenna)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        library.startAntennaScan()
        while waits.durations.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(waits.durations == [.seconds(5)])
        #expect(tuner.lineupStatusFetchCount == 1)
        await library.antennaPageVisible(true)
        while waits.durations.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(tuner.lineupStatusFetchCount == 2)
        #expect(waits.durations == [.seconds(5), .seconds(1)])
        library.stopAntennaScan()
        await awaitScan(library)
    }

    /// Security L4: the 15 minutes are elapsed time, not the wall clock (here an hour per poll).
    @Test func scanLimitIgnoresTheWallClock() async throws {
        let tuner = FakeTuner()
        tuner.setLineupStatusSequence([AntennaFixtures.idleLineupStatusJSON(),
                                       AntennaFixtures.scanningLineupStatusJSON(progress: 1, found: 0)])
        let clock = TestClock(Date(timeIntervalSince1970: 1_791_200_000))
        let antenna = AntennaSource.fake(tuner, now: { clock.now }, sleep: { duration in
            clock.now = clock.now.addingTimeInterval(3600)
            clock.instant = clock.instant.advanced(by: duration)
        }, scanClock: { clock.instant })
        let fixture = try makeLibrary(antenna: antenna)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.discoverAntenna()
        library.startAntennaScan()
        await awaitScan(library)
        #expect(tuner.lineupStatusFetchCount == 1 + 180)
        #expect(library.antenna.scan == .finished(found: 3, added: 0, removed: 0))
    }
}
