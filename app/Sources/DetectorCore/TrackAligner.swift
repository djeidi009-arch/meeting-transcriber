import Foundation

/// Общий старт записи для всех дорожек (секунды в шкале PTS буферов).
/// Обе дорожки получают один и тот же экземпляр, поэтому время в них отсчитывается от одной точки.
public final class RecordingClock {
    private let startTime: Double?
    private let maxStartSkew: Double
    public private(set) var origin: Double?

    /// - Parameters:
    ///   - startTime: момент старта записи в той же шкале, что PTS (часы хоста); nil — неизвестен.
    ///   - maxStartSkew: если первый буфер дальше от `startTime`, чем на столько секунд, шкалы,
    ///     видимо, разные — тогда начало отсчёта берётся от первого буфера любой дорожки.
    public init(startTime: Double?, maxStartSkew: Double = 30) {
        self.startTime = startTime
        self.maxStartSkew = maxStartSkew
    }

    /// Начало отсчёта; фиксируется по первому буферу, пришедшему из любой дорожки.
    public func origin(forFirstBufferAt pts: Double) -> Double {
        if let origin { return origin }
        let resolved: Double
        if let start = startTime, pts >= start - 1, pts - start <= maxStartSkew {
            resolved = start
        } else {
            resolved = pts
        }
        origin = resolved
        return resolved
    }
}

/// Учёт одной дорожки: сколько кадров уже записано и сколько тишины вставить перед следующим буфером,
/// чтобы позиция в файле совпала с его PTS (начальная задержка дорожки и пропуски в потоке).
public struct TrackAligner {
    public let sampleRate: Double
    /// Расхождение меньше этого (секунды) — обычное дрожание PTS, тишину не вставляем.
    public let tolerance: Double
    public private(set) var framesWritten: Int64 = 0

    public init(sampleRate: Double, tolerance: Double = 0.02) {
        self.sampleRate = sampleRate
        self.tolerance = tolerance
    }

    /// Сколько кадров тишины записать перед буфером с данным PTS (0 — писать сразу).
    public func silenceFrames(beforeBufferAt pts: Double, clock: RecordingClock) -> Int64 {
        let origin = clock.origin(forFirstBufferAt: pts)
        let expected = Int64(((pts - origin) * sampleRate).rounded())
        let gap = expected - framesWritten
        return Double(gap) > tolerance * sampleRate ? gap : 0
    }

    /// Записали `frames` кадров (тишины или звука).
    public mutating func didWrite(frames: Int64) {
        framesWritten += frames
    }
}
