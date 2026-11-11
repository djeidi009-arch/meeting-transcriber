import AVKit
import DetectorCore
import SwiftUI

/// Выбранная встреча: у расшифрованной — плеер, summary, спикеры и транскрипт; у остальных — состояние.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MeetingItem

    /// Встреча, которую видели в обработке, пока она открыта: когда дорасшифруется — играет финал.
    @State private var watched: MeetingItem.ID?
    @State private var phase = Phase.check

    /// Финал по очереди: шаг отмечен, форма делает вдох → текст и шаги гаснут → карточка обработки сжимается в карточку плеера,
    /// форма сплющивается в линию записи, снизу поднимается содержимое → из линии вырастают штрихи волны плеера.
    private enum Phase { case check, clear, collapse, settle }

    /// Финал идёт у встречи, которая дорасшифровалась на глазах.
    private var inFinale: Bool { watched == item.id && item.isTranscribed }

    var body: some View {
        Group {
            if item.isTranscribed && !(inFinale && (phase == .check || phase == .clear)) { // и пока идёт повтор summary: транскрипт и плеер остаются
                MeetingScreen(item: item, reveal: inFinale, collapsing: inFinale && phase == .collapse && !reduceMotion)
                    .id(item.id) // у каждой встречи свой плеер и своя прокрутка
            } else {
                // та же колонка и те же поля, что у экрана встречи: в финале шапка остаётся на месте, а не двоится;
                // карточка состояния занимает всю высоту до низа окна
                VStack(alignment: .leading, spacing: 16) {
                    MeetingHeader(item: item, document: nil)
                    MeetingStateView(item: item, finished: inFinale, clearing: inFinale && phase == .clear)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.3), value: item.isTranscribed)
        .overlay {
            if inFinale && phase == .collapse && !reduceMotion,
               let card = model.cardSlot, let playerCard = model.playerCardSlot, let playerWave = model.playerSlot {
                FinaleSurface(card: card, playerCard: playerCard, playerWave: playerWave)
            }
        }
        .onAppear { watch(item) }
        .onChange(of: item) { old, new in
            if old.id != new.id { watched = nil; phase = .check } // смена встречи посреди финала: ничего не доигрывается
            watch(new)
        }
        .task(id: inFinale ? item.id : nil) {
            guard inFinale else { return }
            phase = .check
            // финал — для того, кто смотрит: окно не на виду — экран просто сменяется
            guard model.motionActive else { watched = nil; return }
            // «Уменьшение движения»: без сжатия карточки, реплики проявляются
            guard !reduceMotion else {
                phase = .settle
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { watched = nil; phase = .check }
                return
            }
            try? await Task.sleep(for: .seconds(Finale.check))
            guard !Task.isCancelled else { return }
            // сначала уходит содержимое обработки, потом — без перекрёстного проявления — встаёт экран встречи: два текста не накладываются
            withAnimation(.easeIn(duration: Finale.clear - 0.02)) { phase = .clear }
            try? await Task.sleep(for: .seconds(Finale.clear))
            guard !Task.isCancelled else { return }
            phase = .collapse
            try? await Task.sleep(for: .seconds(Finale.collapse))
            guard !Task.isCancelled else { return }
            phase = .settle
            try? await Task.sleep(for: .seconds(Finale.settle))
            guard !Task.isCancelled else { return }
            watched = nil
            phase = .check
        }
    }

    private func watch(_ item: MeetingItem) {
        // повтор summary у расшифрованной встречи — не «дорасшифровалась»: финала не надо
        if case .processing = item.status, !item.isTranscribed { watched = item.id }
    }
}

