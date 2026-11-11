import DetectorCore
import SwiftUI

/// Текст, который правится на месте: Enter сохраняет, Esc отменяет.
struct EditableText: View {
    let text: String
    var font = Font.body
    /// Сколько кликов начинает правку: название — двойной, имя спикера — одиночный.
    var clicks = 1
    var lines = 2
    let onCommit: (String) -> Void

    // правка — отдельный флаг: поле при закрытии ещё раз пишет в привязку пустую строку
    @State private var editing = false
    @State private var draft = ""
    /// Сохранённое значение показывается, пока модель не перечитала папку, — чтобы старое не мигало.
    @State private var saved: String?
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onAppear { focused = true }
        } else {
            Text(saved ?? text)
                .font(font)
                .lineLimit(lines)
                .frame(maxWidth: .infinity, alignment: .leading) // короткое имя вроде «Я» — слишком мелкая цель для клика
                .contentShape(Rectangle())
                .onTapGesture(count: clicks, perform: start)
                .contextMenu { Button("Переименовать", action: start) }
                .onChange(of: text) { saved = nil }
                .help(clicks == 2 ? "Двойной клик — переименовать" : "Переименовать")
                .accessibilityAction(named: "Переименовать", start)
        }
    }

    private func start() {
        draft = saved ?? text
        editing = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != text else { return }
        // пустое имя возвращает исходное — его покажет модель
        saved = value.isEmpty ? nil : value
        onCommit(value)
    }
}

/// Кружок спикера: цвет стабилен по метке, «Я» — акцент.
struct SpeakerAvatar: View {
    let label: String
    let name: String
    var size: CGFloat = 30

