import Foundation
import DetectorCore

enum DocumentTests {
    static func item(title: String = "Zoom", started: Date? = localDate(2026, 10, 23, 15, 30), duration: TimeInterval? = 3930) -> MeetingItem {
        MeetingItem(id: "m", dir: URL(fileURLWithPath: "/tmp/m"), title: title, app: "Zoom", startedAt: started,
                    duration: duration, status: .ready, sourceFile: nil, summaryFailed: false)
    }

    static let transcript = Transcript(utterances: [
        Utterance(start: 5, end: 35, speaker: "Спикер 1", text: "Начнём."),
        Utterance(start: 40, end: 50, speaker: "Я", text: "Да, давайте."),
        Utterance(start: 3725.4, end: 3735.4, speaker: "Спикер 1", text: "Всем спасибо."),
    ], duration: 3930)

    static func all() {
        test("документ: короткий таймкод, текущая реплика, блоки summary") {
            check(MeetingDocument.shortTimecode(0) == "00:00" && MeetingDocument.shortTimecode(65.9) == "01:05", "мм:сс: \(MeetingDocument.shortTimecode(65.9))")
            check(MeetingDocument.shortTimecode(3725.4) == "1:02:05" && MeetingDocument.shortTimecode(-2) == "00:00", "от часа — ч:мм:сс: \(MeetingDocument.shortTimecode(3725.4))")

            check(MeetingDocument.shortError("Файл не найден: /Users/demo/Movies/Демо для партнёров.mp4") == "Файл не найден: Демо для партнёров.mp4", "путь сжат до имени файла")
            check(MeetingDocument.shortError("Нет речи: 1/2 дорожек") == "Нет речи: 1/2 дорожек" && MeetingDocument.shortError("/tmp/a.wav") == "a.wav" && MeetingDocument.shortError("Сбой /") == "Сбой /", "не путь — как есть")

            let doc = MeetingDocument(item: item(), transcript: transcript,
                                      summaryMarkdown: "### Кратко\nОбсудили **бюджет**.\n\n### Задачи\n- Аня: макеты\n* Я: смета\n  1. Третье", user: UserData())
            check(doc.lineIndex(at: 0) == nil && doc.lineIndex(at: 4.9) == nil, "до первой реплики — ничего")
            check(doc.lineIndex(at: 5) == 0 && doc.lineIndex(at: 39) == 0, "реплика держится до начала следующей")
            check(doc.lineIndex(at: 40) == 1 && doc.lineIndex(at: 9999) == 2, "следующая и последняя")
            check(doc.summaryBlocks() == [.heading("Кратко"), .paragraph("Обсудили **бюджет**."), .heading("Задачи"),
                                          .bullet("Аня: макеты"), .bullet("Я: смета"), .bullet("Третье")], "блоки: \(doc.summaryBlocks())")
            check(MeetingDocument(item: item(), transcript: nil, summaryMarkdown: nil, user: UserData()).summaryBlocks().isEmpty, "нет summary — нет блоков")
        }

        test("документ: markdown в формате meeting.md с названием и именами") {
            let user = UserData(title: "Планёрка по релизу", speakers: ["Спикер 1": "Аня"])
            let doc = MeetingDocument(item: item(title: "Планёрка по релизу"), transcript: transcript,
                                      summaryMarkdown: "### Кратко\nОбсудили бюджет.", user: user)
            let expected = """
            # Планёрка по релизу — 23.10.2026 15:30

            Длительность: 1 ч 5 мин

            ## Summary

            ### Кратко
            Обсудили бюджет.

            ## Транскрипт

            **[00:00:05] Аня:** Начнём.

            **[00:00:40] Я:** Да, давайте.

            **[01:02:05] Аня:** Всем спасибо.

            """
            check(doc.markdown() == expected, "markdown:\n\(doc.markdown())")
            check(doc.title == "Планёрка по релизу" && doc.lines.count == 3, "название и реплики")
            check(doc.lines.first == .init(start: 5, speakerLabel: "Спикер 1", speakerName: "Аня", text: "Начнём."), "метка и имя в строке")

            let plain = MeetingDocument(item: item(started: nil, duration: 45), transcript: nil, summaryMarkdown: nil, user: UserData())
            check(plain.markdown() == "# Zoom\n\nДлительность: 45 с\n\n## Summary\n\nSummary нет.\n\n## Транскрипт\n\nРечь не распознана\n",
                  "без даты, summary и речи:\n\(plain.markdown())")
            check(MeetingDocument(item: item(duration: 1500), transcript: nil, summaryMarkdown: nil, user: UserData()).markdown().contains("Длительность: 25 мин"), "минуты")
        }

        test("документ: простой текст без разметки, таймкоды, доли спикеров") {
            let user = UserData(title: nil, speakers: ["Спикер 1": "Аня"])
            let doc = MeetingDocument(item: item(), transcript: transcript,
                                      summaryMarkdown: "### Кратко\nОбсудили **бюджет**.\n\n### Задачи\n- Аня: макеты", user: user)
            let text = doc.plainText()
            check(text == """
            Zoom
            23.10.2026 15:30 · 1 ч 5 мин

            Кратко
            Обсудили бюджет.

            Задачи
            • Аня: макеты

            [00:00:05] Аня: Начнём.
            [00:00:40] Я: Да, давайте.
            [01:02:05] Аня: Всем спасибо.

            """, "простой текст:\n\(text)")
            check(!text.contains("#") && !text.contains("**"), "разметки нет")
            let noSummary = MeetingDocument(item: item(), transcript: transcript, summaryMarkdown: nil, user: user).plainText()
            check(noSummary.hasPrefix("Zoom\n23.10.2026 15:30 · 1 ч 5 мин\n\n[00:00:05] Аня: Начнём."), "без summary — сразу реплики:\n\(noSummary)")

            check(MeetingDocument.timecode(0) == "00:00:00" && MeetingDocument.timecode(3725.9) == "01:02:05" && MeetingDocument.timecode(-3) == "00:00:00", "таймкод чч:мм:сс")

            let shares = doc.speakerShares()
            check(shares.map(\.label) == ["Спикер 1", "Я"] && shares.map(\.name) == ["Аня", "Я"], "спикеры по порядку появления: \(shares)")
            check(shares.count == 2 && abs(shares[0].share - 0.8) < 1e-9 && abs(shares[1].share - 0.2) < 1e-9, "доли по времени речи 40 с и 10 с: \(shares)")
            check(abs(shares.reduce(0) { $0 + $1.share } - 1) < 1e-9, "в сумме 1")
            check(MeetingDocument(item: item(), transcript: nil, summaryMarkdown: nil, user: user).speakerShares().isEmpty, "нет реплик — нет долей")
        }

        test("демо: выдуманные встречи создаются в настоящем формате и читаются библиотекой") {
            let root = tempDir("demo")
            try DemoLibrary.create(at: root)
            let library = MeetingLibrary(store: MeetingStore(outputDir: root))
            let items = library.items(queue: LibraryTests.empty)
            check((6...8).contains(items.count), "6–8 встреч: \(items.count)")
            let failed = items.filter { if case .failed = $0.status { return true } else { return false } }
            check(failed.count == 1, "одна с ошибкой: \(failed.count)")
            check(items.filter { $0.summaryFailed }.count == 1, "одна без summary")
            let ready = items.filter { $0.status == .ready && !$0.summaryFailed }
            check(ready.count >= 4, "остальные готовы: \(ready.count)")
            check(ready.allSatisfy { library.summaryMarkdown($0.dir)?.contains("### Кратко") == true }, "у готовых есть summary с блоком «Кратко»")
            check(items.filter { $0.status == .ready }.allSatisfy { (library.transcript($0.dir)?.utterances.count ?? 0) >= 6 }, "у расшифрованных есть реплики")
            check(items.allSatisfy { $0.startedAt != nil && readJSON($0.dir.appendingPathComponent("meta.json"))?["app"] is String }, "meta.json настоящий")
            check(Set(items.map(\.app)).count >= 3, "разные приложения: \(Set(items.map(\.app)))")
            check(Set(ready.compactMap(\.duration).map { Int($0 / 60) }).count >= 4, "разные длительности")
            let sections = MeetingLibrary.sections(items, now: Date(), calendar: .current)
            check(sections.count >= 4, "разные дни: \(sections.map(\.title))")
            check(items.contains { $0.title != $0.app } && items.contains { !library.userData($0.dir).speakers.isEmpty }, "есть переименованные встреча и спикеры")
            for item in ready {
                let doc = MeetingDocument(item: item, transcript: library.transcript(item.dir),
                                          summaryMarkdown: library.summaryMarkdown(item.dir), user: library.userData(item.dir))
                let md = (try? String(contentsOf: item.dir.appendingPathComponent("meeting.md"), encoding: .utf8)) ?? ""
                check(md == doc.markdown(), "meeting.md совпадает с документом: \(item.id)")
            }
            check(!library.search("релиз", in: items).isEmpty, "поиск по демо-встречам работает")
        }
    }
}
