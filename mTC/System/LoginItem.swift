import ServiceManagement

/// Автозагрузка через `SMAppService.mainApp`: системный «Объект входа», который видно
/// и можно отключить в «Системные настройки → Основные → Объекты входа».
/// Регистрация привязана к пути до `.app`, поэтому после переноса папки её нужно обновить.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
