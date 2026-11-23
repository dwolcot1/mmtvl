import Testing
@testable import MMTVL

/// M7h step 11: Receiver & TV (D44, L12, L17, L18); from step 13c Audio & TV → Receiver and → TV. Made-up private
/// addresses and MACs only.
struct SettingsReceiverTests {
    private static func settings(_ change: (inout AppSettings) -> Void) -> AppSettings {
        var settings = AppSettings()
        change(&settings)
        return settings
    }

    private static let pioneerSerial = settings {
        $0.receiverBrand = .pioneer
        $0.receiverSerialPort = "/dev/cu.usbserial-TEST1"
    }

    private static let pioneerNetwork = settings {
        $0.receiverBrand = .pioneer
        $0.receiverConnection = .network
        $0.receiverHost = "10.254.0.20"
    }

    private static let panasonic = settings {
        $0.tvBrand = .panasonic
        $0.tvHost = "10.254.0.40"
        $0.tvMAC = "02:00:5e:00:10:ab"
    }

    /// Root → Audio & TV → Receiver, as the remote would get there.
    private func onReceiverPage(_ settings: AppSettings = AppSettings()) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(settings: settings)
        model.open(.audioTV)
        model.open(.receiver)
        return (model, recorder)
    }

    /// Root → Audio & TV → TV.
    private func onTVPage(_ settings: AppSettings = AppSettings()) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(settings: settings)
        model.open(.audioTV)
        model.open(.tv)
        return (model, recorder)
    }

    // MARK: Audio & TV (step 13c)

    @Test func rootOpensAudioTVAfterCasting() {
        let (model, _) = makeSettingsModel()
        let ids = model.actionRowIDs
        #expect(ids.firstIndex(of: "audioTV") == ids.firstIndex(of: "casting")! + 1)
        #expect(ids.firstIndex(of: "remoteInput") == ids.firstIndex(of: "audioTV")! + 1)
        let row = model.row(id: "audioTV")
        #expect(row?.title == "Audio & TV")
        #expect(row?.showsDisclosure == true)
        #expect(row?.description == "The AV receiver for volume and power, the TV's power, and the volume display.")
        #expect(model.row(id: "remoteInput")?.description
            == "The Siri Remote, remote buttons, game controllers, the pointer and the phone remote.")
        model.focus(rowID: "audioTV")
        model.press(.select)
        #expect(model.page == .audioTV)
        #expect(model.pageTitle == "Audio & TV")
        #expect(model.parentSelectionRowID == "audioTV")
    }

    @Test func audioTVRowsWithNothingSetUp() {
        let (model, _) = makeSettingsModel()
        model.open(.audioTV)
        #expect(model.sections.map(\.id) == ["devices", "volume"])
        #expect(model.sections.map(\.title) == [nil, "Volume"])
        #expect(model.actionRowIDs == ["audioTV.receiver", "audioTV.tv", "receiver.showVolume"])
        let receiver = model.row(id: "audioTV.receiver")
        #expect(receiver?.title == "Receiver")
        #expect(receiver?.value == "Not Set Up")
        #expect(receiver?.showsDisclosure == true)
        #expect(receiver?.action == .push(.receiver))
        #expect(receiver?.description == "Volume, mute and power through the AV receiver, over a serial cable, the network or HDMI-CEC.")
        let tv = model.row(id: "audioTV.tv")
        #expect(tv?.title == "TV")
        #expect(tv?.value == "Not Set Up")
        #expect(tv?.showsDisclosure == true)
        #expect(tv?.action == .push(.tv))
        #expect(tv?.description == "Turning the TV on and off with the remote's Power button, and optionally its volume.")
    }

    @Test func audioTVValuesForAReceiverAndATV() {
        let (pioneer, _) = makeSettingsModel(settings: Self.pioneerSerial)
        pioneer.open(.audioTV)
        #expect(pioneer.row(id: "audioTV.receiver")?.value == "Pioneer")
        #expect(pioneer.row(id: "audioTV.tv")?.value == "Not Set Up")
        let (tvOnly, _) = makeSettingsModel(settings: Self.panasonic)
        tvOnly.open(.audioTV)
        #expect(tvOnly.row(id: "audioTV.receiver")?.value == "Not Set Up")
        #expect(tvOnly.row(id: "audioTV.tv")?.value == "VIERA")
        let (both, _) = makeSettingsModel(settings: Self.settings {
            $0.receiverBrand = .onkyo
            $0.tvBrand = .panasonic
        })
        both.open(.audioTV)
        #expect(both.row(id: "audioTV.receiver")?.value == "Onkyo")
        #expect(both.row(id: "audioTV.tv")?.value == "VIERA")
    }

    /// Back (and Left) return to Audio & TV on the row that opened the page, then to the root on Audio & TV.
    @Test func backReturnsThroughAudioTV() {
        let (model, _) = makeSettingsModel()
        model.focus(rowID: "audioTV")
        model.press(.select)
        model.press(.select)
        #expect(model.page == .receiver)
        #expect(model.parentSelectionRowID == "audioTV.receiver")
        model.press(.back)
        #expect(model.page == .audioTV)
        #expect(model.focusedRowID == "audioTV.receiver")
        model.press(.down, .right)
        #expect(model.page == .tv)
        #expect(model.parentSelectionRowID == "audioTV.tv")
        model.press(.left)
        #expect(model.page == .audioTV)
        #expect(model.focusedRowID == "audioTV.tv")
        model.press(.back)
        #expect(model.page == .root)
        #expect(model.focusedRowID == "audioTV")
    }

    @Test func brandNoneRows() {
        let (model, _) = onReceiverPage()
        #expect(model.pageTitle == "Receiver")
        #expect(model.sections.map(\.id) == ["receiver"])
        #expect(model.actionRowIDs == ["receiver.brand", "receiver.connection", "receiver.port", "receiver.find"])
        #expect(model.row(id: "receiver.brand")?.value == "None")
        #expect(model.row(id: "receiver.brand")?.action == .push(.receiverBrand))
        #expect(model.row(id: "receiver.connection")?.value == "Serial")
        #expect(model.row(id: "receiver.port")?.value == "Automatic")
        #expect(model.row(id: "receiver.find")?.title == "Find Receiver")
        #expect(model.row(id: "receiver.showVolume") == nil)
        #expect(model.row(id: "tv.brand") == nil)
        #expect(model.sections.first?.footer == "Volume buttons go to the receiver while it answers.")
    }

    @Test func pioneerSerialRows() {
        let (model, recorder) = makeSettingsModel(settings: Self.pioneerSerial)
        recorder.receiver = ReceiverSettingsStatus(
            state: ReceiverState(power: true, volume: ReceiverVolume(raw: 61, dB: -20), muted: false),
            isConnected: true, isAnswering: true)
        model.refreshStatus()
        model.open(.audioTV)
        model.open(.receiver)
        #expect(model.sections.map(\.id) == ["receiver"])
        #expect(model.actionRowIDs == ["receiver.brand", "receiver.connection", "receiver.port", "receiver.test",
                                          "receiver.find", "receiver.maxVolume"])
        #expect(model.sections.first?.rows.last?.id == "receiver.status")
        #expect(model.row(id: "receiver.brand")?.value == "Pioneer")
        #expect(model.row(id: "receiver.port")?.value == "cu.usbserial-TEST1")
        #expect(model.row(id: "receiver.address") == nil)
        #expect(model.row(id: "receiver.test")?.action == .testReceiver)
        #expect(model.row(id: "receiver.find")?.action == .findReceiver)
        #expect(model.row(id: "receiver.status")?.value == "On · \u{2212}20 dB · Not muted")
        #expect(model.row(id: "receiver.status")?.action == nil)
    }

    @Test func networkShowsAddressInsteadOfSerialPort() {
        let (model, _) = onReceiverPage(Self.pioneerNetwork)
        #expect(model.row(id: "receiver.connection")?.value == "Network")
        #expect(model.row(id: "receiver.port") == nil)
        #expect(model.row(id: "receiver.address")?.value == "10.254.0.20")
        #expect(model.row(id: "receiver.address")?.action == .push(.addressEntry(.receiver)))
        #expect(model.row(id: "receiver.find")?.title == "Find on Network")
        let (noHost, _) = onReceiverPage(Self.settings {
            $0.receiverBrand = .denon
            $0.receiverConnection = .network
        })
        #expect(noHost.row(id: "receiver.address")?.value == "Not Set")
    }

    /// Step 9c: three values, so Connection is a list (Serial / Network / HDMI-CEC).
    @Test func connectionIsAList() {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        #expect(model.row(id: "receiver.connection")?.action == .push(.receiverConnection))
        #expect(model.row(id: "receiver.connection")?.showsDisclosure == true)
        model.activate(rowID: "receiver.connection")
        #expect(model.page == .receiverConnection)
        #expect(model.pageTitle == "Connection")
        #expect(model.actionRowIDs == ["connection.serial", "connection.network", "connection.cec"])
        #expect(model.row(id: "connection.serial")?.value == "Selected")
        #expect(model.row(id: "connection.cec")?.title == "HDMI-CEC")
        #expect(model.row(id: "connection.cec")?.detail == "Through the Mac's HDMI; no volume in dB")
        model.activate(rowID: "connection.network")
        #expect(recorder.appliedSettings.last?.receiverConnection == .network)
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.connection")?.value == "Network")
        model.activate(rowID: "receiver.connection")
        model.activate(rowID: "connection.cec")
        #expect(recorder.appliedSettings.last?.receiverConnection == .cec)
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.connection")?.value == "HDMI-CEC")
    }

    @Test func statusRowWithoutAnswers() {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        #expect(model.row(id: "receiver.status")?.value == "Not connected")
        recorder.receiver = ReceiverSettingsStatus(isConnected: true)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "Waiting for an answer")
        recorder.receiver = ReceiverSettingsStatus(lastError: "Connection refused")
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "Connection refused")
        recorder.receiver = ReceiverSettingsStatus(state: ReceiverState(power: false), isConnected: true)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "Standby · Not answering")
    }

    // MARK: Brand and port lists

    @Test func brandListSavesReceiverBrand() {
        let (model, recorder) = onReceiverPage()
        model.activate(rowID: "receiver.brand")
        #expect(model.page == .receiverBrand)
        // Step 13c: a page takes the title of the row that opened it.
        #expect(model.pageTitle == "Brand")
        #expect(model.actionRowIDs == ReceiverBrand.allCases.map { "brand.\($0.rawValue)" })
        #expect(model.row(id: "brand.none")?.value == "Selected")
        #expect(model.row(id: "brand.pioneer")?.title == "Pioneer")
        #expect(model.row(id: "brand.pioneer")?.detail == "Before 2016")
        #expect(model.row(id: "brand.onkyo")?.title == "Onkyo / Integra / Pioneer")
        #expect(model.row(id: "brand.onkyo")?.detail == "2016 and later")
        #expect(model.row(id: "brand.denon")?.title == "Denon / Marantz")
        #expect(model.row(id: "brand.denon")?.detail == "2010 and later")
        #expect(model.row(id: "brand.yamaha")?.detail == "2010–2020")
        #expect(model.row(id: "brand.anthem")?.detail == nil)
        #expect(model.row(id: "brand.nad")?.title == "NAD")
        #expect(model.sections.first?.footer == "Tested with Pioneer. Serial cables: Pioneer needs a null-modem cable, Denon, Marantz and Onkyo a straight one.")

        model.activate(rowID: "brand.pioneer")
        #expect(recorder.appliedSettings.last?.receiverBrand == .pioneer)
        #expect(model.settings.receiverBrand == .pioneer)
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.brand")?.value == "Pioneer")
    }

    @Test func choosingTheSameBrandSavesNothing() {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        model.open(.receiverBrand)
        model.activate(rowID: "brand.pioneer")
        #expect(recorder.appliedSettings.isEmpty)
        #expect(model.page == .receiver)
    }

    @Test func serialPortList() {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        recorder.serialPorts = [SerialPortInfo(path: "/dev/cu.usbserial-TEST2", usbProductName: "FT232R USB UART"),
                                SerialPortInfo(path: "/dev/cu.debug-console", usbProductName: nil)]
        model.activate(rowID: "receiver.port")
        #expect(recorder.serialPortReads == 1)
        #expect(model.page == .receiverPort)
        #expect(model.actionRowIDs == ["port.automatic", "port./dev/cu.usbserial-TEST2", "port./dev/cu.debug-console",
                                          "port./dev/cu.usbserial-TEST1"])
        #expect(model.row(id: "port.automatic")?.value == nil)
        #expect(model.row(id: "port./dev/cu.usbserial-TEST2")?.title == "cu.usbserial-TEST2")
        #expect(model.row(id: "port./dev/cu.usbserial-TEST2")?.detail == "USB serial port (FT232R USB UART)")
        // The configured port isn't plugged in: still listed, selected.
        #expect(model.row(id: "port./dev/cu.usbserial-TEST1")?.value == "Selected")
        #expect(model.row(id: "port./dev/cu.usbserial-TEST1")?.detail == "Not connected")

        model.activate(rowID: "port./dev/cu.usbserial-TEST2")
        #expect(recorder.appliedSettings.last?.receiverSerialPort == "/dev/cu.usbserial-TEST2")
        #expect(model.page == .receiver)
        model.open(.receiverPort)
        model.activate(rowID: "port.automatic")
        #expect(recorder.appliedSettings.last?.receiverSerialPort == nil)
        #expect(model.row(id: "receiver.port")?.value == "Automatic")
    }

    @Test func noSerialPorts() {
        let (model, _) = onReceiverPage()
        model.open(.receiverPort)
        #expect(model.row(id: "port.automatic")?.value == "Selected")
        #expect(model.row(id: "port.none")?.title == "No serial ports found")
        #expect(model.actionRowIDs == ["port.automatic"])
    }

    // MARK: Test Connection (L12)

    @Test func testConnectionShowsTheReplies() async {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        recorder.receiverTestOutcome = ReceiverTestOutcome(
            replies: ReceiverState(power: true, volume: ReceiverVolume(raw: 61, dB: -20), muted: false))
        model.activate(rowID: "receiver.test")
        #expect(model.row(id: "receiver.test")?.detail == "Testing…")
        #expect(model.isProbeRunning(.testReceiver))
        // A second Select while it runs does nothing.
        model.activate(rowID: "receiver.test")
        await model.probeTasks[.testReceiver]?.value
        #expect(recorder.receiverTests == 1)
        #expect(!model.isProbeRunning(.testReceiver))
        #expect(model.row(id: "receiver.test")?.detail == "On · \u{2212}20 dB · Not muted")
    }

    @Test func testConnectionShowsTheError() async {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        recorder.receiverTestOutcome = ReceiverTestOutcome(error: "Connection refused")
        model.activate(rowID: "receiver.test")
        await model.probeTasks[.testReceiver]?.value
        #expect(model.row(id: "receiver.test")?.detail == "Connection refused")
        recorder.receiverTestOutcome = ReceiverTestOutcome()
        model.activate(rowID: "receiver.test")
        await model.probeTasks[.testReceiver]?.value
        #expect(model.row(id: "receiver.test")?.detail == "No answer")
    }

    @Test func testResultText() {
        #expect(SettingsModel.receiverTestLine(ReceiverTestOutcome()) == "No answer")
        #expect(SettingsModel.receiverTestLine(ReceiverTestOutcome(error: "No serial port found")) == "No serial port found")
        // Replies win over an error.
        #expect(SettingsModel.receiverTestLine(ReceiverTestOutcome(replies: ReceiverState(power: false), error: "x"))
            == "Standby")
        #expect(SettingsModel.receiverStatusLine(ReceiverState()) == nil)
        #expect(SettingsModel.receiverStatusLine(ReceiverState(volume: ReceiverVolume(raw: 0, dB: -.infinity), muted: true))
            == "Volume Min · Muted")
        // Onkyo: a level, no dB.
        #expect(SettingsModel.receiverStatusLine(ReceiverState(power: true, volume: ReceiverVolume(raw: 45, dB: nil)))
            == "On · Volume 45")
        #expect(SettingsModel.receiverStatusLine(ReceiverState(volume: ReceiverVolume(raw: 166, dB: 2.5)))
            == "+2.5 dB")
    }

    @Test func changingTheBrandDropsARunningTest() async {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        recorder.receiverTestOutcome = ReceiverTestOutcome(error: "No answer")
        model.activate(rowID: "receiver.test")
        let task = model.probeTasks[.testReceiver]
        model.perform(.setReceiverBrand(.denon))
        #expect(model.row(id: "receiver.test")?.detail == nil)
        await task?.value
        #expect(model.row(id: "receiver.test")?.detail == nil)
        #expect(!model.isProbeRunning(.testReceiver))
    }

    // MARK: Find (L12, L17)

    @Test func findOnSerialSetsTheBrand() async {
        let (model, recorder) = onReceiverPage(Self.settings { $0.receiverSerialPort = "/dev/cu.usbserial-TEST1" })
        recorder.serialFindResult = .pioneer
        model.activate(rowID: "receiver.find")
        #expect(model.row(id: "receiver.find")?.detail == "Searching…")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.serialFinds == ["/dev/cu.usbserial-TEST1"])
        #expect(recorder.appliedSettings.last?.receiverBrand == .pioneer)
        #expect(model.row(id: "receiver.brand")?.value == "Pioneer")
        #expect(model.row(id: "receiver.find")?.detail == "Found Pioneer")
    }

    @Test func findOnSerialWithNoAnswer() async {
        let (model, recorder) = onReceiverPage()
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.serialFinds == [nil])
        #expect(recorder.appliedSettings.isEmpty)
        #expect(model.row(id: "receiver.find")?.detail == "No receiver answered")
    }

    @Test func findOnNetworkWithNoneSaysSo() async {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.networkFinds == [nil])
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.find")?.detail == "No receivers found")
    }

    @Test func findOnNetworkListsTheReceiversToChoose() async {
        var settings = Self.pioneerNetwork
        settings.receiverNetworkPort = 8102
        let (model, recorder) = onReceiverPage(settings)
        recorder.networkFindResult = [
            FoundReceiver(brand: .pioneer, model: "VSX-1021", name: "Living Room", host: "10.254.0.21", port: 23),
            FoundReceiver(brand: .onkyo, model: "TX-NR686", name: nil, host: "10.254.0.22", port: 60129),
        ]
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.networkFinds == [8102])
        #expect(model.page == .receiverFound)
        #expect(model.pageTitle == "Receivers Found")
        #expect(model.actionRowIDs == ["found.10.254.0.21:23", "found.10.254.0.22:60129"])
        #expect(model.row(id: "found.10.254.0.21:23")?.title == "Living Room")
        #expect(model.row(id: "found.10.254.0.21:23")?.detail == "Pioneer · 10.254.0.21")
        #expect(model.row(id: "found.10.254.0.22:60129")?.title == "TX-NR686")
        #expect(model.row(id: "found.10.254.0.22:60129")?.detail == "Onkyo / Integra / Pioneer · 10.254.0.22:60129")

        // Not the brand's own port: kept.
        model.activate(rowID: "found.10.254.0.22:60129")
        #expect(model.page == .receiver)
        let saved = recorder.appliedSettings.last
        #expect(saved?.receiverBrand == .onkyo)
        #expect(saved?.receiverConnection == .network)
        #expect(saved?.receiverHost == "10.254.0.22")
        #expect(saved?.receiverNetworkPort == 60129)

        // The brand's own port: no override.
        model.perform(.useFoundReceiver(recorder.networkFindResult[0]))
        #expect(recorder.appliedSettings.last?.receiverBrand == .pioneer)
        #expect(recorder.appliedSettings.last?.receiverHost == "10.254.0.21")
        #expect(recorder.appliedSettings.last?.receiverNetworkPort == nil)
    }

    @Test func findOnNetworkWithBrandNone() async {
        let (model, recorder) = onReceiverPage(Self.settings { $0.receiverConnection = .network })
        recorder.networkFindResult = [FoundReceiver(brand: .denon, model: nil, name: "AVR", host: "10.254.0.23", port: 23)]
        #expect(model.row(id: "receiver.test") == nil)
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(model.page == .receiverFound)
        model.activate(rowID: "found.10.254.0.23:23")
        #expect(recorder.appliedSettings.last?.receiverBrand == .denon)
        #expect(model.row(id: "receiver.find")?.detail == nil)
    }

    // MARK: Maximum Volume (step 10)

    @Test func maximumVolumeRowAndList() {
        let (model, recorder) = onReceiverPage(Self.pioneerSerial)
        #expect(model.row(id: "receiver.maxVolume")?.value == "0 dB")
        #expect(model.row(id: "receiver.maxVolume")?.detail == nil)
        #expect(model.row(id: "receiver.maxVolume")?.action == .push(.receiverMaxVolume))
        model.activate(rowID: "receiver.maxVolume")
        #expect(model.page == .receiverMaxVolume)
        #expect(model.actionRowIDs.count == 9)
        #expect(model.row(id: "maxVolume.-30.0")?.title == "\u{2212}30 dB")
        #expect(model.row(id: "maxVolume.10.0")?.title == "+10 dB")
        #expect(model.row(id: "maxVolume.0.0")?.value == "Selected")
        model.activate(rowID: "maxVolume.-10.0")
        #expect(recorder.appliedSettings.last?.receiverMaxDB == -10)
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.maxVolume")?.value == "\u{2212}10 dB")
    }

    @Test func maximumVolumeKeepsAHandEditedValue() {
        var settings = Self.pioneerSerial
        settings.receiverMaxDB = -12.5
        let (model, _) = onReceiverPage(settings)
        model.open(.receiverMaxVolume)
        #expect(model.actionRowIDs.count == 10)
        #expect(model.row(id: "maxVolume.-12.5")?.value == "Selected")
        #expect(model.actionRowIDs.firstIndex(of: "maxVolume.-12.5") == model.actionRowIDs.firstIndex(of: "maxVolume.-15.0")! + 1)
    }

    @Test func onkyoCantBeCapped() {
        let (model, _) = onReceiverPage(Self.settings { $0.receiverBrand = .onkyo })
        #expect(model.row(id: "receiver.maxVolume")?.detail == "Onkyo receivers don't report dB, so there's no limit")
        model.open(.receiverMaxVolume)
        #expect(model.sections.first?.footer?.hasSuffix("Onkyo receivers don't report dB, so there's no limit.") == true)
    }

    // MARK: Show Volume (step 13b; on Audio & TV from step 13c)

    @Test func showVolumeRowIsOnAudioTV() {
        let (model, recorder) = makeSettingsModel()
        model.open(.audioTV)
        let row = model.row(id: "receiver.showVolume")
        #expect(row?.title == "Show Volume")
        #expect(row?.value == "On")
        #expect(row?.action == .toggle(.volumeToast))
        #expect(row?.description == "Shows the volume at the top of the screen when you press a volume button. Messages about volume not working always show.")
        #expect(model.sections.last?.rows.map(\.id) == ["receiver.showVolume"])
        model.activate(rowID: "receiver.showVolume")
        #expect(recorder.appliedSettings.last?.volumeToast == false)
        #expect(model.row(id: "receiver.showVolume")?.value == "Off")
        #expect(model.page == .audioTV)
        model.activate(rowID: "receiver.showVolume")
        #expect(recorder.appliedSettings.last?.volumeToast == true)
        #expect(model.row(id: "receiver.showVolume")?.value == "On")
    }

    @Test func showVolumeIsOnAudioTVForAReceiverToo() {
        var settings = Self.pioneerSerial
        settings.volumeToast = false
        let (model, recorder) = makeSettingsModel(settings: settings)
        model.open(.audioTV)
        #expect(model.actionRowIDs == ["audioTV.receiver", "audioTV.tv", "receiver.showVolume"])
        #expect(model.row(id: "receiver.showVolume")?.value == "Off")
        model.activate(rowID: "receiver.showVolume")
        #expect(recorder.appliedSettings.last?.volumeToast == true)
        #expect(recorder.appliedSettings.last?.receiverBrand == .pioneer)
        #expect(model.row(id: "receiver.showVolume")?.value == "On")
        model.open(.receiver)
        #expect(model.row(id: "receiver.showVolume") == nil)
    }

    // MARK: TV (L18)

    @Test func tvNoneAndPanasonicRows() {
        let (none, _) = onTVPage()
        #expect(none.pageTitle == "TV")
        #expect(none.sections.map(\.id) == ["tv"])
        #expect(none.sections.last?.rows.map(\.id) == ["tv.brand"])
        #expect(none.row(id: "tv.brand")?.title == "Brand")
        #expect(none.row(id: "tv.brand")?.value == "None")
        #expect(none.row(id: "receiver.brand") == nil)
        // Build 25 QA minor: the VIERA setup footer only for a Panasonic TV.
        #expect(none.sections.first { $0.id == "tv" }?.footer == nil)
        let (model, _) = onTVPage(Self.panasonic)
        #expect(model.sections.first { $0.id == "tv" }?.footer == "Turn on TV Remote App and Wake on LAN in the TV's Network settings. The TV must be on Ethernet to turn on from MMTVL.")
        let (cec, _) = onTVPage(Self.settings { $0.tvBrand = .cec })
        #expect(cec.sections.first { $0.id == "tv" }?.footer == "MMTVL shares the Mac's HDMI-CEC with macOS. Turning off also turns off receivers that follow HDMI-CEC.")
        #expect(model.sections.last?.rows.map(\.id) == ["tv.brand", "tv.address", "tv.find", "tv.test", "tv.mac", "tv.volume"])
        #expect(model.row(id: "tv.brand")?.value == "Panasonic VIERA")
        #expect(model.row(id: "tv.address")?.value == "10.254.0.40")
        #expect(model.row(id: "tv.address")?.action == .push(.addressEntry(.tv)))
        #expect(model.row(id: "tv.mac")?.value == "02:00:5e:00:10:ab")
        #expect(model.row(id: "tv.mac")?.action == nil)
        let (noMAC, _) = onTVPage(Self.settings { $0.tvBrand = .panasonic })
        #expect(noMAC.row(id: "tv.address")?.value == "Not Set")
        #expect(noMAC.row(id: "tv.mac")?.value == "Not Set")
        #expect(noMAC.row(id: "tv.mac")?.detail == "MMTVL can't turn the TV on without it; Find TV fills it in")
    }

    @Test func tvBrandList() {
        let (model, recorder) = onTVPage()
        model.activate(rowID: "tv.brand")
        #expect(model.page == .tvBrand)
        #expect(model.pageTitle == "Brand")
        #expect(model.actionRowIDs == ["tvBrand.none", "tvBrand.panasonic", "tvBrand.cec"])
        #expect(model.row(id: "tvBrand.cec")?.title == "HDMI-CEC")
        #expect(model.row(id: "tvBrand.cec")?.detail == "Any TV, through the Mac's HDMI. Also turns a CEC receiver off and on.")
        #expect(model.row(id: "tvBrand.panasonic")?.title == "Panasonic VIERA")
        #expect(model.row(id: "tvBrand.panasonic")?.detail == "2012–2018, network")
        model.activate(rowID: "tvBrand.panasonic")
        #expect(recorder.appliedSettings.last?.tvBrand == .panasonic)
        #expect(model.page == .tv)
        #expect(model.row(id: "tv.find") != nil)
    }

    // MARK: TV over HDMI-CEC (step 9, reopened)

    @Test func cecRowsHaveNoAddressFindOrMAC() {
        let (model, recorder) = onTVPage(Self.settings {
            $0.tvBrand = .cec
            $0.tvHost = "10.254.0.40"   // left from VIERA: not shown, not used
        })
        #expect(recorder.cecRefreshes == 1)   // opening the page checks the tunnel (read-only)
        #expect(model.sections.last?.rows.map(\.id) == ["tv.brand", "tv.test", "tv.status", "tv.volume"])
        #expect(model.actionRowIDs == ["tv.brand", "tv.test", "tv.volume"])
        #expect(model.row(id: "tv.brand")?.value == "HDMI-CEC")
        #expect(model.row(id: "tv.status")?.value == "Checking…")
        #expect(model.row(id: "tv.status")?.action == nil)
        #expect(model.sections.last?.footer == "MMTVL shares the Mac's HDMI-CEC with macOS. Turning off also turns off receivers that follow HDMI-CEC.")
        recorder.cec = .ready
        model.refreshStatus()
        #expect(model.row(id: "tv.status")?.value == "Ready")
        recorder.cec = .notAvailable
        model.refreshStatus()
        #expect(model.row(id: "tv.status")?.value == "HDMI-CEC not available on this display")
        recorder.cec = .noDisplay
        model.refreshStatus()
        #expect(model.row(id: "tv.status")?.value == "No HDMI display")
    }

    @Test func choosingCECChecksTheTunnel() {
        let (model, recorder) = onTVPage(Self.panasonic)
        model.activate(rowID: "tv.brand")
        model.activate(rowID: "tvBrand.cec")
        #expect(recorder.appliedSettings.last?.tvBrand == .cec)
        #expect(recorder.cecRefreshes == 1)
        #expect(model.page == .tv)
        #expect(model.row(id: "tv.find") == nil)
        #expect(model.row(id: "tv.status") != nil)
        // The Audio & TV row names it.
        model.press(.back)
        #expect(model.row(id: "audioTV.tv")?.value == "HDMI-CEC")
    }

    @Test func cecTestTVHasThreeAnswers() async {
        for (status, line) in [(CECPowerStatus.on, "On"), (.standbyToOn, "On"), (.standby, "Standby"),
                               (.onToStandby, "Standby"), (nil, "No answer")] as [(CECPowerStatus?, String)] {
            let (model, recorder) = onTVPage(Self.settings { $0.tvBrand = .cec })
            recorder.cecTestResult = status
            model.activate(rowID: "tv.test")
            #expect(model.row(id: "tv.test")?.detail == "Testing…")
            await model.probeTasks[.testTV]?.value
            #expect(model.row(id: "tv.test")?.detail == line)
            #expect(recorder.cecTests == 1)
            #expect(recorder.tvTests == 0)   // never the network TV's test
        }
    }

    @Test func testTVText() async {
        let (model, recorder) = onTVPage(Self.panasonic)
        recorder.tvTestResult = TVTestResult(isOn: true, volume: 12, isMuted: false, canTurnOn: true)
        model.activate(rowID: "tv.test")
        #expect(model.row(id: "tv.test")?.detail == "Testing…")
        await model.probeTasks[.testTV]?.value
        #expect(model.row(id: "tv.test")?.detail == "On · Volume 12 · Not muted")
        #expect(SettingsModel.tvTestLine(TVTestResult(isOn: false, canTurnOn: true)) == "Off or not answering")
        #expect(SettingsModel.tvTestLine(nil) == "Set the TV's address first")
        #expect(SettingsModel.tvTestLine(TVTestResult(isOn: true, isMuted: true, canTurnOn: false)) == "On · Muted")
    }

    @Test func findTVFillsAddressAndMAC() async throws {
        let (model, recorder) = onTVPage(Self.settings { $0.tvBrand = .panasonic })
        let mac = try #require(MACAddress(parsing: "02:00:5e:00:10:cd"))
        recorder.tvFindResult = [FoundTV(host: "10.254.0.41", name: nil, mac: nil),
                                 FoundTV(host: "10.254.0.42", name: "VIERA VT50", mac: mac)]
        model.activate(rowID: "tv.find")
        #expect(model.row(id: "tv.find")?.detail == "Searching…")
        await model.probeTasks[.findTV]?.value
        #expect(recorder.appliedSettings.last?.tvHost == "10.254.0.42")
        #expect(recorder.appliedSettings.last?.tvMAC == "02:00:5e:00:10:cd")
        #expect(model.row(id: "tv.find")?.detail == "Found VIERA VT50")
        #expect(model.row(id: "tv.address")?.value == "10.254.0.42")
    }

    @Test func findTVWithoutAMAC() async {
        let (model, recorder) = onTVPage(Self.panasonic)
        // Another address: the old MAC is for another TV.
        recorder.tvFindResult = [FoundTV(host: "10.254.0.43", name: "VIERA", mac: nil)]
        model.activate(rowID: "tv.find")
        await model.probeTasks[.findTV]?.value
        #expect(recorder.appliedSettings.last?.tvHost == "10.254.0.43")
        #expect(recorder.appliedSettings.last?.tvMAC == nil)
        #expect(model.row(id: "tv.find")?.detail == "Found VIERA; MMTVL can't turn this TV on")

        // The same address keeps the MAC already set.
        let (same, sameRecorder) = onTVPage(Self.panasonic)
        sameRecorder.tvFindResult = [FoundTV(host: "10.254.0.40", name: "VIERA", mac: nil)]
        same.activate(rowID: "tv.find")
        await same.probeTasks[.findTV]?.value
        #expect(sameRecorder.appliedSettings.isEmpty)
        #expect(same.row(id: "tv.find")?.detail == "Found VIERA")

        let (none, _) = onTVPage(Self.panasonic)
        none.activate(rowID: "tv.find")
        await none.probeTasks[.findTV]?.value
        #expect(none.row(id: "tv.find")?.detail == "No TV found")
    }

    // MARK: Address entry (D41)

    @Test func addressPageEditsWithTheKeyboard() {
        let (model, recorder) = onReceiverPage(Self.settings {
            $0.receiverBrand = .pioneer
            $0.receiverConnection = .network
            $0.receiverHost = "10.254.0.50"
        })
        model.activate(rowID: "receiver.address")
        #expect(model.page == .addressEntry(.receiver))
        #expect(model.pageTitle == "Receiver Address")
        #expect(model.keyboard.text == "10.254.0.50")
        #expect(model.keyboard.mode == .digits)
        #expect(model.isKeyboardActive)
        #expect(model.focusedRowID == nil)
        #expect(model.bandText?.hasPrefix("Type an address like 192.168.1.50") == true)
        // Play/Pause deletes; Left and Right move on the keys, not between pages.
        model.press(.playPause, .left, .right)
        #expect(model.keyboard.text == "10.254.0.5")
        #expect(model.page == .addressEntry(.receiver))
        // Down past the bottom row: the rows (Save first); Up from Save: back to the keys.
        model.press(.down, .down, .down)
        #expect(!model.isKeyboardActive)
        #expect(model.focusedRowID == "address.save")
        model.press(.up)
        #expect(model.isKeyboardActive)
        // Down from the keyboard again lands on Save, the first action row; the rows below still walk.
        model.press(.down)
        #expect(model.focusedRowID == "address.save")
        model.press(.down)
        #expect(model.focusedRowID == "address.clear")
        model.press(.up, .up)
        #expect(model.isKeyboardActive)
        model.press(.down, .select)
        #expect(recorder.appliedSettings.last?.receiverHost == "10.254.0.5")
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.address")?.value == "10.254.0.5")
    }

    @Test func addressPageRefusesAndClears() {
        let (model, recorder) = onTVPage(Self.panasonic)
        model.activate(rowID: "tv.address")
        #expect(model.pageTitle == "TV Address")
        #expect(model.keyboard.text == "10.254.0.40")
        model.perform(.clearAddress)
        #expect(model.keyboard.text.isEmpty)
        #expect(model.row(id: "address.save")?.title == "Save Without an Address")
        // A digit alone isn't an address.
        model.press(.select)
        #expect(model.keyboard.text == "1")
        model.perform(.saveAddress(.tv))
        #expect(model.page == .addressEntry(.tv))
        #expect(model.row(id: "address.save")?.detail == "Use the TV's IPv4 address, like 192.168.1.40, or its name")
        #expect(recorder.appliedSettings.isEmpty)
        // An empty field clears the address.
        model.perform(.clearAddress)
        #expect(model.row(id: "address.save")?.detail == nil)
        model.perform(.saveAddress(.tv))
        #expect(recorder.appliedSettings.last?.tvHost == nil)
        #expect(model.page == .tv)
    }

    @Test func backCancelsTheAddress() {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        model.activate(rowID: "receiver.address")
        model.press(.playPause, .playPause)
        model.press(.back)
        #expect(model.page == .receiver)
        #expect(recorder.appliedSettings.isEmpty)
        #expect(model.row(id: "receiver.address")?.value == "10.254.0.20")
        // A name starts on the letters.
        let (named, _) = onReceiverPage(Self.settings {
            $0.receiverConnection = .network
            $0.receiverHost = "avr.local"
        })
        named.activate(rowID: "receiver.address")
        #expect(named.keyboard.mode == .letters)
    }

    // MARK: QA minors

    /// Minor 1: Find on Network's answers stay reachable after leaving Receiver while it searched.
    @Test func foundReceiversStayReachable() async {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        recorder.networkFindResult = [
            FoundReceiver(brand: .pioneer, model: nil, name: "Den", host: "10.254.0.24", port: 23),
            FoundReceiver(brand: .denon, model: nil, name: "Office", host: "10.254.0.25", port: 23),
        ]
        #expect(model.row(id: "receiver.found") == nil)
        model.activate(rowID: "receiver.find")
        model.open(.receiverBrand)
        await model.probeTasks[.findReceiver]?.value
        #expect(model.page == .receiverBrand)
        model.press(.back)
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.find")?.detail == "2 receivers found")
        #expect(model.row(id: "receiver.found")?.value == "2")
        #expect(model.row(id: "receiver.found")?.action == .push(.receiverFound))
        model.activate(rowID: "receiver.found")
        #expect(model.page == .receiverFound)
        #expect(model.actionRowIDs == ["found.10.254.0.24:23", "found.10.254.0.25:23"])
        // Choosing one is a settings change: the list goes with the old results.
        model.activate(rowID: "found.10.254.0.25:23")
        #expect(model.page == .receiver)
        #expect(model.row(id: "receiver.found") == nil)
    }

    /// Step 13c: the chooser opens only over Receiver, not over TV; opening Receiver again is a fresh visit, as
    /// leaving Receiver & TV was (minor 1's subpages keep the answers, `foundReceiversStayReachable`).
    @Test func findOnNetworkDoesntOpenTheChooserOverTV() async {
        let (model, recorder) = onReceiverPage(Self.pioneerNetwork)
        recorder.networkFindResult = [FoundReceiver(brand: .pioneer, model: nil, name: "Den", host: "10.254.0.24", port: 23)]
        model.activate(rowID: "receiver.find")
        model.press(.back)
        model.open(.tv)
        await model.probeTasks[.findReceiver]?.value
        #expect(model.page == .tv)
        #expect(model.stack.map(\.page) == [.root, .audioTV, .tv])
        model.press(.back)
        model.open(.receiver)
        #expect(model.row(id: "receiver.find")?.detail == nil)
        #expect(model.row(id: "receiver.found") == nil)
    }

    /// Step 13c: opening TV drops only the TV's old results, and opening Receiver only the receiver's.
    @Test func eachPageDropsOnlyItsOwnResults() async {
        var settings = Self.pioneerSerial
        settings.tvBrand = .panasonic
        settings.tvHost = "10.254.0.40"
        let (model, recorder) = onTVPage(settings)
        recorder.tvTestResult = TVTestResult(isOn: true, volume: 12, isMuted: false, canTurnOn: true)
        model.activate(rowID: "tv.test")
        await model.probeTasks[.testTV]?.value
        model.press(.back)
        model.open(.receiver)
        model.activate(rowID: "receiver.test")
        await model.probeTasks[.testReceiver]?.value
        model.press(.back)
        model.open(.tv)
        #expect(model.row(id: "tv.test")?.detail == nil)
        model.press(.back)
        model.open(.receiver)
        #expect(model.row(id: "receiver.test")?.detail == nil)
    }

    /// Minor 2: the band names the mode key as it reads now.
    @Test func addressBandNamesTheModeKey() {
        let (digits, _) = onReceiverPage(Self.pioneerNetwork)
        digits.open(.addressEntry(.receiver))
        #expect(digits.keyboard.mode == .digits)
        #expect(digits.bandText?.contains("abc switches to letters") == true)
        let (letters, _) = onReceiverPage(Self.settings {
            $0.receiverConnection = .network
            $0.receiverHost = "avr.local"
        })
        letters.open(.addressEntry(.receiver))
        #expect(letters.bandText?.contains("123 switches to numbers") == true)
    }

    /// Minor 3: the Siri Remote has its own row now.
    @Test func gameControllersNoLongerMentionTheSiriRemote() {
        let (model, _) = makeSettingsModel()
        model.open(.remoteInput)
        #expect(model.row(id: "controllers")?.description == "Use game controllers as remotes.")
    }

    // MARK: Step 9c: the receiver over HDMI-CEC, and TV volume

    private static let cecReceiver = settings {
        $0.receiverBrand = .pioneer   // left from Serial: not shown, not used
        $0.receiverConnection = .cec
        $0.receiverSerialPort = "/dev/cu.usbserial-TEST1"
    }

    @Test func cecReceiverRowsHideBrandPortAddressAndTheLimit() {
        let (model, recorder) = onReceiverPage(Self.cecReceiver)
        #expect(model.sections.map(\.id) == ["receiver"])
        #expect(model.sections.last?.rows.map(\.id) == ["receiver.connection", "receiver.test", "receiver.find",
                                                        "receiver.maxVolume", "receiver.status"])
        #expect(model.actionRowIDs == ["receiver.connection", "receiver.test", "receiver.find"])
        #expect(model.row(id: "receiver.brand") == nil)
        #expect(model.row(id: "receiver.port") == nil)
        #expect(model.row(id: "receiver.address") == nil)
        #expect(model.row(id: "receiver.connection")?.value == "HDMI-CEC")
        #expect(model.row(id: "receiver.find")?.title == "Find Receiver")
        // Maximum Volume is an info line.
        let limit = model.row(id: "receiver.maxVolume")
        #expect(limit?.action == nil)
        #expect(limit?.value == "No Limit")
        #expect(limit?.detail == "HDMI-CEC receivers can't be limited")
        // Status: the tunnel, then the receiver's answer and name.
        #expect(model.row(id: "receiver.status")?.value == "Checking…")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .notAvailable)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "HDMI-CEC not available on this display")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .noDisplay)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "No HDMI display")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .ready)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "Not answering")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .ready, power: .on, name: "VSX-01TXH",
                                                         isAnswering: true)
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "On · VSX-01TXH")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .ready, power: .standby, name: "VSX-01TXH")
        model.refreshStatus()
        #expect(model.row(id: "receiver.status")?.value == "Standby · VSX-01TXH")
    }

    @Test func audioTVNamesTheCECReceiver() {
        let (model, recorder) = makeSettingsModel(settings: Self.cecReceiver)
        model.open(.audioTV)
        #expect(model.row(id: "audioTV.receiver")?.value == "HDMI-CEC")
        recorder.cecReceiver = CECReceiverSettingsStatus(availability: .ready, power: .on, name: "VSX-01TXH")
        model.refreshStatus()
        #expect(model.row(id: "audioTV.receiver")?.value == "VSX-01TXH")
    }

    @Test func cecTestConnectionShowsTheName() async {
        for (result, line) in [(CECReceiverTest(power: .on, name: "VSX-01TXH"), "On · VSX-01TXH"),
                               (CECReceiverTest(power: .standby, name: "VSX-01TXH"), "Standby · VSX-01TXH"),
                               (CECReceiverTest(power: .on), "On"), (CECReceiverTest(), "No answer")] {
            let (model, recorder) = onReceiverPage(Self.cecReceiver)
            recorder.cecReceiverTestResult = result
            model.activate(rowID: "receiver.test")
            #expect(model.row(id: "receiver.test")?.detail == "Testing…")
            await model.probeTasks[.testReceiver]?.value
            #expect(model.row(id: "receiver.test")?.detail == line)
            #expect(recorder.cecReceiverTests == 1)
            #expect(recorder.receiverTests == 0)
        }
    }

    /// Find Receiver: the serial brands first; a serial match wins (and makes the connection Serial).
    @Test func findPrefersASerialMatchOverHDMICEC() async {
        let (model, recorder) = onReceiverPage(Self.cecReceiver)
        recorder.serialFindResult = .pioneer
        recorder.cecReceiverTestResult = CECReceiverTest(power: .on, name: "VSX-01TXH")
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.serialFinds == ["/dev/cu.usbserial-TEST1"])
        #expect(recorder.cecReceiverTests == 0)
        #expect(recorder.appliedSettings.last?.receiverConnection == .serial)
        #expect(recorder.appliedSettings.last?.receiverBrand == .pioneer)
        #expect(model.row(id: "receiver.find")?.detail == "Found Pioneer")
        #expect(model.row(id: "receiver.port") != nil)
    }

    @Test func findFallsBackToHDMICEC() async {
        let (model, recorder) = onReceiverPage()
        recorder.cecReceiverTestResult = CECReceiverTest(power: .standby, name: "VSX-01TXH")
        model.activate(rowID: "receiver.find")
        await model.probeTasks[.findReceiver]?.value
        #expect(recorder.serialFinds == [nil])
        #expect(recorder.cecReceiverTests == 1)
        #expect(recorder.appliedSettings.last?.receiverConnection == .cec)
        #expect(model.row(id: "receiver.find")?.detail == "Found VSX-01TXH over HDMI-CEC")
        #expect(model.row(id: "receiver.connection")?.value == "HDMI-CEC")
        // Without a name.
        let (unnamed, unnamedRecorder) = onReceiverPage()
        unnamedRecorder.cecReceiverTestResult = CECReceiverTest(power: .on)
        unnamed.activate(rowID: "receiver.find")
        await unnamed.probeTasks[.findReceiver]?.value
        #expect(unnamed.row(id: "receiver.find")?.detail == "Found a receiver over HDMI-CEC")
        // Find on Network never asks HDMI-CEC.
        let (network, networkRecorder) = onReceiverPage(Self.pioneerNetwork)
        network.activate(rowID: "receiver.find")
        await network.probeTasks[.findReceiver]?.value
        #expect(networkRecorder.cecReceiverTests == 0)
    }

    @Test func tvVolumeToggleForPanasonicAndHDMICEC() {
        for settings in [Self.panasonic, Self.settings { $0.tvBrand = .cec }] {
            let (model, recorder) = onTVPage(settings)
            let row = model.row(id: "tv.volume")
            #expect(row?.title == "Volume Buttons Change TV Volume")
            #expect(row?.value == "Off")
            #expect(row?.action == .toggle(.tvVolumeEnabled))
            #expect(row?.description == "When no receiver is set up, the volume buttons change the TV's own volume. For TVs that play through their own speakers. Some TVs ignore HDMI-CEC volume.")
            model.activate(rowID: "tv.volume")
            #expect(recorder.appliedSettings.last?.tvVolumeEnabled == true)
            #expect(model.row(id: "tv.volume")?.value == "On")
        }
        let (none, _) = onTVPage()
        #expect(none.row(id: "tv.volume") == nil)
    }
}