    var body: some View {
        let color = Theme.speakerColor(label)
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(label == "Я" ? Theme.onAccent : .white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Полоса спикеров под плеером: аватар, имя (клик — переименовать), доля речи и тонкая полоска.
struct SpeakersStrip: View {
    let document: MeetingDocument
    let rename: (_ label: String, _ name: String) -> Void
    /// Полоски вырастают от нуля при открытии встречи, по очереди.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // помещаются — делят ширину; много спикеров в узком окне — полоса листается
        ViewThatFits(in: .horizontal) {
            row(minWidth: 132)
            ScrollView(.horizontal) { row(minWidth: 168) }.scrollIndicators(.hidden)
        }
        .onAppear { grown = true }
    }

    private func row(minWidth: CGFloat) -> some View {
        let shares = document.speakerShares()
        return HStack(spacing: 24) {
            ForEach(Array(shares.enumerated()), id: \.element.label) { index, speaker in
                HStack(spacing: 10) {
                    SpeakerAvatar(label: speaker.label, name: speaker.name, size: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            EditableText(text: speaker.name, font: .callout.weight(.medium), lines: 1) { rename(speaker.label, $0) }
                            Text("\(Int((speaker.share * 100).rounded()))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(.quaternary)
                            Capsule().fill(Theme.speakerColor(speaker.label))
                                .frame(width: grown || reduceMotion ? max(4, geo.size.width * speaker.share) : 0)
                                .opacity(grown ? 1 : 0)
                                .animation(reduceMotion ? .easeOut(duration: 0.3)
                                           : .timingCurve(0.16, 1, 0.3, 1, duration: 0.6).delay(0.1 + Double(index) * 0.07), value: grown)
                        }
                        .frame(height: 4)
                    }
                }
                .frame(minWidth: minWidth, maxWidth: 200)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 20) // по левому краю содержимого карточек
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Карточка summary: Markdown по блокам; при сбое — кнопка «Сделать summary».
struct SummaryCard: View {
    let document: MeetingDocument
    let failed: Bool
    /// Пока встреча в очереди или обрабатывается (повтор summary), вместо текста — ход этапа.
    let status: MeetingStatus
    let retry: () -> Void

    /// Свёрнутое summary не заслоняет транскрипт: видно начало, остальное — по кнопке.
    private static let collapsedHeight: CGFloat = 112
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let long = fullHeight > Self.collapsedHeight + 40 // ради пары строк сворачивать незачем
        let collapsed = long && !expanded
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Summary", systemImage: "sparkles").font(.title3.weight(.semibold))
                Spacer()
                if long {
                    Button { expanded.toggle() } label: {
                        Label(expanded ? "Свернуть" : "Показать полностью", systemImage: "chevron.down")
                            .labelStyle(SummaryToggleLabel(up: expanded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            content
                .fixedSize(horizontal: false, vertical: true) // иначе текст обрежется многоточием, а не краем
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                .frame(height: collapsed ? Self.collapsedHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .black.opacity(collapsed ? 0 : 1), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .card()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: expanded)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            let busy = status != .ready
            let blocks = busy ? [] : document.summaryBlocks()
            if busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(status == .queued ? "В очереди: summary начнётся, как только закончится предыдущая обработка."
                         : ProcessingStage.summary.explanation)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if failed {
                Text("Summary не получилось").foregroundStyle(.secondary)
                Button("Сделать summary", action: retry).buttonStyle(AccentButtonStyle())
            } else if blocks.isEmpty {
                Text("Summary нет.").foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.accentInk).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0.height + 2 }
                        Text(Self.inline(text))
                    }
                case .paragraph(let text):
                    Text(Self.inline(text))
                }
            }
            .lineSpacing(3)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Жирный и курсив внутри строки.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Подпись слева, стрелка справа; стрелка переворачивается, когда summary раскрыто.
private struct SummaryToggleLabel: LabelStyle {
    let up: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.caption.weight(.semibold)).rotationEffect(.degrees(up ? 180 : 0))
        }
        .font(.callout.weight(.medium))
        .contentShape(Rectangle())
    }
}

/// Рамка текущей реплики — чтобы подсветка была одна и переезжала, а не гасла и зажигалась.
private struct CurrentLineBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// Транскрипт: реплики с цветом спикера, именем и таймкодом; клик ставит плеер на начало реплики.
struct TranscriptCard: View {
    /// Якорь прокрутки: просто номер совпал бы с номерами блоков summary в том же списке.
    static func lineID(_ index: Int) -> String { "line-\(index)" }

    let document: MeetingDocument
    let currentLine: Int?
    let seek: (Double) -> Void
    let rename: (_ label: String, _ name: String) -> Void
    /// Реплики всплывают по очереди — когда встреча дорасшифровалась на глазах.
    var cascade = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Транскрипт")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            if document.lines.isEmpty {
                Text("Речь не распознана").foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                LineRow(line: line, isCurrent: index == currentLine, seek: seek, rename: rename)
                    .id(TranscriptCard.lineID(index))
                    .anchorPreference(key: CurrentLineBounds.self, value: .bounds) { index == currentLine ? $0 : nil }
                    .cascadeIn(order: index + 2, active: cascade)
            }
        }
        .backgroundPreferenceValue(CurrentLineBounds.self) { anchor in
            GeometryReader { geo in
                if let anchor {
                    let rect = geo[anchor]
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(0.32))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        // при «Уменьшении движения» подсветка не едет, а проявляется на новом месте
                        .id(reduceMotion ? currentLine : nil)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentLine)
        }
        .card(padding: 10)
    }
}

private struct LineRow: View {
    let line: MeetingDocument.Line
    let isCurrent: Bool
    let seek: (Double) -> Void
    let rename: (_ label: String, _ name: String) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpeakerAvatar(label: line.speakerLabel, name: line.speakerName)
            VStack(alignment: .leading, spacing: 2) {
                EditableText(text: line.speakerName, font: .callout.weight(.semibold)) { rename(line.speakerLabel, $0) }
                Text(MeetingDocument.shortTimecode(line.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)
            Text(line.text)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
        }
        .padding(10)
        .background(.primary.opacity(hovered && !isCurrent ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { seek(line.start) }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { seek(line.start) }
        .help("Слушать с этого места")
    }
}
