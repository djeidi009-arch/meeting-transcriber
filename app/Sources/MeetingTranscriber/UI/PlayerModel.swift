import AVFoundation
import DetectorCore
import DSWaveformImage
import Observation

/// Плеер встречи: видео из исходного файла или обе звуковые дорожки одной композицией.
@MainActor @Observable
final class PlayerModel {
    static let rates: [Float] = [1, 1.5, 2]
    static let waveformBars = 220

    let player = AVPlayer()
    var currentTime = 0.0
    var duration = 0.0
    var isPlaying = false
    var hasVideo = false
    /// false — в папке нет ни звука, ни видео: «Запись не сохранилась».
    var hasMedia = false
    var isLoaded = false
    /// Путь исходного видео, которого нет на месте.
    var missingVideo: String?
    var rate: Float = 1 { didSet { player.defaultRate = rate; if isPlaying { player.rate = rate } } }
    /// Громкость по ходу записи, 0…1 — столбики волны.
    var levels: [Float] = []
    /// Реплика под курсором времени; меняется только при переходе к другой, чтобы транскрипт не перерисовывался 10 раз в секунду.
    private(set) var currentLine: Int?
    var document: MeetingDocument? { didSet { updateLine() } }

    @ObservationIgnored private var observer: Any?

    func load(item: MeetingItem) async {
        let fm = FileManager.default
        let tracks = ["mic.m4a", "system.m4a"].map { item.dir.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        var video: URL?
        if let source = item.sourceFile {
            if fm.fileExists(atPath: source.path) {
                if (try? await AVURLAsset(url: source).loadTracks(withMediaType: .video).isEmpty) == false { video = source }
            } else if ["mp4", "mov", "m4v", "mkv", "webm", "avi"].contains(source.pathExtension.lowercased()) {
                missingVideo = source.path
            }
        }

        let playerItem: AVPlayerItem?
        if let video {
            playerItem = AVPlayerItem(url: video)
        } else if tracks.isEmpty {
            playerItem = nil
        } else {
            // обе стороны разговора слышны сразу: дорожки накладываются с нуля
            let mix = AVMutableComposition()
            for url in tracks {
                let asset = AVURLAsset(url: url)
                guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                      let length = try? await asset.load(.duration) else { continue }
                try? mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                    .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: .zero)
            }
            playerItem = mix.tracks.isEmpty ? nil : AVPlayerItem(asset: mix)
        }
        guard let playerItem, !Task.isCancelled else { isLoaded = true; return }

        let length = (try? await playerItem.asset.load(.duration).seconds) ?? 0
        duration = length.isFinite ? length : 0
        hasVideo = video != nil
        hasMedia = true
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = rate
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.isPlaying = self.player.rate != 0
                self.updateLine()
            }
        }
        isLoaded = true

        // волна — по дорожкам из папки встречи (у видео звук тот же); столбик берёт громкую из сторон
        var merged: [Float] = []
        for url in tracks.isEmpty ? [video].compactMap({ $0 }) : tracks {
            guard let samples = try? await WaveformAnalyzer().samples(fromAudioAt: url, count: Self.waveformBars) else { continue }
            // анализатор отдаёт 0 — громко, 1 — тишина
            let loud = samples.map { 1 - min(max($0, 0), 1) }
            merged = merged.isEmpty ? loud : zip(merged, loud).map(max)
        }
        // самая громкая часть — во всю высоту: тихая запись не должна выглядеть ровной линией
        let peak = merged.max() ?? 0
        if !Task.isCancelled { levels = peak > 0 ? merged.map { $0 / peak } : merged }
    }

    func stop() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }

    func play() {
        guard hasMedia else { return }
        if duration > 0, currentTime >= duration - 0.2 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() { player.pause(); isPlaying = false }
    func toggle() { if isPlaying { pause() } else { play() } }

    func seek(to seconds: Double) {
        guard hasMedia else { return }
        let target = min(max(0, seconds), duration)
        currentTime = target
        updateLine()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func updateLine() {
        let line = document?.lineIndex(at: currentTime)
        if line != currentLine { currentLine = line }
    }
}
