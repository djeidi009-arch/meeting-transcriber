import AppKit
import DetectorCore

/// `--demo --screenshots <папка>`: снимает окно с выдуманными встречами в светлой и тёмной теме и выходит.
@MainActor
enum Screenshots {
    /// Код выхода: 0 — все снимки на месте.
    static func run(model: AppModel, window: NSWindow, into dir: URL) async -> Int32 {
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        /// Ждать условия не дольше `limit` секунд.
        func wait(limit: Double, until done: () -> Bool) async {
            var left = limit
            while !done() && left > 0 { await wait(0.1); left -= 0.1 }
        }
        func item(titled title: String) -> MeetingItem? { model.items.first { $0.title == title } }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Не удалось создать папку для снимков: \(error.localizedDescription)\n".utf8))
            return 1
        }
        window.setFrameAutosaveName("") // размер для снимков не запоминать: настройки общие с установленной копией
        window.setFrame(NSRect(x: 0, y: 0, width: 1320, height: 860), display: true)
        window.center()

        await wait(limit: 20) { model.isLoaded }
        guard let ready = model.items.first(where: { $0.status == .ready })?.id else { return 1 }
        // звук первой встречи синтезируется в фоне — без него на снимке не будет волны
        await wait(limit: 30) { model.demoAudioReady.contains(ready) }

        var failed = false
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            func shoot(_ name: String) {
                let file = dir.appendingPathComponent("\(theme)-\(name).png")
                if !capture(window, to: file) {
                    FileHandle.standardError.write(Data("Не удалось снять \(file.lastPathComponent): проверьте доступ «Запись экрана» у терминала\n".utf8))
                    failed = true
                }
            }

            model.selection = ready
            await wait(2.5)
            shoot("meeting")

            // эта встреча «расшифровывается» по кругу; снимаем на втором шаге с известной долей
            if let looping = item(titled: "Вебинар по аналитике") {
                model.selection = looping.id
                await wait(limit: 40) {
                    if case .processing(let info?) = item(titled: looping.title)?.status { info.stage == .asr && (info.fraction ?? 0) > 0.5 } else { false }
                }
                await wait(0.6)
                shoot("processing")
            }

            if let recording = model.items.first(where: { $0.status == .recording }) {
                model.selection = recording.id
                await wait(1.5)
                shoot("recording")
            }

            model.selection = ready
            model.dropTargeted = true
            await wait(1.5)
            shoot("drop")
            model.dropTargeted = false
        }
        return failed ? 1 : 0
    }

    /// Снимок окна делает система: отрисовка изнутри процесса теряет боковую панель, стекло и размытие.
    /// Нужен доступ «Запись экрана» у программы, из которой запущена команда (обычно Терминал).
    private static func capture(_ window: NSWindow, to file: URL) -> Bool {
        try? FileManager.default.removeItem(at: file) // старый снимок не должен сойти за новый
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        guard (try? shot.run()) != nil else { return false }
        shot.waitUntilExit()
        return shot.terminationStatus == 0 && FileManager.default.fileExists(atPath: file.path)
    }
}
