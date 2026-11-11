import CoreGraphics
import Foundation

/// Откуда брать звук для волны на экране обработки.
public enum WaveSource {
    /// Файлы, по которым рисуется волна. Пусто — звука ещё нет (очередь, извлечение) или файлов нет на месте.
    public static func files(dir: URL, stage: ProcessingStage?, sourceFile: URL?,
                             exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [URL] {
        guard let stage, stage != .extract else { return [] }
        let tracks = ["mic.m4a", "system.m4a"].map { dir.appendingPathComponent($0) }.filter(exists)
        return tracks.isEmpty ? [sourceFile].compactMap { $0 }.filter(exists) : tracks
    }
}

/// Полёт карточки файла к волне обработки: подготовка → дуга → доведение. Чистая функция времени — рисует её окно.
public enum WaveFlight {
    public static let crouch = 0.14 // подготовка: карточка оседает и чуть отходит назад
    public static let travel = 0.48 // полёт по дуге
    public static let settle = 0.26 // доведение: волна проскакивает место и успокаивается
    public static let duration = crouch + travel + settle

    public struct Pose: Equatable {
        public var center: CGPoint
        /// 0 — карточка файла, 1 — волна.
        public var morph: Double
        /// Сжатие-растяжение: вдоль движения вытянута, поперёк сжата.
        public var stretch: CGSize
        /// Проявление карточки в точке броска.
        public var appear: Double
        /// Подложка под полётом.
        public var scrim: Double
        /// Размах волны: 1 — покой, больше — всплеск при приземлении.
        public var ring: Double

        public init(center: CGPoint, morph: Double, stretch: CGSize, appear: Double, scrim: Double, ring: Double) {
            self.center = center; self.morph = morph; self.stretch = stretch; self.appear = appear; self.scrim = scrim; self.ring = ring
        }
    }

    /// `ceiling` — выше этой высоты дуга не поднимается (верх окна).
    public static func pose(at time: Double, from: CGPoint, to: CGPoint, ceiling: Double = -.infinity) -> Pose {
        let dx = to.x - from.x, dy = to.y - from.y
        let distance = max((dx * dx + dy * dy).squareRoot(), 1)
        let ux = dx / distance, uy = dy / distance
        let back = min(10, distance * 0.05) // подготовка: шаг против движения
        let start = CGPoint(x: from.x - ux * back, y: from.y - uy * back)
        let scrim = 1 - smooth((time - crouch - travel * 0.35) / (travel * 0.65 + settle * 0.6))
        let squash = CGSize(width: 1.05, height: 0.88)

        if time <= crouch {
            let u = easeOut(max(0, time) / crouch)
            return Pose(center: CGPoint(x: from.x + (start.x - from.x) * u, y: from.y + (start.y - from.y) * u), morph: 0,
                        stretch: CGSize(width: 1 + (squash.width - 1) * u, height: 1 + (squash.height - 1) * u),
                        appear: smooth(time / (crouch * 0.6)), scrim: smooth(time / crouch), ring: 1)
        }
        if time < crouch + travel {
            let u = (time - crouch) / travel
            let along = 0.24 * sin(.pi * u) // растяжение сильнее всего в середине пути
            let rest = 1 - smooth(u / 0.3)  // осевшая карточка распрямляется в начале полёта
            return Pose(center: arc(from: start, to: to, progress: easeInOut(u), ceiling: ceiling), morph: easeInOut(u),
                        stretch: CGSize(width: 1 + along * (abs(ux) - 0.5 * abs(uy)) + (squash.width - 1) * rest,
                                        height: 1 + along * (abs(uy) - 0.5 * abs(ux)) + (squash.height - 1) * rest),
                        appear: 1, scrim: scrim, ring: 1 + 2.2 * smooth((u - 0.55) / 0.45))
        }
        let u = min(1, (time - crouch - travel) / settle)
        // затухающее колебание: проскочила место, вернулась
        let swing = sin(.pi * 1.5 * u) * exp(-3 * u) * (1 - u)
        let over = min(9, distance * 0.04) * swing
        return Pose(center: CGPoint(x: to.x + ux * over, y: to.y + uy * over), morph: 1, stretch: CGSize(width: 1, height: 1),
                    appear: 1, scrim: scrim, ring: 1 + 2.2 * (1 - u) * (1 - u) * cos(.pi * u))
    }

    /// Точка дуги: кривая Безье, середина приподнята над прямой.
    public static func arc(from: CGPoint, to: CGPoint, progress: Double, ceiling: Double = -.infinity) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 1 else { return to }
        // перпендикуляр к пути, направленный вверх (на экране y растёт вниз)
        var nx = dy / distance, ny = -dx / distance
        if ny > 0 { nx = -nx; ny = -ny }
        let lift = min(140, max(36, distance * 0.28))
        let control = CGPoint(x: (from.x + to.x) / 2 + nx * lift, y: max((from.y + to.y) / 2 + ny * lift, min(ceiling, from.y, to.y)))
        let t = min(max(progress, 0), 1), s = 1 - t
        return CGPoint(x: s * s * from.x + 2 * s * t * control.x + t * t * to.x,
                       y: s * s * from.y + 2 * s * t * control.y + t * t * to.y)
    }

    static func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
    static func easeOut(_ x: Double) -> Double { let t = min(max(x, 0), 1); return 1 - (1 - t) * (1 - t) * (1 - t) }
    static func easeInOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t * (t * (6 * t - 15) + 10) // мягче кубической: без рывка в середине пути
    }
}
