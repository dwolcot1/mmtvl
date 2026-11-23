import Foundation

/// `iptv-channels.json` (D10, M6b L5): favorites and hidden channels/groups. Ids not in the playlist are kept and
/// ignored, so a channel that comes back keeps its state. Hand-editable while MMTVL is quit.
nonisolated struct ChannelPreferences: Codable, Equatable, Sendable {
    static let fileName = "iptv-channels.json"

    /// Channel ids, in the order added.
    var favorites: [Channel.ID] = []
    var hiddenChannels: [Channel.ID] = []
    /// Group names as in the playlist (case-sensitive).
    var hiddenGroups: [String] = []
    /// M7f L13: picked team ids (`TeamCatalog`), in the order added.
    var teams: [Team.ID] = []

    init(favorites: [Channel.ID] = [], hiddenChannels: [Channel.ID] = [], hiddenGroups: [String] = [],
         teams: [Team.ID] = []) {
        self.favorites = favorites
        self.hiddenChannels = hiddenChannels
        self.hiddenGroups = hiddenGroups
        self.teams = teams
    }

    /// Per key: missing or undecodable reads as [].
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? container.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        hiddenChannels = (try? container.decodeIfPresent([String].self, forKey: .hiddenChannels)) ?? []
        hiddenGroups = (try? container.decodeIfPresent([String].self, forKey: .hiddenGroups)) ?? []
        teams = (try? container.decodeIfPresent([String].self, forKey: .teams)) ?? []
    }
}

/// M7l 8c: a picked team's game in the guide that starts within `TeamMatcher.upcomingWindow`: one row of the guide's
/// My Teams group, below the live channels. Select tunes `channel`.
nonisolated struct UpcomingTeamGame: Equatable, Hashable, Sendable {
    var channel: Channel
    var programme: Programme

    /// The row's text: the programme's subtitle ("Tampa Bay Buccaneers at Chicago Bears"), else its title.
    var label: String {
        if let subtitle = programme.subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty { return subtitle }
        return programme.title
    }

    /// "Sun 1:00 PM" (the user's locale).
    var dayTime: String {
        programme.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// What every Live TV list shows after favorites and hiding (M6b L11): the guide's groups and rows, zapping,
/// and the Multiview picker guide.
nonisolated struct ChannelLineup: Equatable, Sendable {
    static let favoritesGroup = "Favorites"
    /// M7f L13: live games and channels of the picked teams, right after Favorites. M7l 8c: "My Teams", always shown
    /// (with any visible channel), with Choose Teams and the upcoming games in the guide.
    static let teamsGroup = "My Teams"
    /// M7l 8c: the group's name before 8c; a remembered `lastGroup` of it reads as `teamsGroup`.
    static let legacyTeamsGroup = "Teams"
    /// M7l 8c: at most this many upcoming games in My Teams.
    static let maxUpcomingTeamGames = 30

    /// ["Favorites"] whenever a channel is visible, even with no favorites (the guide then shows one row saying how to
    /// add one; with any, they and the picked teams' live games, M7l 8b), ["My Teams"] whenever a channel is visible
    /// (M7l 8c), then `ChannelList.guideGroups(of: visibleChannels)` (M7j L3: Antenna, All Channels, the
    /// playlist's groups).
    private(set) var groups: [String]
    /// Playlist order, without hidden channels and hidden groups.
    private(set) var visibleChannels: [Channel]
    /// `preferences.favorites` order, visible only: the saved favorites (the home screen's Live TV pages and On Now
    /// shelf, the channel menu's Move Up/Down). Never includes the team channels.
    private(set) var favorites: [Channel]
    /// M7l 8b: the guide's Favorites group: `teams` (same order, every feed) first, then `favorites` not already
    /// listed, so a channel in both shows once, at the top.
    private(set) var favoritesGroupChannels: [Channel]
    /// M7l 8b: the saved favorites shown below the team channels in the Favorites group (`favorites` without the
    /// Teams channels), in saved order. Move Up/Down step among these, so each move visibly moves the row.
    private(set) var movableFavorites: [Channel]
    /// M7f L13: `TeamMatcher`'s order, visible only. The live games: My Teams' channels for zapping and Favorites.
    private(set) var teams: [Channel]
    /// M7l 8c: the upcoming games on visible channels, soonest first, at most `maxUpcomingTeamGames`. Only the
    /// guide's My Teams rows; never zapped through, never in Favorites.
    private(set) var upcomingTeamGames: [UpcomingTeamGame]

    init(channels: [Channel], preferences: ChannelPreferences = ChannelPreferences(), teamChannelIDs: [Channel.ID] = [],
         upcomingTeamGames: [UpcomingTeamGame] = []) {
        let hiddenChannels = Set(preferences.hiddenChannels)
        let hiddenGroups = Set(preferences.hiddenGroups)
        visibleChannels = channels.filter { !hiddenChannels.contains($0.id) && !hiddenGroups.contains($0.group) }
        let byID = Dictionary(visibleChannels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<Channel.ID> = []
        favorites = preferences.favorites.compactMap { id in seen.insert(id).inserted ? byID[id] : nil }
        var seenTeams: Set<Channel.ID> = []
        teams = teamChannelIDs.compactMap { id in seenTeams.insert(id).inserted ? byID[id] : nil }
        let teamIDs = Set(teams.map(\.id))
        movableFavorites = favorites.filter { !teamIDs.contains($0.id) }
        favoritesGroupChannels = teams + movableFavorites
        self.upcomingTeamGames = Array(upcomingTeamGames.compactMap { game in
            byID[game.channel.id].map { UpcomingTeamGame(channel: $0, programme: game.programme) }
        }.prefix(Self.maxUpcomingTeamGames))
        groups = (visibleChannels.isEmpty && favoritesGroupChannels.isEmpty ? [] : [Self.favoritesGroup])
            + (visibleChannels.isEmpty ? [] : [Self.teamsGroup])
            + ChannelList.guideGroups(of: visibleChannels)
    }

    /// Favorites (team channels first, M7l 8b), My Teams' live channels, All Channels, a group's visible channels;
    /// [] for an unknown group.
    func channels(in group: String) -> [Channel] {
        if group == Self.favoritesGroup { return favoritesGroupChannels }
        if group == Self.teamsGroup { return teams }
        guard groups.contains(group) else { return [] }
        return ChannelList.channels(in: group, of: visibleChannels)
    }

    /// M7l 8c: a remembered group name as the lineup knows it: "Teams" (before 8c) is "My Teams", unless the playlist
    /// has a group of that name.
    func resolvedGroup(_ name: String?) -> String? {
        guard name == Self.legacyTeamsGroup, !groups.contains(Self.legacyTeamsGroup) else { return name }
        return Self.teamsGroup
    }

    func isVisible(_ id: Channel.ID) -> Bool {
        visibleChannels.contains { $0.id == id }
    }
}
