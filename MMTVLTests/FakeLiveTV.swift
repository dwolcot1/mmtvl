@testable import MMTVL

/// Records what the router asks Live TV to do.
final class FakeLiveTV: LiveTVHosting {
    var opens = 0
    /// The channel id of each open (nil = the last channel / Multiview).
    var openedChannelIDs: [Channel.ID?] = []
    var leaves = 0
    var handled: [RemoteCommand] = []
    var outcome: LiveTVOutcome = .handled

    func open(channelID: Channel.ID?) {
        calls.append("open")
        opens += 1
        openedChannelIDs.append(channelID)
    }
    /// The `keepingPreview` of each leave.
    var leavesKeepingPreview: [Bool] = []
    /// What a kept leave turns into a preview (nil = nothing playing).
    var playingChannelID: Channel.ID?

    func leave(keepingPreview: Bool) {
        calls.append("leave")
        leaves += 1
        leavesKeepingPreview.append(keepingPreview)
        if keepingPreview, let playingChannelID { previewChannelID = playingChannelID }
        // Like `LiveTVModel.leave`: a leave that keeps nothing stops the channel, so a later leave keeps nothing.
        if !keepingPreview { playingChannelID = nil }
    }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        handled.append(command)
        return outcome
    }

    // M7c L15.
    var previewChannelID: Channel.ID?
    var isPreviewPlaying = false
    var previewFailed = false
    var defaultPreviewChannelID: Channel.ID?
    var previewStarts: [Channel.ID] = []
    var previewStops = 0
    /// Every call, in order: "open", "leave", "start <id>", "stop".
    var calls: [String] = []

    func startPreview(channelID: Channel.ID) {
        calls.append("start \(channelID)")
        guard previewChannelID != channelID else { return }
        previewStarts.append(channelID)
        previewChannelID = channelID
    }

    /// M7m L17.
    var isShowingVideo = false

    var playlistChanges = 0
    func playlistDidChange() {
        calls.append("playlistDidChange")
        playlistChanges += 1
    }

    func stopPreview() {
        calls.append("stop")
        previewStops += 1
        previewChannelID = nil
        previewFailed = false
    }
}
