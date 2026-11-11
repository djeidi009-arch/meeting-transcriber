import SwiftUI

/// Облик живой формы: восемь чисел, между которыми SwiftUI плавно переходит при смене этапа.
struct OrbLook: VectorArithmetic, Equatable {
    var v: SIMD8<Double>

    /// `size` — размер; `wobble` — медленное «дыхание» контура; `ripple` — мелкая рябь; `lobes` — деление на доли;
    /// `core` — светящаяся сердцевина (заполнение); `glow` — яркость; `flat` — сплющивание в линию; `gray` — потухший цвет.
    init(size: Double, wobble: Double, ripple: Double = 0, lobes: Double = 0, core: Double, glow: Double, flat: Double = 0, gray: Double = 0) {
        v = SIMD8(size, wobble, ripple, lobes, core, glow, flat, gray)
    }

    var size: Double { v[0] }
    var wobble: Double { v[1] }
    var ripple: Double { v[2] }
    var lobes: Double { v[3] }
    var core: Double { v[4] }
    var glow: Double { v[5] }
    var flat: Double { v[6] }
    var gray: Double { v[7] }

    /// В очереди: маленькая, почти неподвижная, приглушённая.
    static let queued = OrbLook(size: 0.5, wobble: 0.3, core: 0.25, glow: 0.5)
    /// Только что принятый файл: такой форма садится в карточку после броска.
    static let arrival = OrbLook(size: 0.56, wobble: 0.5, core: 0.3, glow: 0.7)
    /// Извлечение звука: собирается и медленно дышит.
    static let extract = OrbLook(size: 0.72, wobble: 1, core: 0.32, glow: 0.8)
    /// Распознавание: по контуру идёт рябь, сердцевина растёт вместе с долей.
    static func asr(_ fraction: Double) -> OrbLook {
        OrbLook(size: 0.8 + 0.2 * fraction, wobble: 0.6, ripple: 1, core: 0.3 + 0.55 * fraction, glow: 0.9)
    }
    /// Спикеры: форма делится на связанные доли.
    static let diarize = OrbLook(size: 0.98, wobble: 0.5, ripple: 0.15, lobes: 1, core: 0.5, glow: 0.9)
    /// Summary: доли собрались в одну компактную светящуюся форму.
    static let summary = OrbLook(size: 0.66, wobble: 0.5, core: 0.95, glow: 1)
    /// Финал: вдох перед тем, как сплющиться в линию записи.
    static let inhale = OrbLook(size: 0.78, wobble: 0.3, core: 1, glow: 1)
    static let line = OrbLook(size: 0.78, wobble: 0, core: 1, glow: 1, flat: 1)
    /// Ошибка: гаснет и замирает.
    static let failed = OrbLook(size: 0.6, wobble: 0.2, core: 0.2, glow: 0.45, gray: 1)

    static var zero: OrbLook { OrbLook(size: 0, wobble: 0, core: 0, glow: 0) }
    static func + (a: OrbLook, b: OrbLook) -> OrbLook { var r = a; r.v += b.v; return r }
    static func - (a: OrbLook, b: OrbLook) -> OrbLook { var r = a; r.v -= b.v; return r }
    mutating func scale(by factor: Double) { v *= factor }
    var magnitudeSquared: Double { (v * v).sum() }
}

/// Живая форма на фоне карточки обработки: мягкий замкнутый контур в палитре (лайм и холодный нейтральный).
/// У каждого этапа свой облик; в финале форма сплющивается в линию записи.
struct Orb: View, Animatable {
    var look: OrbLook
    /// Время для движения контура; при неизменном времени форма стоит.
    var time = 0.0
    /// Сильно сглаженная громкость записи по кругу, 0…1: рябь распознавания слегка повторяет звук.
    var envelope: [Double] = []
    /// Куда форма сплющивается в финале: место линии записи в координатах формы. nil — по середине, во всю ширину.
    var line: CGRect?

    var animatableData: OrbLook {
        get { look }
        set { look = newValue }
    }

