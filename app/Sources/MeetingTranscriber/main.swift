import AppKit
import DetectorCore

enum AppPaths {
    static var logDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/MeetingTranscriber")
    }

    /// Папка проекта (cwd для Python): из Info.plist (пишет scripts/build_app.sh),
    /// иначе — вверх от исполняемого файла до каталога с `app/Package.swift` (запуск через `swift run`).
    static func projectDir() -> URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "MTProjectDir") as? String, !s.isEmpty {
            return URL(fileURLWithPath: s)
        }
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("app/Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func appName(forBundleID id: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// `--probe`: один снимок (процессы с активным вводом и окна встреч) в stdout.
/// `--probe --watch`: снимок раз в 2 с с событиями детектора, до Ctrl+C.
func runProbe(watch: Bool) -> Never {
    let probe = SystemProbe()
    let config = AppConfig.load(projectDir: AppPaths.projectDir())
    let detectorConfig = DetectorConfig.builtIn(extraBundleIDs: config.extraBundleIDs,
                                                extraTitlePatterns: config.extraTitlePatterns,
                                                nameFor: AppPaths.appName(forBundleID:))
    let detector = MeetingDetector(config: detectorConfig)
    var recording = false
    setvbuf(stdout, nil, _IOLBF, 0)

    Task {
        repeat {
            let procs = probe.micProcesses()
            let snapshot = await probe.snapshot()
            print("--- \(Date())")
            print("микрофон держат (\(procs.count)):")
            for p in procs {
                let known = detectorConfig.match(p.bundleID).map { " → \($0.name)" } ?? ""
                print("  pid=\(p.pid) bundle=\(p.bundleID.isEmpty ? "—" : p.bundleID) name=\(p.name)\(known)")
            }
            let meetingWindows = snapshot.windows.filter { w in
                detectorConfig.match(w.bundleID) != nil
                    && detectorConfig.titlePatterns.contains { w.title.range(of: $0, options: .caseInsensitive) != nil }
            }
            print("окон всего: \(snapshot.windows.count)\(Permissions.screenGranted ? "" : " (нет доступа к записи экрана — заголовков не видно)")")
            for w in meetingWindows { print("  окно встречи: [\(w.bundleID)] \(w.title)") }
            if let e = detector.update(snapshot, autoRecord: true, isRecording: recording) {
                print("событие детектора: \(e)")
                if case .start = e { recording = true } else { recording = false }
            }
            if watch { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        } while watch
        exit(0)
    }
    dispatchMain()
}

let args = CommandLine.arguments
if args.contains("--probe") {
    runProbe(watch: args.contains("--watch"))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = StatusMenu()
    app.delegate = delegate
    app.setActivationPolicy(.regular) // обычное приложение: значок в Dock и окно
    app.run()
}
