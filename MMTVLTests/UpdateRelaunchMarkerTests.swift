import Foundation
import Testing
@testable import MMTVL

/// M15 L8: `update-relaunch.json` carries "the TV is off" across an update's relaunch, read once.
struct UpdateRelaunchMarkerTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "UpdateRelaunchMarker-\(UUID().uuidString)")
    let written = Date(timeIntervalSince1970: 1_800_000_000)

    private var fileURL: URL { UpdateRelaunchMarker.url(in: directory) }

    @Test func roundTrip() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: directory)
        #expect(fileURL.lastPathComponent == "update-relaunch.json")
        let json = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(json == #"{"poweredOff":true,"written":"2027-01-15T08:00:00Z"}"#)
        let marker = UpdateRelaunchMarker.take(from: directory, now: written.addingTimeInterval(45))
        #expect(marker == UpdateRelaunchMarker(poweredOff: true, written: written))
    }

    @Test func olderThan10MinutesIgnored() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: directory)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written.addingTimeInterval(10 * 60)) == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        // Just under 10 minutes still counts; "not powered off" never does.
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: directory)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written.addingTimeInterval(10 * 60 - 1)) != nil)
        try UpdateRelaunchMarker(poweredOff: false, written: written).write(to: directory)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
    }

    @Test func corruptFileDeletedAndIgnored() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"poweredOff\": tru".utf8).write(to: fileURL)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func deletedAfterRead() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        // Missing: nothing.
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: directory)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) != nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
    }

    /// Security L-d: a FIFO at the path is never opened for a blocking read; it's removed and ignored.
    @Test func fifoIgnoredWithoutHanging() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(mkfifo(fileURL.path, 0o600) == 0)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
        var info = stat()
        #expect(lstat(fileURL.path, &info) != 0)
    }

    /// Security L-d: a symlink (even to a valid, fresh marker) is ignored; the link goes, its target stays.
    @Test func symlinkIgnoredAndOnlyTheLinkRemoved() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let elsewhere = directory.appending(path: "elsewhere", directoryHint: .isDirectory)
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: elsewhere)
        let target = UpdateRelaunchMarker.url(in: elsewhere)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
        var info = stat()
        #expect(lstat(fileURL.path, &info) != 0)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    /// Security L-d: more than 4 KB is deleted unread.
    @Test func oversizedFileIgnored() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let padded = #"{"poweredOff":true,"written":"2027-01-15T08:00:00Z","pad":""# + String(repeating: "x", count: 5000) + #""}"#
        try Data(padded.utf8).write(to: fileURL)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// Security L-c: `delete` removes the marker; a missing one is fine.
    @Test func deleteRemovesTheMarker() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try UpdateRelaunchMarker(poweredOff: true, written: written).write(to: directory)
        UpdateRelaunchMarker.delete(from: directory)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        UpdateRelaunchMarker.delete(from: directory)
        #expect(UpdateRelaunchMarker.take(from: directory, now: written) == nil)
    }
}
