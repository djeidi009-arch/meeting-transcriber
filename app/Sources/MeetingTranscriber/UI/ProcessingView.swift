import DetectorCore
import DSWaveformImage
import DSWaveformImageViews
import Pow
import SwiftUI

/// Экран встречи, которая ещё не расшифрована: живая запись, очередь, обработка по этапам, ошибка.
struct MeetingStateView: View {
    let item: MeetingItem

    var body: some View {
        Group {
            if item.status == .recording { RecordingCard(item: item) } else { ProcessingCard(item: item) }
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Theme.card
                if !item.status.isFailed { Aurora() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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

/// Четыре шага обработки: пройденные отмечены, текущий анимирован, упавший — красный.
private struct ProcessingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MeetingItem

    private enum StepState { case pending, current, done, failed }

    private var isProcessing: Bool { if case .processing = item.status { true } else { false } }
    private var progress: ProgressInfo? { if case .processing(let info) = item.status { info } else { nil } }
    /// Шаг, на котором обработка сейчас или на котором упала; у встречи в очереди его нет.
    private var stage: ProcessingStage? {
        if isProcessing { return progress?.stage ?? .extract } // файл этапа ещё не записан — значит, самое начало
        return item.status.isFailed ? model.lastStage[item.id] : nil
    }

    private var title: String {
        if item.status.isFailed { return "Не удалось расшифровать" }
        return isProcessing ? stage?.title ?? "" : "В очереди"
    }

    private var explanation: String {
        if item.status.isFailed { return stage.map { "Обработка остановилась на шаге «\($0.title)»." } ?? "Обработка остановилась." }
        return isProcessing ? stage?.explanation ?? "" : "Расшифровка начнётся, как только закончится предыдущая."
    }

    var body: some View {
        VStack(spacing: 26) {
            PulseWave(energy: isProcessing ? 1 : item.status.isFailed ? 0 : 0.2,
                      tint: item.status.isFailed ? .secondary : Theme.accentInk)
                .frame(height: 104)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
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
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            steps
            if case .failed(let text) = item.status {
                VStack(spacing: 14) {
                    Text(text)
                        .textSelection(.enabled)
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
        .padding(.vertical, 36)
        .animation(.spring(duration: 0.5), value: stage)
        .animation(.spring(duration: 0.5), value: progress?.fraction)
        .accessibilityElement(children: .contain)
    }

    private var steps: some View {
        let current = stage.flatMap { ProcessingStage.allCases.firstIndex(of: $0) }
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(ProcessingStage.allCases.enumerated()), id: \.element) { index, step in
                let state: StepState = current.map { index < $0 ? .done : index > $0 ? .pending : item.status.isFailed ? .failed : .current } ?? .pending
                if index > 0 {
                    Capsule()
                        .fill(state == .pending ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Theme.accentInk))
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
                if state == .current && !reduceMotion {
                    // расходящееся кольцо — «здесь идёт работа»
                    PhaseAnimator([false, true]) { phase in
                        Circle()
                            .stroke(Theme.accentInk.opacity(phase ? 0 : 0.5), lineWidth: 2)
                            .scaleEffect(phase ? 1.6 : 1)
                    } animation: { phase in phase ? .easeOut(duration: 1.3) : .linear(duration: 0.01) }
                }
                Circle().fill(fill(state))
                if state == .current { StageRing(fraction: progress?.fraction) }
                Image(systemName: state == .done ? "checkmark" : state == .failed ? "xmark" : step.symbol)
                    .font(.system(size: state == .done || state == .failed ? 18 : 17, weight: .semibold))
                    .foregroundStyle(state == .done ? AnyShapeStyle(Theme.onAccent) : state == .failed ? AnyShapeStyle(.white)
                        : state == .current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state == .current && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 52, height: 52)
            // пройденный шаг отмечается брызгами искр
            .changeEffect(.spray(origin: .center) {
                Image(systemName: "sparkle").font(.caption).foregroundStyle(Theme.accentInk)
            }, value: state == .done, isEnabled: state == .done && !reduceMotion)
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

/// Кольцо текущего шага: доля, если известна; иначе бегущая дуга.
private struct StageRing: View {
    let fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spinning = fraction == nil && !reduceMotion
        TimelineView(.animation(paused: !spinning)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            ZStack {
                Circle().stroke(Theme.accentInk.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction.map { max(0.03, $0) } ?? 0.28)
                    .stroke(Theme.accentInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90 + (spinning ? turn * 360 : 0)))
            }
        }
    }
}

/// «Идёт запись»: таймер и живая волна от громкости микрофона.
private struct RecordingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MeetingItem

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                Text("Идёт запись").font(.headline)
            }
            if let start = item.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.isRecording {
                Button("Остановить запись") { model.toggleRecording() }
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
    }
}
