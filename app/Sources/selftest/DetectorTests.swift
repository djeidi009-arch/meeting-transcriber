import Foundation
import DetectorCore

enum DetectorTests {
    static func all() {
        test("Zoom держит мик 5 с → start") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 10, mic: ["us.zoom.xos"], isRecording: &rec)
            check(ev.count == 1, "одно событие, а не \(ev.count)")
            check(ev.first?.1 == .start(appName: "Zoom", bundleID: "us.zoom.xos"), "start Zoom: \(String(describing: ev.first?.1))")
            check(ev.first.map { $0.0 >= 5 && $0.0 <= 6 } ?? false, "старт на 5–6 с, а не \(String(describing: ev.first?.0))")
        }

        test("мик меньше 5 с → нет start") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 4, mic: ["us.zoom.xos"], isRecording: &rec)
            check(ev.isEmpty, "старта нет")
            let ev2 = run(d, from: 6, to: 8, mic: [], isRecording: &rec)
            check(ev2.isEmpty, "пропал мик — счёт сбрасывается")
            let ev3 = run(d, from: 10, to: 14, mic: ["us.zoom.xos"], isRecording: &rec)
            check(ev3.isEmpty, "после перерыва снова меньше 5 с")
        }

        test("хелпер Chrome совпадает по префиксу") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 6, mic: ["com.google.Chrome.helper"], isRecording: &rec)
            check(ev.first?.1 == .start(appName: "Chrome", bundleID: "com.google.Chrome"), "start Chrome: \(String(describing: ev.first?.1))")
        }

        test("браузер с окном Meet → имя Google Meet") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 6, mic: ["com.google.Chrome.helper"],
                         windows: [("com.google.Chrome", "Meet – abc-defg-hij")], isRecording: &rec)
            check(ev.first?.1 == .start(appName: "Google Meet", bundleID: "com.google.Chrome"), "имя Google Meet: \(String(describing: ev.first?.1))")
        }

        test("Wispr Flow держит мик → нет start") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 60, mic: ["com.electron.wispr-flow"], isRecording: &rec)
            check(ev.isEmpty, "неизвестное приложение не запускает запись")
        }

        test("окно Zoom Meeting держит встречу при выключенном мике, стоп через 90 с без признаков") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            _ = run(d, from: 0, to: 6, mic: ["us.zoom.xos"], isRecording: &rec)
            check(rec, "запись идёт")
            let held = run(d, from: 8, to: 300, mic: [], windows: [("us.zoom.xos", "Zoom Meeting")], isRecording: &rec)
            check(held.isEmpty && rec, "окно встречи держит запись")
            let gone = run(d, from: 302, to: 500, mic: [], isRecording: &rec)
            check(gone.count == 1 && gone.first?.1 == .stop, "один stop: \(gone)")
            if let t = gone.first?.0 {
                check(t >= 300 + 90 && t <= 302 + 90, "stop через ~90 с после последнего признака, а не на \(t)")
            }
        }

        test("окно «Meet –» в браузере держит встречу") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            _ = run(d, from: 0, to: 6, mic: ["com.google.Chrome.helper"], isRecording: &rec)
            let held = run(d, from: 8, to: 200, mic: [], windows: [("com.google.Chrome", "Meet – xyz")], isRecording: &rec)
            check(held.isEmpty && rec, "окно Meet держит запись")
        }

        test("окно с шаблоном у чужого приложения не держит встречу") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            _ = run(d, from: 0, to: 6, mic: ["us.zoom.xos"], isRecording: &rec)
            let ev = run(d, from: 8, to: 200, mic: [], windows: [("com.apple.Notes", "Zoom Meeting заметки")], isRecording: &rec)
            check(ev.first?.1 == .stop, "stop, хотя есть окно чужого приложения")
        }

        test("ручная остановка: нет повторного старта до исчезновения признаков") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            _ = run(d, from: 0, to: 6, mic: ["us.zoom.xos"], isRecording: &rec)
            d.noteManualStop()
            rec = false
            let again = run(d, from: 8, to: 100, mic: ["us.zoom.xos"], isRecording: &rec)
            check(again.isEmpty, "нет старта, пока Zoom держит мик: \(again)")
            _ = run(d, from: 102, to: 104, mic: [], isRecording: &rec)
            let next = run(d, from: 106, to: 120, mic: ["us.zoom.xos"], isRecording: &rec)
            check(next.first?.1 == .start(appName: "Zoom", bundleID: "us.zoom.xos"), "новая встреча стартует")
        }

        test("автостарт выключен → нет start") {
            let d = MeetingDetector(config: .builtIn)
            var rec = false
            let ev = run(d, from: 0, to: 60, mic: ["us.zoom.xos"], autoRecord: false, isRecording: &rec)
            check(ev.isEmpty, "нет start при autoRecord=false")
        }

        test("ручная запись без распознанной встречи не останавливается сама") {
            let d = MeetingDetector(config: .builtIn)
            var rec = true
            let ev = run(d, from: 0, to: 400, mic: [], isRecording: &rec)
            check(ev.isEmpty && rec, "нет stop")
        }

        test("ручная запись распознанной встречи останавливается по признакам") {
            let d = MeetingDetector(config: .builtIn)
            var rec = true
            _ = run(d, from: 0, to: 20, mic: ["us.zoom.xos"], autoRecord: false, isRecording: &rec)
            let ev = run(d, from: 22, to: 200, mic: [], autoRecord: false, isRecording: &rec)
            check(ev.first?.1 == .stop, "stop после ухода из Zoom: \(ev)")
        }

        test("extraBundleIDs и extraTitlePatterns работают") {
            let config = DetectorConfig.builtIn(extraBundleIDs: ["com.example.Call"],
                                                extraTitlePatterns: ["Созвон с"],
                                                nameFor: { $0 == "com.example.Call" ? "Звонилка" : nil })
            let d = MeetingDetector(config: config)
            var rec = false
            let ev = run(d, from: 0, to: 6, mic: ["com.example.Call"], isRecording: &rec)
            check(ev.first?.1 == .start(appName: "Звонилка", bundleID: "com.example.Call"), "доп. приложение стартует: \(ev)")
            let held = run(d, from: 8, to: 200, mic: [], windows: [("com.example.Call", "Созвон с Петей")], isRecording: &rec)
            check(held.isEmpty && rec, "доп. шаблон окна держит встречу")
            let noName = DetectorConfig.builtIn(extraBundleIDs: ["org.jitsi.jitsi-meet"], extraTitlePatterns: [])
            let d2 = MeetingDetector(config: noName)
            var rec2 = false
            let ev2 = run(d2, from: 0, to: 6, mic: ["org.jitsi.jitsi-meet"], isRecording: &rec2)
            check(ev2.first?.1 == .start(appName: "jitsi-meet", bundleID: "org.jitsi.jitsi-meet"), "имя по умолчанию: \(ev2)")
        }
    }
}
