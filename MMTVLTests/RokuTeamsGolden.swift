import Foundation
@testable import MMTVL

/// M12 step 17: `roku/tests/fixtures/teams.golden.json`, the TeamMatcher parity contract (`RokuParityTests`
/// `teamsMatchTheGolden`). The cases are TeamMatcherTests' (42) and MyTeamsTests' (14) as data: each names its test,
/// an operation (`op`), its inputs, and `expected`, which MMTVL's own `TeamMatcher` gives for them (never written by
/// hand). The Roku's `roku/tests/local/TeamMatcher.test.bs` runs `TeamMatcher.bs` over the same cases.
///
/// - `indexes`: name → the teams an index is built from (`sets`: "pro" is `TeamCatalog.proTeams`, the Roku's
///   `pkg:/data/pro-teams.json`; "college" the bundled `college-teams.json`; any other name a `teamSets` entry) and
///   its `TeamMatchOptions`. "bundled.<off|initials|nicknames|both>" are `TeamMatcher.Index.bundled(options)`.
/// - `teamSets`: the tests' own college teams, in `college-teams.json`'s shape.
/// - `channelSets`: channels as `ChannelList.make` gives them (id, the name as shown, group); `m3u` is the playlist
///   they come from (the Roku checks `M3U.bs` gives the same ones), absent for channels a test builds directly.
/// - Texts (names, titles, summaries) are a string, or `[[piece, count], …]` for the huge ones: each piece repeated
///   `count` times, joined.
/// - Programmes: Unix seconds; `subtitle`, `category` and `summary` absent when nil.
/// - `coverage`: every test of the two suites, "full", "matcher" (only its matcher part can be data; the rest is
///   step 18's lineup, menu or library) or "no", with why.
nonisolated struct TeamsGolden: Codable, Equatable {
    var indexes: [String: TeamIndexGolden]
    var teamSets: [String: [TeamEntryGolden]]
    var channelSets: [String: TeamChannelSetGolden]
    var coverage: [TeamCoverageGolden]
    var cases: [TeamCaseGolden]
}

nonisolated struct TeamIndexGolden: Codable, Equatable {
    var sets: [String]
    var initials: Bool
    var nicknames: Bool
}

/// One team, as `college-teams.json` holds it (`school` and `conference` null for a pro team).
nonisolated struct TeamEntryGolden: Codable, Equatable {
    var id: String
    var league: String
    var name: String
    var school: String?
    var nickname: String
    var conference: String?
    var aliases: [String]
    var abbreviations: [String]

    init(_ team: Team) {
        id = team.id
        league = team.league.rawValue
        name = team.name
        school = team.school
        nickname = team.nickname
        conference = team.conference
        aliases = team.aliases
        abbreviations = team.abbreviations
    }

    var team: Team? {
        guard let league = TeamLeague(rawValue: league) else { return nil }
        if league.isCollege {
            return Team(id: id, league: league, name: name, school: school ?? name, nickname: nickname,
                        conference: conference ?? "", aliases: aliases, abbreviations: abbreviations)
        }
        return Team(String(id.dropFirst(league.rawValue.count + 1)), league, name, nickname, aliases: aliases)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(league, forKey: .league)
        try container.encode(name, forKey: .name)
        try container.encode(school, forKey: .school)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(conference, forKey: .conference)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(abbreviations, forKey: .abbreviations)
    }
}

nonisolated struct TeamChannelSetGolden: Codable, Equatable {
    var m3u: String?
    var channels: [TeamChannelGolden]
}

nonisolated struct TeamChannelGolden: Codable, Equatable {
    var id: String
    var name: GoldenText
    var group: String
}

nonisolated struct TeamProgrammeGolden: Codable, Equatable {
    var title: GoldenText
    var subtitle: GoldenText?
    var category: GoldenText?
    var summary: GoldenText?
    /// Unix seconds.
    var start: Int
    var stop: Int

    var programme: Programme {
        Programme(channelID: "x", start: Date(timeIntervalSince1970: TimeInterval(start)),
                  stop: Date(timeIntervalSince1970: TimeInterval(stop)), title: title.string,
                  subtitle: subtitle?.string, summary: summary?.string, category: category?.string)
    }
}

nonisolated struct TeamCoverageGolden: Codable, Equatable {
    /// "<Suite>.<test>".
    var test: String
    /// "full", "matcher" or "no".
    var carried: String
    var note: String
}

/// One operation of `TeamMatcher` (see `RokuTeamsGolden.evaluate` for each `op`), its inputs, and its result.
nonisolated struct TeamCaseGolden: Codable, Equatable {
    var test: String
    var op: String
    var index: String?
    var text: GoldenText?
    var texts: [String]?
    var channelSet: String?
    /// A channel id in `channelSet`.
    var channel: String?
    /// Only these channels of `channelSet`, in this order (else all of them).
    var channels: [String]?
    var picked: [String]?
    var programme: TeamProgrammeGolden?
    var nowPlaying: [String: TeamProgrammeGolden]?
    var programmes: [String: [TeamProgrammeGolden]]?
    var now: Int?
    /// Candidate team ids (ids not in the index are skipped); absent: every team of the index.
    var among: [String]?
    var conference: String?
    var league: String?
    var key: String?
    var team: String?
    /// upcomingGames: the cancellation check answers true from its (cancelAfter + 1)th call.
    var cancelAfter: Int?
    var expected: JSONValue = .null

    /// The inputs alone.
    var inputs: TeamCaseGolden {
        var copy = self
        copy.expected = .null
        return copy
    }
}

