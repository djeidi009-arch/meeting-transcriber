import SwiftUI

/// Короткий всплеск частиц из точки: штрихи и точки разлетаются и гаснут. Сам себя не убирает — это делает владелец.
struct ParticleBurst: View {
    var origin = UnitPoint(x: 0.5, y: 0.3)
    static let duration = 1.6
    @State private var start = Date()

    private static let colors: [Color] = [Theme.accent, Theme.accentInk, .pink, .blue, .purple, .orange]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < Self.duration else { return }
                let progress = t / Self.duration
                let ease = 1 - pow(1 - progress, 3) // быстро вылетают, плавно тормозят
                for index in 0..<110 {
                    func random(_ salt: Int) -> Double { noise(index, salt) }
                    let angle = random(1) * 2 * .pi
                    let distance = (120 + 460 * random(2)) * ease
                    let x = size.width * origin.x + cos(angle) * distance
                    let y = size.height * origin.y + sin(angle) * distance * 0.75 + 220 * progress * progress
                    var particle = context
                    particle.opacity = (1 - progress * progress) * (0.55 + 0.45 * random(3))
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: .radians(angle + t * (random(4) - 0.5) * 8))
                    let length = 4 + 12 * random(5)
                    let shape = index % 3 == 0
                        ? Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6))
                        : Path(roundedRect: CGRect(x: -length / 2, y: -1.5, width: length, height: 3), cornerRadius: 1.5)
                    particle.fill(shape, with: .color(Self.colors[index % Self.colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Псевдослучайное, но постоянное для частицы число 0…1 (перемешивание битов, как в MurmurHash).
func noise(_ index: Int, _ salt: Int) -> Double {
    var hash = UInt64(index * 73 + salt * 7919 + 1)
    hash ^= hash >> 33
    hash &*= 0xff51_afd7_ed55_8ccd
    hash ^= hash >> 33
    hash &*= 0xc4ce_b9fe_1a85_ec53
    hash ^= hash >> 33
    return Double(hash % 10_000) / 10_000
}
