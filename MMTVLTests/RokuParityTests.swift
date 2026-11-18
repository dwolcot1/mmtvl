import Foundation
import Testing
@testable import MMTVL

/// M12 step 5: the parity contract between MMTVL's Live TV and the Roku app (`roku/`).
///
/// The hand-written fixtures in `roku/tests/fixtures/` (a playlist, two XMLTV guides, an epg-overrides.json) go
/// through MMTVL's real code: `M3UParser.parse`, `ChannelList.make`/`feedName`, `XMLTVParser.parse` and
/// `EPGMatcher.match`. The results must equal the golden files next to them, which the Roku ports (steps 6 and 9)
/// must reproduce in BrightScript. The goldens are plain JSON for `ParseJson`: arrays and objects, `null` for a
/// missing value, times in **Unix seconds** (UTC), never Swift's 2001-based dates.
///
/// - `channels.golden.json`: `guideURLs` (the header's), `entries` (every `#EXTINF` entry as parsed, VOD included:
///   name, group or null, url, attributes with lowercased keys), `feedNames` (each entry's name through
///   `ChannelList.feedName`) and `channels` (id, number, name as shown, group, url, tvgID, tvgName, logo).
/// - `matches.golden.json`: `guides` (the fixture files in priority order) and `matches`: every channel id → `{guide:
///   <0-based priority index>, file, epgID}`, or null for no guide.
/// - `programmes.golden.json`: per guide, the channels `XMLTVParser` keeps (lowercased id, display-names as written),
///   `wantedIDs` (what the importer keeps programmes for: that guide alone matched, as `GuideImporter` does, sorted)
///   and the programmes kept in `window`, in file order.
///
/// When MMTVL's behaviour changes on purpose, regenerate the goldens, review the diff, and update the Roku ports:
///
///     TEST_RUNNER_MMTVL_WRITE_ROKU_GOLDENS=1 xcodebuild -project MMTVL.xcodeproj -scheme MMTVL \
///       -derivedDataPath build test -only-testing:MMTVLTests/RokuParityTests
///
/// (xcodebuild passes `TEST_RUNNER_<name>` to the test process as `<name>`.) With it set, the test writes the
/// goldens instead of comparing; by default it compares.
struct RokuParityTests {
    nonisolated static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "roku/tests/fixtures", directoryHint: .isDirectory)
    /// Priority order (guide A first).
    nonisolated static let guideFiles = ["guide-a.xml", "guide-b.xml"]
    /// 2026-10-05T00:00Z to 2026-10-07T00:00Z, as Unix seconds.
    nonisolated static let window = WindowGolden(start: 1_791_158_400, end: 1_791_331_200)
    nonisolated static var writesGoldens: Bool {
        ProcessInfo.processInfo.environment["MMTVL_WRITE_ROKU_GOLDENS"] == "1"
    }

    // MARK: - Tests

    @Test func fixturePlaylistKeepsItsBOMAndLineEndings() throws {
        let data = try Data(contentsOf: Self.fixtures.appending(path: "playlist.m3u"))
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.unicodeScalars.first == "\u{FEFF}")
        let crlf = text.components(separatedBy: "\r\n").count - 1
        let lf = text.unicodeScalars.filter { $0 == "\n" }.count
        #expect(crlf > 10)
        #expect(lf > crlf)
    }

    @Test func windowIsTheDocumentedOne() {
        #expect(Self.window.start == Int(utc(2026, 10, 5).timeIntervalSince1970))
        #expect(Self.window.end == Int(utc(2026, 10, 7).timeIntervalSince1970))
    }

    @Test func channelsMatchTheGolden() throws {
        let actual = try Self.channelsGolden(Self.playlist())
        try Self.check(actual, file: "channels.golden.json") { actual, golden in
            #expect(actual.guideURLs == golden.guideURLs)
            Self.compare(actual.entries, golden.entries, what: "entry")
            Self.compare(actual.feedNames, golden.feedNames, what: "feed name")
            Self.compare(actual.channels, golden.channels, what: "channel")
        }
    }

    @Test func matchesMatchTheGolden() throws {
        let channels = ChannelList.make(from: try Self.playlist())
        let sources = try Self.guideFiles.map { file in
            EPGSourceChannels(sourceID: file, channels: try Self.parse(file, wantedIDs: { _ in [] }).channels)
        }
        let matches = EPGMatcher.match(channels, sources: sources, overrides: try Self.overrides())
        var golden: [String: MatchGolden?] = [:]
        for channel in channels {
            golden[channel.id] = .some(matches[channel.id].map { ref in
                MatchGolden(guide: Self.guideFiles.firstIndex(of: ref.sourceID) ?? -1, file: ref.sourceID,
                            epgID: ref.epgID)
            })
        }
        let actual = MatchesGolden(guides: Self.guideFiles, matches: golden)
        try Self.check(actual, file: "matches.golden.json") { actual, golden in
            #expect(actual.guides == golden.guides)
            #expect(Set(actual.matches.keys) == Set(golden.matches.keys))
            for id in actual.matches.keys.sorted() {
                #expect(actual.matches[id] == golden.matches[id], "match for \(id)")
            }
        }
    }

    @Test func programmesMatchTheGolden() throws {
        let channels = ChannelList.make(from: try Self.playlist())
        let overrides = try Self.overrides()
        let guides = try Self.guideFiles.map { file in
            var wanted: Set<String> = []
            // As GuideImporter does: that guide alone, matched once at the first <programme>.
            let result = try Self.parse(file) { parsed in
                wanted = Set(EPGMatcher.match(channels, to: parsed, overrides: overrides).values)
                return wanted
            }
            return GuideGolden(
                file: file,
                wantedIDs: wanted.sorted(),
                channels: result.channels.map { ChannelNamesGolden(id: $0.id, names: $0.names) },
                programmes: result.programmes.map(ProgrammeGolden.init)
            )
        }
        let actual = ProgrammesGolden(window: Self.window, guides: guides)
        try Self.check(actual, file: "programmes.golden.json") { actual, golden in
            #expect(actual.window == golden.window)
            #expect(actual.guides.map(\.file) == golden.guides.map(\.file))
            for (a, g) in zip(actual.guides, golden.guides) {
                #expect(a.wantedIDs == g.wantedIDs, "wanted ids in \(a.file)")
                Self.compare(a.channels, g.channels, what: "\(a.file) channel")
                Self.compare(a.programmes, g.programmes, what: "\(a.file) programme")
            }
        }
    }

    // MARK: - MMTVL's code paths

    nonisolated static func playlist() throws -> M3UPlaylist {
        // As IPTVNetwork.fetchText decodes it (the BOM stays for M3UParser to strip).
        let data = try Data(contentsOf: fixtures.appending(path: "playlist.m3u"))
        return try M3UParser.parse(String(decoding: data, as: UTF8.self))
    }

    nonisolated static func overrides() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixtures.appending(path: "overrides.json")))
    }

    nonisolated static func parse(_ file: String,
                                  wantedIDs: ([EPGChannel]) -> Set<String>) throws -> XMLTVParser.Result {
        let interval = DateInterval(start: Date(timeIntervalSince1970: TimeInterval(window.start)),
                                    end: Date(timeIntervalSince1970: TimeInterval(window.end)))
        return try XMLTVParser.parse(fileURL: fixtures.appending(path: file), window: interval, wantedIDs: wantedIDs)
    }

    nonisolated static func channelsGolden(_ playlist: M3UPlaylist) throws -> ChannelsGolden {
        ChannelsGolden(
            guideURLs: playlist.guideURLs.map(\.absoluteString),
            entries: playlist.entries.map { EntryGolden(name: $0.name, group: $0.group, url: $0.url,
                                                         attributes: $0.attributes) },
            feedNames: playlist.entries.map { FeedNameGolden(input: $0.name, output: ChannelList.feedName($0.name)) },
            channels: ChannelList.make(from: playlist).map { channel in
                ChannelGolden(id: channel.id, number: channel.number, name: channel.name, group: channel.group,
                              url: channel.streamURL.absoluteString, tvgID: channel.tvgID, tvgName: channel.tvgName,
                              logo: channel.logoURL?.absoluteString)
            }
        )
    }

    // MARK: - Golden files

    /// Writes `actual` as the golden in write mode; else decodes the golden and runs `compare`.
    nonisolated static func check<T: Codable>(_ actual: T, file: String,
                                              compare: (T, T) -> Void) throws {
        let url = fixtures.appending(path: file)
        if writesGoldens {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(actual)
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
            return
        }
        let golden = try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        compare(actual, golden)
    }

    /// Element by element, so a failure names the item that differs.
    nonisolated static func compare<T: Equatable>(_ actual: [T], _ golden: [T], what: String) {
        #expect(actual.count == golden.count, "\(what) count")
        for (index, (a, g)) in zip(actual, golden).enumerated() {
            #expect(a == g, "\(what) \(index)")
        }
    }

    private func utc(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d))!
    }
}

