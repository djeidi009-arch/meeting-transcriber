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
        // звук готовым встречам — в фоне, новые первыми; экран встречи подхватит его по demoAudioReady
        let dirs = store.allMeetings()
        Task {
            for dir in dirs {
                await synthesizeAudio(dir)
            }
        }
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
            recordingLevels = []
            refresh()
            // громкость «микрофона»: слоги и фразы с паузами, 20 раз в секунду — как от настоящего Recorder
            Task {
                while demoRecordingDir == dir {
                    let t = Date().timeIntervalSinceReferenceDate
                    let phrase = sin(t * 0.8) > -0.5 ? 0.25 + 0.5 * abs(sin(t * 1.9)) : 0.03
                    pushLevel(Float(phrase * (0.3 + 0.7 * abs(sin(t * 11) * sin(t * 2.7 + 1)))))
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    /// Этапы по ~3 с каждый, затем встреча получает готовый выдуманный транскрипт.
    /// Этап пишется в `progress.json` в формате Python — экран читает его тем же путём, что и при настоящей обработке.
    /// Встречи идут по одной, как в настоящей очереди; та, что крутится по кругу, очередь не занимает.
    func simulateProcessing(_ dir: URL, stages: [ProcessingStage] = ProcessingStage.allCases, loop: Bool = false) {
        let id = dir.lastPathComponent
        guard demoStatus[id] == nil else { return }
        demoStatus[id] = .queued
        refresh()
        let previous = loop ? nil : demoQueueTail
        let progressFile = dir.appendingPathComponent("progress.json")
        let task = Task {
            await previous?.value
            try? await Task.sleep(for: .seconds(1.5))
            repeat {
                for stage in stages {
                    for step in 0..<3 {
                        // доля известна только у распознавания — как у настоящей обработки
                        let fraction: Any = stage == .asr ? Double(step) / 3 : NSNull()
                        let json: [String: Any] = ["stage": stage.rawValue, "fraction": fraction, "updatedAt": MeetingStore.iso(Date())]
                        try? JSONSerialization.data(withJSONObject: json).write(to: progressFile, options: .atomic)
                        demoStatus[id] = .processing(nil)
                        refresh()
                        try? await Task.sleep(for: .seconds(1))
                    }
                    // звук «извлечён» — дальше волна обработки показывает его настоящую форму
                    if stage == .extract { await synthesizeAudio(dir, transcript: demoTranscript(dir)) }
                }
            } while loop
            finishDemo(dir)
            await synthesizeAudio(dir)
            try? FileManager.default.removeItem(at: progressFile)
            demoStatus[id] = nil
            refresh()
        }
        if !loop { demoQueueTail = task }
    }

    /// Транскрипт демо-встречи: свой, если есть (повтор summary), иначе выдуманный.
    private func demoTranscript(_ dir: URL) -> Transcript {
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
        return library.transcript(dir) ?? Transcript(utterances: utterances, duration: 72)
    }

    private func finishDemo(_ dir: URL) {
        guard let item = items.first(where: { $0.id == dir.lastPathComponent }) else { return }
        let transcript = demoTranscript(dir)
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
    /// Звук демо-встречи: «голос» каждого спикера — тон своей высоты со слоговой огибающей.
    /// «Я» идёт в `mic.m4a`, собеседники — в `system.m4a`, как у настоящей записи.
    private func synthesizeAudio(_ dir: URL, transcript: Transcript? = nil) async {
        // готовый звук не переписываем: его сейчас может играть плеер
        guard !demoAudioReady.contains(dir.lastPathComponent),
              let transcript = transcript ?? library.transcript(dir), !transcript.utterances.isEmpty else { return }
        await Task.detached {
            let rate = 16000.0
            for (file, mine) in [("mic", true), ("system", false)] {
                let lines = transcript.utterances.filter { ($0.speaker == "Я") == mine }
                if lines.isEmpty { continue }
                var samples = [Int16](repeating: 0, count: Int(transcript.duration * rate))
                for line in lines {
                    let pitch = 110 + Double(line.speaker.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7) * 22
                    for index in Int(line.start * rate)..<min(samples.count, Int(line.end * rate)) {
                        let t = Double(index) / rate
                        // слоги ~4 в секунду; фразы по несколько секунд разной громкости, между ними паузы
                        let phrase = Double((Int(t / 4) &* 2654435761) % 100) / 100
                        let envelope = pow(abs(sin(.pi * 4 * t)), 0.8) * (phrase < 0.12 ? 0 : 0.08 + 0.92 * phrase * phrase)
                        let voice = sin(2 * .pi * pitch * t) + 0.5 * sin(4 * .pi * pitch * t) + 0.25 * sin(6 * .pi * pitch * t)
                        samples[index] = Int16(envelope * voice * 0.12 * 32767 / 1.75)
                    }
                }
                func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
                let bytes = UInt32(samples.count * 2)
                var wav = Data("RIFF".utf8) + le(36 + bytes) + Data("WAVEfmt ".utf8) + le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1))
                wav += le(UInt32(rate)) + le(UInt32(rate) * 2) + le(UInt16(2)) + le(UInt16(16)) + Data("data".utf8) + le(bytes)
                samples.withUnsafeBufferPointer { wav.append(Data(buffer: $0)) } // Apple Silicon — little-endian
                let source = dir.appendingPathComponent("\(file).wav")
                guard (try? wav.write(to: source)) != nil else { continue }
                let convert = Process()
                convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                convert.arguments = ["-f", "m4af", "-d", "aac", "-b", "32000", source.path, dir.appendingPathComponent("\(file).m4a").path]
                try? convert.run()
                convert.waitUntilExit()
                try? FileManager.default.removeItem(at: source)
            }
        }.value
        demoAudioReady.insert(dir.lastPathComponent)
    }
}
