import DetectorCore
import DSWaveformImage
import DSWaveformImageViews
import Pow
import SwiftUI

/// Экран встречи, которая ещё не расшифрована: живая запись, очередь, обработка по этапам, ошибка.
struct MeetingStateView: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem
    /// Финал: обработка только что закончилась — все шаги отмечены, волна застыла перед переездом в плеер.
    var finished = false
    /// Финал, следующий шаг: текст и шаги гаснут, остаются поверхность и волна — они сожмутся в плеер.
    var clearing = false

    var body: some View {
        Group {
            if item.status == .recording { RecordingCard(item: item) } else { ProcessingCard(item: item, finished: finished, clearing: clearing) }
        }
        // карточка занимает всю высоту до низа окна
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Theme.card
                if item.status == .recording { Aurora() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.cardSlot = $0 }
    }
}

extension ProcessingStage {
    var symbol: String {
        switch self {
        case .extract: "waveform"
        case .asr: "captions.bubble"
        case .diarize: "person.2.wave.2"
        case .summary: "sparkles"
        }
    }

    /// Что сейчас происходит — одной строкой под названием этапа.
    var explanation: String {
        switch self {
        case .extract: "Достаём звуковую дорожку и готовим её к распознаванию."
        case .asr: "Речь превращается в текст — прямо на этом Mac, звук никуда не уходит."
        case .diarize: "Разбираемся, кто и когда говорил."
        case .summary: "Claude читает транскрипт и собирает краткое содержание."
        }
    }
}

