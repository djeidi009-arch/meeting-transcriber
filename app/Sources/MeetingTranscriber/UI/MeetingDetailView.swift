import DetectorCore
import SwiftUI

/// Карточка выбранной встречи: шапка с пилюлями и состояние. Плеер, транскрипт и summary добавит экран встречи.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                state.card()
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.system(size: 30, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 8) {
                if let date = item.dateText { Pill(text: date, systemImage: "calendar") }
                if let duration = item.durationText { Pill(text: duration, systemImage: "clock") }
                if !item.app.isEmpty && item.app != item.title {
                    Pill(text: item.app, systemImage: item.sourceFile == nil ? "video" : "doc")
                }
                StatusPill(item: item)
            }
        }
    }

    @ViewBuilder private var state: some View {
        switch item.status {
        case .recording:
            message("Идёт запись", "Когда запись остановится, встреча сама встанет в очередь на расшифровку.")
        case .queued:
            message("В очереди", "Расшифровка начнётся, как только закончится предыдущая.")
        case .processing(let progress):
            VStack(alignment: .leading, spacing: 14) {
                Text("Расшифровывается").font(.title3.weight(.semibold))
                ForEach(ProcessingStage.allCases, id: \.self) { stage in
                    let current = progress?.stage == stage
                    HStack(spacing: 10) {
                        Circle()
                            .fill(current ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary))
                            .frame(width: 10, height: 10)
                        Text(stage.title)
                            .fontWeight(current ? .semibold : .regular)
                            .foregroundStyle(current ? .primary : .secondary)
                        if current { ProgressView().controlSize(.small) }
                    }
                }
            }
        case .ready:
            if item.summaryFailed {
                VStack(alignment: .leading, spacing: 12) {
                    message("Расшифровка готова, а summary не получилось", "Транскрипт сохранён. Summary можно сделать ещё раз.")
                    Button("Повторить summary") { model.resummarize(item) }
                        .buttonStyle(AccentButtonStyle())
                }
            } else {
                message("Расшифровка готова", "Транскрипт и summary сохранены в папке встречи.")
            }
        case .failed(let text):
            VStack(alignment: .leading, spacing: 12) {
                Label("Не удалось расшифровать", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                Text(text)
                    .textSelection(.enabled)
                Button("Повторить") { model.retry(item) }
                    .buttonStyle(AccentButtonStyle())
            }
        }
    }

    private func message(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            Text(text).foregroundStyle(.secondary)
        }
    }
}
