import DetectorCore
import SwiftUI

/// Боковая панель: встречи по дням, статусы, поиск по названию и тексту.
struct MeetingListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hits = model.isSearching ? model.hits ?? [] : []
        let rows = model.isSearching ? hits.map(\.item) : model.items
        let snippets = Dictionary(hits.map { ($0.item.id, $0.snippets) }, uniquingKeysWith: { first, _ in first })

        List(selection: $model.selection) {
            ForEach(MeetingLibrary.sections(rows, now: Date(), calendar: .current)) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        MeetingRow(item: item, snippets: snippets[item.id] ?? [])
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.query, placement: .sidebar, prompt: "Название или текст")
        .overlay {
            if model.isSearching {
                if model.hits?.isEmpty == true {
                    ContentUnavailableView {
                        Label("Нет совпадений", systemImage: "magnifyingglass")
                    } description: {
                        Text("Ничего не найдено по запросу «\(model.query)»")
                    } actions: {
                        Button("Сбросить поиск") { model.query = "" }
                    }
                }
            } else if model.isLoaded && model.items.isEmpty {
                ContentUnavailableView("Встреч пока нет", systemImage: "tray",
                                       description: Text("Здесь появятся записи и загруженные файлы."))
            }
        }
    }
}

private struct MeetingRow: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem
    let snippets: [Snippet]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text([item.timeText, item.durationText].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusPill(item: item)
            }
            if let stage = item.stage {
                Text(stage.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = item.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Повторить") { model.retry(item) }
                    .controlSize(.small)
            }
            ForEach(snippets, id: \.start) { snippet in
                Button {
                    model.selection = item.id
                    model.seekRequest = snippet.start
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(MeetingDocument.timecode(snippet.start))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(snippet.text)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Открыть встречу на этом месте")
            }
        }
        .padding(.vertical, 4)
    }
}
