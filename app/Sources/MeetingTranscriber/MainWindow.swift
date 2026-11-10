import AppKit
import SwiftUI

/// Главное окно: оболочка AppKit, содержимое SwiftUI. Закрытие окна программу не завершает.
@MainActor
final class MainWindow {
    let window: NSWindow

    init(model: AppModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Транскрибатор"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 640)
        let host = NSHostingView(rootView: RootView().environment(model))
        host.sceneBridgingOptions = [.toolbars, .title] // тулбар SwiftUI становится системным тулбаром окна
        window.contentView = host
        window.center()
        window.setFrameAutosaveName("MainWindow")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Главное меню: у обычного приложения без него не работают ⌘Q, ⌘W и ⌘C/⌘V в поле поиска.
@MainActor
enum MainMenu {
    static func build(target: StatusMenu) -> NSMenu {
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            root.submenu = NSMenu(title: title)
            items.forEach { root.submenu?.addItem($0) }
            return root
        }
        func item(_ title: String, _ action: Selector, _ key: String = "", to target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = target
            return i
        }
        let main = NSMenu()
        main.addItem(menu("Транскрибатор", [
            item("Скрыть Транскрибатор", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Завершить Транскрибатор", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(menu("Файл", [
            item("Загрузить аудио или видео…", #selector(StatusMenu.importClicked), "o", to: target),
            item("Закрыть окно", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        main.addItem(menu("Правка", [
            item("Отменить", Selector(("undo:")), "z"),
            item("Повторить", Selector(("redo:")), "Z"),
            .separator(),
            item("Вырезать", #selector(NSText.cut(_:)), "x"),
            item("Скопировать", #selector(NSText.copy(_:)), "c"),
            item("Вставить", #selector(NSText.paste(_:)), "v"),
            item("Выбрать всё", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = menu("Окно", [
            item("Свернуть", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Транскрибатор", #selector(StatusMenu.showWindow), "0", to: target),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }
}
