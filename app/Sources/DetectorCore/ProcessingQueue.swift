import Foundation

/// Последовательно запускает `<pythonPath> -m transcriber process|resummarize <dir>` (cwd — проект).
/// Колбэки приходят с внутренней очереди; приложение само переносит их на main.
public final class ProcessingQueue {
    public enum Kind: String { case process, resummarize }

    public struct Job: Equatable {
        public let dir: URL
        public let kind: Kind
        public init(dir: URL, kind: Kind) { self.dir = dir; self.kind = kind }
    }

    /// Что идёт и что ждёт — по этому снимку окно показывает «Расшифровывается» и «В очереди».
    public struct Snapshot: Equatable {
        public let running: Job?
        public let pending: [Job]
        public init(running: Job?, pending: [Job]) { self.running = running; self.pending = pending }
    }

    /// Код выхода `python -m transcriber process`: транскрипт готов, но summary не получилось.
    public static let exitSummaryFailed: Int32 = 2

    public enum Outcome {
        case success
        /// Встреча расшифрована, `meeting.md` есть, но summary не сделано (код выхода 2); причина — последняя строка stderr.
        case summaryFailed(String)
        case failure(String)
    }

    private let pythonPath: String
    private let projectDir: URL
    private let extraPath: [String]
    private let logURL: URL?
    private let onBusyChange: (Bool) -> Void
    private let onChange: () -> Void
    private let onFinish: (Job, Outcome) -> Void

    private let worker = DispatchQueue(label: "ru.local.meeting-transcriber.processing")
    private let lock = NSLock()
    private var pending: [Job] = []
    private var running: Job?
    private var current: Process?
    private var generation = 0
    private let idle = DispatchGroup()

    /// - Parameter extraPath: каталоги, которые ставятся в начало PATH дочернего процесса
    ///   (папка `claude`, Homebrew для ffmpeg) — у приложения из строки меню PATH минимальный.
    public init(pythonPath: String, projectDir: URL, extraPath: [String] = [], logURL: URL? = nil,
                onBusyChange: @escaping (Bool) -> Void = { _ in },
                onChange: @escaping () -> Void = {},
                onFinish: @escaping (Job, Outcome) -> Void) {
        self.pythonPath = pythonPath
        self.projectDir = projectDir
        self.extraPath = extraPath
        self.logURL = logURL
        self.onBusyChange = onBusyChange
        self.onChange = onChange
        self.onFinish = onFinish
    }

    public var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return running != nil || !pending.isEmpty
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(running: running, pending: pending)
    }

    /// Ставит папку в очередь; повтор того же задания, пока оно ждёт или идёт, игнорируется.
    public func enqueue(_ dir: URL, kind: Kind = .process) {
        let job = Job(dir: dir.standardizedFileURL, kind: kind)
        lock.lock()
        if pending.contains(job) || running == job { lock.unlock(); return }
        let wasIdle = running == nil && pending.isEmpty
        pending.append(job)
        let gen = generation
        idle.enter()
        lock.unlock()
        if wasIdle { onBusyChange(true) }
        onChange()
        worker.async { [self] in runNext(generation: gen) }
    }

    /// Ждёт, пока очередь опустеет (для тестов и выхода).
    public func waitUntilIdle(timeout: TimeInterval) -> Bool {
        idle.wait(timeout: .now() + timeout) == .success
    }

    /// Снимает ожидающие задания и прерывает текущее (при выходе из программы:
    /// необработанные папки подхватятся при следующем запуске).
    public func cancelAll() {
        lock.lock()
        generation += 1
        let proc = current
        lock.unlock()
        if let proc, proc.isRunning { proc.terminate() }
    }

    // MARK: - внутреннее

    private func runNext(generation gen: Int) {
        lock.lock()
        guard !pending.isEmpty else { lock.unlock(); return }
        let job = pending.removeFirst()
        let cancelled = gen != generation
        if !cancelled {
            // progress.json убитого процесса убираем до того, как задание станет видно как идущее:
            // иначе окно покажет старый этап, а потом откатится к первому
            try? FileManager.default.removeItem(at: job.dir.appendingPathComponent("progress.json"))
            running = job
        }
        lock.unlock()
        onChange()

        if !cancelled {
            let outcome = execute(job)
            lock.lock()
            let stillValid = gen == generation
            running = nil
            current = nil
            lock.unlock()
            onChange()
            if stillValid { onFinish(job, outcome) }
        }

        lock.lock()
        let nowIdle = running == nil && pending.isEmpty
        lock.unlock()
        if nowIdle { onBusyChange(false) }
        idle.leave()
    }

    private func execute(_ job: Job) -> Outcome {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-m", "transcriber", job.kind.rawValue, job.dir.path]
        proc.currentDirectoryURL = projectDir
        var env = ProcessInfo.processInfo.environment
        let basePath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPath + [basePath]).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe

        // Ошибку из error.txt прошлой попытки не путаем с новой.
        let errorFile = job.dir.appendingPathComponent("error.txt")
        let errorBefore = (try? FileManager.default.attributesOfItem(atPath: errorFile.path))?[.modificationDate] as? Date

        do {
            lock.lock(); current = proc; lock.unlock()
            try proc.run()
        } catch {
            return .failure("Не удалось запустить обработку (\(pythonPath)): \(error.localizedDescription)")
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let stderr = String(decoding: errData, as: UTF8.self)
        appendLog(job: job, status: proc.terminationStatus, stderr: stderr)

        if proc.terminationStatus == 0 && proc.terminationReason == .exit { return .success }
        if proc.terminationStatus == Self.exitSummaryFailed && proc.terminationReason == .exit {
            return .summaryFailed(lastLine(stderr) ?? "summary не получено")
        }

        let errorAfter = (try? FileManager.default.attributesOfItem(atPath: errorFile.path))?[.modificationDate] as? Date
        if errorAfter != nil, errorAfter != errorBefore || errorBefore == nil,
           let text = try? String(contentsOf: errorFile, encoding: .utf8),
           let first = text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return .failure(first)
        }
        if let line = lastLine(stderr) { return .failure(line) }
        if proc.terminationReason == .uncaughtSignal { return .failure("Обработка прервана (сигнал \(proc.terminationStatus))") }
        return .failure("Обработка завершилась с кодом \(proc.terminationStatus)")
    }

    private func lastLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    private func appendLog(job: Job, status: Int32, stderr: String) {
        guard let logURL else { return }
        let header = "=== \(Date()) \(job.kind.rawValue) \(job.dir.path) → код \(status)\n"
        let data = Data((header + stderr + "\n").utf8)
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