// MARK: - Golden shapes (optionals encode as null, so every key is present)

nonisolated struct ChannelsGolden: Codable, Equatable {
    var guideURLs: [String]
    var entries: [EntryGolden]
    var feedNames: [FeedNameGolden]
    var channels: [ChannelGolden]
}

nonisolated struct EntryGolden: Codable, Equatable {
    var name: String
    var group: String?
    var url: String
    var attributes: [String: String]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(group, forKey: .group)
        try container.encode(url, forKey: .url)
        try container.encode(attributes, forKey: .attributes)
    }
}

nonisolated struct FeedNameGolden: Codable, Equatable {
    var input: String
    var output: String
}

nonisolated struct ChannelGolden: Codable, Equatable {
    var id: String
    var number: Int
    /// As shown: the feed name.
    var name: String
    var group: String
    var url: String
    var tvgID: String?
    var tvgName: String?
    var logo: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(group, forKey: .group)
        try container.encode(url, forKey: .url)
        try container.encode(tvgID, forKey: .tvgID)
        try container.encode(tvgName, forKey: .tvgName)
        try container.encode(logo, forKey: .logo)
    }
}

nonisolated struct MatchesGolden: Codable, Equatable {
    var guides: [String]
    /// Every channel id; null = no guide.
    var matches: [String: MatchGolden?]
}