    /// Где форма стоит в карточке обработки: по центру места над текстом и шагами.
    static func home(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let free = max(size.height - 250, 110) // высота над блоком текста
        return (CGPoint(x: size.width / 2, y: free / 2 + 14), max(44, min(size.width * 0.19, free * 0.4)))
    }

    private static let core = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(red: 0xD4 / 255, green: 0xF2 / 255, blue: 0x5A / 255, alpha: 1) : .white
    })
    /// Края мягкие, поэтому форма рисуется втрое мельче и растягивается: в девять раз меньше точек на кадр.
    private static let coarse: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                context.scaleBy(x: 1 / Self.coarse, y: 1 / Self.coarse)
                draw(&context, geo.size)
            }
            .frame(width: geo.size.width / Self.coarse, height: geo.size.height / Self.coarse)
            .scaleEffect(Self.coarse, anchor: .topLeading)
            .saturation(1 - look.gray)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let home = Self.home(in: size)
        let flat = min(max(look.flat, 0), 1), live = 1 - flat
        let radius = Double(home.radius) * max(look.size, 0.05)
        let target = line ?? CGRect(x: 0, y: size.height / 2, width: size.width, height: 0)
        let center = CGPoint(x: home.center.x + (target.midX - home.center.x) * flat, y: home.center.y + (target.midY - home.center.y) * flat)
        // сплющивание: по ширине — на всё место линии, по высоте — в тонкую линию
        let wide = 1 + (Double(target.width) / 2 / radius - 1) * flat, tall = 1 + (1.2 / radius - 1) * flat

        func contour(_ scale: Double, _ phase: Double) -> Path {
            var path = Path()
            let count = 72
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi
                var bulge = look.wobble * (0.04 * sin(time * 0.8 + phase) + 0.06 * sin(2 * angle + time * 0.45 + phase) + 0.045 * sin(3 * angle - time * 0.33 + phase * 2))
                bulge += look.ripple * (0.028 * sin(7 * angle - time * 1.5) + 0.018 * sin(11 * angle + time * 1.1) + 0.14 * (loudness(angle) - 0.5))
                bulge += look.lobes * 0.26 * cos(3 * (angle - time * 0.09))
                let reach = radius * scale * (1 + bulge * live)
                let point = CGPoint(x: center.x + cos(angle) * reach * wide, y: center.y + sin(angle) * reach * tall)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }

        let body = contour(1, 0)
        if live > 0.01 {
            var halo = context
            halo.opacity = 0.5 * look.glow * live
            halo.addFilter(.blur(radius: radius * 0.42))
            halo.fill(contour(1.4, 1.3), with: .color(Theme.cool))

            var soft = context
            soft.opacity = 0.85 * look.glow * live
            soft.addFilter(.blur(radius: radius * 0.14))
            soft.fill(body, with: .radialGradient(Gradient(colors: [Theme.glow, Theme.glow.opacity(0.8), Theme.cool.opacity(0.7)]),
                                                  center: center, startRadius: 0, endRadius: radius * 1.15))

            // сердцевина: чем дальше обработка, тем она больше и ярче
            var heart = context
            heart.opacity = (0.25 + 0.6 * look.core) * look.glow * live
            heart.addFilter(.blur(radius: radius * 0.2))
            heart.fill(contour(0.22 + 0.5 * look.core, 2.4), with: .color(Self.core))
        }
        if flat > 0.01 {
            // к концу сплющивания остаётся нейтральная линия — цвет несыгранной волны плеера
            var line = context
            line.opacity = flat
            line.fill(body, with: .style(.primary.opacity(0.28)))
        }
    }

    /// Громкость записи в этом направлении контура, плавно между соседними отсчётами.
    private func loudness(_ angle: Double) -> Double {
        guard envelope.count > 1 else { return 0.5 }
        let position = angle / (2 * .pi) * Double(envelope.count)
        let index = Int(position) % envelope.count, mix = (1 - cos((position - floor(position)) * .pi)) / 2
        return envelope[index] * (1 - mix) + envelope[(index + 1) % envelope.count] * mix
    }
}
