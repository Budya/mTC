import AppKit

// MARK: - Редактирование (F4) и новый файл (⇧F4)

extension MainWindowController {
    func filePanel(_ panel: FilePanelViewController, requestsEditOf targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        let setting = settings.value.editor
        guard let editor = FileOperations.editorApplication(setting) else {
            showEditorProblem(
                "Редактор «\(setting)» не найден",
                "Проверьте ключ editor в settings.json: имя программы, путь к .app или bundle id. Пусто — системный редактор текста."
            )
            return
        }

        // Папки — только если редактор задан явно (например, VS Code открывает папку как проект).
        let urls = targets.filter { $0.kind != .directory || !setting.isEmpty }.map(\.url)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        openInEditor(urls, editor: editor)
    }

    func filePanelRequestsNewFile(_ panel: FilePanelViewController) {
        guard let window else { return }
        let suggested = FileOperations.uniqueURL(for: panel.directory.appendingPathComponent("Новый файл.txt"), isDirectory: false)
        TextPrompt.present(
            on: window,
            title: "Новый файл",
            message: "В «\(panel.directory.lastPathComponent)». Если такой файл уже есть — он просто откроется.",
            defaultValue: suggested.lastPathComponent,
            okTitle: "Создать"
        ) { [weak self] name in
            guard let self, let name else {
                panel.focus()
                return
            }
            do {
                let url = try FileOperations.createFile(named: name, in: panel.directory)
                if url.deletingLastPathComponent().standardizedFileURL == panel.directory {
                    panel.select(named: url.lastPathComponent)
                } else {
                    panel.reload()
                }
                panel.focus()
                if let editor = FileOperations.editorApplication(self.settings.value.editor) {
                    self.openInEditor([url], editor: editor)
                }
            } catch {
                panel.focus()
                self.showEditorProblem("Не удалось создать файл", error.localizedDescription)
            }
        }
    }

    private func openInEditor(_ urls: [URL], editor: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.showEditorProblem("Не удалось открыть в «\(editor.deletingPathExtension().lastPathComponent)»", error.localizedDescription)
            }
        }
    }

    private func showEditorProblem(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
