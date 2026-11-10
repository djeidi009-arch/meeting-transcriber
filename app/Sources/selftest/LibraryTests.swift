import Foundation
import DetectorCore

/// Папка встречи в настоящем формате: `meta.json` плюс названные файлы.
func makeMeeting(_ root: URL, _ name: String, app: String, started: Date?, ended: Date? = nil,
                 sourceFile: String? = nil, files: [String: String] = [:]) -> URL {
    let dir = root.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let iso = ISO8601DateFormatter()
    var meta: [String: Any] = ["app": app, "bundleId": "", "manual": false,
                               "startedAt": started.map { iso.string(from: $0) as Any } ?? NSNull(),
                               "endedAt": ended.map { iso.string(from: $0) as Any } ?? NSNull()]
    if let sourceFile { meta["sourceFile"] = sourceFile }
    try? JSONSerialization.data(withJSONObject: meta).write(to: dir.appendingPathComponent("meta.json"))
    for (file, text) in files { touch(dir.appendingPathComponent(file), text) }
    return dir
}

/// `transcript.json` в том виде, в каком его пишет Python.
func transcriptJSON(_ utterances: [(Double, Double, String, String)], duration: Double) -> String {
    let list = utterances.map { ["start": $0.0, "end": $0.1, "speaker": $0.2, "text": $0.3] as [String: Any] }
    let data = try! JSONSerialization.data(withJSONObject: ["utterances": list, "duration": duration])
    return String(decoding: data, as: UTF8.self)
}

func meetingMD(summary: String) -> String {
    "# Zoom — 10.11.2026 10:00\n\nДлительность: 5 мин\n\n## Summary\n\n\(summary)\n\n## Транскрипт\n\n**[00:00:00] Я:** Привет\n"
}

enum LibraryTests {
    static let empty = ProcessingQueue.Snapshot(running: nil, pending: [])