/// Четыре шага обработки: пройденные отмечены, текущий дышит, упавший — красный. Ведущее движение одно — волна.
private struct ProcessingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MeetingItem
    let finished: Bool
    let clearing: Bool

    private enum StepState { case pending, current, done, failed }

    // Шаги идут за настоящим этапом по очереди: линия дорисовывается → галочка → загорается следующий.
    @State private var lines = 0   // сколько линий между шагами дорисовано
    @State private var done = 0    // сколько шагов отмечено галочкой
    @State private var lit: Int?   // какой шаг горит как текущий
    @State private var settled = false

    private var isProcessing: Bool { if case .processing = item.status { true } else { false } }
    private var progress: ProgressInfo? { if case .processing(let info) = item.status { info } else { nil } }
    /// Шаг, на котором обработка сейчас, на котором упала или закончилась; у встречи в очереди его нет.
    private var stage: ProcessingStage? {
        if isProcessing { return progress?.stage ?? .extract } // файл этапа ещё не записан — значит, самое начало
        return item.status.isFailed || finished ? model.lastStage[item.id] : nil
    }
    /// Сколько шагов пройдено по-настоящему.
    private var goal: Int {
        finished ? ProcessingStage.allCases.count : stage.flatMap { ProcessingStage.allCases.firstIndex(of: $0) } ?? 0
    }

    private var title: String {
        if item.status.isFailed { return "Не удалось расшифровать" }
        return isProcessing || finished ? stage?.title ?? "" : "В очереди"
    }

    private var explanation: String {
        if item.status.isFailed { return stage.map { "Обработка остановилась на шаге «\($0.title)»." } ?? "Обработка остановилась." }
        return isProcessing || finished ? stage?.explanation ?? "" : "Расшифровка начнётся, как только закончится предыдущая."
    }

    /// Облик живой формы на этом этапе.
    private var look: OrbLook {
        if item.status.isFailed { return .failed }
        if finished { return .inhale }
        if model.importFlight != nil { return .arrival } // форма только что села сюда после броска
        guard isProcessing else { return .queued }
        switch stage ?? .extract {
        case .extract: return .extract
        case .asr: return .asr(progress?.fraction ?? 0)
        case .diarize: return .diarize
        case .summary: return .summary
        }
    }

    /// Громкость записи, сглаженная до дюжины отсчётов: форма слегка повторяет звук, не рисуя его.
    private static func envelope(_ levels: [Float]?) -> [Double] {
        guard let levels, levels.count >= 12 else { return [] }
        let chunk = levels.count / 12
        return (0..<12).map { index in Double(levels[index * chunk..<(index + 1) * chunk].reduce(0, +)) / Double(chunk) }
    }

    /// Звук для формы и волны плеера: в демо — только когда его синтез закончен (файл не должен читаться недописанным).
    private var waveFiles: [URL] {
        guard isProcessing || finished, !model.isDemo || model.demoAudioReady.contains(item.id) else { return [] }
        return WaveSource.files(dir: item.dir, stage: stage, sourceFile: item.sourceFile)
    }

    var body: some View {
        let files = waveFiles
        let levels = files.isEmpty ? nil : model.waveLevels[item.id]
        VStack(spacing: 28) {
            // место живой формы: она лежит на фоне карточки, над текстом
            Color.clear
                .frame(minHeight: 40, maxHeight: .infinity)
                .task(id: files) {
                    guard !files.isEmpty, model.waveLevels[item.id] == nil else { return }
                    let fresh = await WaveLevels.load(files)
                    if !fresh.isEmpty { model.waveLevels[item.id] = fresh }
                }
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.system(size: 34, weight: .semibold))
                        .id(title)
                        .transition(reduceMotion ? .opacity : .movingParts.blur)
                    if let fraction = progress?.fraction {
                        Text("\(Int((fraction * 100).rounded())) %")
                            .font(.title2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .transition(.opacity)
                    }
                }
                Text(explanation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                facts
            }
            .opacity(clearing ? 0 : 1)
            steps
                .opacity(clearing ? 0 : 1)
            if case .failed(let text) = item.status {
                VStack(spacing: 14) {
                    Text(text)
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 560)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("Повторить") { model.retry(item) }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 36)
        .animation(.spring(duration: 0.5), value: stage)
        .animation(.spring(duration: 0.5), value: progress?.fraction)
        .task(id: [goal, item.status.isFailed ? 1 : 0, isProcessing ? 1 : 0]) { await follow() }
        .background {
            ProcessingOrb(look: look, envelope: Self.envelope(levels), alive: !item.status.isFailed)
        }
        .accessibilityElement(children: .contain)
    }

    /// Только то, что программа знает: длительность записи и сколько идёт текущий шаг.
    @ViewBuilder private var facts: some View {
        let since = isProcessing ? model.stageSince[item.id] : nil
        if item.durationText != nil || since != nil {
            HStack(spacing: 6) {
                if let duration = item.durationText { Text("Запись \(duration)") }
                if item.durationText != nil, since != nil { Text("·") }
                if let since {
                    Text("этот шаг идёт")
                    Text(timerInterval: since...Date.distantFuture, countsDown: false)
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
    }

    /// Довести шаги до настоящего этапа. Вперёд — по очереди, перекрывающимся действием; назад, при ошибке и при первом показе — сразу.
    private func follow() async {
        let count = ProcessingStage.allCases.count
        let current = isProcessing && goal < count ? goal : nil
        guard settled, !reduceMotion, goal > done, isProcessing || finished else {
            withAnimation(settled ? .easeOut(duration: 0.25) : nil) {
                lines = goal
                done = goal
                lit = current
            }
            settled = true
            return
        }
        // финал: пройденные раньше шаги уже отмечены — садится только последняя галочка (даже если список успел сброситься)
        if finished, done < goal - 1 {
            lines = goal - 1
            done = goal - 1
        }
        while done < goal {
            if done + 1 < count {
                withAnimation(.easeInOut(duration: 0.34)) { lines = done + 1 }
                try? await Task.sleep(for: .seconds(0.26))
            }
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { done += 1 }
            try? await Task.sleep(for: .seconds(0.2))
            // прерванная цепочка не бросается на полпути: новый запуск продолжит с этого места
            if Task.isCancelled { return }
        }
        withAnimation(.easeOut(duration: 0.3)) { lit = current }
    }

    private var steps: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(ProcessingStage.allCases.enumerated()), id: \.element) { index, step in
                let state: StepState = item.status.isFailed && index == goal && stage != nil ? .failed
                    : index < done ? .done : index == lit ? .current : .pending
                if index > 0 {
                    Capsule()
                        .fill(.quaternary)
                        .overlay {
                            // линия дорисовывается слева направо
                            Capsule().fill(Theme.accentInk).scaleEffect(x: index <= lines ? 1 : 0, anchor: .leading)
                        }
                        .frame(height: 3)
                        .frame(maxWidth: 110)
                        .padding(.top, 24.5)
                        .padding(.horizontal, -18) // линия подходит к кружкам, а не к краям подписей
                }
                badge(step, state)
            }
        }
    }

    private func badge(_ step: ProcessingStage, _ state: StepState) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(fill(state))
                if state == .current {
                    StageRing(fraction: progress?.fraction, breathing: model.motionActive && !reduceMotion)
                        .transition(.opacity)
                }
                Image(systemName: state == .done ? "checkmark" : state == .failed ? "xmark" : step.symbol)
                    .font(.system(size: state == .done || state == .failed ? 18 : 17, weight: .semibold))
                    .foregroundStyle(state == .done ? AnyShapeStyle(Theme.onAccent) : state == .failed ? AnyShapeStyle(.white)
                        : state == .current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 52, height: 52)
            // галочка садится с коротким сжатием и отскоком
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: state == .done && settled && !reduceMotion) { view, size in
                view.scaleEffect(size)
            } keyframes: { _ in
                KeyframeTrack(\.width) {
                    CubicKeyframe(1.14, duration: 0.1)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
                KeyframeTrack(\.height) {
                    CubicKeyframe(0.84, duration: 0.1)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
            }
            Text(step.title)
                .font(.callout.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .fixedSize()
        }
        .frame(width: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(state == .done ? "готово" : state == .current ? "идёт" : state == .failed ? "ошибка" : "ожидает")
    }

    private func fill(_ state: StepState) -> AnyShapeStyle {
        switch state {
        case .pending: AnyShapeStyle(.quaternary)
        case .current: AnyShapeStyle(Theme.card)
        case .done: AnyShapeStyle(Theme.accent)
        case .failed: AnyShapeStyle(.red)
        }
    }
}

/// Живая форма на фоне карточки обработки: у каждого этапа свой облик, переходы между ними — плавный морфинг.
private struct ProcessingOrb: View {
    let look: OrbLook
    let envelope: [Double]
    /// false — ошибка: форма замерла.
    let alive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // один ведущий цикл экрана: не чаще 30 кадров в секунду и только пока окно на виду
        let moving = alive && model.motionActive && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
            Orb(look: look, time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate, envelope: envelope)
                .animation(.easeInOut(duration: 1.1), value: look)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.waveSlot = $0 }
        // пока карточка файла летит сюда, места формы пусто: форма в полёте и эта — один объект
        .opacity(model.importFlight != nil && !reduceMotion ? 0 : 1)
    }
}

