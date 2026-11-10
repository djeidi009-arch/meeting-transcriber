import Foundation
import DetectorCore

func tempDir(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mt-selftest-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

func touch(_ url: URL, _ text: String = "x", modified: Date? = nil) {
    try? text.data(using: .utf8)!.write(to: url)
    if let modified {
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

/// 2026-10-23 14:05:00 по местному времени.
func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

enum StoreTests {
    static func all() {
        test("создание папки встречи по контракту") {
            let root = tempDir("store")
            let store = MeetingStore(outputDir: root.appendingPathComponent("transcripts"))
            let started = localDate(2026, 10, 23, 14, 5)
            let dir = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: false, startedAt: started)
            check(dir.lastPathComponent == "2026-10-23 14-05 Zoom", "имя папки: \(dir.lastPathComponent)")
            check(exists(dir.appendingPathComponent(".recording")), "есть .recording")
            let meta = readJSON(dir.appendingPathComponent("meta.json"))
            check(meta?["app"] as? String == "Zoom", "meta.app")
            check(meta?["bundleId"] as? String == "us.zoom.xos", "meta.bundleId")
            check(meta?["manual"] as? Bool == false, "meta.manual")
            check(meta?.keys.contains("endedAt") == true && meta?["endedAt"] is NSNull, "endedAt: null")
            let startedAt = meta?["startedAt"] as? String ?? ""
            let parsed = ISO8601DateFormatter().date(from: startedAt)
            check(parsed == started, "startedAt ISO-8601 с поясом: \(startedAt)")
            check(startedAt.hasSuffix("Z") || startedAt.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) != nil, "есть часовой пояс: \(startedAt)")
            let dir2 = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: true, startedAt: started)
            check(dir2.lastPathComponent == "2026-10-23 14-05 Zoom (2)", "суффикс (2): \(dir2.lastPathComponent)")
        }

        test("остановка: длинная запись остаётся, короткая удаляется") {
            let root = tempDir("finish")
            let store = MeetingStore(outputDir: root)
            let started = localDate(2026, 10, 23, 15, 0)
            let dir = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: false, startedAt: started)
            let kept = store.finishMeeting(dir, endedAt: started.addingTimeInterval(600))
            check(kept, "10 минут — оставлена")
            check(!exists(dir.appendingPathComponent(".recording")), ".recording снят")
            let ended = readJSON(dir.appendingPathComponent("meta.json"))?["endedAt"] as? String
            check(ended.flatMap { ISO8601DateFormatter().date(from: $0) } == started.addingTimeInterval(600), "endedAt записан: \(String(describing: ended))")

            let short = try store.createMeeting(app: "Meet", bundleID: "", manual: true, startedAt: started)
            touch(short.appendingPathComponent("mic.caf"))
            let keptShort = store.finishMeeting(short, endedAt: started.addingTimeInterval(14))
            check(!keptShort, "14 с — удалена")
            check(!exists(short), "папки нет")
        }

        test("при запуске: устаревшие .recording снимаются, необработанные — в очередь") {
            let root = tempDir("recover")
            let store = MeetingStore(outputDir: root)
            let started = Date().addingTimeInterval(-3600)
            // упала посреди записи
            let crashed = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: false, startedAt: started)
            touch(crashed.appendingPathComponent("mic.caf"), modified: started.addingTimeInterval(1200))
            touch(crashed.appendingPathComponent("system.caf"), modified: started.addingTimeInterval(1260))
            // обработанная
            let done = try store.createMeeting(app: "Teams", bundleID: "com.microsoft.teams2", manual: false, startedAt: started.addingTimeInterval(60))
            _ = store.finishMeeting(done, endedAt: started.addingTimeInterval(1000))
            touch(done.appendingPathComponent("mic.m4a"))
            touch(done.appendingPathComponent("meeting.md"))
            // остановлена, но не обработана (выход из программы)
            let pending = try store.createMeeting(app: "Slack", bundleID: "com.tinyspeck.slackmacgap", manual: false, startedAt: started.addingTimeInterval(120))
            touch(pending.appendingPathComponent("system.caf"))
            _ = store.finishMeeting(pending, endedAt: started.addingTimeInterval(900))
            // упала через 5 с — мусор
            let tiny = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: false, startedAt: started.addingTimeInterval(180))
            touch(tiny.appendingPathComponent("mic.caf"), modified: started.addingTimeInterval(185))
            // без аудио
            let empty = try store.createMeeting(app: "FaceTime", bundleID: "com.apple.FaceTime", manual: false, startedAt: started.addingTimeInterval(240))
            _ = store.finishMeeting(empty, endedAt: started.addingTimeInterval(900))

            let found = store.recoverPending().map(\.lastPathComponent).sorted()
            check(found == [crashed.lastPathComponent, pending.lastPathComponent].sorted(), "в очередь: \(found)")
            check(!exists(crashed.appendingPathComponent(".recording")), ".recording снят")
            let ended = readJSON(crashed.appendingPathComponent("meta.json"))?["endedAt"] as? String
            check(ended.flatMap { ISO8601DateFormatter().date(from: $0) }.map { abs($0.timeIntervalSince(started.addingTimeInterval(1260))) < 1 } == true, "endedAt по последней записи в .caf: \(String(describing: ended))")
            check(!exists(tiny), "короткая упавшая запись удалена")
            check(exists(done) && exists(empty), "остальные папки на месте")
        }

        test("загруженный файл: папка по имени файла, sourceFile, без .recording, подхватывается при запуске") {
            let root = tempDir("import")
            let store = MeetingStore(outputDir: root)
            let file = root.appendingPathComponent("Интервью с клиентом.mp4")
            touch(file)
            let dir = try store.createImport(file: file, at: localDate(2026, 11, 10, 12, 0))
            check(dir.lastPathComponent == "2026-11-10 12-00 Интервью с клиентом", "имя папки: \(dir.lastPathComponent)")
            let meta = readJSON(dir.appendingPathComponent("meta.json"))
            check(meta?["sourceFile"] as? String == file.standardizedFileURL.path, "sourceFile: \(String(describing: meta?["sourceFile"]))")
            check(!exists(dir.appendingPathComponent(".recording")), "нет .recording")
            check(store.recoverPending().map(\.lastPathComponent) == [dir.lastPathComponent], "необработанный файл — в очередь")
        }

        test("последние встречи и встреча для повторного summary") {
            let root = tempDir("recent")
            let store = MeetingStore(outputDir: root)
            var dirs: [URL] = []
            for i in 0..<7 {
                let d = try store.createMeeting(app: "Zoom", bundleID: "us.zoom.xos", manual: false,
                                                startedAt: localDate(2026, 10, 20 + i / 3, 10 + i, 0))
                _ = store.finishMeeting(d, endedAt: Date())
                if i != 6 { touch(d.appendingPathComponent("meeting.md")) }
                if i <= 4 { touch(d.appendingPathComponent("transcript.json")) }
                dirs.append(d)
            }
            let recent = store.recentMeetings(limit: 5)
            check(recent.map(\.lastPathComponent) == dirs[1...5].reversed().map(\.lastPathComponent), "5 последних с meeting.md: \(recent.map(\.lastPathComponent))")
            check(store.lastMeetingWithTranscript()?.lastPathComponent == dirs[4].lastPathComponent, "последняя с transcript.json")
        }
    }
}
