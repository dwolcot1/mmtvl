import Foundation
import Testing
@testable import MMTVL

/// M6b L5, L11.
struct ChannelLineupTests {
    private static let nfl = "id:nflnetwork.us"
    private static let nba = "id:nbatv.us"
    private static let redZone = "name:red zone"

    private var channels: [Channel] {
        get throws { ChannelList.make(from: try M3UParser.parse(IPTVFixtures.playlist)) }
    }

    @Test func noPreferencesKeepsTheGroups() throws {
        let lineup = ChannelLineup(channels: try channels)
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.favorites.isEmpty)
        #expect(lineup.channels(in: "Favorites").isEmpty)
        #expect(lineup.visibleChannels.count == 5)
        #expect(lineup.channels(in: "All Channels").count == 5)
        #expect(lineup.channels(in: "NBA Games").map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat"])
        #expect(lineup.channels(in: "Nope").isEmpty)
    }

    @Test func favoritesComeFirstInTheOrderAdded() throws {
        let lineup = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: [Self.nba, Self.nfl]))
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NBA TV", "NFL Network"])
    }

    @Test func hiddenFavoriteIsNotAFavorite() throws {
        let lineup = ChannelLineup(channels: try channels,
                                   preferences: ChannelPreferences(favorites: [Self.nba, Self.nfl], hiddenChannels: [Self.nba]))
        #expect(lineup.favorites.map(\.name) == ["NFL Network"])
        #expect(!lineup.isVisible(Self.nba))
        #expect(lineup.isVisible(Self.nfl))
        #expect(!lineup.visibleChannels.contains { $0.id == Self.nba })
        #expect(!lineup.channels(in: "Live Channels").contains { $0.id == Self.nba })
    }

    @Test func hidingAGroup() throws {
        let lineup = ChannelLineup(channels: try channels, preferences: ChannelPreferences(hiddenGroups: ["NBA Games"]))
        // One visible group left, so no All Channels.
        #expect(lineup.groups == ["Favorites", "My Teams", "Live Channels"])
        #expect(lineup.visibleChannels.map(\.name) == ["NFL Network", "NBA TV", "Red Zone"])
        #expect(lineup.channels(in: "NBA Games").isEmpty)
    }

    @Test func unknownFavoritesAreIgnored() throws {
        let lineup = ChannelLineup(channels: try channels,
                                   preferences: ChannelPreferences(favorites: ["id:gone", Self.redZone]))
        #expect(lineup.favorites.map(\.name) == ["Red Zone"])
        let none = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: ["id:gone"]))
        #expect(none.groups.prefix(2) == ["Favorites", "My Teams"])
        #expect(none.channels(in: "Favorites").isEmpty)
    }

    // MARK: Favorites is always listed (2026-11-23)

    @Test func favoritesIsListedWithNoFavorites() throws {
        let lineup = ChannelLineup(channels: try channels)
        #expect(lineup.groups.first == "Favorites")
        #expect(lineup.favorites.isEmpty)
        #expect(lineup.favoritesGroupChannels.isEmpty)
        #expect(lineup.movableFavorites.isEmpty)
        // Only with a visible channel: none at all, no groups.
        #expect(ChannelLineup(channels: []).groups.isEmpty)
        let allHidden = ChannelLineup(channels: try channels,
                                      preferences: ChannelPreferences(hiddenGroups: ["Live Channels", "NBA Games"]))
        #expect(allHidden.visibleChannels.isEmpty)
        #expect(allHidden.groups.isEmpty)
    }

    // MARK: M7l 8b: live team games top Favorites

    @Test func teamChannelsComeFirstInFavorites() throws {
        let channels = try channels
        let games = channels.filter { $0.group == "NBA Games" }.map(\.id)
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.nfl])
        let lineup = ChannelLineup(channels: channels, preferences: preferences, teamChannelIDs: games)
        #expect(lineup.groups.prefix(3) == ["Favorites", "My Teams", "All Channels"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat", "NBA TV", "NFL Network"])
        // The My Teams group and the saved favorites are unchanged.
        #expect(lineup.channels(in: "My Teams").map(\.id) == games)
        #expect(lineup.favorites.map(\.name) == ["NBA TV", "NFL Network"])
        #expect(preferences.favorites == [Self.nba, Self.nfl])
    }

    @Test func aTeamChannelThatIsAFavoriteShowsOnceAtTheTop() throws {
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.redZone, Self.nfl])
        let lineup = ChannelLineup(channels: try channels, preferences: preferences, teamChannelIDs: [Self.nfl])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NFL Network", "NBA TV", "Red Zone"])
        #expect(lineup.favorites.map(\.name) == ["NBA TV", "Red Zone", "NFL Network"])
    }

    @Test func liveTeamGamesAloneMakeAFavoritesGroup() throws {
        let lineup = ChannelLineup(channels: try channels, teamChannelIDs: [Self.redZone])
        #expect(lineup.groups.prefix(2) == ["Favorites", "My Teams"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["Red Zone"])
        #expect(lineup.favorites.isEmpty)
        // Hidden team channels don't count.
        let hidden = ChannelLineup(channels: try channels, preferences: ChannelPreferences(hiddenChannels: [Self.redZone]),
                                   teamChannelIDs: [Self.redZone])
        #expect(hidden.groups.prefix(2) == ["Favorites", "My Teams"])
        #expect(hidden.channels(in: "Favorites").isEmpty)
    }

    @Test func withoutTeamGamesFavoritesIsAsBefore() throws {
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.nfl])
        let lineup = ChannelLineup(channels: try channels, preferences: preferences, teamChannelIDs: [])
        #expect(lineup == ChannelLineup(channels: try channels, preferences: preferences))
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NBA TV", "NFL Network"])
        #expect(lineup.channels(in: "Favorites") == lineup.favorites)
    }

    @Test func tolerantDecoding() throws {
        let json = #"{"favorites": 3, "hiddenGroups": ["x"]}"#
        let preferences = try JSONDecoder().decode(ChannelPreferences.self, from: Data(json.utf8))
        #expect(preferences == ChannelPreferences(hiddenGroups: ["x"]))
        #expect(try JSONDecoder().decode(ChannelPreferences.self, from: Data("{}".utf8)) == ChannelPreferences())
    }

    // MARK: M7j L3: the Antenna group

    @Test func antennaGroupComesAfterMyTeams() throws {
        let lineup = ChannelLineup(channels: try channels + AntennaFixtures.liveChannels(firstNumber: 6))
        #expect(lineup.groups == ["Favorites", "My Teams", "Antenna", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Antenna").map(\.name) == ["WSB-HD", "WAGA-HD", "WXIA-HD"])
        #expect(lineup.channels(in: "Antenna").map(\.displayNumber) == ["2.1", "5.1", "11.1"])
        let favorites = ChannelLineup(channels: try channels + AntennaFixtures.liveChannels(firstNumber: 6),
                                      preferences: ChannelPreferences(favorites: [Self.nba]))
        #expect(favorites.groups.prefix(3) == ["Favorites", "My Teams", "Antenna"])
    }

    @Test func allChannelsListsPlaylistThenAntenna() throws {
        let playlist = try channels
        let antenna = AntennaFixtures.liveChannels(firstNumber: 6)
        let lineup = ChannelLineup(channels: playlist + antenna)
        #expect(lineup.channels(in: "All Channels").map(\.id) == playlist.map(\.id) + ["antenna:2.1", "antenna:5.1", "antenna:11.1"])
        #expect(lineup.channels(in: "All Channels").map(\.number) == Array(1...8))
    }

    @Test func antennaOnlyHasMyTeamsAndAntenna() {
        let lineup = ChannelLineup(channels: AntennaFixtures.liveChannels())
        #expect(lineup.groups == ["Favorites", "My Teams", "Antenna"])
        #expect(lineup.channels(in: "Antenna").count == 3)
        #expect(lineup.channels(in: "All Channels").isEmpty)
    }

    @Test func hiddenAntennaGroupHidesThemEverywhere() throws {
        let preferences = ChannelPreferences(favorites: ["antenna:5.1", Self.nba], hiddenGroups: ["Antenna"])
        let lineup = ChannelLineup(channels: try channels + AntennaFixtures.liveChannels(firstNumber: 6),
                                   preferences: preferences, teamChannelIDs: ["antenna:2.1"])
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(!lineup.visibleChannels.contains { $0.isDirectStream })
        #expect(lineup.channels(in: "All Channels").count == 5)
        #expect(lineup.channels(in: "Antenna").isEmpty)
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NBA TV"])
        #expect(lineup.channels(in: "My Teams").isEmpty)
        #expect(!lineup.isVisible("antenna:5.1"))
    }

    @Test func playlistGroupNamedAntennaMergesAfterTheTuners() throws {
        let local = Channel(id: "name:local news", number: 6, name: "Local News", group: "Antenna", tvgID: nil,
                            tvgName: nil, logoURL: nil, streamURL: IPTVFixtures.streamURL(6))
        let lineup = ChannelLineup(channels: try channels + [local] + AntennaFixtures.liveChannels(firstNumber: 7))
        #expect(lineup.groups == ["Favorites", "My Teams", "Antenna", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Antenna").map(\.name) == ["WSB-HD", "WAGA-HD", "WXIA-HD", "Local News"])
        // A playlist with only an "Antenna" group: one group, no All Channels.
        let alone = ChannelLineup(channels: [local])
        #expect(alone.groups == ["Favorites", "My Teams", "Antenna"])
        #expect(alone.channels(in: "Antenna").map(\.name) == ["Local News"])
    }

    @Test func antennaFavoritesShowInFavorites() throws {
        let preferences = ChannelPreferences(favorites: ["antenna:5.1", Self.nba])
        let lineup = ChannelLineup(channels: try channels + AntennaFixtures.liveChannels(firstNumber: 6),
                                   preferences: preferences)
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["WAGA-HD", "NBA TV"])
        #expect(lineup.favorites.map(\.id) == ["antenna:5.1", Self.nba])
    }
}
