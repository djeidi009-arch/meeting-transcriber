import DetectorCore
import Pow
import SwiftUI

/// Общие токены облика: один акцент (лайм), карточки без рамок, пилюли. Остальное — системные цвета.
enum Theme {
    static let accent = Color(red: 0xD4 / 255, green: 0xF2 / 255, blue: 0x5A / 255)
    /// Текст и значки на акценте — графит, в обеих темах.
    static let onAccent = Color(red: 0.11, green: 0.12, blue: 0.13)
    /// Акцент для тонких штрихов и точек: на светлом фоне лайм не читается, поэтому там он темнее.
    static let accentInk = dynamic(light: NSColor(red: 0.47, green: 0.62, blue: 0.04, alpha: 1), dark: NSColor(red: 0xD4 / 255, green: 0xF2 / 255, blue: 0x5A / 255, alpha: 1))
    static let cardRadius: CGFloat = 18

    /// Едва серый фон под карточками.
    static let page = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.11, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.07))

    /// Холодный нейтральный тон для мягких градиентов: рядом с лаймом не даёт грязи ни на белом, ни на графите.
    static let cool = dynamic(light: NSColor(red: 0.50, green: 0.66, blue: 0.82, alpha: 1), dark: NSColor(red: 0.36, green: 0.56, blue: 0.72, alpha: 1))

    /// Лайм для тех же градиентов: поверх графита жёлто-зелёный даёт оливковую грязь, поэтому в тёмной теме он холоднее.
    static let glow = dynamic(light: NSColor(red: 0xD4 / 255, green: 0xF2 / 255, blue: 0x5A / 255, alpha: 1), dark: NSColor(red: 0.46, green: 0.80, blue: 0.58, alpha: 1))

    /// Цвета спикеров приглушены: различимы между собой, но не спорят с акцентом.
    private static let speakerPalette: [Color] = [
        Color(red: 0.40, green: 0.54, blue: 0.76), Color(red: 0.56, green: 0.49, blue: 0.74), Color(red: 0.74, green: 0.48, blue: 0.58),
        Color(red: 0.76, green: 0.58, blue: 0.40), Color(red: 0.34, green: 0.60, blue: 0.62), Color(red: 0.44, green: 0.46, blue: 0.66),
    ]

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
    /// В шапке записи таймер не нужен: он крупно стоит в карточке.
    var timer = true
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
                    if timer, let start = item.startedAt {
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

/// Основная кнопка: лаймовая, с графитовым текстом. `compact` — для боковой панели.
struct AccentButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.callout : .body).weight(.semibold))
            .padding(.horizontal, compact ? 11 : 16)
            .padding(.vertical, compact ? 4 : 8)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
            .buttonFeel(pressed: configuration.isPressed)
    }
}

/// Круглая кнопка-значок без фона: подложка появляется под курсором.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .buttonFeel(pressed: configuration.isPressed, hoverFill: true)
    }
}

/// Главная кнопка плеера: при нажатии сплющивается, при отпускании пружинит обратно.
struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.buttonFeel(pressed: configuration.isPressed, springy: true)
    }
}

/// Отклик кнопки: наведение и нажатие. При «Уменьшении движения» вместо сжатия — затемнение.
private struct ButtonFeel: ViewModifier {
    let pressed: Bool
    var springy = false
    var hoverFill = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        let squash: CGSize = reduceMotion || !pressed ? CGSize(width: 1, height: 1)
            : springy ? CGSize(width: 0.96, height: 0.86) : CGSize(width: 0.97, height: 0.97)
        content
            .background(.primary.opacity(hoverFill && hovered && enabled ? (pressed ? 0.14 : 0.08) : 0), in: Circle())
            .brightness(!hoverFill && hovered && enabled && !pressed ? -0.05 : 0)
            .opacity(reduceMotion && pressed ? 0.7 : 1)
            .scaleEffect(squash)
            // сжатие быстрое, возврат — с отскоком только у пружинящей кнопки
            .animation(pressed ? .easeOut(duration: 0.1) : springy ? .spring(duration: 0.4, bounce: 0.4) : .easeOut(duration: 0.18), value: pressed)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .onHover { hovered = $0 }
    }
}

private extension View {
    func buttonFeel(pressed: Bool, springy: Bool = false, hoverFill: Bool = false) -> some View {
        modifier(ButtonFeel(pressed: pressed, springy: springy, hoverFill: hoverFill))
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
