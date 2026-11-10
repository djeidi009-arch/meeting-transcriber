import AVKit
import DetectorCore
import SwiftUI

/// Выбранная встреча: у расшифрованной — плеер, summary, спикеры и транскрипт; у остальных — состояние.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem

    var body: some View {
        if item.status == .ready {
            MeetingScreen(item: item).id(item.id) // у каждой встречи свой плеер и своя прокрутка
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MeetingHeader(item: item, document: nil)
                    state.card()
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
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
            EmptyView()
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

/// Шапка встречи: название (правится на месте), пилюли «дата · длительность», меню «Экспорт».
struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem
    /// nil — встреча не расшифрована: экспортировать нечего.
    let document: MeetingDocument?
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                EditableText(text: item.title, font: .system(size: 30, weight: .semibold), clicks: 2) { title in
                    do {
                        try model.library.setTitle(title, for: item.dir)
                        model.refresh()
                    } catch {
                        Export.alert("Не удалось переименовать встречу", error)
                    }
                }
                HStack(spacing: 8) {
                    if let date = item.dateText { Pill(text: date, systemImage: "calendar") }
                    if let duration = item.durationText { Pill(text: duration, systemImage: "clock") }
                    if !item.app.isEmpty && item.app != item.title {
                        Pill(text: item.app, systemImage: item.sourceFile == nil ? "video" : "doc")
                    }
                    StatusPill(item: item)
                }
            }
            Spacer(minLength: 12)
            if copied {
                Pill(text: "Скопировано", systemImage: "checkmark", tone: .accent)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Menu {
                ForEach(Export.Format.allCases, id: \.self) { format in
                    Button(format.title) { if let document { Export.save(document, as: format) } }
                }
                Divider()
                Button("Копировать текст") {
                    guard let document else { return }
                    Export.copy(document)
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation { copied = false }
                    }
                }
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .disabled(document == nil)
            .help(document == nil ? "Экспорт появится, когда встреча будет расшифрована" : "Сохранить или скопировать встречу")
        }
    }
}

/// Экран расшифрованной встречи.
private struct MeetingScreen: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem

    @State private var player = PlayerModel()
    @State private var document: MeetingDocument?
    /// Список идёт за текущей фразой, пока его не прокрутили вручную.
    @State private var following = true
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeetingHeader(item: item, document: document.flatMap { $0.lines.isEmpty ? nil : $0 })
            PlayerBar(player: player)
            if let document {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        if player.hasVideo {
                            VideoPlayer(player: player.player)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        }
                        SpeakersCard(document: document, rename: rename)
                    }
                    .frame(width: 272)
                    transcript(document)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: document == nil)
        .task(id: item) { await reload() }
        .task(id: model.demoAudioReady.contains(item.id)) {
            player.stop()
            await player.load(item: item)
            applySeekRequest()
        }
        .onChange(of: model.seekRequest) { applySeekRequest() }
        .onAppear {
            // пробел — пуск и пауза, если сейчас не печатают в поле
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      event.window?.sheets.isEmpty == true, !(event.window?.firstResponder is NSText) else { return event }
                player.toggle()
                return nil
            }
        }
        .onDisappear {
            player.stop()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    private func transcript(_ document: MeetingDocument) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    SummaryCard(document: document, failed: item.summaryFailed) { model.resummarize(item) }
                    TranscriptCard(document: document, currentLine: player.currentLine, seek: { start in
                        following = true
                        player.seek(to: start)
                        player.play()
                    }, rename: rename)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .continuous))
            .onScrollPhaseChange { _, phase in if phase == .interacting { following = false } }
            .onChange(of: player.currentLine) { _, line in
                if following, let line { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(TranscriptCard.lineID(line), anchor: .center) } }
            }
            .overlay(alignment: .bottom) {
                if !following, let line = player.currentLine {
                    Button {
                        following = true
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(TranscriptCard.lineID(line), anchor: .center) }
                    } label: {
                        Label("К текущей фразе", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.glass)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: following)
        }
    }

    /// Транскрипт читается с диска — не на главном потоке.
    private func reload() async {
        let library = model.library, item = item
        let fresh = await Task.detached {
            MeetingDocument(item: item, transcript: library.transcript(item.dir),
                            summaryMarkdown: library.summaryMarkdown(item.dir), user: library.userData(item.dir))
        }.value
        document = fresh
        player.document = fresh
    }

    private func rename(_ label: String, _ name: String) {
        do {
            try model.library.setSpeakerName(name, label: label, for: item.dir)
            Task { await reload() }
        } catch {
            Export.alert("Не удалось переименовать спикера", error)
        }
    }

    /// Переход из найденного фрагмента поиска: поставить плеер на его таймкод и показать реплику.
    private func applySeekRequest() {
        guard let time = model.seekRequest, player.isLoaded else { return }
        model.seekRequest = nil
        following = true
        player.seek(to: time)
    }
}
