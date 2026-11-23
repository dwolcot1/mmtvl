import Testing
@testable import MMTVL

/// Settings → Plex (M7 L15).
struct SettingsPlexTests {
    @Test func rootRow() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "plex")?.value == "Not Signed In")
        #expect(model.row(id: "plex")?.action == .push(.plex))
        recorder.plex.isSignedIn = true
        model.refreshStatus()
        #expect(model.row(id: "plex")?.value == "Signed In")
        let ids = model.actionRowIDs
        // M7g L6: Plex follows Live TV.
        #expect(ids.firstIndex(of: "plex") == ids.firstIndex(of: "liveTV")! + 1)
    }

    @Test func signedOutPageOffersSignIn() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        #expect(recorder.plexRefreshes == 1)
        #expect(model.actionRowIDs == ["plex.signIn"])
        #expect(model.row(id: "plex.signIn")?.action == .push(.plexLink))
    }

    @Test func signedInPageRows() {
        let (model, recorder) = makeSettingsModel()
        recorder.plex = PlexSettingsStatus(isSignedIn: true, serverName: "Living Room",
                                           servers: [.init(id: "srv1", name: "Living Room", detail: "Yours")],
                                           statusLine: "Connected · 7 items", itemCount: 7)
        model.refreshStatus()
        model.perform(.push(.plex))
        #expect(model.row(id: "plex.server")?.value == "Living Room")
        #expect(model.row(id: "plex.server")?.action == nil)
        #expect(model.row(id: "plex.status")?.value == "Connected · 7 items")
        #expect(model.actionRowIDs == ["plex.signOut"])

        recorder.plex.servers.append(.init(id: "srv2", name: "Attic", detail: "Shared with you"))
        model.refreshStatus()
        #expect(model.row(id: "plex.server")?.action == .push(.plexServers))
    }

    @Test func linkPageSyncsTheCode() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        model.perform(.push(.plexLink))
        #expect(recorder.plexLinkingCalls == [true])
        #expect(model.row(id: "plexLink.code")?.value == "…")
        recorder.plex.linkCode = "AB12"
        recorder.plex.linkURL = PlexAPI.linkURL(code: "AB12")
        model.refreshStatus()
        #expect(model.row(id: "plexLink.code")?.value == "AB12")
        #expect(model.accessory(for: model.page) == .qrCode("https://plex.tv/link/?pin=AB12"))
        #expect(model.actionRowIDs == ["plexLink.cancel"])
        model.press(.back)
        #expect(recorder.plexLinkingCalls == [true, false])
    }

    @Test func goingHomeStopsLinking() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        model.perform(.push(.plexLink))
        model.screenDidClose()
        #expect(recorder.plexLinkingCalls == [true, false])
    }

    @Test func signingInWithOneServerReturnsToThePlexPage() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        model.perform(.push(.plexLink))
        recorder.plex = PlexSettingsStatus(isSignedIn: true, serverName: "Living Room",
                                           servers: [.init(id: "srv1", name: "Living Room", detail: "Yours")])
        model.refreshStatus()
        #expect(model.page == .plex)
        #expect(recorder.plexLinkingCalls == [true, false])
    }

    @Test func signingInWithSeveralServersShowsTheList() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        model.perform(.push(.plexLink))
        recorder.plex = PlexSettingsStatus(isSignedIn: true, servers: [
            .init(id: "srv1", name: "Attic", detail: "Yours"), .init(id: "srv2", name: "Zed", detail: "Shared with you"),
        ], needsServerChoice: true)
        model.refreshStatus()
        #expect(model.page == .plexServers)
        #expect(model.stack.count == 3)
        #expect(model.actionRowIDs == ["plexServer.srv1", "plexServer.srv2"])
        model.press(.down, .select)
        #expect(recorder.chosenPlexServers == ["srv2"])
        #expect(model.page == .plex)
    }

    @Test func signingInWithNoServerSaysSo() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.plex))
        model.perform(.push(.plexLink))
        recorder.plex = PlexSettingsStatus(isSignedIn: true, hasNoServer: true)
        model.refreshStatus()
        #expect(model.page == .plexLink)
        #expect(model.row(id: "plexLink.noServer")?.title == "No Plex Media Server on this account")
    }

    @Test func signOutAsksFirst() {
        let (model, recorder) = makeSettingsModel()
        recorder.plex = PlexSettingsStatus(isSignedIn: true, serverName: "Living Room")
        model.refreshStatus()
        model.perform(.push(.plex))
        model.activate(rowID: "plex.signOut")
        #expect(model.page == .confirmPlexSignOut)
        #expect(model.focusedRowID == "confirm.cancel")
        model.activate(rowID: "confirm.signOutOfPlex")
        #expect(recorder.plexSignOuts == 1)
        #expect(model.page == .plex)
    }
}
