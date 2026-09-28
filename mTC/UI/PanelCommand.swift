import Foundation

/// Команды, которым назначаются горячие клавиши (см. `CommandCatalog` и `Hotkeys`).
/// Имя случая — ключ в `mTC-data/hotkeys.json`, поэтому переименовывать случаи нельзя.
enum PanelCommand: String {
    case open
    case goUp
    case switchPanel
    /// Выделить/снять файл под курсором и перейти ниже (Space, Insert).
    case toggleMark
    /// Инвертировать выделение файла под курсором и перейти выше/ниже (⇧↑ / ⇧↓), как в Total Commander.
    case invertMovingUp
    case invertMovingDown
    case markByMask
    case unmarkByMask
    case invertMarks
    case markAll
    case unmarkAll
    /// Если выделено всё — снять выделение, иначе выделить всё (⌘A).
    case toggleMarkAll
    case nextTab
    case previousTab
    /// Файловые операции.
    case goBack
    case goForward
    case goHome
    case goToVolumeRoot
    case goToOppositeDirectory
    case editPath
    case openInNewTab
    case quickLook
    case edit
    case newFile
    /// Esc: закрыть просмотр, если открыт.
    case closePreview
    case makeDirectory
    case copyToOtherPanel
    case moveToOtherPanel
    case rename
    case moveToTrash
    case deletePermanently
    /// Команды окна — панель передаёт их окну.
    case refresh
    case toggleHiddenFiles
    case newTab
    case closeTab
    /// Глобальная клавиша: регистрируется в системе, в панели не обрабатывается.
    case showHideWindow
}