/// A text, or a huge one as pieces repeated.
nonisolated enum GoldenText: Codable, Equatable, ExpressibleByStringLiteral {
    case plain(String)
    case parts([GoldenTextPart])

    init(stringLiteral value: String) { self = .plain(value) }

    static func repeated(_ parts: (String, Int)...) -> GoldenText {
        .parts(parts.map { GoldenTextPart(text: $0.0, count: $0.1) })
    }

    var string: String {
        switch self {
        case .plain(let text): text
        case .parts(let parts): parts.map { String(repeating: $0.text, count: $0.count) }.joined()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .plain(text)
        } else {
            self = .parts(try container.decode([GoldenTextPart].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .plain(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

/// `[piece, count]`.
nonisolated struct GoldenTextPart: Codable, Equatable {
    var text: String
    var count: Int

    init(text: String, count: Int) {
        self.text = text
        self.count = count
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        text = try container.decode(String.self)
        count = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(text)
        try container.encode(count)
    }
}

/// Any JSON value (an expected result).
nonisolated enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
    static func optional(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }
}

/// The cases, and how MMTVL's code answers them.
enum RokuTeamsGolden {
    // MARK: - Inputs

    static let start = 1_791_200_000

    static func programme(_ title: GoldenText, subtitle: GoldenText? = nil, category: GoldenText? = nil,
                          summary: GoldenText? = nil, start: Int = start, length: Int = 3600) -> TeamProgrammeGolden {
        TeamProgrammeGolden(title: title, subtitle: subtitle, category: category, summary: summary, start: start,
                            stop: start + length)
    }

    static func college(_ league: TeamLeague, _ slug: String, _ name: String, school: String, nickname: String,
                        conference: String = "Test", aliases: [String] = [], abbreviations: [String] = []) -> Team {
        Team(id: "\(league.rawValue).\(slug)", league: league, name: name, school: school, nickname: nickname,
             conference: conference, aliases: aliases, abbreviations: abbreviations)
    }

    static let indexes: [String: TeamIndexGolden] = [
        "bundled.off": TeamIndexGolden(sets: ["pro", "college"], initials: false, nicknames: false),
        "bundled.initials": TeamIndexGolden(sets: ["pro", "college"], initials: true, nicknames: false),
        "bundled.nicknames": TeamIndexGolden(sets: ["pro", "college"], initials: false, nicknames: true),
        "bundled.both": TeamIndexGolden(sets: ["pro", "college"], initials: true, nicknames: true),
        "fixture": TeamIndexGolden(sets: ["pro", "collegeFixture"], initials: false, nicknames: false),
        "fixtureBigger": TeamIndexGolden(sets: ["pro", "collegeFixture", "unpicked"], initials: false, nicknames: false),
        "variant": TeamIndexGolden(sets: ["pro", "variantFixture"], initials: false, nicknames: false),
        "variantNicknames": TeamIndexGolden(sets: ["pro", "variantFixture"], initials: false, nicknames: true),
        "ulmInitials": TeamIndexGolden(sets: ["ulm"], initials: true, nicknames: false),
        "ulmPlain": TeamIndexGolden(sets: ["ulm"], initials: false, nicknames: false),
        "hawksOneWord": TeamIndexGolden(sets: ["hawksOneWord"], initials: false, nicknames: true),
        "hawksMultiWord": TeamIndexGolden(sets: ["hawksMultiWord"], initials: false, nicknames: true),
        "owls": TeamIndexGolden(sets: ["owls"], initials: false, nicknames: true),
    ]

    static let owlConferences = ["Southern (FCS)", "American", "Mid-American", "Northeast (FCS)", "West Coast", "Big Ten",
                                 "Conference USA", "FBS Independents", "Missouri Valley Football (FCS)",
                                 "Pioneer Football League (FCS)", "UAC (FCS)", "CAA"]

    static func hawks(_ aliases: [String]) -> [Team] {
        [
            college(.ncaaf, "monmouth-hawks", "Monmouth Hawks", school: "Monmouth", nickname: "Hawks", aliases: ["Monmouth"]),
            college(.ncaaf, "hartford-hawks", "Hartford Hawks", school: "Hartford", nickname: "Hawks",
                    aliases: ["Hartford"] + aliases),
        ]
    }

    static var teamSets: [String: [Team]] {
        [
            "collegeFixture": TeamMatcherTests.collegeFixture,
            "unpicked": [
                college(.ncaabase, "texas-longhorns", "Texas Longhorns", school: "Texas", nickname: "Longhorns",
                        aliases: ["Texas"]),
                college(.ncaaf, "grambling-tigers", "Grambling Tigers", school: "Grambling", nickname: "Tigers",
                        aliases: ["Grambling State"]),
            ],
            "variantFixture": TeamMatcherTests.variantFixture,
            "ulm": [
                college(.ncaaf, "ul-monroe-warhawks", "UL Monroe Warhawks", school: "UL Monroe", nickname: "Warhawks",
                        aliases: ["UL Monroe", "Louisiana-Monroe"], abbreviations: ["ULM"]),
            ],
            "hawksOneWord": hawks(["Long"]),
            "hawksMultiWord": hawks(["Long Island"]),
            "owls": owlConferences.enumerated().map { n, conference in
                college(.ncaaf, "owls-\(n)", "Owls \(n) Owls", school: "Owls \(n)", nickname: "Owls", conference: conference)
            },
        ]
    }

    /// Playlists (the channels come from `ChannelList.make`), and channels built directly.
    static var playlists: [String: String] {
        [
            "playlist": TeamMatcherTests.playlist,
            "noTvgID": "#EXTM3U\n#EXTINF:0 group-title=\"Live-Games\",A Team @ B Team-H\n\(TeamMatcherTests.url(9))\n",
            "leagueGroups": TeamMatcherTests.leagueGroups,
            "collegeGames": TeamMatcherTests.collegeGames,
            "networks": TeamMatcherTests.networks,
            "variantGames": TeamMatcherTests.variantGames,
            "iptv": IPTVFixtures.playlist,
        ]
    }

    static let hugeName = GoldenText.repeated(("Los Angeles Lakers @ Miami Heat", 1), (" x", 50_000))

    /// MyTeamsTests' `channel(_:group:)`.
    static func myChannel(_ name: String, group: String = "Live") -> TeamChannelGolden {
        TeamChannelGolden(id: "name:\(name.lowercased())", name: .plain(name), group: group)
    }

    static let builtChannels: [String: [TeamChannelGolden]] = [
        "huge": [TeamChannelGolden(id: "id:huge", name: hugeName, group: "NBA")],
        "myTeams": [myChannel("ESPN"), myChannel("FOX"), myChannel("Miami Heat @ Los Angeles Lakers", group: "NBA"),
                    myChannel("ESPN2")],
    ]

    static var channelSets: [String: TeamChannelSetGolden] {
        var sets: [String: TeamChannelSetGolden] = [:]
        for (name, m3u) in playlists {
            let channels = (try? ChannelList.make(from: M3UParser.parse(m3u))) ?? []
            sets[name] = TeamChannelSetGolden(m3u: m3u, channels: channels.map {
                TeamChannelGolden(id: $0.id, name: .plain($0.name), group: $0.group)
            })
        }
        for (name, channels) in builtChannels {
            sets[name] = TeamChannelSetGolden(m3u: nil, channels: channels)
        }
        return sets
    }

    static let coverage: [TeamCoverageGolden] = {
        let full = "full"
        let matcher = "matcher"
        let no = "no"
        let t = "TeamMatcherTests."
        let m = "MyTeamsTests."
        return [
            .init(test: t + "catalogHasEveryTeamOnce", carried: full, note: "league counts; every pro full name and alias"),
            .init(test: t + "feedNamesAreSpelledOutAndIdsKept", carried: full, note: "the playlist's channels (M3U.bs), feedName, game(from:)"),
            .init(test: t + "feedNamesWithoutTvgIDKeepTheirOldID", carried: full, note: "as a playlist entry without tvg-id"),
            .init(test: t + "gamesMatchEitherSideWithThePickedTeamsFeedFirst", carried: full, note: ""),
            .init(test: t + "gameEntriesCountInAnyGroupButReplays", carried: full, note: ""),
            .init(test: t + "networkProgrammesMatchByNameOrNicknameAndLeague", carried: full, note: ""),
            .init(test: t + "teamsGroupComesRightAfterFavoritesWithAVisibleMatch", carried: no,
                  note: "ChannelLineup's groups: step 18 (Lineup.bs, MyTeamsLineupTests)"),
            .init(test: t + "preferencesKeepTeams", carried: no,
                  note: "ChannelPreferences JSON: the Roku keeps teams in SettingsStore's prefs (step 7, step 18)"),
            .init(test: t + "pickingATeamBuildsTheTeamsGroup", carried: matcher,
                  note: "the matcher's channel ids; picking, saving and the lineup are step 18"),
            .init(test: t + "aLiveTeamGameTopsFavorites", carried: no,
                  note: "Favorites, the saved list and the home preview: step 18's lineup (its matcher part is pickingATeamBuildsTheTeamsGroup's)"),
            .init(test: t + "favoritesMoveOnlyBelowTheTeamChannels", carried: no, note: "the guide's Favorites and Move Up/Down: step 18"),
            .init(test: t + "aLateTeamUpdateDoesntUndoANewerPick", carried: matcher,
                  note: "the channel ids for both picks; the update ordering is step 18's Task"),
            .init(test: t + "aCancelledUpdateWithTheSamePicksStillSetsTheGroup", carried: no,
                  note: "update cancellation in IPTVLibrary: step 18's Task (its matcher result is pickingATeamBuildsTheTeamsGroup's)"),
            .init(test: t + "theChannelMenuOffersTheGamesTeams", carried: matcher,
                  note: "teams(inGame:) and pickTitle; the menu items are step 18"),
            .init(test: t + "collegeSportComesFromTheTitleAndCategory", carried: full, note: ""),
            .init(test: t + "collegeSidesAreParsedExactly", carried: full, note: ""),
            .init(test: t + "collegeSidesFromTheSummary", carried: full, note: ""),
            .init(test: t + "aLongHostileSummaryIsCheap", carried: full, note: "results; the time limits are Swift's (the Roku logs its times)"),
            .init(test: t + "repeatedVerbPhrasesAreCheap", carried: full, note: "results; the time limits are Swift's"),
            .init(test: t + "fuzzedLeadsAreCheap", carried: full,
                  note: "the first 100 of the 10,000 leads (same seed), with Swift's results; the time limit is Swift's"),
            .init(test: t + "theLeadScanKeepsTheRegexsReadings", carried: full, note: ""),
            .init(test: t + "aGatorsGameNamedOnlyInTheSummaryMatches", carried: full, note: ""),
            .init(test: t + "collegeProgrammesMatchTheirSportsSchoolsExactly", carried: full, note: ""),
            .init(test: t + "collegeTeamsShowWithTheirSport", carried: full, note: "pickTitle"),
            .init(test: t + "collegeGameEntriesMatchTheSchoolInAnySport", carried: full, note: ""),
            .init(test: t + "networkMatchingTestsOnlyThePickedTeams", carried: full, note: ""),
            .init(test: t + "schoolFormsWithTheNicknameMatchFromTheBundledCatalog", carried: full, note: ""),
            .init(test: t + "aKeyTeamsShareMatchesEachOfThem", carried: full, note: ""),
            .init(test: t + "withBothOptionsOffInitialsAndNicknamesAloneMatchNothing", carried: full, note: ""),
            .init(test: t + "matchInitialsAddsTheAbbreviations", carried: full, note: ""),
            .init(test: t + "eachCombinationOfTheOptionsHasItsIndex", carried: full, note: ""),
            .init(test: t + "aNicknameAloneFallsBackToItsTeams", carried: full, note: ""),
            .init(test: t + "anExactKeyWinsOverTheNickname", carried: full, note: ""),
            .init(test: t + "onlyMultiWordAliasesNarrow", carried: full, note: ""),
            .init(test: t + "conferencesAreNamedByTheirPhrases", carried: full, note: "the matched ids (the test maps them to conferences)"),
            .init(test: t + "theConferenceIsReadFromTheSummarysLead", carried: full, note: ""),
            .init(test: t + "teamsBySideKeepsEachSidesTeams", carried: full, note: ""),
            .init(test: t + "anExactSideKeepsItsTeamFromAnEarlierFallbackSide", carried: full, note: ""),
            .init(test: t + "aHugeTitleOrSubtitleIsCheap", carried: full, note: "results and the bounded texts; the time limits are Swift's"),
            .init(test: t + "aHugeGameEntryNameIsCheap", carried: full, note: "results; the time limit is Swift's"),
            .init(test: t + "gameEntriesUseEveryKeyButNoNicknameFallback", carried: full, note: ""),
            .init(test: t + "theFallbackStaysCheapOnAHugeSummary", carried: full, note: "results; the time limit is Swift's"),
            .init(test: m + "aCancelledMatchingOfUpcomingGamesStopsEarly", carried: matcher,
                  note: "the isCancelled check (50 programmes, not 5,000); a cancelled Swift Task has no Roku form: cancelAfter 0 stands for it"),
            .init(test: m + "upcomingGamesAreTheNext72HoursSoonestFirst", carried: full, note: ""),
            .init(test: m + "upcomingGamesDontShareAMatchAcrossSummaries", carried: full, note: ""),
            .init(test: m + "aGameWithoutSubtitleIsLabelledByItsTitle", carried: matcher,
                  note: "the label; dayTime is the user's locale formatting (step 18's UI)"),
            .init(test: m + "theListIsCalledMyTeams", carried: no, note: "UI strings: step 18 (My Teams, Choose Teams) and step 19 (search hints)"),
            .init(test: m + "myTeamsIsAlwaysAfterFavoritesAndUpcomingRowsStayOutOfFavorites", carried: no,
                  note: "ChannelLineup (groups, hidden channels, the 30-game cap): step 18's MyTeamsLineupTests"),
            .init(test: m + "pickingATeamListsItsUpcomingGames", carried: matcher,
                  note: "the matcher over the test's guide (live game, upcoming games); the library, Favorites and saving are step 18"),
            .init(test: m + "anUpdateCancelledDuringItsReadKeepsTheNetworkAndUpcomingGames", carried: no,
                  note: "IPTVLibrary's cancelled store read: step 18's Task (its matcher results are pickingATeamListsItsUpcomingGames')"),
            .init(test: m + "selectOnAnUpcomingGameTunesItsChannel", carried: no, note: "the guide's rows and keys: step 18"),
            .init(test: m + "theChannelMenuOffersEachSidesTeamsPickedFirst", carried: matcher,
                  note: "teamsBySide and My Teams' channels; picked-first and 3 a side are the menu's (step 18)"),
            .init(test: m + "theChannelMenuOffersAtMostThreeTeamsASide", carried: matcher, note: "teamsBySide; the cap of 3 is the menu's (step 18)"),
            .init(test: m + "theChannelMenuOffersNoNicknameTeamsWithTheOptionOff", carried: matcher, note: "teamsBySide and My Teams' channels"),
            .init(test: m + "changingMatchInitialsRecomputesMyTeamsAndTheMenu", carried: matcher,
                  note: "both options' results; recomputing on a change is step 18"),
            .init(test: m + "aRememberedTeamsGroupOpensMyTeams", carried: no, note: "the lineup's legacy group name: step 18"),
        ]
    }()

    /// Every case, `expected` unset.
    static var cases: [TeamCaseGolden] {
        var all: [TeamCaseGolden] = []
        func add(_ test: String, _ op: String, index: String? = nil, text: GoldenText? = nil, texts: [String]? = nil,
                 channelSet: String? = nil, channel: String? = nil, channels: [String]? = nil, picked: [String]? = nil,
                 programme: TeamProgrammeGolden? = nil, nowPlaying: [String: TeamProgrammeGolden]? = nil,
                 programmes: [String: [TeamProgrammeGolden]]? = nil, now: Int? = nil, among: [String]? = nil,
                 conference: String? = nil, league: String? = nil, key: String? = nil, team: String? = nil,
                 cancelAfter: Int? = nil) {
            let suite = test.hasPrefix("my:") ? "MyTeamsTests." : "TeamMatcherTests."
            let name = test.hasPrefix("my:") ? String(test.dropFirst(3)) : test
            all.append(TeamCaseGolden(test: suite + name, op: op, index: index, text: text, texts: texts,
                                      channelSet: channelSet, channel: channel, channels: channels, picked: picked,
                                      programme: programme, nowPlaying: nowPlaying, programmes: programmes, now: now,
                                      among: among, conference: conference, league: league, key: key, team: team,
                                      cancelAfter: cancelAfter))
        }
        func p(_ title: GoldenText, subtitle: GoldenText? = nil, category: GoldenText? = nil,
               summary: GoldenText? = nil) -> TeamProgrammeGolden {
            programme(title, subtitle: subtitle, category: category, summary: summary)
        }
        let off = "bundled.off"
        let heatAway = TeamMatcherTests.heatAway
        let heatHome = TeamMatcherTests.heatHome
        let heatReplay = TeamMatcherTests.heatReplay
        let espn = TeamMatcherTests.espn

        // catalogHasEveryTeamOnce
        var test = "catalogHasEveryTeamOnce"
        add(test, "leagueTeamCounts", index: off)
        add(test, "teamNamedMany", index: off,
            texts: TeamCatalog.proTeams.flatMap(\.fullNames) + ["los angeles LAKERS", "Montréal Canadiens", "Los Angeles"])

        // feedNamesAreSpelledOutAndIdsKept
        test = "feedNamesAreSpelledOutAndIdsKept"
        add(test, "channels", channelSet: "playlist")
        for name in ["ESPN-H", "Philadelphia @ Tampa Bay-A", "Miami Heat @ Los Angeles Lakers-H"] {
            add(test, "feedName", text: .plain(name))
        }
        add(test, "game", text: "Miami Heat @ Los Angeles Lakers (Home Feed)")

        // feedNamesWithoutTvgIDKeepTheirOldID
        add("feedNamesWithoutTvgIDKeepTheirOldID", "channels", channelSet: "noTvgID")

        // gamesMatchEitherSideWithThePickedTeamsFeedFirst
        test = "gamesMatchEitherSideWithThePickedTeamsFeedFirst"
        for picked in [["nba.lal"], ["nba.mia"], ["nba.mia", "nba.lal"], ["nba.lac"], ["nfl.den", "nfl.kc"]] {
            add(test, "gameChannelIDs", index: off, channelSet: "playlist", picked: picked)
        }
        add(test, "channelIDs", index: off, channelSet: "playlist", picked: [], nowPlaying: [:])
        add(test, "teamsInGame", index: off, channelSet: "playlist", channel: heatHome)
        add(test, "teamsInGame", index: off, channelSet: "playlist", channel: heatReplay)

        // gameEntriesCountInAnyGroupButReplays
        test = "gameEntriesCountInAnyGroupButReplays"
        let network = "id:nflnetwork.us"
        let home = "id:tampa bay buccaneers @ chicago bears-h"
        let redZone = "id:nflredzone.us"
        add(test, "gameEntries", index: off, channelSet: "leagueGroups")
        for picked in [["nfl.tb"], ["nfl.chi"], ["nfl.tb", "nfl.chi"], ["nfl.kc"]] {
            add(test, "gameChannelIDs", index: off, channelSet: "leagueGroups", picked: picked)
        }
        for channel in [home, network, "id:tampa bay buccaneers @ chicago bears (r)"] {
            add(test, "teamsInGame", index: off, channelSet: "leagueGroups", channel: channel)
        }
        let bucs = p("NFL Football", subtitle: "Tampa Bay Buccaneers at Chicago Bears")
        let leagueNow = [network: bucs, redZone: p("NFL RedZone", subtitle: "Buccaneers"), home: bucs]
        add(test, "networkChannelIDs", index: off, channelSet: "leagueGroups", picked: ["nfl.tb"], nowPlaying: leagueNow)
        add(test, "channelIDs", index: off, channelSet: "leagueGroups", picked: ["nfl.tb"], nowPlaying: leagueNow)

        // networkProgrammesMatchByNameOrNicknameAndLeague
        test = "networkProgrammesMatchByNameOrNicknameAndLeague"
        let heatGame = p("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers")
        for programme in [heatGame, p("Kings", category: "Hockey"), p("Kings of Comedy"), p("World Athletics Championships"),
                          p("MLB Baseball", subtitle: "Athletics at Rays")] {
            add(test, "teamsIn", index: off, programme: programme)
        }
        add(test, "isLiveGame", programme: p("Lakers Postgame", category: "Basketball"))
        add(test, "isLiveGame", programme: heatGame)
        add(test, "networkChannelIDs", index: off, channelSet: "playlist", picked: ["nba.mia"], nowPlaying: [espn: heatGame])
        add(test, "networkChannelIDs", index: off, channelSet: "playlist", picked: ["nhl.la"], nowPlaying: [espn: heatGame])
        add(test, "networkChannelIDs", index: off, channelSet: "playlist", picked: ["nba.lal"],
            nowPlaying: [espn: p("Lakers Postgame", subtitle: "NBA")])
        add(test, "channelIDs", index: off, channelSet: "playlist", picked: ["nba.mia"], nowPlaying: [espn: heatGame])

        // pickingATeamBuildsTheTeamsGroup, aLateTeamUpdateDoesntUndoANewerPick, theChannelMenuOffersTheGamesTeams
        add("pickingATeamBuildsTheTeamsGroup", "channelIDs", index: off, channelSet: "playlist", picked: ["nba.lal"],
            nowPlaying: [:])
        // Unknown ids aren't teams (setTeamPicked looks ids up the same way).
        add("pickingATeamBuildsTheTeamsGroup", "pickTitle", index: off, team: "nba.nope")
        add("aLateTeamUpdateDoesntUndoANewerPick", "channelIDs", index: off, channelSet: "playlist",
            picked: ["nba.lal", "nba.tor"], nowPlaying: [:])
        add("theChannelMenuOffersTheGamesTeams", "teamsInGame", index: off, channelSet: "playlist", channel: heatHome)
        add("theChannelMenuOffersTheGamesTeams", "pickTitle", index: off, team: "nba.mia")

        // collegeSportComesFromTheTitleAndCategory
        test = "collegeSportComesFromTheTitleAndCategory"
        for programme in [p("College Football"), p("Live: College Basketball"), p("Live: Women's College Basketball"),
                          p("College Baseball"), p("Basketball", category: "NCAAW"), p("Live: Women's College Soccer"),
                          p("NBA Basketball")] {
            add(test, "collegeLeague", programme: programme)
        }

        // collegeSidesAreParsedExactly
        test = "collegeSidesAreParsedExactly"
        for programme in [p("College Football", subtitle: "Texas A&M at South Carolina"),
                          p("College Basketball", subtitle: "SEC Tournament: Georgia vs. Oklahoma"),
                          p("College Basketball", subtitle: "#5 Duke vs Kansas"),
                          p("College Basketball", subtitle: "(12) Duke @ Kansas"),
                          p("College Football: Georgia at Texas"), p("Live: College Basketball"),
                          p("College Football", subtitle: "TBA")] {
            add(test, "collegeSides", programme: programme)
        }

        // collegeSidesFromTheSummary
        test = "collegeSidesFromTheSummary"
        let summaries: [(String, String?)] = [
            ("The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I game in Florida. "
                + "The Gators lead the series.", nil),
            ("The No. 6 Michigan State Spartans face the No. 2 Duke Blue Devils for an NCAA Division I game.", nil),
            ("The Ohio Bobcats visit the Miami (OH) RedHawks for a MAC game.", nil),
            ("The Nebraska Cornhuskers (5-3) visit the Illinois Fighting Illini (5-3) at Memorial Stadium.", nil),
            ("The Louisiana-Monroe Warhawks host the Louisiana Ragin' Cajuns in Sun Belt play.", nil),
            ("The Pittsburgh Panthers meet the Florida State Seminoles.", nil),
            ("The Colorado Buffaloes clash with the No. 17 Houston Cougars in Big 12 play.", nil),
            ("The Villanova Wildcats host the St. John's Red Storm.", nil),
            ("The Duke Blue Devils host the Stephen F. Austin Lumberjacks for a non-conference game.", nil),
            ("From Breslin Center in East Lansing, Mich.", nil),
            ("The Huskies (5-3, 2-3 Big Ten) try to solve the Nittany Lions (4-4, 1-4).", nil),
            ("Men's college basketball action.", nil),
            ("The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I game.", "Duke at Kansas"),
        ]
        for (summary, subtitle) in summaries {
            add(test, "collegeSides", programme: p("Live: College Basketball", subtitle: subtitle.map { .plain($0) },
                                                    summary: .plain(summary)))
        }
        add(test, "teamsIn", index: off,
            programme: p("College Basketball", summary: .plain("The Duke Blue Devils host the Stephen F. Austin Lumberjacks for a "
                            + "non-conference game.")),
            among: ["ncaam.stephen-f-austin-lumberjacks"])

        // aLongHostileSummaryIsCheap
        test = "aLongHostileSummaryIsCheap"
        let spaces = GoldenText.repeated(("the", 1), ("     visits     the", 5), (" ", 300), ("x", 1))
        let newlines = GoldenText.repeated(("the", 1), ("\n\n\n\n\nvisits\n\n\n\n\nthe", 5), ("\n", 300), ("x", 1))
        for summary in [GoldenText.repeated(("The A", 1), (" visits the (1", 1_500)), spaces, newlines,
                        .repeated(("the ", 1), ("a visits the ", 30), ("b", 1), ("\u{301}", 200_000)),
                        "The Duke Blue Devils host\n  the Kansas Jayhawks for a game."] {
            add(test, "summarySides", text: summary)
        }

        // repeatedVerbPhrasesAreCheap
        test = "repeatedVerbPhrasesAreCheap"
        for attack in ["#1 x plays the ", "#1 x hosts the ", "no. 1 x plays the ", "(1) x plays the ", "#1 x (1) meets the "] {
            add(test, "summarySides", text: .repeated(("the ", 1), (attack, 40)))
        }
        add(test, "teamsIn", index: "bundled.both",
            programme: p("Live: College Basketball", category: "Sports", summary: .repeated(("the ", 1), ("#1 x plays the ", 40))))

        // fuzzedLeadsAreCheap: the test's first 100 leads.
        let pieces = ["the", "#1", "no. 1", "(1", ")", "x", "st.", ",", ".", "visits", "faces", "meets", "hosts",
                      "clashes with", "takes on", "plays", "battles", "squares off against", "for", "at", "in", "on",
                      "to", "The", "(1-2)", "No.1"]
        var generator = SplitMix(seed: 34)
        var leads: [String] = []
        for _ in 0..<100 {
            var text = "the "
            while text.utf16.count < TeamMatcher.summaryLeadLength {
                text += pieces[Int(generator.next() % UInt64(pieces.count))] + (generator.next() % 4 == 0 ? "" : " ")
            }
            leads.append(text)
        }
        add("fuzzedLeadsAreCheap", "summarySidesMany", texts: leads)

        // theLeadScanKeepsTheRegexsReadings
        test = "theLeadScanKeepsTheRegexsReadings"
        for summary in ["the #3 Duke Blue Devils (5-0) host the (12) Kansas Jayhawks (4-1), in a rematch.",
                        "THE DUKE BLUE DEVILS VISIT THE KANSAS JAYHAWKS TONIGHT FOR A GAME.",
                        "The Texas Longhorns take on the Mt. Olive Trojans; it's early.",
                        "The Texas Longhorns squares off against the No. 9 Ohio State Buckeyes at noon.",
                        "The Duke Blue Devils clash with the UNC Tar Heels on-campus.",
                        "The Visitors meet the Hosts.", "Duke hosts the Kansas Jayhawks.", "The Duke Blue Devils host Kansas.",
                        "The Duke Blue Devils host the Kansas Jayhawks", "The plays the x."] {
            add(test, "summarySides", text: .plain(summary))
        }

        // aGatorsGameNamedOnlyInTheSummaryMatches
        test = "aGatorsGameNamedOnlyInTheSummaryMatches"
        let gatorsGame = p("Live: College Basketball", category: "Sports",
                           summary: .plain("The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I "
                            + "game in Florida. The Gators look to stay unbeaten."))
        for among in [["ncaam.florida-gators", "ncaam.florida-state-seminoles"], ["ncaam.florida-gators"],
                      ["ncaam.south-florida-bulls"]] {
            add(test, "teamsIn", index: off, programme: gatorsGame, among: among)
        }
        add(test, "teamsIn", index: off,
            programme: p("The Secret Life of Pets", category: "Movie",
                         summary: "Max's life is turned upside down when his owner adopts Duke, a big, unruly dog."),
            among: ["ncaam.duke-blue-devils"])
        add(test, "teamsIn", index: off,
            programme: p("SportsCenter", category: "Sports", summary: "The Duke Blue Devils face the Kansas Jayhawks for a preview."),
            among: ["ncaam.duke-blue-devils"])

        // collegeProgrammesMatchTheirSportsSchoolsExactly
        test = "collegeProgrammesMatchTheirSportsSchoolsExactly"
        for programme in [p("College Football", subtitle: "Texas A&M at South Carolina", category: "Sports"),
                          p("Live: College Basketball", subtitle: "Grambling State at Texas"),
                          p("Live: Women's College Basketball", subtitle: "Villanova at Princeton"),
                          p("Live: Women's College Soccer", subtitle: "SEC Tournament: Georgia vs. Oklahoma"),
                          p("College Basketball", subtitle: "No. 5 Duke vs. Kansas"),
                          p("College Basketball", subtitle: "Alabama State Hornets at Duke"),
                          p("NBA Basketball", subtitle: "Hornets at Heat"),
                          p("NHL Hockey", subtitle: "New Jersey Devils at Toronto Maple Leafs")] {
            add(test, "teamsIn", index: "fixture", programme: programme)
        }
        add(test, "isLiveGame", programme: p("College Basketball Pregame", subtitle: "Duke vs. Kansas"))

        // collegeTeamsShowWithTheirSport
        add("collegeTeamsShowWithTheirSport", "pickTitle", index: "fixture", team: "ncaaw.michigan-wolverines")
        add("collegeTeamsShowWithTheirSport", "pickTitle", index: off, team: "nba.lal")

        // collegeGameEntriesMatchTheSchoolInAnySport
        test = "collegeGameEntriesMatchTheSchoolInAnySport"
        for picked in [["ncaaw.michigan-wolverines"], ["ncaaf.ohio-state-buckeyes"], ["ncaaw.grambling-lady-tigers"],
                       ["ncaaf.texas-longhorns"], ["ncaam.duke-blue-devils"], ["nba.lal"]] {
            add(test, "gameChannelIDs", index: "fixture", channelSet: "collegeGames", picked: picked)
        }

        // networkMatchingTestsOnlyThePickedTeams
        test = "networkMatchingTestsOnlyThePickedTeams"
        let networkNow = [
            "id:espn.us": p("Live: College Basketball", subtitle: "Grambling State at Texas"),
            "id:secn.us": p("College Football", subtitle: "Texas A&M at South Carolina"),
            "id:espn2.us": p("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers"),
        ]
        for picked in [["ncaam.texas-longhorns"], ["ncaaf.texas-longhorns"], ["ncaaf.south-carolina-gamecocks"],
                       ["nba.lal", "ncaam.grambling-tigers"], []] {
            for index in ["fixture", "fixtureBigger"] {
                add(test, "networkChannelIDs", index: index, channelSet: "networks", picked: picked, nowPlaying: networkNow)
            }
        }
        add(test, "teamsIn", index: "fixture", programme: networkNow["id:espn.us"], among: ["ncaam.texas-longhorns"])

        // schoolFormsWithTheNicknameMatchFromTheBundledCatalog
        test = "schoolFormsWithTheNicknameMatchFromTheBundledCatalog"
        let football = "College Football"
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "Louisiana-Monroe Warhawks at Troy Trojans"))
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "Brigham Young Cougars at Hawaii Rainbow Warriors"))
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "Hawai'i Rainbow Warriors at UTEP"))
        add(test, "teamsIn", index: off, programme: p("College Basketball", subtitle: "St Johns Red Storm at Villanova"),
            among: ["ncaam.st-johns-red-storm"])
        add(test, "teamsIn", index: "variant", programme: p(.plain(football), subtitle: "Appalachian State Mountaineers at Nowhere"))

        // aKeyTeamsShareMatchesEachOfThem
        test = "aKeyTeamsShareMatchesEachOfThem"
        let mer = p("College Baseball", subtitle: "MER at Nowhere")
        add(test, "teamsIn", index: "variant", programme: mer)
        add(test, "teamsIn", index: "variant", programme: mer, among: ["ncaabase.mercyhurst-lakers"])
        add(test, "teamsIn", index: "bundled.initials", programme: mer)
        add(test, "teamsIn", index: off, programme: mer)

        // withBothOptionsOffInitialsAndNicknamesAloneMatchNothing
        test = "withBothOptionsOffInitialsAndNicknamesAloneMatchNothing"
        let ulm = "ncaaf.ul-monroe-warhawks"
        let big12 = "The Cougars meet the Bearcats in Big 12 play."
        add(test, "indexFacts", index: off)
        add(test, "team", index: off, team: ulm)
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "ULM Warhawks at Troy"), among: [ulm])
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "ULM at Troy"), among: [ulm])
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "Louisiana-Monroe Warhawks at Troy"), among: [ulm])
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "LSU at Alabama"))
        add(test, "teamsIn", index: off, programme: p(.plain(football), subtitle: "BYU Cougars at Utah"), among: ["ncaaf.byu-cougars"])
        add(test, "teamsIn", index: "variant", programme: p(.plain(football), summary: .plain(big12)))
        add(test, "teamsIn", index: off, programme: p(.plain(football), summary: .plain(big12)))
        add(test, "teamsIn", index: "variant", programme: p(.plain(football), subtitle: "Springfield Cougars at Nowhere"))
        add(test, "fallbackTablesEmpty", index: off)
        add(test, "isGameEntry", index: off, channelSet: "variantGames", channel: "id:shorthand")
        add(test, "gameChannelIDs", index: off, channelSet: "variantGames", picked: ["ncaaf.buffalo-bulls"])

        // matchInitialsAddsTheAbbreviations
        test = "matchInitialsAddsTheAbbreviations"
        let initials = "bundled.initials"
        add(test, "indexFacts", index: initials)
        add(test, "teamsIn", index: initials, programme: p(.plain(football), subtitle: "ULM Warhawks at Troy"), among: [ulm])
        add(test, "teamsIn", index: initials, programme: p(.plain(football), subtitle: "ULM at Troy"), among: [ulm])
        add(test, "teamsIn", index: initials, programme: p("College Basketball", subtitle: "UTRGV Vaqueros at Nowhere"),
            among: ["ncaam.ut-rio-grande-valley-vaqueros"])
        add(test, "teamsIn", index: initials, programme: p(.plain(football), summary: .plain(big12)))
        add(test, "isGameEntry", index: initials, channelSet: "variantGames", channel: "id:shorthand")
        add(test, "gameChannelIDs", index: initials, channelSet: "variantGames", picked: ["ncaaf.buffalo-bulls"])
        add(test, "collegeNamesKey", index: "ulmInitials", league: "ncaaf", key: " ulm warhawks ")
        add(test, "collegeSchoolsKey", index: "ulmInitials", key: " ulm ")
        add(test, "collegeNamesKey", index: "ulmPlain", league: "ncaaf", key: " ulm warhawks ")
        add(test, "collegeSchoolsKey", index: "ulmPlain", key: " ulm ")

        // eachCombinationOfTheOptionsHasItsIndex
        test = "eachCombinationOfTheOptionsHasItsIndex"
        for index in ["bundled.off", "bundled.initials", "bundled.nicknames", "bundled.both"] {
            add(test, "indexFacts", index: index)
        }
        add(test, "teamsIn", index: "bundled.both", programme: p(.plain(football), subtitle: "ULM Warhawks at Troy"), among: [ulm])
        add(test, "teamsIn", index: "bundled.both",
            programme: p(.plain(football),
                         summary: "The Rainbow Warriors (2-6, 1-4) visit the Miners (1-7, 0-4) for a Mountain West affair."))

        // aNicknameAloneFallsBackToItsTeams
        test = "aNicknameAloneFallsBackToItsTeams"
        let nick = "variantNicknames"
        func fallback(_ subtitle: GoldenText? = nil, summary: GoldenText? = nil, title: GoldenText = "College Football",
                      among: [String]? = nil) {
            add(test, "teamsIn", index: nick, programme: p(title, subtitle: subtitle, summary: summary), among: among)
        }
        fallback(summary: "The Rainbow Warriors (2-6, 1-4) visit the Miners (1-7, 0-4) for a Mountain West affair.")
        fallback(summary: .plain(big12))
        fallback(summary: .plain(big12), among: ["ncaaf.washington-state-cougars"])
        fallback(summary: "The Cougars meet the Bearcats.")
        fallback(summary: "The Huskies host the Miners in Southland play.")
        fallback("Springfield Cougars at Nowhere")
        fallback("Springfield Cougars at Nowhere", among: ["ncaaf.houston-cougars"])
        fallback(summary: "The Washington Cougars meet the Bearcats in Big 12 play.")
        fallback(summary: "The State Cougars meet the Bearcats.")
        fallback("Springfield at Nowhere")
        fallback("Cougars Fans at Nowhere")
        fallback("Cougars at Bearcats", title: "NFL Football")

        // anExactKeyWinsOverTheNickname
        test = "anExactKeyWinsOverTheNickname"
        fallback("Houston Christian Huskies at Nowhere")
        fallback("Houston Christian Huskies at Nowhere", among: ["ncaaf.houston-cougars"])
        fallback("Houston Christian Huskies at Nowhere", among: ["ncaaf.washington-huskies", "ncaaf.uconn-huskies"])
        fallback(summary: "The Houston Cougars meet the West Virginia Mountaineers in Big 12 play.")

        // onlyMultiWordAliasesNarrow
        test = "onlyMultiWordAliasesNarrow"
        for index in ["hawksOneWord", "hawksMultiWord"] {
            add(test, "teamsIn", index: index, programme: p(.plain(football), subtitle: "Long Beach Hawks at Nowhere"))
            add(test, "teamsIn", index: index, programme: p(.plain(football), subtitle: "Long Hawks at Nowhere"))
        }
        for team in ["ncaaf.ul-monroe-warhawks", "ncaaf.washington-state-cougars", "ncaaf.hawaii-rainbow-warriors"] {
            add(test, "schoolWords", index: "bundled.nicknames", team: team)
        }
        add(test, "conferences", index: "bundled.nicknames", team: "ncaaf.ul-monroe-warhawks")

        // conferencesAreNamedByTheirPhrases
        test = "conferencesAreNamedByTheirPhrases"
        for tail in ["in Southern Conference play.", "in a SoCon game.", "in American Athletic play.", "for an AAC game.",
                     "for a MAC game.", "in Mid-American play.", "in an NEC game.", "in West Coast Conference play.",
                     "in B1G play.", "in C-USA play.", "in MVFC play.", "in Missouri Valley Football Conference play.",
                     "in Pioneer League play.", "in United Athletic Conference play.", "in a UAC game.",
                     "in Coastal Athletic Association play.", "in CAA play.", "with an All-American guard.",
                     "after beating Southern Miss.", "in the Northeast.", "on the West Coast.", "as FBS Independents.",
                     "in a MAC and AAC doubleheader."] {
            add(test, "teamsIn", index: "owls", programme: p(.plain(football), summary: .plain("The Owls host the Nowhere Pumas \(tail)")))
        }
        for conference in ["Big Sky (FCS)", "FCS Independents", "Southern (FCS)"] {
            add(test, "phrases", conference: conference)
        }

        // theConferenceIsReadFromTheSummarysLead
        test = "theConferenceIsReadFromTheSummarysLead"
        let late = GoldenText.repeated(("The Cougars meet the Bearcats.", 1), (" x", TeamMatcher.summaryLeadLength),
                                       (" in Big 12 play.", 1))
        add(test, "conferenceSearchText", programme: p(.plain(football), summary: late))
        add(test, "teamsIn", index: nick, programme: p(.plain(football), summary: late))
        add(test, "teamsIn", index: nick, programme: p("College Football: Big 12 Showdown", summary: late))

        // teamsBySideKeepsEachSidesTeams
        test = "teamsBySideKeepsEachSidesTeams"
        let cougars = p(.plain(football), summary: "The Cougars meet the Bearcats.")
        add(test, "teamsBySide", index: nick, programme: cougars)
        add(test, "teamsIn", index: nick, programme: cougars)
        add(test, "teamsBySide", index: nick, programme: cougars, among: ["ncaaf.cincinnati-bearcats"])
        add(test, "teamsBySide", index: nick, programme: p(.plain(football), subtitle: "Houston at Houston Cougars"))
        add(test, "teamsBySide", index: nick, programme: p(.plain(football), subtitle: "Cougars at Houston Cougars"))
        add(test, "teamsIn", index: nick, programme: p(.plain(football), subtitle: "Cougars at Houston Cougars"))
        add(test, "teamsBySide", index: nick, programme: p(.plain(football), subtitle: "Cincinnati at BYU"))
        add(test, "teamsBySide", index: nick, programme: p("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers"))
        add(test, "teamsBySide", index: nick, programme: p("Movie"))
        add(test, "teamsBySide", index: "variant", programme: cougars)

        // anExactSideKeepsItsTeamFromAnEarlierFallbackSide
        test = "anExactSideKeepsItsTeamFromAnEarlierFallbackSide"
        let lsu = p(.plain(football), summary: "The Tigers host the LSU Tigers.")
        add(test, "teamsBySide", index: "bundled.nicknames", programme: lsu)
        add(test, "teamsIn", index: "bundled.nicknames", programme: lsu)

        // aHugeTitleOrSubtitleIsCheap
        test = "aHugeTitleOrSubtitleIsCheap"
        let filler = (" x", 500_000)
        let huge: [TeamProgrammeGolden] = [
            p(.repeated(("NBA Basketball: Miami Heat at Los Angeles Lakers", 1), filler)),
            p("NBA Basketball", subtitle: .repeated(("Miami Heat at Los Angeles Lakers", 1), filler)),
            p("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers", category: .repeated(("Sports", 1), filler)),
            p(.repeated(("College Football", 1), filler), summary: .plain(big12)),
            p(.plain(football), subtitle: .repeated(("Cincinnati Bearcats at BYU Cougars", 1), filler)),
            p(.repeated(("NBA Basketball: Miami Heat at Los Angeles Lakers x", 1), ("\u{301}", 1_000_000))),
        ]
        for programme in huge {
            add(test, "teamsIn", index: nick, programme: programme)
            add(test, "isLiveGame", programme: programme)
            add(test, "conferenceSearchText", programme: programme)
            add(test, "bounded", programme: programme)
        }

        // aHugeGameEntryNameIsCheap
        test = "aHugeGameEntryNameIsCheap"
        add(test, "gameEntry", index: off, channelSet: "huge", channel: "id:huge")
        add(test, "isGameEntry", index: off, channelSet: "huge", channel: "id:huge")
        add(test, "gameChannelIDs", index: off, channelSet: "huge", picked: ["nba.lal"])

        // gameEntriesUseEveryKeyButNoNicknameFallback
        test = "gameEntriesUseEveryKeyButNoNicknameFallback"
        add(test, "gameChannelIDs", index: off, channelSet: "variantGames", picked: [ulm])
        add(test, "gameChannelIDs", index: off, channelSet: "variantGames", picked: ["ncaaf.troy-trojans"])
        add(test, "isGameEntry", index: off, channelSet: "variantGames", channel: "id:nicknames")
        add(test, "isGameEntry", index: "bundled.both", channelSet: "variantGames", channel: "id:nicknames")
        add(test, "gameChannelIDs", index: off, channelSet: "variantGames", picked: ["ncaaf.buffalo-bulls"])
        add(test, "gameChannelIDs", index: "bundled.both", channelSet: "variantGames", picked: ["ncaaf.buffalo-bulls"])
        add(test, "gameChannelIDs", index: "bundled.both", channelSet: "variantGames", picked: ["ncaabase.mercer-bears"])
        add(test, "gameChannelIDs", index: "bundled.both", channelSet: "variantGames", picked: ["ncaabase.mercyhurst-lakers"])
        add(test, "gameChannelIDs", index: off, channelSet: "variantGames", picked: ["ncaabase.mercer-bears"])
        add(test, "gameEntries", index: "bundled.both", channelSet: "variantGames")

        // theFallbackStaysCheapOnAHugeSummary
        test = "theFallbackStaysCheapOnAHugeSummary"
        let hugeSummary = GoldenText.repeated(("The Cougars meet the Bearcats ", 1), ("in Big 12 play ", 100_000))
        add(test, "teamsIn", index: nick, programme: p(.plain(football), summary: hugeSummary))
        add(test, "teamsIn", index: nick, programme: p(.plain(football), subtitle: "Springfield Cougars at Nowhere Bearcats",
                                                       summary: hugeSummary))

        // Normalization over code points: "x" + c + "y" for every code point up to U+052F, Latin Extended Additional,
        // the ones TeamMatcher folds unlike EPGMatcher (gen-team-tables.swift), and every 31st elsewhere in the BMP.
        var codes: [Int] = []
        for code in 1...0xFFFF where !(0xD800...0xDFFF).contains(code) {
            if code <= 0x52F || (0x1E00...0x1EFF).contains(code) || (0x24B6...0x24E9).contains(code)
                || (0xF880...0xF8D6).contains(code) || [0x0F3E, 0x0F3F, 0x1CE1, 0x1CF7, 0xABEC].contains(code)
                || code % 31 == 0 {
                codes.append(code)
            }
        }
        // Packed: the codes as 4 hex digits each, one string.
        add("catalogHasEveryTeamOnce", "normalizedCodePoints",
            text: .plain(codes.map { String(format: "%04X", $0) }.joined()))
        add("catalogHasEveryTeamOnce", "normalizedMany",
            texts: ["los angeles LAKERS", "Montréal Canadiens", "  Texas  A&M  ", "Hawai'i", "Hawaiʻi", "St. John’s",
                    "Ⓐ Team", "ＴＥＸＡＳ", "e\u{301}cole", "Ⅻ ½ ²", "a_b-c", "", "   ", "😀 Team 🏈", "Ⓐⓑ"])

        // MyTeamsTests
        let now = start
        func hours(_ h: Double) -> Int { now + Int(h * 3600) }
        func mp(_ h: Double, _ title: String, _ subtitle: String? = nil, summary: String? = nil, length: Int = 3 * 3600)
            -> TeamProgrammeGolden {
            programme(.plain(title), subtitle: subtitle.map { .plain($0) }, summary: summary.map { .plain($0) },
                      start: hours(h), length: length)
        }
        let myESPN = "name:espn"
        let myFOX = "name:fox"
        let myGame = "name:miami heat @ los angeles lakers"
        let myESPN2 = "name:espn2"

        // aCancelledMatchingOfUpcomingGamesStopsEarly (50 programmes)
        test = "my:aCancelledMatchingOfUpcomingGamesStopsEarly"
        let many = (0..<50).map { n in
            programme("NBA Basketball", subtitle: .plain("Los Angeles Lakers at Team \(n)"), start: now + 3600 + n * 36,
                      length: 3 * 3600)
        }
        for cancelAfter in [3, nil, 0] as [Int?] {
            add(test, "upcomingGames", index: off, channelSet: "myTeams", channels: [myESPN], picked: ["nba.lal"],
                programmes: [myESPN: many], now: now, cancelAfter: cancelAfter)
        }

        // upcomingGamesAreTheNext72HoursSoonestFirst
        test = "my:upcomingGamesAreTheNext72HoursSoonestFirst"
        let lakersCeltics = mp(5, "NBA Basketball", "Los Angeles Lakers at Boston Celtics")
        let upcoming: [String: [TeamProgrammeGolden]] = [
            myESPN: [mp(-1, "NBA Basketball", "Miami Heat at Los Angeles Lakers"), lakersCeltics,
                     mp(8, "Lakers Postgame", "Los Angeles Lakers"), mp(30, "NBA Basketball", "Boston Celtics at New York Knicks"),
                     mp(73, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets")],
            myFOX: [mp(2, "NBA Replay", "Los Angeles Lakers at Utah Jazz"), lakersCeltics,
                    mp(48, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers")],
            myGame: [mp(1, "NBA Basketball", "Miami Heat at Los Angeles Lakers")],
        ]
        add(test, "upcomingGames", index: off, channelSet: "myTeams", channels: [myESPN, myFOX, myGame], picked: ["nba.lal"],
            programmes: upcoming, now: now)
        add(test, "upcomingGames", index: off, channelSet: "myTeams", channels: [myESPN, myFOX], picked: [],
            programmes: upcoming, now: now)

        // upcomingGamesDontShareAMatchAcrossSummaries
        test = "my:upcomingGamesDontShareAMatchAcrossSummaries"
        let summaryGames = [
            myESPN: [mp(1, "College Basketball",
                        summary: "The No. 6 Michigan State Spartans face the No. 2 Duke Blue Devils for an NCAA game.")],
            myESPN2: [mp(2, "College Basketball",
                         summary: "The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA game.")],
        ]
        add(test, "upcomingGames", index: off, channelSet: "myTeams", channels: [myESPN, myESPN2],
            picked: ["ncaam.florida-gators"], programmes: summaryGames, now: now)
        add(test, "upcomingGames", index: off, channelSet: "myTeams", channels: [myESPN2, myESPN],
            picked: ["ncaam.duke-blue-devils"], programmes: summaryGames, now: now)

        // aGameWithoutSubtitleIsLabelledByItsTitle
        add("my:aGameWithoutSubtitleIsLabelledByItsTitle", "label", programme: mp(1, "Lakers vs. Celtics"))
        add("my:aGameWithoutSubtitleIsLabelledByItsTitle", "label",
            programme: mp(1, "NBA Basketball", "  Los Angeles Lakers at Boston Celtics "))
        add("my:aGameWithoutSubtitleIsLabelledByItsTitle", "label", programme: mp(1, "NBA Basketball", "   "))

        // pickingATeamListsItsUpcomingGames: MyTeamsTests.guide()'s programmes, on the channels its guide matches.
        test = "my:pickingATeamListsItsUpcomingGames"
        let nbaTV = "id:nbatv.us"
        let nflNetwork = "id:nflnetwork.us"
        let guideProgrammes = [
            nbaTV: [mp(-0.5, "NBA Basketball", "Miami Heat at Los Angeles Lakers", length: 3600),
                    mp(2, "NBA Basketball", "Los Angeles Lakers at Boston Celtics", length: 3600),
                    mp(80, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets", length: 3600)],
            nflNetwork: [mp(1, "NBA Replay", "Los Angeles Lakers at Utah Jazz", length: 3600),
                         mp(1.5, "NBA Basketball", "Boston Celtics at New York Knicks", length: 3600),
                         mp(5, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers", length: 3600)],
        ]
        add(test, "channelIDs", index: off, channelSet: "iptv", picked: ["nba.lal"],
            nowPlaying: [nbaTV: mp(-0.5, "NBA Basketball", "Miami Heat at Los Angeles Lakers", length: 3600)])
        add(test, "upcomingGames", index: off, channelSet: "iptv", channels: [nflNetwork, nbaTV], picked: ["nba.lal"],
            programmes: guideProgrammes, now: now)
        add(test, "channelIDs", index: off, channelSet: "iptv", picked: [], nowPlaying: [:])

        // The channel menu's and My Teams' matcher parts (MyTeamsTests.collegeGuide: on now on NBA TV).
        func onNow(_ title: String, subtitle: String? = nil, summary: String? = nil) -> TeamProgrammeGolden {
            programme(.plain(title), subtitle: subtitle.map { .plain($0) }, summary: summary.map { .plain($0) },
                      start: now - 1800, length: 3 * 3600)
        }
        let big12Basketball = onNow("College Basketball", summary: big12)
        test = "my:theChannelMenuOffersEachSidesTeamsPickedFirst"
        add(test, "teamsBySide", index: "bundled.nicknames", programme: big12Basketball)
        add(test, "networkChannelIDs", index: "bundled.nicknames", channelSet: "iptv", picked: ["ncaam.houston-cougars"],
            nowPlaying: [nbaTV: big12Basketball])
        test = "my:theChannelMenuOffersAtMostThreeTeamsASide"
        let plainCougars = onNow("College Basketball", summary: "The Cougars meet the Bearcats.")
        add(test, "teamsBySide", index: "bundled.nicknames", programme: plainCougars)
        add(test, "networkChannelIDs", index: "bundled.nicknames", channelSet: "iptv",
            picked: ["ncaam.washington-state-cougars"], nowPlaying: [nbaTV: plainCougars])
        test = "my:theChannelMenuOffersNoNicknameTeamsWithTheOptionOff"
        add(test, "teamsBySide", index: off, programme: big12Basketball)
        add(test, "networkChannelIDs", index: off, channelSet: "iptv", picked: ["ncaam.houston-cougars"],
            nowPlaying: [nbaTV: big12Basketball])
        test = "my:changingMatchInitialsRecomputesMyTeamsAndTheMenu"
        let ulmGame = onNow("College Football", subtitle: "ULM Warhawks at Troy Trojans")
        for index in [off, "bundled.initials"] {
            add(test, "teamsBySide", index: index, programme: ulmGame)
            add(test, "networkChannelIDs", index: index, channelSet: "iptv", picked: [ulm], nowPlaying: [nbaTV: ulmGame])
        }
        return all
    }

    // MARK: - Golden

    /// The golden as MMTVL's code writes it.
    static func make() -> TeamsGolden {
        var context = Context(indexes: indexes, teamSets: teamSets, channelSets: channelSets)
        let evaluated = cases.map { item -> TeamCaseGolden in
            var item = item
            item.expected = evaluate(item, in: &context)
            return item
        }
        return TeamsGolden(indexes: indexes, teamSets: teamSets.mapValues { $0.map(TeamEntryGolden.init) },
                           channelSets: channelSets, coverage: coverage, cases: evaluated)
    }

    /// The indexes, teams and channels the cases refer to, built on first use.
    struct Context {
        var indexes: [String: TeamIndexGolden]
        var teamSets: [String: [Team]]
        var channelSets: [String: TeamChannelSetGolden]
        var built: [String: TeamMatcher.Index] = [:]

        init(indexes: [String: TeamIndexGolden], teamSets: [String: [Team]], channelSets: [String: TeamChannelSetGolden]) {
            self.indexes = indexes
            self.teamSets = teamSets
            self.channelSets = channelSets
        }

        /// From a golden's own data.
        init(_ golden: TeamsGolden) {
            self.init(indexes: golden.indexes, teamSets: golden.teamSets.mapValues { $0.compactMap(\.team) },
                      channelSets: golden.channelSets)
        }

        mutating func index(_ name: String?) -> TeamMatcher.Index {
            let name = name ?? "bundled.off"
            if let index = built[name] { return index }
            let spec = indexes[name] ?? TeamIndexGolden(sets: ["pro", "college"], initials: false, nicknames: false)
            let teams = spec.sets.flatMap { set -> [Team] in
                switch set {
                case "pro": TeamCatalog.proTeams
                case "college": TeamCatalog.collegeTeams
                default: teamSets[set] ?? []
                }
            }
            let index = TeamMatcher.Index(teams: teams, options: TeamMatchOptions(initials: spec.initials,
                                                                                  nicknames: spec.nicknames))
            built[name] = index
            return index
        }

        func channels(_ set: String?, only ids: [String]? = nil) -> [Channel] {
            let all = (channelSets[set ?? ""]?.channels ?? []).map { channel in
                Channel(id: channel.id, number: 1, name: channel.name.string, group: channel.group, tvgID: nil, tvgName: nil,
                        logoURL: nil, streamURL: URL(string: "https://cdn.example/team.m3u8")!)
            }
            guard let ids else { return all }
            return ids.compactMap { id in all.first { $0.id == id } }
        }
    }

    static func ids(_ teams: [Team]) -> JSONValue { .strings(teams.map(\.id)) }

    static func game(_ game: TeamMatcher.Game?) -> JSONValue {
        guard let game else { return .null }
        let feed: JSONValue = switch game.feed {
        case .home?: .string("home")
        case .away?: .string("away")
        case nil: .null
        }
        return .object(["away": .string(game.away), "home": .string(game.home), "feed": feed])
    }

    /// What MMTVL's code gives for one case.
    static func evaluate(_ item: TeamCaseGolden, in context: inout Context) -> JSONValue {
        let index = context.index(item.index)
        let programme = item.programme?.programme
        let picked = Set(item.picked ?? [])
        let channels = context.channels(item.channelSet, only: item.channels)
        let channel = channels.first { $0.id == item.channel }
        let nowPlaying = (item.nowPlaying ?? [:]).mapValues(\.programme)
        let candidates = item.among.map { $0.compactMap { index.byID[$0] } } ?? index.teams
        switch item.op {
        case "leagueTeamCounts":
            return .object(Dictionary(uniqueKeysWithValues: TeamLeague.allCases.map { league in
                (league.rawValue, JSONValue.int(index.teams.count { $0.league == league }))
            }))
        case "teamNamedMany":
            return .array((item.texts ?? []).map { .optional(TeamMatcher.team(named: $0, index: index)?.id) })
        case "channels":
            return .array(channels.map { .object(["id": .string($0.id), "name": .string($0.name), "group": .string($0.group)]) })
        case "feedName":
            return .string(ChannelList.feedName(item.text?.string ?? ""))
        case "game":
            return game(TeamMatcher.game(from: item.text?.string ?? ""))
        case "gameEntry":
            return game(channel.flatMap { TeamMatcher.gameEntry($0, index: index) })
        case "isGameEntry":
            return .bool(channel.map { TeamMatcher.isGameEntry($0, index: index) } ?? false)
        case "gameEntries":
            return .strings(channels.filter { TeamMatcher.isGameEntry($0, index: index) }.map(\.id))
        case "teamsInGame":
            return ids(channel.map { TeamMatcher.teams(inGame: $0, index: index) } ?? [])
        case "gameChannelIDs":
            return .strings(TeamMatcher.gameChannelIDs(channels: channels, picked: picked, index: index))
        case "networkChannelIDs":
            return .strings(TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked,
                                                          index: index))
        case "channelIDs":
            return .strings(TeamMatcher.channelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked, index: index))
        case "teamsIn":
            return ids(programme.map { TeamMatcher.teams(in: $0, among: candidates, index: index) } ?? [])
        case "teamsBySide":
            return .array((programme.map { TeamMatcher.teamsBySide(in: $0, among: candidates, index: index) } ?? []).map(ids))
        case "isLiveGame":
            return .bool(programme.map { TeamMatcher.isLiveGame($0) } ?? false)
        case "collegeLeague":
            return .optional(programme.flatMap { TeamMatcher.collegeLeague(of: $0) }?.rawValue)
        case "collegeSides":
            return .strings(programme.map { TeamMatcher.collegeSides(of: $0) } ?? [])
        case "summarySides":
            return .strings(TeamMatcher.summarySides(of: item.text?.string ?? ""))
        case "summarySidesMany":
            return .array((item.texts ?? []).map { .strings(TeamMatcher.summarySides(of: $0)) })
        case "conferenceSearchText":
            return .string(programme.map { TeamMatcher.conferenceSearchText(of: $0) } ?? "")
        case "phrases":
            return .strings(TeamMatcher.Index.phrases(naming: item.conference ?? ""))
        case "bounded":
            guard let programme else { return .null }
            let bounded = TeamMatcher.bounded(programme)
            return .object(["title": .string(bounded.title), "subtitle": .optional(bounded.subtitle),
                            "category": .optional(bounded.category)])
        case "upcomingGames":
            var checks = 0
            let limit = item.cancelAfter
            let programmes = (item.programmes ?? [:]).mapValues { $0.map(\.programme) }
            let result = TeamMatcher.finishedUpcomingGames(
                channels: channels, programmes: programmes, picked: picked,
                now: Date(timeIntervalSince1970: TimeInterval(item.now ?? 0)), index: index,
                isCancelled: {
                    checks += 1
                    return limit.map { checks > $0 } ?? false
                })
            return .object([
                "finished": .bool(result != nil),
                "checks": .int(checks),
                "games": .array((result ?? []).map { game in
                    .object(["channel": .string(game.channel.id), "start": .int(Int(game.programme.start.timeIntervalSince1970)),
                             "label": .string(game.label)])
                }),
            ])
        case "label":
            guard let programme else { return .null }
            return .string(UpcomingTeamGame(channel: context.channels("myTeams")[0], programme: programme).label)
        case "pickTitle":
            return .optional(index.byID[item.team ?? ""]?.pickTitle)
        case "normalizedMany":
            return .strings((item.texts ?? []).map { TeamMatcher.normalized($0) })
        case "normalizedCodePoints":
            // One string: for each code c (4 hex digits each in `text`) where normalized("x" + c + "y") isn't
            // " x<c>y " (c kept as it is), "<code>:<result>", the entries joined by U+001F (never in a result).
            let hex = Array(item.text?.string ?? "")
            var entries: [String] = []
            for start in stride(from: 0, to: hex.count - 3, by: 4) {
                let code = String(hex[start..<start + 4])
                guard let value = UInt32(code, radix: 16), let scalar = Unicode.Scalar(value) else { continue }
                let c = String(Character(scalar))
                let result = TeamMatcher.normalized("x" + c + "y")
                if result != " x" + c + "y " { entries.append(code + ":" + result) }
            }
            return .string(entries.joined(separator: "\u{1F}"))
        case "collegeNamesKey":
            guard let league = TeamLeague(rawValue: item.league ?? ""),
                  let teams = index.collegeNames[league]?[item.key ?? ""] else { return .null }
            return ids(teams)
        case "collegeSchoolsKey":
            return index.collegeSchools[item.key ?? ""].map { .strings($0.sorted()) } ?? .null
        case "schoolWords":
            return index.collegeSchoolWords[item.team ?? ""].map { .strings($0.sorted()) } ?? .null
        case "conferences":
            return index.collegeConferences[item.team ?? ""].map { .strings($0) } ?? .null
        case "fallbackTablesEmpty":
            return .bool(index.collegeNicknames.isEmpty && index.collegeSchoolWords.isEmpty
                         && index.collegeConferences.isEmpty)
        case "indexFacts":
            return .object(["teamCount": .int(index.teams.count), "initials": .bool(index.options.initials),
                            "nicknames": .bool(index.options.nicknames), "maxNicknameWords": .int(index.maxNicknameWords)])
        case "team":
            guard let team = index.byID[item.team ?? ""] else { return .null }
            return .object(["abbreviations": .strings(team.abbreviations), "aliases": .strings(team.aliases)])
        default:
            return .string("unknown op \(item.op)")
        }
    }
}
