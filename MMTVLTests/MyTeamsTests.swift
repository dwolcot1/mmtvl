import Foundation
import Testing
@testable import MMTVL

/// M7l 8c: My Teams: always in the guide, Choose Teams as its first row, then the live games, then the upcoming ones.
struct MyTeamsTests {
    private static let now = Date(timeIntervalSince1970: 1_791_200_000)
    private static let nfl = "id:nflnetwork.us"
    private static let nba = "id:nbatv.us"
    private static let redZone = "name:red zone"

    private static func channel(_ name: String, group: String = "Live") -> Channel {
        Channel(id: "name:\(name.lowercased())", number: 1, name: name, group: group, tvgID: nil, tvgName: nil,
                logoURL: nil, streamURL: URL(string: "https://cdn.example/\(name.count).m3u8")!)
    }

    private static func programme(hours: Double, _ title: String, _ subtitle: String? = nil,
                                  summary: String? = nil) -> Programme {
        let start = now + hours * 3600
        return Programme(channelID: "x", start: start, stop: start + 3 * 3600, title: title, subtitle: subtitle,
                         summary: summary)
    }

    // MARK: TeamMatcher.upcomingGames

    /// The security review for build 34 (L3): a cancelled matching stops at once and gives nothing, not part.
    @Test func aCancelledMatchingOfUpcomingGamesStopsEarly() async {
        let espn = Self.channel("ESPN")
        let programmes = (0..<5_000).map { n in
            Self.programme(hours: Double(n) / 100 + 1, "NBA Basketball", "Los Angeles Lakers at Team \(n)")
        }
        var checks = 0
        let stopped = TeamMatcher.finishedUpcomingGames(channels: [espn], programmes: [espn.id: programmes],
                                                        picked: ["nba.lal"], now: Self.now,
                                                        isCancelled: { checks += 1; return checks > 3 })
        #expect(stopped == nil)
        #expect(checks == 4)
        // Not cancelled: every programme is looked at.
        checks = 0
        let all = TeamMatcher.finishedUpcomingGames(channels: [espn], programmes: [espn.id: programmes],
                                                    picked: ["nba.lal"], now: Self.now,
                                                    isCancelled: { checks += 1; return false })
        #expect(all?.count == programmes.count)
        #expect(checks == programmes.count)
        // A cancelled task: nothing, and `upcomingGames` gives an empty list rather than part of one.
        let now = Self.now
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return (TeamMatcher.finishedUpcomingGames(channels: [espn], programmes: [espn.id: programmes],
                                                      picked: ["nba.lal"], now: now),
                    TeamMatcher.upcomingGames(channels: [espn], programmes: [espn.id: programmes],
                                              picked: ["nba.lal"], now: now))
        }
        let (finished, partial) = await task.value
        #expect(finished == nil)
        #expect(partial.isEmpty)
    }

    @Test func upcomingGamesAreTheNext72HoursSoonestFirst() {
        let espn = Self.channel("ESPN")
        let fox = Self.channel("FOX")
        let game = Self.channel("Miami Heat @ Los Angeles Lakers", group: "NBA")
        let lakersCeltics = Self.programme(hours: 5, "NBA Basketball", "Los Angeles Lakers at Boston Celtics")
        let programmes: [Channel.ID: [Programme]] = [
            espn.id: [
                Self.programme(hours: -1, "NBA Basketball", "Miami Heat at Los Angeles Lakers"),   // on now: live, not upcoming
                lakersCeltics,
                Self.programme(hours: 8, "Lakers Postgame", "Los Angeles Lakers"),                // postgame
                Self.programme(hours: 30, "NBA Basketball", "Boston Celtics at New York Knicks"),  // not picked
                Self.programme(hours: 73, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets"),  // past 72 h
            ],
            fox.id: [
                Self.programme(hours: 2, "NBA Replay", "Los Angeles Lakers at Utah Jazz"),        // replay
                lakersCeltics,                                                                     // the same game: its own row
                Self.programme(hours: 48, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers"),
            ],
            game.id: [Self.programme(hours: 1, "NBA Basketball", "Miami Heat at Los Angeles Lakers")],  // a game entry
        ]
        let games = TeamMatcher.upcomingGames(channels: [espn, fox, game], programmes: programmes, picked: ["nba.lal"],
                                              now: Self.now)
        #expect(games.map(\.channel.name) == ["ESPN", "FOX", "FOX"])
        #expect(games.map(\.label) == ["Los Angeles Lakers at Boston Celtics", "Los Angeles Lakers at Boston Celtics",
                                       "Golden State Warriors at Los Angeles Lakers"])
        #expect(games.allSatisfy { $0.programme.start > Self.now && $0.programme.start < Self.now + 72 * 3600 })
        #expect(TeamMatcher.upcomingGames(channels: [espn, fox], programmes: programmes, picked: [], now: Self.now).isEmpty)
    }

    /// M7m L25: subtitle-less college games share a title; the summary keeps their matches apart.
    @Test func upcomingGamesDontShareAMatchAcrossSummaries() {
        let espn = Self.channel("ESPN")
        let espn2 = Self.channel("ESPN2")
        let other = Self.programme(hours: 1, "College Basketball",
                                   summary: "The No. 6 Michigan State Spartans face the No. 2 Duke Blue Devils for an NCAA game.")
        let gators = Self.programme(hours: 2, "College Basketball",
                                    summary: "The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA game.")
        let programmes: [Channel.ID: [Programme]] = [espn.id: [other], espn2.id: [gators]]
        let games = TeamMatcher.upcomingGames(channels: [espn, espn2], programmes: programmes,
                                              picked: ["ncaam.florida-gators"], now: Self.now)
        #expect(games.map(\.channel.name) == ["ESPN2"])
        // And the other way round: the first answer isn't reused for the second.
        let first = TeamMatcher.upcomingGames(channels: [espn2, espn], programmes: programmes,
                                              picked: ["ncaam.duke-blue-devils"], now: Self.now)
        #expect(first.map(\.channel.name) == ["ESPN"])
    }

    @Test func aGameWithoutSubtitleIsLabelledByItsTitle() {
        let game = UpcomingTeamGame(channel: Self.channel("ESPN"), programme: Self.programme(hours: 1, "Lakers vs. Celtics"))
        #expect(game.label == "Lakers vs. Celtics")
        #expect(!game.dayTime.isEmpty)
    }

    // MARK: Names

    @Test func theListIsCalledMyTeams() {
        #expect(ChannelLineup.teamsGroup == "My Teams")
        #expect(TeamPicker.pickedValue == "In My Teams")   // the picker's and search's team values
        #expect(LiveSearchView.teamHint(isPicked: false) == "Select: add to My Teams · Left: keyboard")
        #expect(LiveSearchView.teamHint(isPicked: true) == "Select: remove from My Teams · Left: keyboard")
        #expect(TeamPicker.title == "Choose Teams")
    }

    // MARK: Lineup

    @Test func myTeamsIsAlwaysAfterFavoritesAndUpcomingRowsStayOutOfFavorites() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(IPTVFixtures.playlist))
        let none = ChannelLineup(channels: channels)
        #expect(none.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(none.channels(in: "My Teams").isEmpty)
        let nfl = try #require(channels.first { $0.id == Self.nfl })
        let upcoming = [UpcomingTeamGame(channel: nfl, programme: Self.programme(hours: 3, "NFL Football", "A at B"))]
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: [Self.redZone]),
                                   teamChannelIDs: [Self.nba], upcomingTeamGames: upcoming)
        #expect(Array(lineup.groups.prefix(3)) == ["Favorites", "My Teams", "All Channels"])
        // Favorites and zapping (`channels(in:)`) take only the live games.
        #expect(lineup.channels(in: "Favorites").map(\.id) == [Self.nba, Self.redZone])
        #expect(lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
        #expect(lineup.upcomingTeamGames == upcoming)
        // A hidden channel's upcoming game doesn't show; the cap holds.
        let hidden = ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: [Self.nfl]),
                                   upcomingTeamGames: upcoming)
        #expect(hidden.upcomingTeamGames.isEmpty)
        let many = Array(repeating: upcoming[0], count: 40)
        #expect(ChannelLineup(channels: channels, upcomingTeamGames: many).upcomingTeamGames.count
                == ChannelLineup.maxUpcomingTeamGames)
        // No visible channel: no groups at all.
        #expect(ChannelLineup(channels: []).groups.isEmpty)
    }

    // MARK: Library and Live TV

    /// NBA TV: the Lakers on now, then at +2 h; NFL Network: a Lakers replay at +1 h, a Lakers game at +5 h and a
    /// Knicks game at +1 h; the Lakers again on NBA TV past 72 h.
    private static func guide() -> String {
        func entry(_ channel: String, hours: Double, _ title: String, _ subtitle: String) -> String {
            let start = now + hours * 3600
            return "<programme start=\"\(IPTVFixtures.stamp(start))\" stop=\"\(IPTVFixtures.stamp(start + 3600))\" "
                + "channel=\"\(channel)\"><title>\(title)</title><sub-title>\(subtitle)</sub-title></programme>\n"
        }
        return """
        <?xml version="1.0"?>
        <tv>
        <channel id="NFL.Network.HD.us2"><display-name>NFL Network HD</display-name></channel>
        <channel id="nbatv.us"><display-name>NBA TV</display-name></channel>
        """
            + entry("nbatv.us", hours: -0.5, "NBA Basketball", "Miami Heat at Los Angeles Lakers")
            + entry("nbatv.us", hours: 2, "NBA Basketball", "Los Angeles Lakers at Boston Celtics")
            + entry("nbatv.us", hours: 80, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets")
            + entry("NFL.Network.HD.us2", hours: 1, "NBA Replay", "Los Angeles Lakers at Utah Jazz")
            + entry("NFL.Network.HD.us2", hours: 1.5, "NBA Basketball", "Boston Celtics at New York Knicks")
            + entry("NFL.Network.HD.us2", hours: 5, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers")
            + "</tv>\n"
    }

    private func makeFixture(preferences: ChannelPreferences? = nil, state: IPTVState? = nil) async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      files: [IPTVFixtures.customGuideURL: Self.guide()], state: state,
                                      preferences: preferences, now: Self.now)
        await fixture.library.refreshAll()
        return fixture
    }

    @Test func pickingATeamListsItsUpcomingGames() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(favorites: [Self.redZone]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.lineup.upcomingTeamGames.isEmpty)
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
        #expect(library.lineup.upcomingTeamGames.map(\.channel.id) == [Self.nba, Self.nfl])
        #expect(library.lineup.upcomingTeamGames.map(\.label)
                == ["Los Angeles Lakers at Boston Celtics", "Golden State Warriors at Los Angeles Lakers"])
        // Favorites: the live game, then the saved favorites; never the upcoming games. The saved list is unchanged.
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.nba, Self.redZone])
        #expect(fixture.preferencesFile.load().favorites == [Self.redZone])
        // Unpicked: no upcoming games, My Teams stays.
        library.setTeamPicked("nba.lal", false)
        await library.teamUpdateTask?.value
        #expect(library.lineup.upcomingTeamGames.isEmpty)
        #expect(library.lineup.groups.contains("My Teams"))
    }

    /// QA (8c): an update cancelled during its store read (the read gives nothing) keeps the network channels and
    /// upcoming games it had; game entries need no read.
    @Test func anUpdateCancelledDuringItsReadKeepsTheNetworkAndUpcomingGames() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let live = library.lineup.channels(in: "My Teams").map(\.id)
        let upcoming = library.lineup.upcomingTeamGames
        #expect(live == [Self.nba])
        #expect(upcoming.count == 2)

        let gate = SlowFetchGate()
        library.beforeTeamProgrammesFetch = { await gate.wait() }
        let update = Task { await library.updateTeams() }
        for _ in 0..<1000 where !gate.isWaiting { await Task.yield() }
        #expect(gate.isWaiting)
        update.cancel()
        gate.release()
        await update.value
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == live)
        #expect(library.lineup.upcomingTeamGames == upcoming)
    }

    @Test func selectOnAnUpcomingGameTunesItsChannel() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]),
                                            state: IPTVState(lastChannelID: Self.redZone))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: library, now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        player.state.phase = .playing
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
        #expect(model.mode == .guide)
        // Groups → My Teams.
        _ = model.handle(.left)
        _ = model.handle(.left)
        for _ in 0..<20 where model.guide?.focus != .groups(0) { _ = model.handle(.up) }
        #expect(model.guide?.groups.prefix(2) == ["Favorites", "My Teams"])
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.rows.map(\.kind) == [.chooseTeams, .channel, .upcoming, .upcoming])
        // Menu on Choose Teams does nothing; the last row is NFL Network's game.
        _ = model.handle(.menu)
        #expect(model.menu == nil)
        for _ in 0..<3 { _ = model.handle(.down) }
        #expect(model.guide?.focusedChannel?.id == Self.nfl)
        _ = model.handle(.menu)
        #expect(model.menu == nil)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(model.currentChannel?.id == Self.nfl)
        #expect(player.played.last == IPTVFixtures.streamURL(1))
        // Zapping in My Teams steps through the live games only: NFL Network isn't one, so its own group.
        #expect(library.state.lastGroup == "My Teams")
        _ = model.handle(.down)
        #expect(model.currentChannel?.id == Self.nba)
    }

    // MARK: Matching options (M7m L29, L31)

    /// NBA TV's programme on now is a college game: `title`, with `subtitle` and `summary`.
    private static func collegeGuide(_ title: String, subtitle: String? = nil, summary: String? = nil) -> String {
        let start = now - 1800
        let subtitleTag = subtitle.map { "<sub-title>\($0)</sub-title>" } ?? ""
        let summaryTag = summary.map { "<desc>\($0)</desc>" } ?? ""
        return """
        <?xml version="1.0"?>
        <tv>
        <channel id="nbatv.us"><display-name>NBA TV</display-name></channel>
        <programme start="\(IPTVFixtures.stamp(start))" stop="\(IPTVFixtures.stamp(start + 3 * 3600))" \
        channel="nbatv.us"><title>\(title)</title>\(subtitleTag)\(summaryTag)</programme>
        </tv>

        """
    }

    private func makeCollegeFixture(_ guide: String, teams: [Team.ID], options: TeamMatchOptions = .off) async throws
        -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      files: [IPTVFixtures.customGuideURL: guide],
                                      state: IPTVState(lastChannelID: Self.nba),
                                      preferences: ChannelPreferences(teams: teams), now: Self.now)
        fixture.library.teamMatchOptions = options
        await fixture.library.refreshAll()
        await fixture.library.updateTeams()
        return fixture
    }

    /// The channel menu's team items for the playing channel (NBA TV), once the banner has its programme.
    private func menuTeamTitles(_ fixture: LibraryFixture) async -> [String] {
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        for _ in 0..<1000 where model.banner?.now == nil { await Task.yield() }
        #expect(model.banner?.now != nil)
        _ = model.handle(.menu)
        return (model.menu?.items ?? []).filter { $0.id.hasPrefix("team.") }.map(\.title)
    }

    private static func pickTitle(_ id: Team.ID) -> String { TeamCatalog.byID[id]?.pickTitle ?? id }
    private static func add(_ id: Team.ID) -> String { "Add \(pickTitle(id)) to My Teams" }
    private static func remove(_ id: Team.ID) -> String { "Remove \(pickTitle(id)) from My Teams" }

    /// L31: a nickname-only side offers its teams (Big 12: Houston and BYU), the picked one first, and the other
    /// side's team is still offered.
    @Test func theChannelMenuOffersEachSidesTeamsPickedFirst() async throws {
        let guide = Self.collegeGuide("College Basketball", summary: "The Cougars meet the Bearcats in Big 12 play.")
        let fixture = try await makeCollegeFixture(guide, teams: ["ncaam.houston-cougars"],
                                                   options: TeamMatchOptions(nicknames: true))
        defer { fixture.cleanUp() }
        // BYU comes before Houston in the catalog; the picked Houston leads its side.
        let titles = await menuTeamTitles(fixture)
        #expect(titles == [Self.remove("ncaam.houston-cougars"), Self.add("ncaam.byu-cougars"),
                           Self.add("ncaam.cincinnati-bearcats")])
        #expect(fixture.library.lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
    }

    /// L31: without a conference every Cougars team is a candidate; the menu offers 3 of them, the picked one first,
    /// then catalog order, and both Bearcats.
    @Test func theChannelMenuOffersAtMostThreeTeamsASide() async throws {
        let guide = Self.collegeGuide("College Basketball", summary: "The Cougars meet the Bearcats.")
        let fixture = try await makeCollegeFixture(guide, teams: ["ncaam.washington-state-cougars"],
                                                   options: TeamMatchOptions(nicknames: true))
        defer { fixture.cleanUp() }
        let titles = await menuTeamTitles(fixture)
        #expect(LiveTVModel.menuTeamsPerSide == 3)
        #expect(titles == [Self.remove("ncaam.washington-state-cougars"), Self.add("ncaam.byu-cougars"),
                           Self.add("ncaam.houston-cougars"),
                           Self.add("ncaam.binghamton-bearcats"), Self.add("ncaam.cincinnati-bearcats")])
    }

    /// L29: with Match Nicknames Alone off, a nickname-only programme offers no team and isn't in My Teams.
    @Test func theChannelMenuOffersNoNicknameTeamsWithTheOptionOff() async throws {
        let guide = Self.collegeGuide("College Basketball", summary: "The Cougars meet the Bearcats in Big 12 play.")
        let fixture = try await makeCollegeFixture(guide, teams: ["ncaam.houston-cougars"])
        defer { fixture.cleanUp() }
        #expect(await menuTeamTitles(fixture).isEmpty)
        #expect(fixture.library.lineup.channels(in: "My Teams").isEmpty)
    }

    /// L29: changing an option recomputes My Teams, and the channel menu follows it.
    @Test func changingMatchInitialsRecomputesMyTeamsAndTheMenu() async throws {
        let guide = Self.collegeGuide("College Football", subtitle: "ULM Warhawks at Troy Trojans")
        let fixture = try await makeCollegeFixture(guide, teams: ["ncaaf.ul-monroe-warhawks"])
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.teamMatchOptions == .off)
        #expect(library.lineup.channels(in: "My Teams").isEmpty)
        // Off: only Troy, named in full.
        #expect(await menuTeamTitles(fixture) == [Self.add("ncaaf.troy-trojans")])

        await library.applyTeamMatchOptions(TeamMatchOptions(initials: true))
        #expect(library.teamMatchIndex.options == TeamMatchOptions(initials: true))
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
        #expect(await menuTeamTitles(fixture)
                == [Self.remove("ncaaf.ul-monroe-warhawks"), Self.add("ncaaf.troy-trojans")])

        // Back off: gone again.
        await library.applyTeamMatchOptions(.off)
        #expect(library.lineup.channels(in: "My Teams").isEmpty)
        #expect(await menuTeamTitles(fixture) == [Self.add("ncaaf.troy-trojans")])
    }

    /// A `lastGroup` of "Teams" (before 8c) opens My Teams and zaps through its live games.
    @Test func aRememberedTeamsGroupOpensMyTeams() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]),
                                            state: IPTVState(lastChannelID: Self.nba, lastGroup: "Teams"))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.focusedChannel?.id == Self.nba)
    }
}
