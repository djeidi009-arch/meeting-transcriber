import DetectorCore
import SwiftUI

/// Загрузка перетаскиванием: зона броска на всё окно, полёт файла к волне обработки и сообщение, если файл не подошёл.
private struct ImportFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Где в окне начинается содержимое: точка броска приходит в его координатах.
    @State private var origin = CGPoint.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
            .dropDestination(for: URL.self) { urls, location in
                _ = model.importFiles(urls, from: CGPoint(x: origin.x + location.x, y: origin.y + location.y))
                return true
            } isTargeted: { model.dropTargeted = $0 }
            .overlay {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    if model.dropTargeted {
                        DropZone().transition(.opacity)
                    } else if let flight = model.importFlight {
                        // без точки броска (кнопка «Загрузить», меню) карточка выходит из-под кнопки в тулбаре
                        let from = flight.origin ?? CGPoint(x: frame.maxX - 200, y: frame.minY + 104)
                        // места формы ещё нет (экран обработки не успел появиться) — оно там же, где у любой встречи в обработке
                        let slot = model.waveSlot ?? CGRect(x: frame.midX - 200, y: frame.minY + 160, width: 700, height: max(300, frame.height - 190))
                        ImportFlight(name: flight.name, from: CGPoint(x: from.x - frame.minX, y: from.y - frame.minY),
                                     slot: slot.offsetBy(dx: -frame.minX, dy: -frame.minY))
                            .id(flight.id)
                    }
                }
            }
            // полёт короче секунды и ничего не задерживает: обработка к этому времени уже идёт
            .task(id: model.importFlight?.id) {
                guard let id = model.importFlight?.id else { return }
                try? await Task.sleep(for: .seconds(WaveFlight.duration))
                if model.importFlight?.id == id { model.importFlight = nil }
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
            // зона броска уходит быстрее, чем входит: бросок не должен ждать
            .animation(model.dropTargeted ? .easeOut(duration: 0.25) : .easeIn(duration: 0.15), value: model.dropTargeted)
            .animation(.spring(duration: 0.4), value: model.notice)
    }
}

extension View {
    func importFlow() -> some View { modifier(ImportFlow()) }
}

/// Пока файл над окном: «Отпустите, чтобы расшифровать». Движение одно — приглашение тянется к файлу.
private struct DropZone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull = CGSize.zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.accentInk, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [14, 12]))
                .padding(20)
            VStack(spacing: 18) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 96, height: 96)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                    .scaleEffect(pull == .zero ? 1 : 1.08)
                Text("Отпустите, чтобы расшифровать")
                    .font(.system(size: 34, weight: .semibold))
                Text("Видео или аудио, можно несколько файлов сразу")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(40)
            // подготовка к броску: приглашение подаётся навстречу файлу, плитка чуть вырастает
            .offset(pull)
            .animation(.spring(duration: 0.45, bounce: 0.35), value: pull)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !reduceMotion {
                PointerTracker { offset in
                    // тянется не дальше, чем на полсотни точек
                    let reach = offset.map { CGSize(width: min(max($0.x * 0.16, -48), 48), height: min(max($0.y * 0.16, -48), 48)) } ?? .zero
                    if abs(reach.width - pull.width) + abs(reach.height - pull.height) > 0.5 { pull = reach }
                }
            }
        }
        .background { Backdrop() }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// Где указатель относительно середины зоны, пока над окном держат файл: событий мыши в это время нет,
/// поэтому положение спрашивается у окна 30 раз в секунду. nil — указатель вне окна.
private struct PointerTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) { view.onMove = onMove }

    final class TrackerView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var timer: Timer?
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            timer?.invalidate()
            timer = nil
            guard window != nil else { return } // зону убрали — таймер не остаётся
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    self.onMove?(self.bounds.contains(point) ? CGPoint(x: point.x - self.bounds.midX, y: point.y - self.bounds.midY) : nil)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
}

/// После броска: карточка файла появляется там, где файл отпустили, оседает, летит по дуге к карточке обработки,
/// по пути превращаясь в каплю живой формы, и садится с доведением — уже как форма экрана обработки. Меньше секунды.
private struct ImportFlight: View {
    let name: String
    /// Точка броска и место живой формы (карточка обработки) — в координатах этого слоя.
    let from: CGPoint
    let slot: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let cardSize = CGSize(width: 340, height: 92)

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            if reduceMotion {
                // без полёта: карточка проявляется в точке броска и гаснет, форма уже на месте
                card
                    .opacity(WaveFlight.pose(at: time, from: from, to: from).appear * (1 - min(1, max(0, (time - 0.5) / 0.3))))
                    .position(from)
            } else {
                let home = Orb.home(in: slot.size)
                let pose = WaveFlight.pose(at: time, from: from, to: CGPoint(x: slot.minX + home.center.x, y: slot.minY + home.center.y), ceiling: 64)
                let form = pose.morph * pose.morph * (3 - 2 * pose.morph)
                let splash = (pose.ring - 1) / 2.2 // приземление: капля на миг расплющивается
                ZStack {
                    Theme.page.opacity(0.5 * pose.scrim).ignoresSafeArea()
                    // та же живая форма, что стоит в карточке обработки: к приземлению совпадает с ней
                    Orb(look: .arrival, time: timeline.date.timeIntervalSinceReferenceDate)
                        .frame(width: slot.width, height: slot.height)
                        .scaleEffect(x: pose.stretch.width * (0.5 + 0.5 * form) * (1 + 0.16 * splash),
                                     y: pose.stretch.height * (0.5 + 0.5 * form) * (1 - 0.14 * splash),
                                     anchor: UnitPoint(x: 0.5, y: home.center.y / max(slot.height, 1)))
                        .opacity(min(1, max(0, (pose.morph - 0.12) / 0.4)))
                        .position(x: pose.center.x, y: pose.center.y + slot.height / 2 - home.center.y)
                    card
                        // карточка сжимается в каплю и растворяется в форме
                        .scaleEffect(x: pose.stretch.width * (1 - 0.55 * form), y: pose.stretch.height * (1 - 0.55 * form))
                        .opacity(pose.appear * (1 - min(1, pose.morph / 0.55)))
                        .position(pose.center)
                }
            }
        }
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
        .frame(maxWidth: Self.cardSize.width)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }
}

/// Матовая подложка зоны броска на всё окно, вместе с полосой заголовка. Неподвижна.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.page.opacity(0.5)
            Aurora()
        }
        .ignoresSafeArea()
    }
}