/// Карточка обработки сжимается в карточку плеера: одна поверхность — фон и скругление переезжают, меняется только рамка.
/// Живая форма по пути вытягивается и сплющивается в линию записи; из неё потом вырастают штрихи волны плеера.
private struct FinaleSurface: View {
    /// Рамки карточек обработки и плеера и волны плеера в координатах окна.
    let card: CGRect
    let playerCard: CGRect
    let playerWave: CGRect
    @State private var landed = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let local = { (rect: CGRect) in rect.offsetBy(dx: -origin.x, dy: -origin.y) }
            let surface = local(landed ? playerCard : card), form = local(card), line = local(playerWave)
            ZStack(alignment: .top) {
                Theme.card
                SoftGradient().opacity(landed ? 1 : 0) // по пути проступает фон плеера
                // форма остаётся внутри сжимающейся карточки: рамка у неё прежняя, движется и сплющивается она сама
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Orb(look: landed ? .line : .inhale, time: timeline.date.timeIntervalSinceReferenceDate,
                        line: line.offsetBy(dx: -form.minX, dy: -form.minY))
                }
                // под конец форма уступает место линии волны плеера — той самой, что останется после
                .animation(.easeIn(duration: Finale.collapse)) { $0.opacity(landed ? 0 : 1) }
                .frame(width: form.width, height: form.height)
            }
            .frame(width: surface.width, height: surface.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .position(x: surface.midX, y: surface.midY)
            WaveBars()
                .animation(.easeIn(duration: Finale.collapse)) { $0.opacity(landed ? 1 : 0) }
                .frame(width: line.width, height: line.height)
                .position(x: line.midX, y: line.midY)
        }
        .allowsHitTesting(false)
        // плавный разгон и торможение, в конце карточка чуть проскакивает свою высоту и садится
        .onAppear { withAnimation(.spring(duration: Finale.collapse - 0.05, bounce: 0.14)) { landed = true } }
    }
}

/// Шапка встречи: название (правится на месте), пилюли «дата · длительность», меню «Экспорт».
struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem
    /// nil — встреча не расшифрована: экспортировать нечего.
    let document: MeetingDocument?
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    StatusPill(item: item, timer: false)
                }
            }
            Spacer(minLength: 12)
            if copied {
                Pill(text: "Скопировано", systemImage: "checkmark", tone: .accent)
                    .padding(.top, 6)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
            }
            Menu {
                ForEach(Export.Format.allCases, id: \.self) { format in
                    Button(format.title) { if let document { Export.save(document, as: format) } }
                }
                Divider()
                Button("Копировать текст") {
                    guard let document else { return }
                    Export.copy(document)
                    // вход — короткая пружина, уход быстрее входа
                    withAnimation(.spring(duration: 0.3, bounce: 0.25)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeIn(duration: 0.15)) { copied = false }
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
    /// Обработка только что закончилась: содержимое появляется каскадом, а не сразу.
    let reveal: Bool
    /// Пока карточка обработки сжимается в плеер, сам плеер скрыт: глаз видит одну поверхность.
    var collapsing = false

    @State private var player = PlayerModel()
    @State private var document: MeetingDocument?
    /// Список идёт за текущей фразой, пока его не прокрутили вручную.
    @State private var following = true
    @State private var keyMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeetingHeader(item: item, document: document.flatMap { $0.lines.isEmpty ? nil : $0 })
            PlayerBar(player: player, collapsing: collapsing)
            if let document {
                // шапка, плеер и спикеры закреплены; ниже одна колонка, прокручивается только она
                VStack(spacing: 16) {
                    if !document.lines.isEmpty {
                        SpeakersStrip(document: document, rename: rename)
                            .cascadeIn(order: 0, active: reveal)
                    }
                    if player.hasVideo {
                        // на всю ширину колонки; высота ограничена, чтобы транскрипту осталось место
                        VideoPlayer(player: player.player)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
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
            // форма звука, посчитанная на экране обработки, — та же волна, что приехала в плеер
            if player.levels.isEmpty { player.levels = model.waveLevels[item.id] ?? [] }
            await player.load(item: item, noteMissingVideo: !model.isDemo) // у демо-встреч исходных файлов нет вовсе
            if !player.levels.isEmpty { model.waveLevels[item.id] = player.levels }
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
                    SummaryCard(document: document, failed: item.summaryFailed, status: item.status) { model.resummarize(item) }
                        .cascadeIn(order: 1, active: reveal)
                    TranscriptCard(document: document, currentLine: player.currentLine, seek: { start in
                        following = true
                        player.seek(to: start)
                        player.play()
                    }, rename: rename, cascade: reveal)
                        .cascadeIn(order: 2, active: reveal) // и сама карточка: иначе её заголовок виден раньше, чем сжалась обработка
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
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                }
            }
            // кнопка входит короткой пружиной, уходит быстрее
            .animation(following ? .easeIn(duration: 0.15) : .spring(duration: 0.3, bounce: 0.25), value: following)
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
