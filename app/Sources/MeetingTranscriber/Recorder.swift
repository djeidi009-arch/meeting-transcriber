import AVFoundation
import CoreGraphics
import CoreMedia
import DetectorCore
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case noScreenAccess
    case noMicrophoneAccess
    case noDisplay
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noScreenAccess:
            return "Нет доступа к записи экрана и звука системы. Разрешите MeetingTranscriber в «Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного аудио» и перезапустите программу."
        case .noMicrophoneAccess:
            return "Нет доступа к микрофону. Разрешите MeetingTranscriber в «Системные настройки → Конфиденциальность и безопасность → Микрофон»."
        case .noDisplay:
            return "Не найден дисплей для захвата звука."
        case .failed(let reason):
            return "Не удалось начать запись: \(reason)"
        }
    }

    var isPermission: Bool {
        switch self {
        case .noScreenAccess, .noMicrophoneAccess: return true
        default: return false
        }
    }
}

enum Permissions {
    static var microphoneGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var microphoneDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }
    static var screenGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Первый запуск: macOS сама показывает диалоги с объяснением из Info.plist.
    static func requestIfNeeded() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }
}

/// Пишет одну дорожку в CAF (16 бит PCM, частота и каналы — как пришли от ScreenCaptureKit).
/// Позиция в файле следует PTS буферов: задержка начала дорожки относительно старта записи
/// и пропуски в потоке заполняются тишиной (расчёт — `TrackAligner` в DetectorCore).
private final class TrackWriter {
    let url: URL
    private let clock: RecordingClock
    private var aligner: TrackAligner?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var lastError: Error?
    /// Громкость дорожки 0…1, не чаще 20 раз в секунду (вызывается с очереди звука).
    var onLevel: ((Float) -> Void)?
    private var lastLevelAt = 0.0

    init(url: URL, clock: RecordingClock) {
        self.url = url
        self.clock = clock
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                   into: pcm.mutableAudioBufferList)
        guard status == noErr else { return }
        reportLevel(pcm)
        do {
            if file == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
                file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            }
            guard let file else { return }
            if aligner == nil { aligner = TrackAligner(sampleRate: file.processingFormat.sampleRate) }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if pts.isValid, pts.isNumeric, let silence = aligner?.silenceFrames(beforeBufferAt: pts.seconds, clock: clock),
               silence > 0 {
                try writeSilence(frames: silence, to: file)
            }
            let out = pcm.format == file.processingFormat ? pcm : try convert(pcm, to: file.processingFormat)
            try file.write(from: out)
            aligner?.didWrite(frames: Int64(out.frameLength))
        } catch {
            lastError = error
        }
    }

    private func reportLevel(_ pcm: AVAudioPCMBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard let onLevel, now - lastLevelAt >= 0.05, pcm.frameLength > 0 else { return }
        lastLevelAt = now
        let count = Int(pcm.frameLength)
        var sum: Float = 0
        if let samples = pcm.floatChannelData?[0] {
            for index in 0..<count { sum += samples[index] * samples[index] }
        } else if let samples = pcm.int16ChannelData?[0] {
            for index in 0..<count { let value = Float(samples[index]) / 32768; sum += value * value }
        } else {
            return
        }
        // шкала в децибелах: −50 дБ и тише — ноль, 0 дБ — единица
        let decibels = 10 * log10(max(sum / Float(count), 1e-10))
        onLevel(min(max((decibels + 50) / 50, 0), 1))
    }

    private func writeSilence(frames: Int64, to file: AVAudioFile) throws {
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw RecorderError.failed("нет буфера")
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var left = frames
        while left > 0 {
            let n = AVAudioFrameCount(min(Int64(chunk), left))
            buffer.frameLength = n
            for b in list { if let data = b.mData { memset(data, 0, Int(b.mDataByteSize)) } }
            try file.write(from: buffer)
            aligner?.didWrite(frames: Int64(n))
            left -= Int64(n)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { throw RecorderError.failed("нет конвертера формата") }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw RecorderError.failed("нет буфера")
        }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return out
    }

    func close() {
        file = nil // AVAudioFile дописывает заголовок CAF при освобождении
    }
}

/// Запись звука системы (без звука самой программы) и микрофона одним потоком ScreenCaptureKit.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var system: TrackWriter?
    private var mic: TrackWriter?
    private let audioQueue = DispatchQueue(label: "ru.local.meeting-transcriber.audio")
    private let screenQueue = DispatchQueue(label: "ru.local.meeting-transcriber.screen")

    /// Поток остановился сам (отозвали разрешение, сбой) — приложение завершает встречу.
    var onUnexpectedStop: ((Error) -> Void)?
    /// Громкость микрофона 0…1, не чаще 20 раз в секунду, с очереди звука — для живой волны.
    var onLevel: ((Float) -> Void)?

    var isRunning: Bool { stream != nil }

    func start(dir: URL) async throws {
        if Permissions.microphoneDenied { throw RecorderError.noMicrophoneAccess }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecorderError.noMicrophoneAccess }
        }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw RecorderError.noScreenAccess
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw RecorderError.noScreenAccess
        }
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // Видео не нужно, но поток без него не бывает: минимальный кадр раз в секунду.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3

        // Общий старт записи в шкале часов хоста (в ней же PTS буферов ScreenCaptureKit).
        let clock = RecordingClock(startTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds)
        system = TrackWriter(url: dir.appendingPathComponent("system.caf"), clock: clock)
        mic = TrackWriter(url: dir.appendingPathComponent("mic.caf"), clock: clock)
        mic?.onLevel = { [weak self] level in self?.onLevel?(level) }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
            try await stream.startCapture()
        } catch {
            system = nil
            mic = nil
            let ns = error as NSError
            if ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.userDeclined.rawValue {
                throw RecorderError.noScreenAccess
            }
            throw RecorderError.failed(error.localizedDescription)
        }
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            audioQueue.async { [self] in
                system?.close(); mic?.close()
                system = nil; mic = nil
                c.resume()
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio: system?.append(sampleBuffer)
        case .microphone: mic?.append(sampleBuffer)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard self.stream === stream else { return }
        self.stream = nil
        // Сообщить о сбое только после закрытия файлов: встречу сразу ставят в очередь обработки.
        audioQueue.async { [self] in
            system?.close(); mic?.close()
            system = nil; mic = nil
            onUnexpectedStop?(error)
        }
    }
}
