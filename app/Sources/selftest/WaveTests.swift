import Foundation
import DetectorCore

enum WaveTests {
    static func all() {
        test("волна обработки: откуда брать звук") {
            let dir = URL(fileURLWithPath: "/tmp/m"), source = URL(fileURLWithPath: "/tmp/a.mp4")
            let mic = dir.appendingPathComponent("mic.m4a"), system = dir.appendingPathComponent("system.m4a")
            func files(_ stage: ProcessingStage?, have: [URL]) -> [URL] {
                WaveSource.files(dir: dir, stage: stage, sourceFile: source) { have.contains($0) }
            }
            check(files(nil, have: [mic, system, source]).isEmpty, "в очереди звука ещё нет")
            check(files(.extract, have: [mic, system, source]).isEmpty, "на извлечении — тоже")
            check(files(.asr, have: [mic, system, source]) == [mic, system], "дорожки из папки важнее исходника")
            check(files(.summary, have: [system]) == [system], "одна дорожка")
            check(files(.diarize, have: [source]) == [source], "нет дорожек — исходный файл")
            check(files(.asr, have: []).isEmpty, "ничего нет — пусто")
            check(WaveSource.files(dir: dir, stage: .asr, sourceFile: nil) { $0 == system } == [system], "запись без исходника")
        }

        test("полёт файла: дуга от точки броска к волне, без скачков") {
            let to = CGPoint(x: 800, y: 250)
            for from in [CGPoint(x: 200, y: 700), CGPoint(x: 1250, y: 30), CGPoint(x: 820, y: 600)] {
                let first = WaveFlight.pose(at: 0, from: from, to: to), last = WaveFlight.pose(at: WaveFlight.duration, from: from, to: to)
                check(first.center == from && first.morph == 0 && first.appear == 0, "старт — в точке броска, ещё карточкой: \(first)")
                check(last == .init(center: to, morph: 1, stretch: CGSize(width: 1, height: 1), appear: 1, scrim: 0, ring: 1), "финиш — волна на месте: \(last)")
                check(WaveFlight.pose(at: WaveFlight.duration + 5, from: from, to: to) == last, "после конца ничего не меняется")

                // подготовка: шаг назад, против движения
                let crouched = WaveFlight.pose(at: WaveFlight.crouch, from: from, to: to)
                let toward = (crouched.center.x - from.x) * (to.x - from.x) + (crouched.center.y - from.y) * (to.y - from.y)
                check(toward < 0 && crouched.stretch.height < 1, "подготовка: назад и оседает: \(crouched)")

                // дуга приподнята над прямой
                let mid = WaveFlight.arc(from: from, to: to, progress: 0.5)
                check(mid.y < (from.y + to.y) / 2 || abs(from.x - to.x) < 40, "середина дуги выше прямой: \(mid)")

                // без скачков: соседние кадры (120 в секунду) рядом, все величины в разумных пределах
                var previous = first, jump = 0.0, sane = true
                let distance = hypot(to.x - from.x, to.y - from.y)
                for frame in 1...Int(WaveFlight.duration * 120) {
                    let pose = WaveFlight.pose(at: Double(frame) / 120, from: from, to: to)
                    jump = max(jump, hypot(pose.center.x - previous.center.x, pose.center.y - previous.center.y))
                    sane = sane && (0...1).contains(pose.morph) && (0...1).contains(pose.scrim) && pose.morph >= previous.morph - 1e-9
                        && pose.stretch.width > 0.7 && pose.stretch.height > 0.7 && pose.ring > 0.2
                    previous = pose
                }
                check(sane, "все позы в разумных пределах")
                check(jump < distance * 0.035 + 2, "нет скачка положения: \(jump) при пути \(distance)")
            }
            // вытягивается вдоль движения
            let flat = WaveFlight.pose(at: WaveFlight.crouch + WaveFlight.travel / 2, from: CGPoint(x: 0, y: 300), to: CGPoint(x: 900, y: 300))
            check(flat.stretch.width > 1.15 && flat.stretch.height < 0.95, "горизонтальный полёт — шире и ниже: \(flat.stretch)")
            let tall = WaveFlight.pose(at: WaveFlight.crouch + WaveFlight.travel / 2, from: CGPoint(x: 500, y: 900), to: CGPoint(x: 500, y: 100))
            check(tall.stretch.height > 1.15 && tall.stretch.width < 0.95, "вертикальный — выше и уже: \(tall.stretch)")
            check(WaveFlight.duration < 1, "вся последовательность короче секунды")
            check(WaveFlight.arc(from: to, to: to, progress: 0.3) == to, "нулевой путь")
            // бросок у верхнего края окна: дуга не уходит за него
            let top = (0...20).map { WaveFlight.arc(from: CGPoint(x: 1100, y: 80), to: CGPoint(x: 700, y: 250), progress: Double($0) / 20, ceiling: 79).y }.min() ?? 0
            let free = (0...20).map { WaveFlight.arc(from: CGPoint(x: 1100, y: 80), to: CGPoint(x: 700, y: 250), progress: Double($0) / 20).y }.min() ?? 0
            check(top >= 79 && free < 79, "потолок дуги: \(top) против \(free)")
        }
    }
}
