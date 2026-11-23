import Testing
@testable import MMTVL

/// MR step 4: Settings → Licenses and each component's page.
struct SettingsLicensesTests {
    private func rowIDs(_ model: SettingsModel) -> [String] {
        model.sections.flatMap(\.rows).map(\.id)
    }

    @Test func rootRowComesLastAndPushesLicenses() {
        let (model, _) = makeSettingsModel()
        let ids = rowIDs(model)
        #expect(ids.last == "licenses")
        #expect(ids.firstIndex(of: "licenses")! > ids.firstIndex(of: "about")!)
        let row = model.row(id: "licenses")
        #expect(row?.title == "Licenses")
        #expect(row?.showsDisclosure == true)
        #expect(row?.action == .push(.licenses))
        #expect(row?.description != nil)

        model.focus(rowID: "licenses")
        model.press(.select)
        #expect(model.page == .licenses)
        #expect(model.pageTitle == "Licenses")
    }

    @Test func listShowsEveryComponentInOrder() {
        let (model, _) = makeSettingsModel()
        model.open(.licenses)
        #expect(model.actionRowIDs == ThirdPartyLicenses.all.map { "license.\($0.id)" })
        #expect(model.actionRowIDs.first == "license.mmtvl")
        for component in ThirdPartyLicenses.all {
            let row = model.row(id: "license.\(component.id)")
            #expect(row?.title == component.name)
            #expect(row?.value == component.license)
            #expect(row?.detail == "Version \(component.version)")
            #expect(row?.showsDisclosure == true)
            #expect(row?.action == .push(.license(id: component.id)))
        }
        #expect(model.sections.first?.footer?.contains("THIRD_PARTY_NOTICES.md") == true)
        #expect(model.accessory(for: .licenses) == nil)
    }

    @Test func selectOpensTheComponentWithItsQRCode() throws {
        let (model, _) = makeSettingsModel()
        model.open(.licenses)
        model.focus(rowID: "license.ffmpeg")
        model.press(.select)
        #expect(model.page == .license(id: "ffmpeg"))

        let ffmpeg = try #require(ThirdPartyLicenses.component(id: "ffmpeg"))
        #expect(model.pageTitle == "FFmpeg")
        #expect(model.accessory(for: model.page) == .qrCode(ffmpeg.url))
        #expect(rowIDs(model) == ["license.version", "license.license", "license.copyright", "license.source",
                                  "license.done"])
        #expect(model.actionRowIDs == ["license.done"])
        #expect(model.row(id: "license.version")?.value == ffmpeg.version)
        #expect(model.row(id: "license.license")?.value == ffmpeg.license)
        #expect(model.row(id: "license.copyright")?.title == ffmpeg.copyright)
        #expect(model.row(id: "license.copyright")?.value == nil)
        #expect(model.row(id: "license.source")?.value == String(ffmpeg.url.dropFirst("https://".count)))
    }

    @Test func everyComponentPageHasItsQRCode() {
        let (model, _) = makeSettingsModel()
        for component in ThirdPartyLicenses.all {
            #expect(model.accessory(for: .license(id: component.id)) == .qrCode(component.url))
            #expect(model.title(for: .license(id: component.id)) == component.name)
        }
    }

    @Test func doneReturnsToTheList() {
        let (model, _) = makeSettingsModel()
        model.open(.licenses)
        model.focus(rowID: "license.grdb")
        model.press(.select)
        #expect(model.page == .license(id: "grdb"))
        model.press(.select)
        #expect(model.page == .licenses)
        #expect(model.focusedRowID == "license.grdb")
    }

    @Test func backReturnsFromBothPages() {
        let (model, _) = makeSettingsModel()
        model.focus(rowID: "licenses")
        model.press(.select)
        model.focus(rowID: "license.mpv")
        model.press(.select)
        #expect(model.page == .license(id: "mpv"))
        model.press(.back)
        #expect(model.page == .licenses)
        model.press(.back)
        #expect(model.page == .root)
        #expect(model.focusedRowID == "licenses")
    }

    @Test func unknownComponentShowsOnlyDone() {
        let (model, _) = makeSettingsModel()
        model.open(.licenses)
        model.open(.license(id: "nope"))
        #expect(model.pageTitle == "License")
        #expect(rowIDs(model) == ["license.done"])
        #expect(model.accessory(for: model.page) == nil)
        model.press(.select)
        #expect(model.page == .licenses)
    }
}
