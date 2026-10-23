import AppKit
import UserNotifications

/// Уведомления: UNUserNotificationCenter в собранном .app, иначе (или без разрешения) — osascript.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var authorized = false
    private let canUseCenter = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil

    func setup() {
        guard canUseCenter else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    /// - Parameter open: файл, который откроется по клику на уведомление.
    func notify(title: String, body: String, open: URL? = nil) {
        if canUseCenter && authorized {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let open { content.userInfo = ["open": open.path] }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if error != nil { self.osascript(title: title, body: body) }
            }
        } else {
            osascript(title: title, body: body)
        }
    }

    private func osascript(title: String, body: String) {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
        try? p.run()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["open"] as? String {
            DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
        completionHandler()
    }
}
