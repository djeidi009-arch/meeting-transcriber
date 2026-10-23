import AppKit
import DetectorCore

/// Значок в строке меню и вся логика приложения: опрос, автостарт/стоп, запись, очередь.
@MainActor
final class StatusMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let autoRecordKey = "autoRecord"

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let notifier = Notifier()
    private let probe = SystemProbe()
    private let recorder = Recorder()

    private var config: AppConfig!
    private var store: MeetingStore!
    private var queue: ProcessingQueue!
    private var detector: MeetingDetector!

    private var recordingDir: URL?
    private var recordingApp = ""
    private var recordingStart: Date?
    private var transitioning = false       // идёт старт или остановка записи
    private var terminating = false         // идёт выход: новых записей не начинать
    private var processing = false
    private var probing = false
    private var permissionProblem: String?  // текст ошибки доступа, пока он не выдан
    private var lastSnapshot: Snapshot?
    private var timers: [Timer] = []

    private var autoRecord: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoRecordKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoRecordKey) }
    }

    // MARK: - запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.autoRecordKey: false])

        let projectDir = AppPaths.projectDir()
        config = AppConfig.load(projectDir: projectDir)
        store = MeetingStore(outputDir: config.outputDir)
        detector = MeetingDetector(config: DetectorConfig.builtIn(
            extraBundleIDs: config.extraBundleIDs,
            extraTitlePatterns: config.extraTitlePatterns,
            nameFor: AppPaths.appName(forBundleID:)))

        var extraPath = ["/opt/homebrew/bin", "/usr/local/bin"]
        if config.claudePath.hasPrefix("/") {
            extraPath.insert((config.claudePath as NSString).deletingLastPathComponent, at: 0)
        }
        queue = ProcessingQueue(
            pythonPath: config.pythonPath, projectDir: projectDir, extraPath: extraPath,
            logURL: AppPaths.logDir.appendingPathComponent("processing.log"),
            onBusyChange: { busy in Task { @MainActor in self.processing = busy; self.refreshTitle() } },
            onFinish: { job, outcome in Task { @MainActor in self.processingFinished(job, outcome) } })

        recorder.onUnexpectedStop = { error in
            Task { @MainActor in self.recordingFailed(error) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        refreshTitle()

        notifier.setup()
        Task {
            await Permissions.requestIfNeeded()
            self.checkPermissions(notifyIfMissing: true)
        }

        // Встречи, оставшиеся после выхода или сбоя посреди записи.
        for dir in store.recoverPending() { queue.enqueue(dir) }

        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.refreshTitle() }
        })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        timers.forEach { $0.invalidate() }
        queue.cancelAll()
        guard recordingDir != nil || transitioning else { return .terminateNow }
        // Корректно закрыть файлы и дописать endedAt; в обработку встреча уйдёт при следующем запуске.
        // Если как раз идёт старт или остановка — сначала дождаться её конца.
        Task {
            while self.transitioning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if self.recordingDir != nil {
                await self.stopRecording(manual: true, enqueue: false)
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - опрос и детектор

    private func poll() {
        guard !probing else { return }
        probing = true
        Task {
            let snapshot = await probe.snapshot()
            self.probing = false
            self.lastSnapshot = snapshot
            guard !self.transitioning, !self.terminating else { return }
            let event = self.detector.update(snapshot, autoRecord: self.autoRecord,
                                             isRecording: self.recordingDir != nil)
            switch event {
            case .start(let app, let bundleID)?:
                await self.startRecording(app: app, bundleID: bundleID, manual: false)
            case .stop?:
                await self.stopRecording(manual: false)
            case nil:
                break
            }
        }
    }

    // MARK: - запись

    private func startRecording(app: String, bundleID: String, manual: Bool) async {
        guard recordingDir == nil, !transitioning, !terminating else { return }
        transitioning = true
        defer { transitioning = false; refreshTitle() }
        let dir: URL
        do {
            dir = try store.createMeeting(app: app, bundleID: bundleID, manual: manual)
        } catch {
            notifier.notify(title: "Запись не началась", body: "Не удалось создать папку встречи: \(error.localizedDescription)")
            if !manual { detector.noteManualStop() }
            return
        }
        do {
            try await recorder.start(dir: dir)
            recordingDir = dir
            recordingApp = app
            recordingStart = Date()
            permissionProblem = nil
        } catch {
            try? FileManager.default.removeItem(at: dir) // пустая папка: только meta.json
            // Не пытаться снова каждые 2 с, пока эта встреча идёт.
            if !manual { detector.noteManualStop() }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if (error as? RecorderError)?.isPermission == true { permissionProblem = message }
            notifier.notify(title: "Запись не началась", body: message)
        }
    }

    private func stopRecording(manual: Bool, enqueue: Bool = true) async {
        guard let dir = recordingDir, !transitioning else { return }
        transitioning = true
        defer { transitioning = false; refreshTitle() }
        if manual { detector.noteManualStop() }
        await recorder.stop()
        recordingDir = nil
        recordingStart = nil
        if store.finishMeeting(dir), enqueue {
            queue.enqueue(dir)
        }
    }

    private func recordingFailed(_ error: Error) {
        guard let dir = recordingDir else { return }
        recordingDir = nil
        recordingStart = nil
        detector.noteManualStop()
        // Recorder сообщает о сбое уже после закрытия файлов. При выходе — обработка при следующем запуске.
        if store.finishMeeting(dir), !terminating { queue.enqueue(dir) }
        checkPermissions(notifyIfMissing: false)
        notifier.notify(title: "Запись прервалась", body: error.localizedDescription)
        refreshTitle()
    }

    // MARK: - обработка

    private func processingFinished(_ job: ProcessingQueue.Job, _ outcome: ProcessingQueue.Outcome) {
        let name = job.dir.lastPathComponent
        let md = job.dir.appendingPathComponent("meeting.md")
        switch (outcome, job.kind) {
        case (.success, .process):
            notifier.notify(title: "Встреча расшифрована", body: name, open: md)
        case (.success, .resummarize):
            notifier.notify(title: "Summary обновлено", body: name, open: md)
        case (.summaryFailed(let reason), _):
            notifier.notify(title: "Встреча расшифрована, но summary не получилось — Меню → Повторить summary",
                            body: "\(name). \(reason)", open: md)
        case (.failure(let message), _):
            notifier.notify(title: "Ошибка обработки: \(name)", body: message)
        }
        refreshTitle()
    }

    // MARK: - разрешения

    private func checkPermissions(notifyIfMissing: Bool) {
        var missing: [String] = []
        if !Permissions.microphoneGranted { missing.append("микрофону") }
        if !Permissions.screenGranted { missing.append("записи экрана и системного аудио (нужна для звука собеседников)") }
        if missing.isEmpty {
            permissionProblem = nil
        } else {
            let text = "Нет доступа к " + missing.joined(separator: " и ") + ". Без него встречи не записываются."
            permissionProblem = text
            if notifyIfMissing { notifier.notify(title: "MeetingTranscriber: нужен доступ", body: text) }
        }
    }

    // MARK: - меню

    private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        if let start = recordingStart {
            let s = Int(Date().timeIntervalSince(start))
            let time = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                                 : String(format: "%02d:%02d", s / 60, s % 60)
            button.title = "🔴 \(time)"
        } else if processing {
            button.title = "⏳"
        } else {
            button.title = "🎙"
        }
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuildMenu() }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if Permissions.microphoneGranted && Permissions.screenGranted { permissionProblem = nil }

        if recordingDir != nil {
            menu.addItem(disabled("Идёт запись: \(recordingApp)"))
            menu.addItem(item("Остановить запись", #selector(stopClicked)))
        } else {
            if processing { menu.addItem(disabled("Идёт обработка…")) }
            menu.addItem(item("Начать запись", #selector(startClicked)))
        }
        let auto = item("Записывать автоматически", #selector(toggleAuto))
        auto.state = autoRecord ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Последние встречи", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let recent = store.recentMeetings(limit: 5)
        if recent.isEmpty {
            sub.addItem(disabled("Пока нет"))
        } else {
            for dir in recent {
                let i = item(dir.lastPathComponent, #selector(openMeeting(_:)))
                i.representedObject = dir
                sub.addItem(i)
            }
        }
        recentItem.submenu = sub
        menu.addItem(recentItem)

        let resummary = item("Повторить summary (последняя встреча)", #selector(resummarize))
        resummary.isEnabled = store.lastMeetingWithTranscript() != nil
        menu.addItem(resummary)
        menu.addItem(item("Открыть папку транскриптов", #selector(openOutput)))

        if let problem = permissionProblem {
            menu.addItem(.separator())
            let p = item("Нет доступа: открыть настройки", #selector(openSettings))
            p.toolTip = problem
            menu.addItem(p)
        }
        menu.addItem(.separator())
        menu.addItem(item("Выход", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func startClicked() {
        // Если созвон из списка уже держит микрофон — назвать папку по нему.
        let known = lastSnapshot?.micBundleIDs.lazy.compactMap { self.detector.config.match($0) }.first
        Task { await startRecording(app: known?.name ?? "Встреча", bundleID: known?.prefix ?? "", manual: true) }
    }

    @objc private func stopClicked() {
        Task { await stopRecording(manual: true) }
    }

    @objc private func toggleAuto() {
        autoRecord.toggle()
    }

    @objc private func openMeeting(_ sender: NSMenuItem) {
        guard let dir = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(dir.appendingPathComponent("meeting.md"))
    }

    @objc private func resummarize() {
        guard let dir = store.lastMeetingWithTranscript() else { return }
        queue.enqueue(dir, kind: .resummarize)
    }

    @objc private func openOutput() {
        try? FileManager.default.createDirectory(at: config.outputDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(config.outputDir)
    }

    @objc private func openSettings() {
        let pane = Permissions.screenGranted ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
