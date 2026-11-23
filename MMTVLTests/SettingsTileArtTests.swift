import Foundation
import Testing
@testable import MMTVL

/// Settings → a tile → Tile Art (M7 L25).
struct SettingsTileArtTests {
    static let poster = PictureFile(url: URL(fileURLWithPath: "/Users/me/Downloads/Poster.PNG"), folder: "Downloads",
                                    modified: Date(timeIntervalSince1970: 1_791_200_000))

    private func onArtPage(_ id: String = "plex", pictures: [PictureFile] = [poster]) async -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel()
        recorder.pictures = pictures
        model.perform(.push(.homeScreen))
        model.perform(.push(.tile(id: id)))
        model.perform(.push(.tileArt(id: id)))
        await model.loadPictures()
        return (model, recorder)
    }

    @Test func appTilesOfferBothStylesAndPictures() async {
        let (model, _) = await onArtPage()
        #expect(model.pageTitle == "Tile Art")
        #expect(model.actionRowIDs == ["art.designed", "art.icon", "art.file.0"])
        #expect(model.row(id: "art.designed")?.value == "Selected")
        #expect(model.row(id: "art.icon")?.value == nil)
        #expect(model.row(id: "art.file.0")?.title == "Poster.PNG")
        #expect(model.row(id: "art.file.0")?.image == .picture(Self.poster.url))
        #expect(model.accessory(for: model.page) == .tileArt(itemID: "plex", .style(.designed)))
        model.press(.down)
        #expect(model.accessory(for: model.page) == .tileArt(itemID: "plex", .style(.icon)))
        model.press(.down)
        #expect(model.accessory(for: model.page) == .tileArt(itemID: "plex", .file(Self.poster.url)))
    }

    @Test func builtInTilesOnlyHaveTheDesignedStyle() async {
        let (model, _) = await onArtPage("youtube", pictures: [])
        #expect(model.actionRowIDs == ["art.designed"])
        #expect(model.row(id: "art.file.none")?.title == "No pictures in Downloads, Pictures or Desktop")
    }

    @Test func choosingAStyleSavesIt() async {
        let (model, recorder) = await onArtPage()
        model.activate(rowID: "art.icon")
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.artStyle == "icon")
        #expect(model.row(id: "art.icon")?.value == "Selected")
        model.activate(rowID: "art.designed")
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.artStyle == nil)
    }

    @Test func choosingAPictureCopiesItThenItCanBeRemoved() async {
        let (model, recorder) = await onArtPage()
        model.activate(rowID: "art.file.0")
        #expect(recorder.pictureSets == ["plex ← Poster.PNG"])
        #expect(model.row(id: "art.custom")?.title == "plex.png")
        #expect(model.row(id: "art.designed")?.detail == "Removes your picture")
        #expect(model.row(id: "art.designed")?.value == nil)
        model.activate(rowID: "art.removeCustom")
        #expect(recorder.pictureRemovals == ["plex"])
        #expect(model.row(id: "art.custom") == nil)
        #expect(model.focusedRowID == "art.designed")
    }

    /// M7c L33: going back to a style removes the picture.
    @Test func choosingAStyleRemovesThePicture() async {
        let (model, recorder) = await onArtPage()
        model.activate(rowID: "art.file.0")
        model.activate(rowID: "art.designed")
        #expect(recorder.pictureRemovals == ["plex"])
        #expect(model.row(id: "art.custom") == nil)
        #expect(model.row(id: "art.designed")?.value == "Selected")
        // Without a picture, nothing is removed.
        model.activate(rowID: "art.icon")
        #expect(recorder.pictureRemovals == ["plex"])
    }

    @Test func aFailedCopySaysSo() async {
        let (model, recorder) = await onArtPage()
        recorder.pictureSetResult = "Couldn't copy that picture"
        model.activate(rowID: "art.file.0")
        #expect(model.row(id: "art.message")?.title == "Couldn't copy that picture")
        model.press(.back)
        model.perform(.push(.tileArt(id: "plex")))
        #expect(model.row(id: "art.message") == nil)
    }

    @Test func showsLoadingUntilThePicturesArrive() {
        let (model, _) = makeSettingsModel()
        model.perform(.push(.tileArt(id: "plex")))
        #expect(model.row(id: "art.file.loading")?.title == "Looking for pictures…")
    }
}
