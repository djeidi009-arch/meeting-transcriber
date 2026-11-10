import DetectorCore
import Foundation

/// Режим `--demo`: выдуманные встречи во временной папке, обработка и запись проигрываются без Python и микрофона.
extension AppModel {
    static func demoDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("transcriber-demo-\(getpid())")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try DemoLibrary.create(at: dir)
        return dir
    }

    /// Добавляет к готовым встречам по одной на каждый «живой» статус, чтобы все пять были видны сразу.
    func startDemo() {
        toggleRecording = { [unowned self] in demoToggleRecording() }
        let now = Date()
        func movie(_ name: String) -> URL { URL(fileURLWithPath: "/Users/demo/Movies/\(name).mp4") }

        demoToggleRecording(title: "Созвон с подрядчиком", startedAt: now.addingTimeInterval(-125))
        // без meeting.md и error.txt папка сама считается «В очереди»
        _ = try? store.createImport(file: movie("Лекция о типографике"), at: now.addingTimeInterval(-600))
        // эта «расшифровывается» по кругу — экран обработки всегда можно показать и снять
        if let dir = try? store.createImport(file: movie("Вебинар по аналитике"), at: now.addingTimeInterval(-1200)) {
            simulateProcessing(dir, loop: true)
        }
        // эта проходит «В очереди → Расшифровывается → Готово» на глазах
        if let dir = try? store.createImport(file: movie("Созвон с заказчиком"), at: now.addingTimeInterval(-300)) {
            simulateProcessing(dir)
        }
        refresh()
    }

    private func demoToggleRecording(title: String = "Встреча", startedAt: Date = Date()) {
        if let dir = demoRecordingDir {
            demoRecordingDir = nil
            isRecording = false
            recordingStartedAt = nil
            store.finishMeeting(dir, minDuration: 0)
            simulateProcessing(dir)
        } else if let dir = try? store.createMeeting(app: title, bundleID: "", manual: true, startedAt: startedAt) {
            demoRecordingDir = dir
            isRecording = true
            recordingStartedAt = startedAt
            refresh()
        }
    }

    /// Этапы по ~3 с каждый, затем встреча получает готовый выдуманный транскрипт.
    func simulateProcessing(_ dir: URL, stages: [ProcessingStage] = ProcessingStage.allCases, loop: Bool = false) {
        let id = dir.lastPathComponent
        guard demoStatus[id] == nil else { return }
        demoStatus[id] = .queued
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(3))
            repeat {
                for stage in stages {
                    for step in 0..<3 {
                        demoStatus[id] = .processing(ProgressInfo(stage: stage, fraction: Double(step) / 3))
                        refresh()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } while loop
            finishDemo(dir)
            demoStatus[id] = nil
            refresh()
        }
    }

    private func finishDemo(_ dir: URL) {
        guard let item = items.first(where: { $0.id == dir.lastPathComponent }) else { return }
        let lines: [(String, String)] = [
            ("Я", "Давайте коротко сверимся по «Маяку». Что с новой картой этажа?"),
            ("Спикер 1", "Карта готова, осталось проверить её на маленьких экранах."),
            ("Я", "Когда сможем показать команде?"),
            ("Спикер 1", "В четверг. К этому времени поправлю подписи комнат и масштаб."),
            ("Я", "Отлично, тогда в четверг и решим, что берём в релиз."),
        ]
        let utterances = lines.enumerated().map { index, line in
            Utterance(start: Double(index) * 14 + 2, end: Double(index) * 14 + 13, speaker: line.0, text: line.1)
        }
        // у встречи с транскриптом (повтор summary) текст не подменяем
        let transcript = library.transcript(dir) ?? Transcript(utterances: utterances, duration: 72)
        let summary = """
        ### Кратко
        Сверились по карте этажа «Маяка»: она готова, осталась проверка на маленьких экранах.

        ### Решения
        - Показ команде — в четверг.

        ### Задачи
        - Спикер 1: поправить подписи комнат и масштаб до четверга.

        ### Открытые вопросы
        - Что из готового войдёт в релиз.
        """
        let markdown = MeetingDocument(item: item, transcript: transcript, summaryMarkdown: summary,
                                       user: library.userData(dir)).markdown()
        try? JSONEncoder().encode(transcript).write(to: dir.appendingPathComponent("transcript.json"))
        try? Data(markdown.utf8).write(to: dir.appendingPathComponent("meeting.md"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("error.txt"))
    }
}