    static func all() {
        test("библиотека: статус каждой встречи по файлам и снимку очереди, новые первыми") {
            let root = tempDir("library")
            let store = MeetingStore(outputDir: root)
            let library = MeetingLibrary(store: store)
            let day = localDate(2026, 11, 10, 10, 0)
            func at(_ minutes: Double) -> Date { day.addingTimeInterval(minutes * 60) }
            let transcript = transcriptJSON([(0, 4, "Я", "Привет")], duration: 300.5)

            let old = makeMeeting(root, "1 old", app: "Zoom", started: at(1), ended: at(31),
                                  files: ["meeting.md": meetingMD(summary: "### Кратко\nОбсудили план."), "transcript.json": transcript])
            let failed = makeMeeting(root, "2 failed", app: "Meet", started: at(2), ended: at(12),
                                     files: ["error.txt": "Файл не найден: /tmp/нет.mp4\nподробности\n"])
            let noSummary = makeMeeting(root, "3 nosummary", app: "Zoom", started: at(3),
                                        files: ["meeting.md": meetingMD(summary: "Summary не удалось сделать: истёк таймаут. Меню → Повторить summary")])
            let running = makeMeeting(root, "4 running", app: "Толк", started: at(4), sourceFile: "/tmp/Интервью.mp4",
                                      files: ["progress.json": #"{"stage": "asr", "fraction": 0.5, "updatedAt": "2026-11-10T19:30:00+07:00"}"#,
                                              "error.txt": "старая ошибка"])
            let pending = makeMeeting(root, "5 pending", app: "Zoom", started: at(5))
            let recording = makeMeeting(root, "6 recording", app: "Zoom", started: at(6), files: [".recording": ""])
            let untouched = makeMeeting(root, "7 untouched", app: "Zoom", started: at(7))
            let starting = makeMeeting(root, "8 starting", app: "Zoom", started: at(8))

            let snapshot = ProcessingQueue.Snapshot(running: .init(dir: running, kind: .process),
                                                    pending: [.init(dir: pending, kind: .process)])
            let items = library.items(queue: snapshot)
            check(items.map(\.id) == ["8 starting", "7 untouched", "6 recording", "5 pending", "4 running", "3 nosummary", "2 failed", "1 old"],
                  "новые первыми: \(items.map(\.id))")
            func item(_ dir: URL) -> MeetingItem? { items.first { $0.id == dir.lastPathComponent } }

            check(item(recording)?.status == .recording, "есть .recording → идёт запись")
            check(item(pending)?.status == .queued, "в pending → в очереди")
            check(item(running)?.status == .processing(ProgressInfo(stage: .asr, fraction: 0.5)),
                  "идёт, этап из progress.json: \(String(describing: item(running)?.status))")
            check(item(old)?.status == .ready, "старая папка без новых файлов → готово")
            check(item(failed)?.status == .failed("Файл не найден: /tmp/нет.mp4"), "error.txt → первая строка: \(String(describing: item(failed)?.status))")
            check(item(untouched)?.status == .queued, "ничего нет → в очереди")
            check(item(noSummary)?.status == .ready && item(noSummary)?.summaryFailed == true, "summary не удалось: готово + summaryFailed")
            check(item(old)?.summaryFailed == false, "обычная готовая встреча — summaryFailed нет")

            let onlyStarting = library.items(queue: .init(running: .init(dir: starting, kind: .process), pending: []))
            check(onlyStarting.first?.status == .processing(nil), "идёт, но progress.json ещё нет → этап неизвестен")
            check(onlyStarting.first { $0.id == "4 running" }?.status == .failed("старая ошибка"), "без очереди та же папка — ошибка")
            let resummarizing = library.items(queue: .init(running: .init(dir: old, kind: .resummarize), pending: []))
            check(resummarizing.last?.status == .processing(nil), "повтор summary на готовой встрече → расшифровывается")
            check(resummarizing.last?.isTranscribed == true, "повтор summary: meeting.md на месте — экран встречи остаётся")
            check(item(old)?.isTranscribed == true && item(failed)?.isTranscribed == false && onlyStarting.first?.isTranscribed == false,
                  "isTranscribed — только у встреч с meeting.md")

            check(item(old)?.title == "Zoom" && item(old)?.app == "Zoom", "название — meta.app")
            check(item(old)?.startedAt == at(1), "startedAt из meta")
            check(item(old)?.duration == 300.5, "длительность из transcript.json: \(String(describing: item(old)?.duration))")
            check(item(failed)?.duration == 600, "без транскрипта — endedAt − startedAt: \(String(describing: item(failed)?.duration))")
            check(item(pending)?.duration == nil, "нет ни транскрипта, ни конца → nil")
            check(item(running)?.sourceFile?.path == "/tmp/Интервью.mp4" && item(old)?.sourceFile == nil, "sourceFile из meta")
            check(item(old)?.dir.lastPathComponent == "1 old", "dir — папка встречи")

            check(MeetingLibrary(store: MeetingStore(outputDir: root.appendingPathComponent("нет"))).items(queue: empty).isEmpty,
                  "папки транскриптов нет — пустой список, не ошибка")
            check(MeetingStatus.recording.title == "Идёт запись" && MeetingStatus.queued.title == "В очереди"
                  && MeetingStatus.processing(nil).title == "Расшифровывается" && MeetingStatus.ready.title == "Готово"
                  && MeetingStatus.failed("x").title == "Ошибка", "подписи статусов")
            check(ProcessingStage.allCases.map(\.title) == ["Извлечение звука", "Распознавание речи", "Спикеры", "Summary"], "подписи этапов по порядку")
        }

        test("библиотека: progress.json, transcript.json и summary из meeting.md") {
            let root = tempDir("library-files")
            let library = MeetingLibrary(store: MeetingStore(outputDir: root))
            let dir = makeMeeting(root, "m", app: "Zoom", started: localDate(2026, 11, 10, 10, 0))
            check(library.progress(dir) == nil && library.transcript(dir) == nil && library.summaryMarkdown(dir) == nil, "файлов нет — nil")

            touch(dir.appendingPathComponent("progress.json"), #"{"stage": "summary", "fraction": null}"#)
            check(library.progress(dir) == ProgressInfo(stage: .summary, fraction: nil), "fraction: null")
            touch(dir.appendingPathComponent("progress.json"), #"{"stage": "diarize"}"#)
            check(library.progress(dir) == ProgressInfo(stage: .diarize, fraction: nil), "обязателен только stage")
            touch(dir.appendingPathComponent("progress.json"), #"{"stage": "upload"}"#)
            check(library.progress(dir) == nil, "неизвестный этап — nil")
            touch(dir.appendingPathComponent("progress.json"), "{не json")
            check(library.progress(dir) == nil, "битый файл — nil")

            touch(dir.appendingPathComponent("transcript.json"),
                  transcriptJSON([(0, 1.5, "Спикер 1", "Начнём"), (3, 4, "Я", "Да")], duration: 12.25), modified: Date().addingTimeInterval(-60))
            check(library.transcript(dir) == Transcript(utterances: [Utterance(start: 0, end: 1.5, speaker: "Спикер 1", text: "Начнём"),
                                                                     Utterance(start: 3, end: 4, speaker: "Я", text: "Да")], duration: 12.25), "транскрипт прочитан")
            touch(dir.appendingPathComponent("transcript.json"), transcriptJSON([(0, 1, "Я", "Заново")], duration: 1))
            check(library.transcript(dir)?.utterances.map(\.text) == ["Заново"], "после повторной обработки читается новый файл")

            // старый формат: в transcript.json нет ключа duration
            let legacy = makeMeeting(root, "legacy", app: "Zoom", started: nil, files: ["transcript.json":
                #"{"utterances": [{"start": 0, "end": 4, "speaker": "Я", "text": "Привет"}, {"start": 10, "end": 42.5, "speaker": "Спикер 1", "text": "Добрый день"}]}"#])
            check(library.transcript(legacy)?.utterances.map(\.text) == ["Привет", "Добрый день"], "без duration реплики на месте: \(String(describing: library.transcript(legacy)))")
            check(library.transcript(legacy)?.duration == 42.5, "длительность — конец последней реплики")
            check(library.items(queue: empty).first { $0.id == "legacy" }?.duration == 42.5, "длительность встречи в списке — тоже")

            touch(dir.appendingPathComponent("meeting.md"), meetingMD(summary: "### Кратко\nОбсудили план.\n\n### Задачи\n- Аня: макеты"))
            check(library.summaryMarkdown(dir) == "### Кратко\nОбсудили план.\n\n### Задачи\n- Аня: макеты", "summary между заголовками: \(library.summaryMarkdown(dir) ?? "nil")")
            touch(dir.appendingPathComponent("meeting.md"), meetingMD(summary: "Summary не удалось сделать: таймаут. Меню → Повторить summary"))
            check(library.summaryMarkdown(dir) == nil, "сбой summary — текста нет")
            touch(dir.appendingPathComponent("meeting.md"), meetingMD(summary: "Summary нет: в записи нечего обобщать."))
            check(library.summaryMarkdown(dir) == nil, "пустая запись — текста нет")
        }

        test("библиотека: название и имена спикеров живут в user.json") {
            let root = tempDir("library-user")
            let library = MeetingLibrary(store: MeetingStore(outputDir: root))
            let dir = makeMeeting(root, "2026-11-10 10-00 Zoom", app: "Zoom", started: localDate(2026, 11, 10, 10, 0))
            let userFile = dir.appendingPathComponent("user.json")
            check(library.userData(dir) == UserData() && !exists(userFile), "пока ничего не переименовано — файла нет")

            try library.setTitle("  Планёрка по релизу ", for: dir)
            try library.setSpeakerName("Аня", label: "Спикер 1", for: dir)
            try library.setSpeakerName("Никита", label: "Я", for: dir)
            let json = readJSON(userFile)
            check(json?["title"] as? String == "Планёрка по релизу", "title в user.json: \(String(describing: json?["title"]))")
            check(json?["speakers"] as? [String: String] == ["Спикер 1": "Аня", "Я": "Никита"], "speakers в user.json: \(String(describing: json?["speakers"]))")
            check((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.sorted() == ["meta.json", "user.json"], "папка не переименована, временных файлов нет")

            let fresh = MeetingLibrary(store: MeetingStore(outputDir: root))  // «после перезапуска»
            check(fresh.items(queue: empty).first?.title == "Планёрка по релизу", "название в списке")
            check(fresh.items(queue: empty).first?.app == "Zoom" && readJSON(dir.appendingPathComponent("meta.json"))?["app"] as? String == "Zoom", "meta.app не тронут")
            let user = fresh.userData(dir)
            check(user.name(for: "Спикер 1") == "Аня" && user.name(for: "Я") == "Никита" && user.name(for: "Спикер 2") == "Спикер 2", "имена по меткам")

            try library.setTitle("   ", for: dir)
            try library.setSpeakerName("", label: "Спикер 1", for: dir)
            check(library.items(queue: empty).first?.title == "Zoom", "пустое название возвращает исходное")
            check(library.userData(dir).name(for: "Спикер 1") == "Спикер 1" && library.userData(dir).name(for: "Я") == "Никита", "пустое имя возвращает метку, остальные на месте")

            touch(userFile, "{не json")
            check(library.userData(dir) == UserData() && library.items(queue: empty).first?.title == "Zoom", "битый user.json — как будто его нет")
            touch(userFile, #"{"title": "Только название"}"#)
            check(library.userData(dir) == UserData(title: "Только название", speakers: [:]), "нет ключа speakers — пусто")
        }

        test("библиотека: секции по дням — Сегодня, Вчера, дата, прошлый год с годом") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            func item(_ id: String, _ date: Date?) -> MeetingItem {
                MeetingItem(id: id, dir: URL(fileURLWithPath: "/tmp/\(id)"), title: id, app: "Zoom", startedAt: date,
                            duration: nil, status: .ready, sourceFile: nil, summaryFailed: false)
            }
            let items = [item("a", localDate(2026, 11, 10, 9, 0)), item("b", localDate(2026, 11, 10, 0, 5)),
                         item("c", localDate(2026, 11, 9, 23, 55)), item("d", localDate(2026, 11, 5, 12, 0)),
                         item("e", localDate(2026, 1, 1, 12, 0)), item("f", localDate(2025, 11, 5, 12, 0)), item("g", nil)]
            let sections = MeetingLibrary.sections(items, now: localDate(2026, 11, 10, 12, 0), calendar: calendar)
            check(sections.map(\.title) == ["Сегодня", "Вчера", "5 ноября", "1 января", "5 ноября 2025", "Без даты"], "заголовки: \(sections.map(\.title))")
            check(sections.map { $0.items.map(\.id) } == [["a", "b"], ["c"], ["d"], ["e"], ["f"], ["g"]], "встречи по секциям, порядок сохранён")
            check(Set(sections.map(\.id)).count == sections.count, "id секций разные")
            check(MeetingLibrary.sections([], now: Date(), calendar: calendar).isEmpty, "нет встреч — нет секций")
            let newYear = MeetingLibrary.sections([item("x", localDate(2025, 12, 31, 20, 0))], now: localDate(2026, 1, 1, 10, 0), calendar: calendar)
            check(newYear.map(\.title) == ["Вчера"], "вчера через границу года: \(newYear.map(\.title))")
        }

        test("библиотека: поиск по названию и тексту без регистра и ё/е, до трёх фрагментов") {
            let root = tempDir("library-search")
            let library = MeetingLibrary(store: MeetingStore(outputDir: root))
            let day = localDate(2026, 11, 10, 10, 0)
            let long = String(repeating: "очень длинная вводная часть реплики ", count: 6) + "тут про Ёлку и подарки"
                + String(repeating: " и ещё много слов после", count: 6)
            _ = makeMeeting(root, "1 budget", app: "Zoom", started: day, files: ["transcript.json": transcriptJSON([
                (0, 5, "Я", "Давайте ещё раз обсудим бюджет"), (12.5, 20, "Спикер 1", "Бюджет на ёлку утверждён"),
                (30, 40, "Я", "БЮДЖЕТ пересчитаем"), (50, 60, "Спикер 1", "Про бюджет всё"), (70, 80, "Я", long)], duration: 80)])
            let planning = makeMeeting(root, "2 planning", app: "Meet", started: day.addingTimeInterval(60),
                                       files: ["transcript.json": transcriptJSON([(0, 5, "Я", "Обсудили сроки")], duration: 5)])
            try library.setTitle("Планёрка", for: planning)
            _ = makeMeeting(root, "3 empty", app: "Толк", started: day.addingTimeInterval(120))
            let items = library.items(queue: empty)

            let all = library.search("  ", in: items)
            check(all.map(\.item.id) == items.map(\.id) && all.allSatisfy { $0.snippets.isEmpty && !$0.inTitle }, "пустой запрос — все встречи без фрагментов")

            let budget = library.search("бюджет", in: items)
            check(budget.map(\.item.id) == ["1 budget"], "найдена одна встреча: \(budget.map(\.item.id))")
            check(budget.first?.inTitle == false, "совпадение не в названии")
            check(budget.first?.snippets.map(\.start) == [0, 12.5, 30], "до трёх фрагментов с таймкодом: \(String(describing: budget.first?.snippets.map(\.start)))")
            check(budget.first?.snippets.first?.text == "Давайте ещё раз обсудим бюджет", "короткая реплика целиком")
            check(budget.first?.snippets.last?.text == "БЮДЖЕТ пересчитаем", "регистр не важен, текст — как в записи")

            check(library.search("еще раз", in: items).first?.snippets.map(\.start) == [0], "«еще» находит «ещё»")
            let tree = library.search("ЕЛКУ", in: items).first?.snippets ?? []
            check(tree.map(\.start) == [12.5, 70], "«ЕЛКУ» находит «ёлку» и «Ёлку»: \(tree.map(\.start))")
            if let cut = tree.last?.text {
                check(cut.contains("про Ёлку и подарки") && cut.hasPrefix("…") && cut.hasSuffix("…") && cut.count < 140,
                      "из длинной реплики — фрагмент вокруг совпадения: \(cut)")
            }

            let title = library.search("планерка", in: items)
            check(title.map(\.item.id) == ["2 planning"] && title.first?.inTitle == true && title.first?.snippets.isEmpty == true, "по названию, «е» вместо «ё»")
            check(library.search("zoom", in: items).map(\.item.id) == ["1 budget"], "название по умолчанию — приложение")
            check(library.search("квартальный отчёт", in: items).isEmpty, "ничего не нашлось — пусто")
        }
    }
}
