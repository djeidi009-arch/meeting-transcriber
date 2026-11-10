import DetectorCore
import Pow
import SwiftUI

/// Общие токены облика: один акцент (лайм), карточки без рамок, пилюли. Остальное — системные цвета.
enum Theme {
    static let accent = Color(red: 0xD4 / 255, green: 0xF2 / 255, blue: 0x5A / 255)
    /// Текст и значки на акценте — графит, в обеих темах.
    static let onAccent = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let cardRadius: CGFloat = 18

    /// Едва серый фон под карточками.
    static let page = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.11, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.07))

    private static let speakerPalette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo]

    /// Цвет спикера стабилен по метке (между запусками тоже — поэтому не hashValue); «Я» — всегда акцент.
    static func speakerColor(_ label: String) -> Color {
        if label == "Я" { return accent }
        let sum = label.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return speakerPalette[sum % speakerPalette.count]
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
}

extension View {
    /// Скруглённая карточка без рамки.
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Пилюля-капсула для статусов и метаданных.
struct Pill: View {
    enum Tone { case neutral, accent, danger }
    let text: String
    var systemImage: String?
    var tone = Tone.neutral

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: AnyShapeStyle {
        switch tone {
        case .neutral: AnyShapeStyle(.secondary)
        case .accent: AnyShapeStyle(Theme.onAccent)
        case .danger: AnyShapeStyle(.red)
        }
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .neutral: AnyShapeStyle(.quaternary)
        case .accent: AnyShapeStyle(Theme.accent)
        case .danger: AnyShapeStyle(.red.opacity(0.14))
        }
    }
}

/// Пилюля статуса встречи; у готовой встречи пилюли нет.
struct StatusPill: View {
    let item: MeetingItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch item.status {
            case .ready:
                EmptyView()
            case .recording:
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                    Text(item.status.title)
                    if let start = item.startedAt {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
                    }
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(.red)
                .background(.red.opacity(0.14), in: Capsule())
            case .queued:
                Pill(text: item.status.title, systemImage: "clock")
            case .processing:
                Pill(text: item.status.title, systemImage: "waveform", tone: .accent)
            case .failed:
                Pill(text: item.status.title, systemImage: "exclamationmark.triangle.fill", tone: .danger)
            }
        }
        // блик при смене статуса; при «Уменьшении движения» — без него
        .changeEffect(.shine, value: item.status.title, isEnabled: !reduceMotion)
    }
}

/// Основная кнопка: лаймовая, с графитовым текстом.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

extension MeetingItem {
    private static let russian = Locale(identifier: "ru_RU")

    /// «14:30»
    var timeText: String? {
        startedAt?.formatted(.dateTime.hour().minute().locale(Self.russian))
    }

    /// «10 ноября 2026 г. в 14:30»
    var dateText: String? {
        startedAt?.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Self.russian))
    }

    var durationText: String? {
        duration.flatMap { $0 > 0 ? MeetingDocument.durationText($0) : nil }
    }

    var stage: ProcessingStage? {
        if case .processing(let progress?) = status { return progress.stage }
        return nil
    }

    var errorText: String? {
        if case .failed(let text) = status { return text }
        return nil
    }
}
