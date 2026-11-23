import Testing
@testable import MMTVL

struct SettingsPhoneRemoteTests {
    private func rowIDs(_ model: SettingsModel) -> [String] {
        model.sections.flatMap(\.rows).map(\.id)
    }

    @Test func rootRowShowsOnOff() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.row(id: "phoneRemote")?.value == "On")
        #expect(model.row(id: "phoneRemote")?.action == .push(.phoneRemote))

        var settings = AppSettings()
        settings.phoneRemoteEnabled = false
        let (off, _) = makeSettingsModel(settings: settings)
        off.open(.remoteInput)
        #expect(off.row(id: "phoneRemote")?.value == "Off")
    }

    @Test func pageRowsFollowTheStatus() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        #expect(model.pageTitle == "Phone Remote")
        // Enabled but not running: address, no pair row; no phones: no forget row.
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: false, problem: "Starting…")
        model.refreshStatus()
        #expect(rowIDs(model).contains("phone.address"))
        #expect(!rowIDs(model).contains("phone.pair"))
        #expect(!rowIDs(model).contains("phone.forget"))
        #expect(model.row(id: "phone.enabled")?.detail == "Starting…")
        #expect(model.row(id: "phone.address")?.value == "No network connection")

        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairedCount: 2, connectedCount: 1)
        model.refreshStatus()
        #expect(rowIDs(model).contains("phone.pair"))
        #expect(rowIDs(model).contains("phone.forget"))
        #expect(model.row(id: "phone.address")?.value == "http://192.168.1.20:8765")
        #expect(model.row(id: "phone.count")?.value == "2")
        #expect(model.row(id: "phone.count")?.detail == "1 connected now")
        #expect(model.row(id: "phone.accessibility")?.value == "Not Allowed")
    }

    @Test func toggleAppliesSetting() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.toggle(.phoneRemoteEnabled))
        #expect(recorder.appliedSettings.last?.phoneRemoteEnabled == false)
        #expect(model.row(id: "phone.enabled")?.value == "Off")
        #expect(!rowIDs(model).contains("phone.address"))
    }

    @Test func pairingFollowsThePairPage() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        #expect(recorder.pairingCalls.isEmpty)
        model.perform(.push(.pairPhone))
        #expect(recorder.pairingCalls == [true])
        model.press(.back)
        #expect(recorder.pairingCalls == [true, false])
        #expect(model.page == .phoneRemote)
    }

    @Test func resetEndsPairing() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        model.reset()
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func screenDidCloseEndsPairingOnlyWhilePairing() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.screenDidClose()
        #expect(recorder.pairingCalls.isEmpty)
        model.perform(.push(.pairPhone))
        model.screenDidClose()
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func pairPageShowsTheQRCode() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        #expect(model.accessory(for: model.page) == .symbol("iphone"))
        #expect(model.row(id: "pair.code")?.value == "—")

        let url = "http://192.168.1.20:8765/#pair=1234"
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairingCode: "1234", pairingURL: url, lastPairedName: "iPhone")
        model.refreshStatus()
        #expect(model.accessory(for: model.page) == .qrCode(url))
        #expect(model.row(id: "pair.code")?.value == "1234")
        #expect(model.row(id: "pair.done")?.title == "Paired \"iPhone\"")
        #expect(model.actionRowIDs == ["pair.close"])
    }

    /// Re-review L1: after too many wrong codes the page keeps the QR code and says the typed code is off.
    @Test func pairPageShowsTheCodeIsOff() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        let url = "http://192.168.1.20:8765/#pair=0123456789abcdef0123456789abcdef"
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairingCode: "1234", pairingURL: url, pairingCodeLocked: true)
        model.refreshStatus()
        #expect(model.accessory(for: model.page) == .qrCode(url))
        #expect(model.row(id: "pair.locked")?.title == "Pairing Code Off")
        #expect(model.row(id: "pair.locked")?.detail?.contains("Scan the QR code") == true)
        #expect(model.row(id: "pair.code") == nil)
        #expect(model.row(id: "pair.ended") == nil)
        #expect(model.actionRowIDs == ["pair.close"])
    }

    /// The pairing expired: the page says pairing ended; no code, no QR.
    @Test func pairPageShowsPairingEnded() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairingEnded: true)
        model.refreshStatus()
        #expect(model.row(id: "pair.ended")?.title == "Pairing Ended")
        #expect(model.row(id: "pair.code") == nil)
        #expect(model.accessory(for: model.page) == .symbol("iphone"))
        #expect(model.actionRowIDs == ["pair.close"])
    }

    @Test func forgetAllConfirms() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.confirmForgetPhones))
        model.perform(.forgetAllPhones)
        #expect(recorder.forgets == 1)
        #expect(model.page == .phoneRemote)
    }

    @Test func qrCodeImage() throws {
        let image = try #require(QRCodeImage.make("http://192.168.1.20:8765/#pair=1234"))
        #expect(image.width > 0)
        #expect(image.width % 10 == 0)
    }
}
