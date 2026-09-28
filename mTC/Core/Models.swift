import Foundation

/// `mTC-data/settings.json`: то, что пользователь настраивает.
struct AppSettings: Codable {
    var version = 1
    var showInDock = true
    var showHiddenFiles = false
    /// Показывать окно при обычном запуске (при автозапуске mTC всегда стартует свёрнутым в строку меню).
    var showWindowAtLaunch = true
    var showWindowHotKey = HotKeySpec.showWindowDefault
    /// Спрашивать подтверждение перед перемещением в Корзину (удаление насовсем спрашивается всегда).
    var confirmMoveToTrash = true
}

/// `mTC-data/state.json`: то, что приложение запоминает само.
struct AppState: Codable {
    var version = 1
    var windowFrame: WindowFrame?
    var splitRatio = 0.5
    var activePanel = PanelSide.left
    var leftTabs = SavedPanel()
    var rightTabs = SavedPanel()
    /// Устаревшие поля (до вкладок): используются, только если `leftTabs`/`rightTabs` пусты.
    var leftPath: String?
    var rightPath: String?
    /// Путь к `.app`, для которого включена автозагрузка. Нужен, чтобы заметить перенос папки.
    var loginItemAppPath: String?
    /// Последняя маска в диалоге «Выделить по маске».
    var lastSelectionMask = "*"
    var maskIncludesDirectories = false
}

/// Вкладки одной панели в `state.json`.
struct SavedPanel: Codable, Equatable {
    var tabs: [SavedTab] = []
    var activeTab = 0
}

struct SavedTab: Codable, Equatable {
    var path: String
    var sortKey: String?
    var sortAscending: Bool?
}

enum PanelSide: String, Codable {
    case left, right

    var opposite: PanelSide { self == .left ? .right : .left }
}

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
