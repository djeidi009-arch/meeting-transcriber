import SwiftUI

/// Волна записи: штрихи по настоящей форме звука, сыгранная часть — акцентом.
/// Пока формы нет — ровная линия; появилась — штрихи вырастают из линии от середины к краям.
struct WaveBars: View, Animatable {
    static let count = 220

    /// Громкость по ходу записи, 0…1; пусто — формы ещё нет.
    var levels: [Float] = []
    /// 0 — линия, 1 — настоящая форма звука.
    var real = 0.0
    /// Доля слева, закрашенная акцентом.
    var played = 0.0
    /// Курсор времени плеера.
    var head = false

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(real, played) }
        set { real = newValue.first; played = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let count = Self.count
            let step = size.width / CGFloat(count)
            let width = max(1, step / 2)
            var bars = Path()
            for bar in 0..<count {
                let x = (Double(bar) + 0.5) / Double(count)
                let grown = min(max(real * 1.7 - abs(x - 0.5) * 1.4, 0), 1) // середина вырастает первой
                let loud = levels.isEmpty ? 0 : Double(levels[bar * levels.count / count])
                let length = max(2, loud * grown * size.height)
                bars.addRoundedRect(in: CGRect(x: CGFloat(bar) * step + (step - width) / 2, y: (size.height - length) / 2, width: width, height: length),
                                    cornerSize: CGSize(width: width / 2, height: width / 2))
            }
            context.fill(bars, with: .style(.primary.opacity(0.28)))
            if played > 0.001 {
                var done = context
                done.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * played, height: size.height)))
                done.fill(bars, with: .color(Theme.accentInk))
            }
            if head {
                context.fill(Path(CGRect(x: size.width * played - 0.5, y: 0, width: 1, height: size.height)), with: .style(.primary.opacity(0.55)))
            }
        }
        .accessibilityHidden(true)
    }
}
