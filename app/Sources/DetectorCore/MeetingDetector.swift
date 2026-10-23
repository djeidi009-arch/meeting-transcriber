import Foundation

/// Снимок состояния системы: кто держит микрофон и какие окна открыты.
public struct Snapshot {
    public var micBundleIDs: [String]
    public var windows: [(bundleID: String, title: String)]
    public var time: TimeInterval

    public init(micBundleIDs: [String], windows: [(bundleID: String, title: String)] = [], time: TimeInterval) {
        self.micBundleIDs = micBundleIDs
        self.windows = windows
        self.time = time
    }
}

public struct DetectorConfig {
    /// Префикс bundle ID → имя приложения для папки встречи.
    public var appBundlePrefixes: [String: String]
    /// Подстроки заголовков окон встречи (без учёта регистра).
    public var titlePatterns: [String]
    /// Шаблон заголовка → более точное имя для папки (например, «Meet –» в Chrome → «Google Meet»).
    public var titleAppNames: [String: String]
    public var startAfter: TimeInterval
    public var stopAfter: TimeInterval
    /// Сколько подряд не должно быть признаков встречи, чтобы снялся запрет автостарта после ручной остановки.
    public var resumeAfter: TimeInterval
    /// Префиксы приложений, которым одного микрофона для автостарта мало: браузеры и мессенджеры
    /// (голосовые, голосовой ввод, диктовка). Старт — только если у того же приложения открыто окно созвона.
    public var windowRequired: Set<String>

    public init(appBundlePrefixes: [String: String],
                titlePatterns: [String],
                titleAppNames: [String: String] = [:],
                startAfter: TimeInterval = 5,
                stopAfter: TimeInterval = 90,
                resumeAfter: TimeInterval = 30,
                windowRequired: Set<String> = []) {
        self.resumeAfter = resumeAfter
        self.windowRequired = windowRequired
        self.appBundlePrefixes = appBundlePrefixes
        self.titlePatterns = titlePatterns
        self.titleAppNames = titleAppNames
        self.startAfter = startAfter
        self.stopAfter = stopAfter
    }

    public static let builtIn = DetectorConfig(
        appBundlePrefixes: [
            "us.zoom.xos": "Zoom",
            "com.microsoft.teams": "Teams",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.hnc.Discord": "Discord",
            "ru.keepcoder.Telegram": "Telegram",
            "org.telegram.desktop": "Telegram",
            "com.apple.FaceTime": "FaceTime",
            "Cisco-Systems.Spark": "Webex",
            "com.webex.meetingmanager": "Webex",
            "com.cisco.webexmeetingsapp": "Webex",
            "com.skype.skype": "Skype",
            "ru.yandex.telemost": "Телемост",
            "ru.yandex.desktop.telemost": "Телемост",
            "kontur.talk": "Толк", // /Applications/Толк.app; хелперы kontur.talk.* совпадают по префиксу
            "ru.kontur.talk": "Толк",
            "ru.skbkontur.talk": "Толк",
            // Браузеры: хелперы (com.google.Chrome.helper и т.п.) совпадают по префиксу.
            "com.google.Chrome": "Chrome",
            "com.apple.Safari": "Safari",
            "com.apple.WebKit.GPU": "Safari",
            "company.thebrowser.Browser": "Arc",
            "ru.yandex.desktop.yandex-browser": "Яндекс.Браузер",
            "org.mozilla.firefox": "Firefox",
            "com.microsoft.edgemac": "Edge",
        ],
        titlePatterns: ["Zoom Meeting", "Meet –", "Meet - ", "Телемост", "Толк", "Microsoft Teams"],
        titleAppNames: [
            "Zoom Meeting": "Zoom",
            "Microsoft Teams": "Teams",
            "Meet –": "Google Meet",
            "Meet - ": "Google Meet",
            "Телемост": "Телемост",
            "Толк": "Толк",
        ],
        windowRequired: [
            "ru.keepcoder.Telegram", "org.telegram.desktop", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
            "com.google.Chrome", "com.apple.Safari", "com.apple.WebKit.GPU", "company.thebrowser.Browser",
            "ru.yandex.desktop.yandex-browser", "org.mozilla.firefox", "com.microsoft.edgemac",
        ]
    )

