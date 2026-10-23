import Foundation

/// Папка встречи по контракту из interfaces.md: `<outputDir>/<YYYY-MM-DD HH-MM> <App>/`
/// с `meta.json`, маркером `.recording` и дорожками `mic.caf`/`system.caf`.
public final class MeetingStore {
    public let outputDir: URL
    private let fm = FileManager.default

    public static let recordingMarker = ".recording"
    public static let metaFile = "meta.json"
    public static let audioFiles = ["mic.caf", "system.caf", "mic.m4a", "system.m4a"]

    public init(outputDir: URL) {
        self.outputDir = outputDir
    }

    public static func folderName(startedAt: Date, app: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let safeApp = app.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(f.string(from: startedAt)) \(safeApp)"
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Создаёт папку, `meta.json` (endedAt: null) и маркер `.recording`.
    public func createMeeting(app: String, bundleID: String, manual: Bool, startedAt: Date = Date()) throws -> URL {
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let base = Self.folderName(startedAt: startedAt, app: app)
        var dir = outputDir.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dir.path) {
            dir = outputDir.appendingPathComponent("\(base) (\(n))", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: false)
        let meta: [String: Any] = [
            "app": app,
            "bundleId": bundleID,
            "startedAt": Self.iso(startedAt),
            "endedAt": NSNull(),
            "manual": manual,
        ]
        try writeMeta(meta, to: dir)
        fm.createFile(atPath: dir.appendingPathComponent(Self.recordingMarker).path, contents: Data())
        return dir
    }

    /// Снимает `.recording` и дописывает `endedAt`. Запись короче `minDuration` удаляется целиком.
    /// Возвращает true, если встреча осталась и её нужно обработать.
    @discardableResult
    public func finishMeeting(_ dir: URL, endedAt: Date = Date(), minDuration: TimeInterval = 15) -> Bool {
        var meta = readMeta(dir) ?? [:]
        let started = Self.parseISO(meta["startedAt"] as? String) ?? endedAt
        if endedAt.timeIntervalSince(started) < minDuration {
            try? fm.removeItem(at: dir)
            return false
        }
        meta["endedAt"] = Self.iso(endedAt)
        try? writeMeta(meta, to: dir)
        try? fm.removeItem(at: dir.appendingPathComponent(Self.recordingMarker))
        return true
    }

    /// Вызывается при запуске программы (когда запись точно не идёт): снимает устаревшие `.recording`
    /// (время конца — по последней записи в аудиофайлы) и возвращает папки с аудио без `meeting.md`.
    public func recoverPending(minDuration: TimeInterval = 15) -> [URL] {
        var result: [URL] = []
        for dir in meetingDirs() {
            if fm.fileExists(atPath: dir.appendingPathComponent(Self.recordingMarker).path) {
                let ended = lastAudioWrite(dir) ?? Date()
                if !finishMeeting(dir, endedAt: ended, minDuration: minDuration) { continue }
            }
            let hasAudio = Self.audioFiles.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
            let done = fm.fileExists(atPath: dir.appendingPathComponent("meeting.md").path)
            if hasAudio && !done { result.append(dir) }
        }
        return result
    }

    /// Последние обработанные встречи (с `meeting.md`), новые первыми.
    public func recentMeetings(limit: Int = 5) -> [URL] {
        Array(meetingDirs()
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("meeting.md").path) }
            .prefix(limit))
    }

    /// Последняя встреча, для которой можно перегенерировать summary (есть `transcript.json`).
    public func lastMeetingWithTranscript() -> URL? {
        meetingDirs().first { fm.fileExists(atPath: $0.appendingPathComponent("transcript.json").path) }
    }

    // MARK: - внутреннее

    /// Папки встреч (с `meta.json`), новые первыми.
    private func meetingDirs() -> [URL] {
        guard let items = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        let dirs = items.filter { fm.fileExists(atPath: $0.appendingPathComponent(Self.metaFile).path) }
        return dirs.sorted { a, b in
            let da = Self.parseISO(readMeta(a)?["startedAt"] as? String) ?? .distantPast
            let db = Self.parseISO(readMeta(b)?["startedAt"] as? String) ?? .distantPast
            if da != db { return da > db }
            return a.lastPathComponent > b.lastPathComponent
        }
    }

    private func lastAudioWrite(_ dir: URL) -> Date? {
        ["mic.caf", "system.caf"].compactMap { name -> Date? in
            (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.modificationDate] as? Date
        }.max()
    }

    func readMeta(_ dir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(Self.metaFile)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeMeta(_ meta: [String: Any], to dir: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: dir.appendingPathComponent(Self.metaFile), options: .atomic)
    }
}
