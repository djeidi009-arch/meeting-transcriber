import Foundation

/// `~/.config/meeting-transcriber/config.json`. Нет файла или ключа — значение по умолчанию.
public struct AppConfig {
    public var outputDir: URL
    public var language: String
    public var claudePath: String
    public var pythonPath: String
    public var summaryTimeoutSec: Int
    public var extraBundleIDs: [String]
    public var extraTitlePatterns: [String]

    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/meeting-transcriber/config.json")
    }

    public static func defaults(projectDir: URL) -> AppConfig {
        AppConfig(outputDir: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("transcripts"),
                  language: "ru",
                  claudePath: "claude",
                  pythonPath: projectDir.appendingPathComponent(".venv/bin/python").path,
                  summaryTimeoutSec: 300,
                  extraBundleIDs: [],
                  extraTitlePatterns: [])
    }

    public static func load(from url: URL = defaultURL, projectDir: URL) -> AppConfig {
        var cfg = defaults(projectDir: projectDir)
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return cfg }
        if let s = json["outputDir"] as? String, !s.isEmpty {
            cfg.outputDir = URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        if let s = json["language"] as? String, !s.isEmpty { cfg.language = s }
        if let s = json["claudePath"] as? String, !s.isEmpty { cfg.claudePath = (s as NSString).expandingTildeInPath }
        if let s = json["pythonPath"] as? String, !s.isEmpty { cfg.pythonPath = (s as NSString).expandingTildeInPath }
        if let n = json["summaryTimeoutSec"] as? Int { cfg.summaryTimeoutSec = n }
        if let a = json["extraBundleIDs"] as? [String] { cfg.extraBundleIDs = a }
        if let a = json["extraTitlePatterns"] as? [String] { cfg.extraTitlePatterns = a }
        return cfg
    }
}
