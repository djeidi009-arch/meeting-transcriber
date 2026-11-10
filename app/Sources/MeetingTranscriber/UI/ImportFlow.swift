import SwiftUI

/// Загрузка перетаскиванием: зона броска на всё окно, «втягивание» файла и сообщение, если файл не подошёл.
private struct ImportFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // окно под зоной броска и «втягиванием» уходит в расфокус
            .blur(radius: model.dropTargeted || model.importFlight != nil ? (reduceMotion ? 0 : 14) : 0)
            .dropDestination(for: URL.self) { urls, _ in
                _ = model.importFiles(urls)
                return true
            } isTargeted: { model.dropTargeted = $0 }
            .overlay {
                if model.dropTargeted {
                    DropZone().transition(.opacity)
                } else if let flight = model.importFlight {
                    ImportFlight(name: flight.name)
                        .id(flight.id)
                        .transition(.opacity)
                        // до секунды, обработка к этому времени уже идёт
                        .task {
                            try? await Task.sleep(for: .seconds(0.95))
                            model.importFlight = nil
                        }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = model.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .padding(.bottom, 24)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { model.notice = nil }
                        .help("Скрыть")
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(6))
                            model.notice = nil
                        }
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.dropTargeted)
            .animation(.easeOut(duration: 0.25), value: model.importFlight?.id)
            .animation(.spring(duration: 0.4), value: model.notice)
    }
}

extension View {
    func importFlow() -> some View { modifier(ImportFlow()) }
}

/// Пока файл над окном: «Отпустите, чтобы расшифровать».
private struct DropZone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    // искры стягиваются к середине — «окно втягивает файл»
                    Canvas { context, size in
                        for index in 0..<56 {
                            func random(_ salt: Int) -> Double { noise(index, salt) }
                            let life = (t * (0.18 + 0.2 * random(1)) + random(2)).truncatingRemainder(dividingBy: 1)
                            let angle = random(3) * 2 * .pi
                            let distance = (1 - life) * (0.2 + 0.4 * random(4)) * max(size.width, size.height)
                            let point = CGPoint(x: size.width / 2 + cos(angle) * distance, y: size.height / 2 + sin(angle) * distance * 0.7)
                            let radius = 1.5 + 2.5 * random(5)
                            context.opacity = sin(.pi * life) * 0.7
                            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                                         with: .color(index % 2 == 0 ? Theme.accentInk : .primary.opacity(0.5)))
                        }
                    }
                    // пунктир бежит по рамке
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Theme.accentInk, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [14, 12], dashPhase: -t * 30))
                        .padding(20)
                }
            }
            VStack(spacing: 18) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .symbolEffect(.bounce.down, options: .repeating, isActive: !reduceMotion)
                    .frame(width: 96, height: 96)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 30)
                Text("Отпустите, чтобы расшифровать")
                    .font(.system(size: 34, weight: .semibold))
                Text("Видео или аудио, можно несколько файлов сразу")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Backdrop() }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// После броска: карточка файла стягивается в волну на переливающемся фоне. Меньше секунды, ничего не задерживает.
private struct ImportFlight: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    private struct Frame {
        var card = 1.0       // масштаб карточки файла
        var cardOpacity = 1.0
        var wave = 0.0       // ширина волны, 0…1
        var waveOpacity = 0.0
        var backdrop = 1.0
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                Backdrop()
                card
            } else {
                KeyframeAnimator(initialValue: Frame(), trigger: started) { frame in
                    ZStack {
                        Backdrop().opacity(frame.backdrop)
                        card
                            .scaleEffect(frame.card)
                            .blur(radius: (1 - frame.card) * 14)
                            .opacity(frame.cardOpacity)
                        PulseWave()
                            .frame(width: 460, height: 120)
                            .scaleEffect(x: frame.wave, y: 0.4 + 0.6 * frame.wave)
                            .opacity(frame.waveOpacity)
                    }
                } keyframes: { _ in
                    KeyframeTrack(\.card) {
                        LinearKeyframe(1, duration: 0.15)
                        SpringKeyframe(0.2, duration: 0.4, spring: .smooth)
                    }
                    KeyframeTrack(\.cardOpacity) {
                        LinearKeyframe(1, duration: 0.3)
                        LinearKeyframe(0, duration: 0.2)
                    }
                    KeyframeTrack(\.wave) {
                        LinearKeyframe(0.1, duration: 0.25)
                        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                    }
                    KeyframeTrack(\.waveOpacity) {
                        LinearKeyframe(0, duration: 0.25)
                        LinearKeyframe(1, duration: 0.2)
                        LinearKeyframe(1, duration: 0.2)
                        LinearKeyframe(0, duration: 0.25)
                    }
                    KeyframeTrack(\.backdrop) {
                        LinearKeyframe(1, duration: 0.6)
                        LinearKeyframe(0, duration: 0.3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { started = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 56, height: 56)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }
}

/// Полупрозрачная переливающаяся подложка на всё окно, вместе с полосой заголовка.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            Theme.page.opacity(0.72)
            Aurora()
        }
        .ignoresSafeArea()
    }
}
