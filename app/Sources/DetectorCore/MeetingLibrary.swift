import Foundation

/// Этап обработки из `progress.json` (пишет Python).
public enum ProcessingStage: String, CaseIterable, Sendable {
    case extract, asr, diarize, summary

    public var title: String {
        switch self {
        case .extract: return "Извлечение звука"
        case .asr: return "Распознавание речи"
        case .diarize: return "Спикеры"
        case .summary: return "Summary"
        }
    }
}

public struct ProgressInfo: Equatable, Sendable {
    public let stage: ProcessingStage
    public let fraction: Double?
    public init(stage: ProcessingStage, fraction: Double?) { self.stage = stage; self.fraction = fraction }
}

/// Статус не хранится, а вычисляется по файлам папки и снимку очереди — старые папки работают сами.
public enum MeetingStatus: Equatable, Sendable {
    case recording, queued, processing(ProgressInfo?), ready, failed(String)

    public var title: String {
        switch self {
        case .recording: return "Идёт запись"
        case .queued: return "В очереди"
        case .processing: return "Расшифровывается"
        case .ready: return "Готово"
        case .failed: return "Ошибка"
        }
    }
}

public struct MeetingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let dir: URL
    public let title: String
    public let app: String
    public let startedAt: Date?
    public let duration: TimeInterval?
    public let status: MeetingStatus
    public let sourceFile: URL?
    public let summaryFailed: Bool
    /// `meeting.md` есть: экран встречи показывает транскрипт, даже пока идёт повтор summary.
    public let isTranscribed: Bool

    public init(id: String, dir: URL, title: String, app: String, startedAt: Date?, duration: TimeInterval?,
                status: MeetingStatus, sourceFile: URL?, summaryFailed: Bool, isTranscribed: Bool = false) {
        self.isTranscribed = isTranscribed
        self.id = id; self.dir = dir; self.title = title; self.app = app; self.startedAt = startedAt
        self.duration = duration; self.status = status; self.sourceFile = sourceFile; self.summaryFailed = summaryFailed
    }
}

public struct Utterance: Codable, Equatable, Sendable {
    public let start, end: Double
    public let speaker: String
    public let text: String
    public init(start: Double, end: Double, speaker: String, text: String) {
        self.start = start; self.end = end; self.speaker = speaker; self.text = text
    }
}

public struct Transcript: Codable, Equatable, Sendable {
    public let utterances: [Utterance]
    public let duration: Double
    public init(utterances: [Utterance], duration: Double) { self.utterances = utterances; self.duration = duration }

    // в старых transcript.json ключа duration нет — берём конец последней реплики
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utterances = try c.decode([Utterance].self, forKey: .utterances)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? utterances.map(\.end).max() ?? 0
    }
}

/// Правки пользователя из `user.json`: пишет только приложение, Python читает.
public struct UserData: Codable, Equatable, Sendable {
    public var title: String?
    public var speakers: [String: String]

    public init(title: String? = nil, speakers: [String: String] = [:]) { self.title = title; self.speakers = speakers }

    // нет ключа или не тот тип — как будто правки нет: файл мог быть написан руками
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        speakers = (try? c.decodeIfPresent([String: String].self, forKey: .speakers)) ?? [:]
    }

    public func name(for label: String) -> String {
        speakers[label].flatMap { $0.isEmpty ? nil : $0 } ?? label
    }
}

public struct DaySection: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let items: [MeetingItem]
}

public struct Snippet: Equatable {
    public let start: Double
    public let text: String
}

public struct SearchHit: Equatable {
    public let item: MeetingItem
    public let inTitle: Bool
    public let snippets: [Snippet]
}

/// Чтение встреч для окна: список со статусами, транскрипт, правки пользователя, поиск.
public final class MeetingLibrary {
    private let store: MeetingStore
    private let fm = FileManager.default
    // транскрипты кешируются по времени изменения: список обновляется раз в секунду, поиск — на каждую букву
    private let lock = NSLock()
    private var transcripts: [String: (modified: Date, transcript: Transcript)] = [:]

    public init(store: MeetingStore) { self.store = store }

