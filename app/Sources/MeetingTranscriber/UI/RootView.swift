import SwiftUI

/// Каркас окна: боковая панель со встречами и поиском, справа — выбранная встреча.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            MeetingListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 440)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.page)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { model.toggleRecording() } label: {
                            Label(model.isRecording ? "Остановить запись" : "Начать запись",
                                  systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
                        }
                        Button { model.chooseFiles() } label: {
                            Label("Загрузить", systemImage: "square.and.arrow.down")
                        }
                        .help("Загрузить аудио или видео")
                    }
                }
                .labelStyle(.titleAndIcon)
        }
        .navigationTitle("Транскрибатор")
        .importFlow()
    }

    @ViewBuilder private var detail: some View {
        if let item = model.items.first(where: { $0.id == model.selection }) {
            MeetingDetailView(item: item)
        } else if model.isLoaded && model.items.isEmpty {
            invitation
        } else if model.isLoaded {
            ContentUnavailableView("Выберите встречу", systemImage: "waveform",
                                   description: Text("Встречи — в списке слева."))
        }
    }

    /// Первый запуск: встреч ещё нет.
    private var invitation: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 96, height: 96)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text("Перетащите сюда видео или аудио")
                .font(.largeTitle.weight(.semibold))
            Text("Транскрибатор расшифрует запись по спикерам и соберёт краткое summary. Всё остаётся на этом Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Загрузить") { model.chooseFiles() }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(40)
    }
}
