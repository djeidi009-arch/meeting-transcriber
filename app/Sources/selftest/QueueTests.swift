import Foundation
import DetectorCore

/// Фейковый «python»: пишет в лог, работает 0.3 с, падает на папках со словом bad.
func makeFakePython(in root: URL, log: URL) throws -> URL {
    let script = root.appendingPathComponent("fake-python")
    let body = """
    #!/bin/sh
    # $1=-m $2=transcriber $3=process|resummarize $4=dir
    echo "start $3 $(basename "$4") cwd=$(pwd) path=$PATH" >> "\(log.path)"
    [ -f "$4/progress.json" ] && echo "stale-progress $(basename "$4")" >> "\(log.path)"
    sleep 0.3
    case "$4" in
      *sumfail*) echo "загрузка модели" >&2; echo "Summary не удалось сделать: истёк таймаут" >&2; exit 2;;
      *bad2*) printf "Summary не удалось: таймаут\\nподробности\\n" > "$4/error.txt"; echo "трейсбек" >&2; exit 1;;
      *bad*) echo "прогресс 50%" >&2; echo "Не удалось расшифровать: нет ffmpeg" >&2; echo "end $3 $(basename "$4")" >> "\(log.path)"; exit 1;;
    esac
    echo "end $3 $(basename "$4")" >> "\(log.path)"
    exit 0
    """
    try body.data(using: .utf8)!.write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

enum QueueTests {
    static func all() {
        test("очередь: по одной, cwd — проект, PATH с папкой claude, ошибка с текстом") {
            let root = tempDir("queue")
            let project = root.appendingPathComponent("project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let log = root.appendingPathComponent("log.txt")
            let python = try makeFakePython(in: root, log: log)
            let lock = NSLock()
            var results: [(String, ProcessingQueue.Kind, ProcessingQueue.Outcome)] = []
            var busyChanges: [Bool] = []
            let queue = ProcessingQueue(pythonPath: python.path, projectDir: project,
                                        extraPath: ["/opt/claude-bin"],
                                        onBusyChange: { b in lock.lock(); busyChanges.append(b); lock.unlock() },
                                        onFinish: { job, outcome in
                                            lock.lock(); results.append((job.dir.lastPathComponent, job.kind, outcome)); lock.unlock()
                                        })
            let a = root.appendingPathComponent("A"), bad = root.appendingPathComponent("bad"), c = root.appendingPathComponent("C")
            queue.enqueue(a)
            queue.enqueue(bad)
            queue.enqueue(a) // дубликат, пока A в очереди
            queue.enqueue(c, kind: .resummarize)
            check(queue.isBusy, "занята сразу после постановки")
            check(queue.waitUntilIdle(timeout: 10), "очередь отработала")
            check(!queue.isBusy, "свободна")

            let lines = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            let order = lines.map { $0.split(separator: " ").prefix(3).joined(separator: " ") }
            check(order == ["start process A", "end process A", "start process bad", "end process bad",
                            "start resummarize C", "end resummarize C"], "строго по одной: \(order)")
            check(lines.first?.contains("cwd=\(project.path)") == true || lines.first?.contains("cwd=/private\(project.path)") == true, "cwd — проект: \(lines.first ?? "")")
            check(lines.first?.contains("path=/opt/claude-bin:") == true, "PATH начинается с папки claude: \(lines.first ?? "")")
            check(results.count == 3, "три результата: \(results.count)")
            if results.count == 3 {
                if case .success = results[0].2 {} else { check(false, "A — успех") }
                if case .failure(let msg) = results[1].2 {
                    check(msg == "Не удалось расшифровать: нет ффмпег".replacingOccurrences(of: "ффмпег", with: "ffmpeg"), "текст ошибки — последняя строка stderr: \(msg)")
                } else { check(false, "bad — ошибка") }
                check(results[2].1 == .resummarize, "вид задания сохраняется")
            }
            check(busyChanges.first == true && busyChanges.last == false, "оповещения о занятости: \(busyChanges)")
        }

        test("очередь: снимок показывает идущее и ждущие, onChange — при постановке, старте и завершении") {
            let root = tempDir("queue-snapshot")
            let python = try makeFakePython(in: root, log: root.appendingPathComponent("log.txt"))
            let lock = NSLock()
            var seen: [ProcessingQueue.Snapshot] = []
            var queue: ProcessingQueue!
            queue = ProcessingQueue(pythonPath: python.path, projectDir: root,
                                    onChange: { let s = queue.snapshot(); lock.lock(); seen.append(s); lock.unlock() },
                                    onFinish: { _, _ in })
            check(queue.snapshot() == ProcessingQueue.Snapshot(running: nil, pending: []), "пустая очередь — пустой снимок")
            let a = ProcessingQueue.Job(dir: root.appendingPathComponent("A").standardizedFileURL, kind: .process)
            let b = ProcessingQueue.Job(dir: root.appendingPathComponent("B").standardizedFileURL, kind: .resummarize)
            queue.enqueue(a.dir)
            queue.enqueue(b.dir, kind: .resummarize)
            check(queue.waitUntilIdle(timeout: 10), "очередь отработала")
            lock.lock(); let states = seen; lock.unlock()
            typealias S = ProcessingQueue.Snapshot
            check(states.contains(S(running: nil, pending: [a])) || states.contains(S(running: nil, pending: [a, b])),
                  "постановка видна как ждущее задание: \(states)")
            check(states.contains(S(running: a, pending: [b])), "A идёт, B ждёт: \(states)")
            check(states.contains(S(running: b, pending: [])), "B идёт, очередь пуста: \(states)")
            check(states.last == S(running: nil, pending: []), "после завершения снимок пуст: \(String(describing: states.last))")
            check(states.count >= 6, "onChange на каждое изменение (2 постановки, 2 старта, 2 завершения): \(states.count)")
            check(queue.snapshot() == S(running: nil, pending: []), "в конце очередь пуста")
        }

        test("очередь: progress.json от убитого процесса не доживает до старта нового задания") {
            let root = tempDir("queue-stale")
            let log = root.appendingPathComponent("log.txt")
            let python = try makeFakePython(in: root, log: log)
            let store = MeetingStore(outputDir: root.appendingPathComponent("transcripts"))
            let dir = try store.createMeeting(app: "Zoom", bundleID: "", manual: true, startedAt: localDate(2026, 11, 10, 10, 0))
            store.finishMeeting(dir, endedAt: localDate(2026, 11, 10, 10, 30))
            touch(dir.appendingPathComponent("progress.json"), #"{"stage": "summary", "fraction": null}"#)
            let library = MeetingLibrary(store: store)
            let lock = NSLock()
            var seen: [MeetingStatus] = []
            var queue: ProcessingQueue!
            queue = ProcessingQueue(pythonPath: python.path, projectDir: root,
                                    onChange: {
                                        guard let status = library.items(queue: queue.snapshot()).first?.status else { return }
                                        lock.lock(); seen.append(status); lock.unlock()
                                    },
                                    onFinish: { _, _ in })
            queue.enqueue(dir)
            check(queue.waitUntilIdle(timeout: 10), "очередь отработала")
            lock.lock(); let statuses = seen; lock.unlock()
            check(statuses.contains(.processing(nil)), "на старте этап неизвестен: \(statuses)")
            check(!statuses.contains(.processing(ProgressInfo(stage: .summary, fraction: nil))), "старый этап «Summary» не показан: \(statuses)")
            let lines = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            check(lines.contains("start process") && !lines.contains("stale-progress"), "обработка стартует без чужого progress.json: \(lines)")
        }

        test("очередь: error.txt важнее stderr, нет python — понятная ошибка") {
            let root = tempDir("queue2")
            let log = root.appendingPathComponent("log.txt")
            let python = try makeFakePython(in: root, log: log)
            let bad = root.appendingPathComponent("bad2")
            try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
            // старый error.txt от прошлой попытки не должен попасть в уведомление
            try "старая ошибка".data(using: .utf8)!.write(to: bad.appendingPathComponent("error.txt"))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: bad.appendingPathComponent("error.txt").path)
            var outcome: ProcessingQueue.Outcome?
            let q = ProcessingQueue(pythonPath: python.path, projectDir: root, onFinish: { _, o in outcome = o })
            q.enqueue(bad)
            _ = q.waitUntilIdle(timeout: 10)
            if case .failure(let msg) = outcome { check(msg == "Summary не удалось: таймаут", "из error.txt: \(msg)") } else { check(false, "ошибка ожидалась") }

            let sumfail = root.appendingPathComponent("sumfail")
            try FileManager.default.createDirectory(at: sumfail, withIntermediateDirectories: true)
            var outcome3: ProcessingQueue.Outcome?
            let q3 = ProcessingQueue(pythonPath: python.path, projectDir: root, onFinish: { _, o in outcome3 = o })
            q3.enqueue(sumfail)
            _ = q3.waitUntilIdle(timeout: 10)
            if case .summaryFailed(let msg) = outcome3 {
                check(msg == "Summary не удалось сделать: истёк таймаут", "причина из stderr: \(msg)")
            } else { check(false, "код 2 → summaryFailed, а не \(String(describing: outcome3))") }

            var outcome2: ProcessingQueue.Outcome?
            let q2 = ProcessingQueue(pythonPath: "/nonexistent/python", projectDir: root, onFinish: { _, o in outcome2 = o })
            q2.enqueue(root.appendingPathComponent("X"))
            _ = q2.waitUntilIdle(timeout: 10)
            if case .failure(let msg) = outcome2 { check(msg.contains("/nonexistent/python"), "ошибка называет путь: \(msg)") } else { check(false, "ошибка ожидалась") }
        }

        test("очередь: сбой без error.txt виден как «Ошибка» до новой постановки, отмена следа не оставляет") {
            let root = tempDir("queue-failure")
            let python = try makeFakePython(in: root, log: root.appendingPathComponent("log.txt"))
            let store = MeetingStore(outputDir: root.appendingPathComponent("transcripts"))
            let library = MeetingLibrary(store: store)
            let idle = ProcessingQueue.Snapshot(running: nil, pending: [])
            let bad = makeMeeting(store.outputDir, "1 bad", app: "Zoom", started: localDate(2026, 11, 10, 10, 0))
            let lost = makeMeeting(store.outputDir, "2 lost", app: "Zoom", started: localDate(2026, 11, 10, 11, 0))
            func status(_ dir: URL, _ snapshot: ProcessingQueue.Snapshot) -> MeetingStatus? {
                library.items(queue: snapshot).first { $0.id == dir.lastPathComponent }?.status
            }

            // python упал, error.txt не написал
            let queue = ProcessingQueue(pythonPath: python.path, projectDir: root, onFinish: { _, _ in })
            queue.enqueue(bad)
            check(queue.waitUntilIdle(timeout: 10), "очередь отработала")
            check(status(bad, idle) == .failed("Не удалось расшифровать: нет ffmpeg"), "текст из Outcome: \(String(describing: status(bad, idle)))")
            queue.enqueue(bad)
            check(status(bad, queue.snapshot()) != status(bad, idle), "повторная постановка снимает «Ошибку»: \(String(describing: status(bad, queue.snapshot())))")
            check(queue.waitUntilIdle(timeout: 10), "повтор отработал")

            // python не запустился вовсе
            let broken = ProcessingQueue(pythonPath: "/nonexistent/python", projectDir: root, onFinish: { _, _ in })
            broken.enqueue(lost)
            check(broken.waitUntilIdle(timeout: 10), "очередь отработала")
            if case .failed(let text)? = status(lost, idle) { check(text.contains("/nonexistent/python"), "ошибка называет путь: \(text)") }
            else { check(false, "нет python → «Ошибка», а не \(String(describing: status(lost, idle)))") }

            // выход из программы посреди обработки: встреча не ошибка, обработается при следующем запуске
            let quit = makeMeeting(store.outputDir, "3 quit", app: "Zoom", started: localDate(2026, 11, 10, 12, 0))
            queue.enqueue(quit)
            Thread.sleep(forTimeInterval: 0.1)
            queue.cancelAll()
            check(queue.waitUntilIdle(timeout: 10), "отмена завершила очередь")
            check(status(quit, idle) == .queued, "прерванная выходом — не ошибка: \(String(describing: status(quit, idle)))")
        }
    }
}