    /// Все встречи, новые первыми.
    public func items(queue: ProcessingQueue.Snapshot) -> [MeetingItem] {
        let running = queue.running?.dir.standardizedFileURL.path
        let pending = Set(queue.pending.map { $0.dir.standardizedFileURL.path })
        return store.allMeetings().map { dir in
            let meta = store.readMeta(dir) ?? [:]
            let app = meta["app"] as? String ?? ""
            let path = dir.standardizedFileURL.path
            func has(_ name: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(name).path) }

            let status: MeetingStatus
            if has(MeetingStore.recordingMarker) { status = .recording }
            else if path == running { status = .processing(progress(dir)) }
            else if pending.contains(path) { status = .queued }
            else if has("meeting.md") { status = .ready }
            else if let text = try? String(contentsOf: dir.appendingPathComponent("error.txt"), encoding: .utf8) {
                status = .failed(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? "Ошибка обработки")
            } else { status = .queued }

            let started = MeetingStore.parseISO(meta["startedAt"] as? String)
            let ended = MeetingStore.parseISO(meta["endedAt"] as? String)
            let title = userData(dir).title.flatMap { $0.isEmpty ? nil : $0 } ?? (app.isEmpty ? dir.lastPathComponent : app)
            return MeetingItem(
                id: dir.lastPathComponent, dir: dir, title: title, app: app, startedAt: started,
                duration: transcript(dir)?.duration ?? started.flatMap { s in ended.map { $0.timeIntervalSince(s) } },
                status: status,
                sourceFile: (meta["sourceFile"] as? String).map { URL(fileURLWithPath: $0) },
                summaryFailed: summaryFailed(dir), isTranscribed: has("meeting.md"))
        }
    }

    public func transcript(_ dir: URL) -> Transcript? {
        let url = dir.appendingPathComponent("transcript.json")
        guard let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        lock.lock(); let cached = transcripts[url.path]; lock.unlock()
        if let cached, cached.modified == modified { return cached.transcript }
        guard let data = try? Data(contentsOf: url),
              let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else { return nil }
        lock.lock(); transcripts[url.path] = (modified, transcript); lock.unlock()
        return transcript
    }

    /// Текст между «## Summary» и «## Транскрипт» в `meeting.md`; nil, если summary нет или оно не получилось.
    public func summaryMarkdown(_ dir: URL) -> String? {
        guard let md = try? String(contentsOf: dir.appendingPathComponent("meeting.md"), encoding: .utf8),
              let from = md.range(of: "## Summary\n"),
              // с конца: строка «## Транскрипт» может встретиться в самом summary, а среди реплик — нет
              let to = md.range(of: "\n## Транскрипт", options: .backwards, range: from.upperBound..<md.endIndex) else { return nil }
        let text = md[from.upperBound..<to.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.hasPrefix(Self.summaryFailedPrefix) || text.hasPrefix("Summary нет:") ? nil : text
    }

    public func userData(_ dir: URL) -> UserData {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("user.json")),
              let user = try? JSONDecoder().decode(UserData.self, from: data) else { return UserData() }
        return user
    }

    /// Пустое название возвращает исходное (`meta.app`).
    public func setTitle(_ title: String, for dir: URL) throws {
        var user = userData(dir)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        user.title = title.isEmpty ? nil : title
        try write(user, to: dir)
    }

    /// Пустое имя возвращает метку из транскрипта.
    public func setSpeakerName(_ name: String, label: String, for dir: URL) throws {
        var user = userData(dir)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        user.speakers[label] = name.isEmpty || name == label ? nil : name
        try write(user, to: dir)
    }

    public func progress(_ dir: URL) -> ProgressInfo? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("progress.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stage = (json["stage"] as? String).flatMap(ProcessingStage.init(rawValue:)) else { return nil }
        return ProgressInfo(stage: stage, fraction: (json["fraction"] as? NSNumber)?.doubleValue)
    }

    /// Секции по дням в порядке списка: «Сегодня», «Вчера», «5 ноября», прошлые годы — «5 ноября 2025».
    public static func sections(_ items: [MeetingItem], now: Date, calendar: Calendar) -> [DaySection] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        var order: [String] = []
        var groups: [String: (title: String, items: [MeetingItem])] = [:]
        for item in items {
            var id = "none", title = "Без даты"
            if let date = item.startedAt {
                let day = calendar.dateComponents([.year, .month, .day], from: date)
                id = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
                let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
                if daysAgo == 0 { title = "Сегодня" }
                else if daysAgo == 1 { title = "Вчера" }
                else {
                    formatter.dateFormat = day.year == calendar.component(.year, from: now) ? "d MMMM" : "d MMMM yyyy"
                    title = formatter.string(from: date)
                }
            }
            if groups[id] == nil { order.append(id); groups[id] = (title, []) }
            groups[id]?.items.append(item)
        }
        return order.map { DaySection(id: $0, title: groups[$0]!.title, items: groups[$0]!.items) }
    }

    /// Поиск по названию и тексту реплик без учёта регистра и «ё/е». Пустой запрос — все встречи без фрагментов.
    /// Читает транскрипты — вызывать не с главного потока.
    public func search(_ query: String, in items: [MeetingItem]) -> [SearchHit] {
        let query = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return items.map { SearchHit(item: $0, inTitle: false, snippets: []) } }
        return items.compactMap { item in
            let inTitle = Self.fold(item.title).contains(query)
            var snippets: [Snippet] = []
            for utterance in transcript(item.dir)?.utterances ?? [] {
                guard let text = Self.excerpt(utterance.text, around: query) else { continue }
                snippets.append(Snippet(start: utterance.start, text: text))
                if snippets.count == 3 { break }
            }
            return inTitle || !snippets.isEmpty ? SearchHit(item: item, inTitle: inTitle, snippets: snippets) : nil
        }
    }

    // MARK: - внутреннее

    static let summaryFailedPrefix = "Summary не удалось сделать"

    /// Строка о сбое summary стоит в начале `meeting.md` — весь файл ради неё не читаем.
    private func summaryFailed(_ dir: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: dir.appendingPathComponent("meeting.md")) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 2048), as: UTF8.self)
        return head.contains("## Summary\n\n\(Self.summaryFailedPrefix)")
    }

    private func write(_ user: UserData, to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(user).write(to: dir.appendingPathComponent("user.json"), options: .atomic)
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// Кусок реплики вокруг совпадения, в исходном написании.
    private static func excerpt(_ text: String, around query: String) -> String? {
        let folded = fold(text)
        guard let match = folded.range(of: query) else { return nil }
        // замена «ё→е» и нижний регистр не меняют число символов, поэтому смещения годятся для исходной строки
        let chars = Array(text)
        let at = min(folded.distance(from: folded.startIndex, to: match.lowerBound), chars.count)
        let from = max(0, at - 40), to = min(chars.count, at + query.count + 60)
        let cut = String(chars[from..<to]).trimmingCharacters(in: .whitespaces)
        return (from > 0 ? "…" : "") + cut + (to < chars.count ? "…" : "")
    }
}