    /// Встроенный список, дополненный значениями из config.json.
    /// `nameFor` подбирает человеческое имя для дополнительного bundle ID (по умолчанию — последний компонент).
    public static func builtIn(extraBundleIDs: [String],
                               extraTitlePatterns: [String],
                               nameFor: (String) -> String? = { _ in nil }) -> DetectorConfig {
        var config = DetectorConfig.builtIn
        for id in extraBundleIDs where !id.isEmpty {
            config.appBundlePrefixes[id] = nameFor(id) ?? id.split(separator: ".").last.map(String.init) ?? id
        }
        for pattern in extraTitlePatterns where !pattern.isEmpty && !config.titlePatterns.contains(pattern) {
            config.titlePatterns.append(pattern)
        }
        return config
    }

    /// Самый длинный подходящий префикс → (канонический bundle ID, имя); nil — приложение не из списка.
    public func match(_ bundleID: String) -> (prefix: String, name: String)? {
        var best: (prefix: String, name: String)?
        for (prefix, name) in appBundlePrefixes where bundleID.hasPrefix(prefix) {
            if best == nil || prefix.count > best!.prefix.count { best = (prefix, name) }
        }
        return best
    }

    func matchingPattern(_ title: String) -> String? {
        titlePatterns.first { title.range(of: $0, options: .caseInsensitive) != nil }
    }
}

public enum DetectorEvent: Equatable {
    case start(appName: String, bundleID: String)
    case stop
}

/// Политика автостарта/автостопа. Без системных вызовов: всё приходит в `Snapshot`.
public final class MeetingDetector {
    public let config: DetectorConfig

    private var micSince: TimeInterval?
    private var lastEvidence: TimeInterval?
    private var meetingActive = false
    private var suppressed = false
    private var quietSince: TimeInterval?   // начало текущего отрезка без признаков

    public init(config: DetectorConfig) {
        self.config = config
    }

    public func update(_ s: Snapshot, autoRecord: Bool, isRecording: Bool) -> DetectorEvent? {
        let micApps = s.micBundleIDs.compactMap { config.match($0) }
        let meetingWindows = s.windows.compactMap { w -> (prefix: String, name: String, pattern: String)? in
            guard let app = config.match(w.bundleID), let p = config.matchingPattern(w.title) else { return nil }
            return (app.prefix, app.name, p)
        }
        // Окно созвона того же приложения; сравнение по имени — у Safari мик держит com.apple.WebKit.GPU.
        func window(for app: (prefix: String, name: String)) -> (prefix: String, name: String, pattern: String)? {
            meetingWindows.first { $0.prefix == app.prefix || $0.name == app.name }
        }
        // Кандидат на автостарт: приложение созвонов, а браузер/мессенджер — только с окном созвона.
        let micApp = micApps.first { !config.windowRequired.contains($0.prefix) || window(for: $0) != nil }
        let evidence = !micApps.isEmpty || !meetingWindows.isEmpty

        if micApp != nil {
            if micSince == nil { micSince = s.time }
        } else {
            micSince = nil
        }
        if evidence {
            lastEvidence = s.time
            quietSince = nil
        } else if quietSince == nil {
            quietSince = s.time
        }

        // После ручной остановки молчим, пока признаков нет ≥ resumeAfter подряд
        // (один пустой опрос — частый сбой CoreAudio — запрет не снимает).
        if suppressed {
            guard let quiet = quietSince, s.time - quiet >= config.resumeAfter else { return nil }
            suppressed = false
            meetingActive = false
        }

        if isRecording {
            if evidence { meetingActive = true }
            if meetingActive, !evidence, let last = lastEvidence, s.time - last >= config.stopAfter {
                meetingActive = false
                micSince = nil
                return .stop
            }
            return nil
        }

        meetingActive = false
        guard autoRecord, let app = micApp, let since = micSince, s.time - since >= config.startAfter else {
            return nil
        }
        var name = app.name
        // Более точное имя по окну встречи того же приложения (Chrome + «Meet –» → Google Meet).
        if let w = window(for: app), let better = config.titleAppNames[w.pattern] {
            name = better
        }
        meetingActive = true
        lastEvidence = s.time
        return .start(appName: name, bundleID: app.prefix)
    }

    /// Пользователь остановил запись сам (или старт не удался): не стартовать снова,
    /// пока признаков встречи нет хотя бы `resumeAfter` секунд подряд.
    public func noteManualStop() {
        suppressed = true
        quietSince = nil
        meetingActive = false
        micSince = nil
    }
}
