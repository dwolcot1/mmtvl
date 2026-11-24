import Foundation

/// M15 L8: carries "the TV is off" across an update's relaunch. `poweredOffByMMTVL` is memory only, so an idle install
/// during Power-off writes `update-relaunch.json` just before calling Sparkle's install block, and the relaunched MMTVL
/// reads it once at launch (`AppDelegate.setUpPower`), deletes it, and restores the power state when it's fresh.
nonisolated struct UpdateRelaunchMarker: Codable, Equatable, Sendable {
    static let fileName = "update-relaunch.json"
    /// Older markers are ignored (the install didn't relaunch soon after it was written).
    static let maxAge: TimeInterval = 10 * 60

    var poweredOff: Bool
    var written: Date

    /// The file in `directory` (`LaunchItemStore.defaultDirectory` in the app).
    static func url(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    /// `{"poweredOff": true, "written": "<ISO 8601>"}`, atomically. Creates the directory if needed.
    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: Self.url(in: directory), options: .atomic)
    }

    /// Security L-d: the most `take` reads; a bigger file is deleted and ignored.
    static let maxBytes = 4096

    /// Reads the marker once and deletes it, whatever it holds. nil when it's missing, corrupt, not "powered off", or
    /// not written within the last `maxAge` (a clock that moved back more than a minute counts as old too).
    /// Security L-d: only a regular file is read (`lstat`, then opened without following a link and without waiting,
    /// and checked again with `fstat`), at most `maxBytes`; a FIFO, link, device or bigger file is unlinked (the path
    /// itself, never a link's target) and ignored.
    static func take(from directory: URL, now: Date) -> UpdateRelaunchMarker? {
        let path = url(in: directory).path
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        defer { unlink(path) }
        guard info.st_mode & S_IFMT == S_IFREG, let data = readRegularFile(path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let marker = try? decoder.decode(UpdateRelaunchMarker.self, from: data), marker.poweredOff else { return nil }
        let age = now.timeIntervalSince(marker.written)
        guard age < maxAge, age > -60 else { return nil }
        return marker
    }

    /// Removes the marker (an install that didn't happen, security L-c). The path itself, never a link's target.
    static func delete(from directory: URL) {
        unlink(url(in: directory).path)
    }

    /// At most `maxBytes` of a regular file; nil for anything else or anything bigger.
    private static func readRegularFile(_ path: String) -> Data? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maxBytes,
              let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes
        else { return nil }
        return data
    }
}