/// Кольцо текущего шага: доля, если известна; иначе кольцо мягко дышит.
private struct StageRing: View {
    let fraction: Double?
    let breathing: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accentInk.opacity(0.22), lineWidth: 3)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.03, fraction))
                    .stroke(Theme.accentInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathing)) { timeline in
                    let breath = breathing ? 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2.4) : 0.6
                    Circle().stroke(Theme.accentInk.opacity(0.15 + 0.65 * breath), lineWidth: 3)
                }
            }
        }
    }
}

/// Экран записи: живая волна от громкости микрофона во всю высоту и таймер. Статус — в шапке, «Остановить запись» — в тулбаре.
private struct RecordingCard: View {
    @Environment(AppModel.self) private var model
    let item: MeetingItem

    var body: some View {
        VStack(spacing: 20) {
            if let start = item.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 72, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            // у DSWaveformImage 0 — громко, 1 — тишина; каждое значение растянуто, чтобы волна шла быстрее
            WaveformLiveCanvas(
                samples: model.recordingLevels.flatMap { level in repeatElement(1 - level, count: 3) },
                configuration: Waveform.Configuration(
                    style: .striped(.init(color: NSColor(Theme.accentInk), width: 2, spacing: 3)),
                    damping: .init(percentage: 0.125, sides: .both)),
                shouldDrawSilencePadding: true)
                .frame(height: 120)
                .accessibilityLabel("Громкость микрофона")
            Text("Когда запись остановится, встреча сама встанет в очередь на расшифровку.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
        // карточка на всю высоту, содержимое — по её середине
        .frame(maxHeight: .infinity)
    }
}
