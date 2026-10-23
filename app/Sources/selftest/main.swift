import Foundation
import DetectorCore

// Тесты без XCTest: на Command Line Tools его нет.
setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        passed += 1
    } else {
        failures += 1
        print("FAIL \(line): \(message)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch {
        failures += 1
        print("FAIL \(name): исключение \(error)")
    }
    print(failures == before ? "ok   \(name)" : "FAIL \(name)")
}

/// Прогоняет снимки раз в 2 с и возвращает все события с моментом времени.
func run(_ detector: MeetingDetector,
         from: TimeInterval, to: TimeInterval, step: TimeInterval = 2,
         mic: [String], windows: [(bundleID: String, title: String)] = [],
         autoRecord: Bool = true, isRecording: inout Bool) -> [(TimeInterval, DetectorEvent)] {
    var events: [(TimeInterval, DetectorEvent)] = []
    var t = from
    while t <= to {
        if let e = detector.update(Snapshot(micBundleIDs: mic, windows: windows, time: t),
                                   autoRecord: autoRecord, isRecording: isRecording) {
            events.append((t, e))
            switch e {
            case .start: isRecording = true
            case .stop: isRecording = false
            }
        }
        t += step
    }
    return events
}

DetectorTests.all()
StoreTests.all()
ConfigTests.all()
QueueTests.all()

print("\(passed) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
