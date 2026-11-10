import Foundation

/// Встреча с подставленными названием и именами — одна модель для экрана и экспорта.
public struct MeetingDocument: Equatable {
    public struct Line: Equatable {
        public let start: Double
        public let speakerLabel: String
        public let speakerName: String
        public let text: String
        public init(start: Double, speakerLabel: String, speakerName: String, text: String) {
            self.start = start; self.speakerLabel = speakerLabel; self.speakerName = speakerName; self.text = text
        }
    }

    public let title: String
    public let startedAt: Date?
    public let duration: TimeInterval?
    public let summaryMarkdown: String?
    public let lines: [Line]

    /// Длина каждой реплики в секундах — для долей речи.
    private let lengths: [Double]

    public init(item: MeetingItem, transcript: Transcript?, summaryMarkdown: String?, user: UserData) {
        title = user.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.title
        startedAt = item.startedAt
        duration = item.duration
        self.summaryMarkdown = summaryMarkdown
        let utterances = transcript?.utterances ?? []
        lines = utterances.map { Line(start: $0.start, speakerLabel: $0.speaker, speakerName: user.name(for: $0.speaker), text: $0.text) }
        lengths = utterances.map { max(0, $0.end - $0.start) }
    }

    /// Тот же формат, что `meeting.md` (его пишет `transcriber/render.py`).
    public func markdown() -> String {
        var out = ["# " + ([title] + dateText()).joined(separator: " — "), "",
                   "Длительность: \(Self.durationText(duration ?? 0))", "",
                   "## Summary", "", summaryMarkdown ?? "Summary нет.", "",
                   "## Транскрипт", ""]
        if lines.isEmpty { out.append("Речь не распознана") }
        for line in lines { out += ["**[\(Self.timecode(line.start))] \(line.speakerName):** \(line.text)", ""] }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// Summary и реплики без разметки — для «Копировать текст».
    public func plainText() -> String {
        var out = [title, (dateText() + [Self.durationText(duration ?? 0)]).joined(separator: " · "), ""]
        if let summaryMarkdown {
            for line in summaryMarkdown.components(separatedBy: "\n") {
                out.append(line
                    .replacingOccurrences(of: #"^\s*#+\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(\s*)[-*]\s+"#, with: "$1• ", options: .regularExpression)
                    .replacingOccurrences(of: "**", with: ""))
            }
            out.append("")
        }
        out += lines.map { "[\(Self.timecode($0.start))] \($0.speakerName): \($0.text)" }
        return out.joined(separator: "\n") + "\n"
    }

    public static func timecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// «1 ч 5 мин», «25 мин», «45 с» — как в `meeting.md`.
    public static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = total % 3600 / 60
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        return minutes > 0 ? "\(minutes) мин" : "\(total) с"
    }

    /// Доля речи каждого спикера по времени его реплик, в порядке первого появления; в сумме 1.
    public func speakerShares() -> [(label: String, name: String, share: Double)] {
        // у всех реплик нулевая длина (битый транскрипт) — делим по числу реплик
        let weights = lengths.contains { $0 > 0 } ? lengths : lengths.map { _ in 1 }
        let total = weights.reduce(0, +)
        var order: [(label: String, name: String)] = []
        var sums: [String: Double] = [:]
        for (line, weight) in zip(lines, weights) {
            if sums[line.speakerLabel] == nil { order.append((line.speakerLabel, line.speakerName)) }
            sums[line.speakerLabel, default: 0] += weight
        }
        return order.map { (label: $0.label, name: $0.name, share: sums[$0.label]! / total) }
    }

    /// Таймкод для экрана: «мм:сс», от часа — «ч:мм:сс».
    public static func shortTimecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let tail = String(format: "%02d:%02d", total % 3600 / 60, total % 60)
        return total >= 3600 ? "\(total / 3600):\(tail)" : tail
    }

    /// Номер реплики, которая звучит в этот момент: последняя, начавшаяся не позже `time`.
    public func lineIndex(at time: Double) -> Int? {
        lines.lastIndex { $0.start <= time }
    }

    public enum SummaryBlock: Equatable { case heading(String), bullet(String), paragraph(String) }

    /// Summary по блокам — для отрисовки на экране и в DOCX/PDF (жирный внутри строки остаётся разметкой).
    public func summaryBlocks() -> [SummaryBlock] {
        (summaryMarkdown ?? "").components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") { return .heading(String(line.drop { $0 == "#" || $0 == " " })) }
            if let mark = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                return .bullet(String(line[mark.upperBound...]))
            }
            return .paragraph(line)
        }
    }

    private func dateText() -> [String] {
        guard let startedAt else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return [formatter.string(from: startedAt)]
    }
}
