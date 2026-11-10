import SwiftUI

/// Волна-индикатор: штрихи дышат, по ним слева направо бежит блик. `energy` 0 — замерла, 1 — идёт работа.
struct PulseWave: View {
    var energy: Double = 1
    var tint: Color = Theme.accentInk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || energy == 0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let step: CGFloat = 6
                let count = max(1, Int(size.width / step))
                let inset = (size.width - CGFloat(count) * step) / 2
                let scan = (t * 0.45).truncatingRemainder(dividingBy: 1.4) - 0.2
                for bar in 0..<count {
                    let x = Double(bar) / Double(count)
                    let window = pow(sin(.pi * x), 1.5) // к краям волна затухает
                    let wave = 0.5 + 0.25 * sin(x * 14 - t * 3.1) + 0.25 * sin(x * 31 + t * 4.7)
                    let length = max(3, (0.05 + window * (0.1 + 0.85 * wave * energy)) * size.height)
                    let rect = CGRect(x: inset + CGFloat(bar) * step + 1.5, y: (size.height - length) / 2, width: 3, height: length)
                    let path = Path(roundedRect: rect, cornerRadius: 1.5)
                    let glow = reduceMotion ? 0.5 : max(0, 1 - abs(x - scan) * 4) * energy
                    context.fill(path, with: .style(.primary.opacity(0.2)))
                    context.fill(path, with: .color(tint.opacity(0.2 + 0.8 * glow)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
