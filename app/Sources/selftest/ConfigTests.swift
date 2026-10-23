import Foundation
import DetectorCore

enum ConfigTests {
    static func all() {
        test("нет файла настроек → значения по умолчанию") {
            let root = tempDir("cfg")
            let project = URL(fileURLWithPath: "/tmp/proj")
            let cfg = AppConfig.load(from: root.appendingPathComponent("nope.json"), projectDir: project)
            check(cfg.outputDir.path == NSHomeDirectory() + "/transcripts", "outputDir: \(cfg.outputDir.path)")
            check(cfg.language == "ru", "language")
            check(cfg.claudePath == "claude", "claudePath")
            check(cfg.pythonPath == "/tmp/proj/.venv/bin/python", "pythonPath: \(cfg.pythonPath)")
            check(cfg.summaryTimeoutSec == 300, "summaryTimeoutSec")
            check(cfg.extraBundleIDs.isEmpty && cfg.extraTitlePatterns.isEmpty, "доп. списки пусты")
        }

        test("значения из config.json, ~ раскрывается, нет ключа — по умолчанию") {
            let root = tempDir("cfg2")
            let file = root.appendingPathComponent("config.json")
            let json = #"{"outputDir": "~/Встречи", "claudePath": "/opt/claude", "extraBundleIDs": ["com.example.Call"], "extraTitlePatterns": ["Созвон"]}"#
            try json.data(using: .utf8)!.write(to: file)
            let cfg = AppConfig.load(from: file, projectDir: URL(fileURLWithPath: "/p"))
            check(cfg.outputDir.path == NSHomeDirectory() + "/Встречи", "outputDir: \(cfg.outputDir.path)")
            check(cfg.claudePath == "/opt/claude", "claudePath")
            check(cfg.language == "ru", "language по умолчанию")
            check(cfg.extraBundleIDs == ["com.example.Call"] && cfg.extraTitlePatterns == ["Созвон"], "доп. списки")
        }

        test("битый config.json → значения по умолчанию") {
            let root = tempDir("cfg3")
            let file = root.appendingPathComponent("config.json")
            try "{не json".data(using: .utf8)!.write(to: file)
            let cfg = AppConfig.load(from: file, projectDir: URL(fileURLWithPath: "/p"))
            check(cfg.language == "ru" && cfg.claudePath == "claude", "по умолчанию")
        }
    }
}
