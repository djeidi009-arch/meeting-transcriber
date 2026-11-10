import DetectorCore
import SwiftUI

/// Текст, который правится на месте: Enter сохраняет, Esc отменяет.
struct EditableText: View {
    let text: String
    var font = Font.body
    /// Сколько кликов начинает правку: название — двойной, имя спикера — одиночный.
    var clicks = 1
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
                .lineLimit(2)
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

/// Карточка «Спикеры»: доля речи с полоской, здесь же переименование.
struct SpeakersCard: View {
    let document: MeetingDocument
    let rename: (_ label: String, _ name: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Спикеры").font(.title3.weight(.semibold))
            let shares = document.speakerShares()
            if shares.isEmpty {
                Text("Речь не распознана").foregroundStyle(.secondary)
            }
            ForEach(shares, id: \.label) { speaker in
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        SpeakerAvatar(label: speaker.label, name: speaker.name)
                        EditableText(text: speaker.name, font: .body.weight(.medium)) { rename(speaker.label, $0) }
                        Spacer(minLength: 4)
                        Text("\(Int((speaker.share * 100).rounded()))%")
                            .font(.title3.weight(.medium).monospacedDigit())
                    }
                    GeometryReader { geo in
                        Capsule().fill(.quaternary)
                        Capsule().fill(speaker.label == "Я" ? Theme.accent : Theme.speakerColor(speaker.label))
                            .frame(width: max(6, geo.size.width * speaker.share))
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

/// Карточка summary: Markdown по блокам; при сбое — кнопка «Сделать summary».
struct SummaryCard: View {
    let document: MeetingDocument
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Summary", systemImage: "sparkles").font(.title3.weight(.semibold))
            let blocks = document.summaryBlocks()
            if failed {
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
        .card()
    }

    /// Жирный и курсив внутри строки.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Транскрипт: реплики с цветом спикера, именем и таймкодом; клик ставит плеер на начало реплики.
struct TranscriptCard: View {
    /// Якорь прокрутки: просто номер совпал бы с номерами блоков summary в том же списке.
    static func lineID(_ index: Int) -> String { "line-\(index)" }

    let document: MeetingDocument
    let currentLine: Int?
    let seek: (Double) -> Void
    let rename: (_ label: String, _ name: String) -> Void

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
            }
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
        .background(isCurrent ? AnyShapeStyle(Theme.accent.opacity(0.32)) : AnyShapeStyle(.primary.opacity(hovered ? 0.05 : 0)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { seek(line.start) }
        .animation(.easeOut(duration: 0.2), value: isCurrent)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { seek(line.start) }
        .help("Слушать с этого места")
    }
}