nonisolated struct MatchGolden: Codable, Equatable {
    /// 0-based, in `guides` (priority) order.
    var guide: Int
    var file: String
    var epgID: String
}

nonisolated struct WindowGolden: Codable, Equatable {
    /// Unix seconds.
    var start: Int
    var end: Int
}

nonisolated struct ProgrammesGolden: Codable, Equatable {
    var window: WindowGolden
    var guides: [GuideGolden]
}

nonisolated struct GuideGolden: Codable, Equatable {
    var file: String
    var wantedIDs: [String]
    var channels: [ChannelNamesGolden]
    var programmes: [ProgrammeGolden]
}

nonisolated struct ChannelNamesGolden: Codable, Equatable {
    var id: String
    var names: [String]
}

nonisolated struct ProgrammeGolden: Codable, Equatable {
    var channelID: String
    /// Unix seconds.
    var start: Int
    var stop: Int
    var title: String
    var subtitle: String?
    var summary: String?
    var category: String?
    var episode: String?

    init(_ programme: Programme) {
        channelID = programme.channelID
        start = Int(programme.start.timeIntervalSince1970)
        stop = Int(programme.stop.timeIntervalSince1970)
        title = programme.title
        subtitle = programme.subtitle
        summary = programme.summary
        category = programme.category
        episode = programme.episode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(start, forKey: .start)
        try container.encode(stop, forKey: .stop)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(summary, forKey: .summary)
        try container.encode(category, forKey: .category)
        try container.encode(episode, forKey: .episode)
    }
}
