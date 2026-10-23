import Foundation
import DetectorCore

/// Выравнивание дорожек по PTS: сколько тишины вставить перед буфером.
enum AlignerTests {
    static func all() {
        test("PTS: дорожки отсчитываются от общего старта записи") {
            let clock = RecordingClock(startTime: 1000.0)
            var system = TrackAligner(sampleRate: 48_000)
            var mic = TrackAligner(sampleRate: 48_000)
            // system пришла через 0.5 с после старта, мик — через 2 с
            check(system.silenceFrames(beforeBufferAt: 1000.5, clock: clock) == 24_000, "system: 0.5 с тишины")
            system.didWrite(frames: 24_000); system.didWrite(frames: 4_800)
            check(mic.silenceFrames(beforeBufferAt: 1002.0, clock: clock) == 96_000, "mic: 2 с тишины")
            mic.didWrite(frames: 96_000); mic.didWrite(frames: 4_800)
            // буферы идут встык — ничего не вставляется
            check(system.silenceFrames(beforeBufferAt: 1000.6, clock: clock) == 0, "system встык")
            check(mic.silenceFrames(beforeBufferAt: 1002.1, clock: clock) == 0, "mic встык")
        }

        test("PTS: пропуск в потоке заполняется тишиной, дрожание не трогается") {
            let clock = RecordingClock(startTime: 0)
            var t = TrackAligner(sampleRate: 48_000)
            check(t.silenceFrames(beforeBufferAt: 0, clock: clock) == 0, "первый буфер в момент старта")
            t.didWrite(frames: 48_000) // 1 с
            check(t.silenceFrames(beforeBufferAt: 1.004, clock: clock) == 0, "4 мс дрожания — без вставки")
            t.didWrite(frames: 48_000) // до 2 с
            check(t.silenceFrames(beforeBufferAt: 5.0, clock: clock) == 144_000, "пропуск 3 с → 3 с тишины")
            t.didWrite(frames: 144_000)
            check(t.framesWritten == 240_000, "учёт кадров: \(t.framesWritten)")
            check(t.silenceFrames(beforeBufferAt: 4.9, clock: clock) == 0, "буфер из прошлого — без тишины")
        }

        test("PTS: часы потока не совпали со стартом → начало от первого буфера") {
            // PTS в другой шкале времени (на порядки больше старта) — не вставлять часы тишины
            let clock = RecordingClock(startTime: 50.0)
            var system = TrackAligner(sampleRate: 48_000)
            var mic = TrackAligner(sampleRate: 48_000)
            check(system.silenceFrames(beforeBufferAt: 90_000.0, clock: clock) == 0, "первая дорожка — от себя")
            system.didWrite(frames: 4_800)
            check(mic.silenceFrames(beforeBufferAt: 90_001.0, clock: clock) == 48_000, "вторая — относительно первой: 1 с")
            let noStart = RecordingClock(startTime: nil)
            var a = TrackAligner(sampleRate: 16_000)
            check(a.silenceFrames(beforeBufferAt: 7.0, clock: noStart) == 0, "без времени старта — от первого буфера")
            a.didWrite(frames: 16_000)
            check(a.silenceFrames(beforeBufferAt: 10.0, clock: noStart) == 32_000, "пропуск 2 с при 16 кГц")
        }
    }
}
