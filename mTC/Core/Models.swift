import Foundation

/// `mTC-data/settings.json`: то, что пользователь настраивает.
struct AppSettings: Codable {
    var version = 1
    var showInDock = true
    var showHiddenFiles = false
    /// Показывать окно при обычном запуске (при автозапуске mTC всегда стартует свёрнутым в строку меню).
    var showWindowAtLaunch = true
    /// Спрашивать подтверждение перед перемещением в Корзину (удаление насовсем спрашивается всегда).
    var confirmMoveToTrash = true
    /// Редактор для F4: пусто — системный редактор текста; иначе имя программы, путь к .app или bundle id.
    var editor = ""
    /// Раскраска файлов по маскам (`FileColorRule`): первое совпавшее правило. Пустой список — без цвета.
    var fileColors = FileColorRule.defaults
    /// Тема оформления: как в системе, светлая или тёмная.
    var theme = AppTheme.system
}

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
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
    /// Последний выбор в диалоге «Упаковать…».
    var lastArchiveKind = ArchiveKind.zip
    var archiveToOtherPanel = false
    var lastZipEncryption = ZipEncryption.zipCrypto
    /// Последние условия в окне поиска.
    var lastSearch = SearchQuery()
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
