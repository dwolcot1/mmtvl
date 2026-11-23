import Testing
@testable import MMTVL

struct GuideViewHintTests {
    /// M7m L4: with a channel, Back goes back to it.
    @Test func watchHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: false, hasChannel: true)
                == "Select: watch · Left at now: channel options · Back: back to the channel")
        #expect(GuideView.hint(focus: .channel, isPicking: false, hasChannel: true)
                == "Select: options · Left: groups · Right: programmes · Back: back to the channel")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false, hasChannel: true) == "Select: show group · Back: close list")
        // M7l 8c: My Teams' Choose Teams and upcoming rows.
        #expect(GuideView.hint(focus: .grid, isPicking: false, row: .chooseTeams, hasChannel: true)
                == "Select: choose your teams · Left: groups · Back: back to the channel")
        #expect(GuideView.hint(focus: .channel, isPicking: false, row: .upcoming, hasChannel: true)
                == "Select: watch this channel · Left: groups · Back: back to the channel")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false, row: .upcoming, hasChannel: true)
                == "Select: show group · Back: close list")
    }

    /// M7m L4: with no channel, Back does nothing in the watch guide, so the hint doesn't mention it.
    @Test func watchHintsWithNoChannel() {
        #expect(GuideView.hint(focus: .grid, isPicking: false, hasChannel: false)
                == "Select: watch · Left at now: channel options")
        #expect(GuideView.hint(focus: .channel, isPicking: false, hasChannel: false)
                == "Select: options · Left: groups · Right: programmes")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false, hasChannel: false) == "Select: show group · Back: close list")
        #expect(GuideView.hint(focus: .grid, isPicking: false, row: .chooseTeams, hasChannel: false)
                == "Select: choose your teams · Left: groups")
        #expect(GuideView.hint(focus: .channel, isPicking: false, row: .upcoming, hasChannel: false)
                == "Select: watch this channel · Left: groups")
    }

    @Test func pickHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: true) == "Select: show in window · Left at now: channel · Back: cancel")
        #expect(GuideView.hint(focus: .channel, isPicking: true)
                == "Select: show in window · Left: groups · Right: programmes · Back: cancel")
        #expect(GuideView.hint(focus: .groups(2), isPicking: true) == "Select: show group · Back: close list")
        #expect(GuideView.hint(focus: .grid, isPicking: true, row: .upcoming)
                == "Select: show this channel in window · Left: groups · Back: cancel")
        // The picker's hints don't depend on a channel.
        #expect(GuideView.hint(focus: .grid, isPicking: true, hasChannel: true)
                == "Select: show in window · Left at now: channel · Back: cancel")
    }

    /// An empty Favorites' placeholder row: Select does nothing there, so the hint offers only Left (and Back).
    @Test func emptyFavoritesHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: false, row: .favoritesEmpty, hasChannel: true)
                == "Left: groups · Back: back to the channel")
        #expect(GuideView.hint(focus: .channel, isPicking: false, row: .favoritesEmpty, hasChannel: false)
                == "Left: groups")
        #expect(GuideView.hint(focus: .grid, isPicking: true, row: .favoritesEmpty) == "Left: groups · Back: cancel")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false, row: .favoritesEmpty, hasChannel: true)
                == "Select: show group · Back: close list")
    }
}
