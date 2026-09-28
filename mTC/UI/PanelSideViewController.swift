import AppKit

/// Одна сторона окна: строка вкладок и файловая панель.
///
/// Панель одна на сторону, вкладки — это сохранённые состояния (`PanelTab`):
/// при переключении текущее состояние запоминается, а выбранное показывается в панели.
/// Строка вкладок видна, только когда вкладок больше одной.
final class PanelSideViewController: NSViewController {
    let panel: FilePanelViewController
    /// Вкладки изменились (открыли, закрыли, переключили, сменили папку) — пора сохранить.
    var onTabsChanged: (() -> Void)?

    private let tabBar = TabBarView()
    private var tabs: [PanelTab] = []
    private(set) var activeIndex = 0

    var tabCount: Int { tabs.count }

    var isActive = false {
        didSet {
            panel.isActive = isActive
            tabBar.isActivePanel = isActive
        }
    }

    init(panel: FilePanelViewController) {
        self.panel = panel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override func loadView() {
        tabBar.onSelect = { [weak self] index in self?.selectTab(at: index) }
        tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabBar.onCloseOthers = { [weak self] index in self?.closeOtherTabs(keeping: index) }
        tabBar.onNewTab = { [weak self] in self?.newTab() }

        let stack = NSStackView(views: [tabBar, panel.view])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        for subview in [tabBar, panel.view] {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        view = stack
    }

    // MARK: - Сохранение

    /// Восстанавливает вкладки из `state.json`. Пропавшие папки отбрасываются.
    func restore(_ saved: SavedPanel, legacyPath: String?) {
        _ = view
        tabs = saved.tabs.compactMap { tab in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: tab.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return PanelTab(
                directory: URL(fileURLWithPath: tab.path),
                sortKey: tab.sortKey.flatMap(SortKey.init(rawValue:)) ?? .name,
                sortAscending: tab.sortAscending ?? true
            )
        }
        if tabs.isEmpty {
            let path = legacyPath ?? FileManager.default.homeDirectoryForCurrentUser.path
            tabs = [PanelTab(directory: URL(fileURLWithPath: path))]
        }
        activeIndex = min(max(saved.activeTab, 0), tabs.count - 1)
        panel.restore(tabs[activeIndex])
        updateTabBar()
    }

    var saved: SavedPanel {
        let current = currentTabs()
        return SavedPanel(
            tabs: current.map { SavedTab(path: $0.directory.path, sortKey: $0.sortKey.rawValue, sortAscending: $0.sortAscending) },
            activeTab: activeIndex
        )
    }

    // MARK: - Действия

    /// Панель сменила папку — обновляем заголовок текущей вкладки.
    func panelDidChangeDirectory() {
        guard tabs.indices.contains(activeIndex) else { return }
        tabs[activeIndex] = panel.snapshot()
        updateTabBar()
        onTabsChanged?()
    }

    /// Новая вкладка с той же папкой (без выделения), сразу после текущей.
    func newTab() {
        storeCurrentTab()
        var tab = panel.snapshot()
        tab.marked = []
        tabs.insert(tab, at: activeIndex + 1)
        activeIndex += 1
        panel.restore(tab)
        updateTabBar()
        onTabsChanged?()
        panel.focus()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if index != activeIndex {
            storeCurrentTab()
            activeIndex = index
            panel.restore(tabs[index])
            updateTabBar()
            onTabsChanged?()
        }
        panel.focus()
    }

    func selectTab(offset: Int) {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeIndex + offset + tabs.count) % tabs.count)
    }

    /// Закрывает вкладку. Последнюю вкладку закрыть нельзя — возвращает `false`.
    @discardableResult
    func closeTab(at index: Int) -> Bool {
        guard tabs.count > 1, tabs.indices.contains(index) else { return false }
        storeCurrentTab()
        tabs.remove(at: index)
        if index == activeIndex {
            activeIndex = min(index, tabs.count - 1)
            panel.restore(tabs[activeIndex])
        } else if index < activeIndex {
            activeIndex -= 1
        }
        updateTabBar()
        onTabsChanged?()
        panel.focus()
        return true
    }

    func closeOtherTabs(keeping index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        storeCurrentTab()
        let kept = tabs[index]
        tabs = [kept]
        if index != activeIndex {
            activeIndex = 0
            panel.restore(kept)
        }
        activeIndex = 0
        updateTabBar()
        onTabsChanged?()
        panel.focus()
    }

    // MARK: - Внутреннее

    private func storeCurrentTab() {
        if tabs.indices.contains(activeIndex) {
            tabs[activeIndex] = panel.snapshot()
        }
    }

    private func currentTabs() -> [PanelTab] {
        var result = tabs
        if result.indices.contains(activeIndex) {
            result[activeIndex] = panel.snapshot()
        }
        return result
    }

    private func updateTabBar() {
        tabBar.isHidden = tabs.count <= 1
        tabBar.update(
            tabs: tabs.map { TabBarView.Tab(title: $0.title, toolTip: $0.directory.path) },
            selected: activeIndex
        )
    }
}
