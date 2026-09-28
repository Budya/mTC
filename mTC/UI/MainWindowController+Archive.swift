import AppKit

// MARK: - Архивы: распаковка (⌥F9)

extension MainWindowController {
    func filePanel(_ panel: FilePanelViewController, requestsExtractOf targets: [FileItem]) {
        let archives = targets.filter { $0.kind == .file && ArchiveFormats.isArchive($0.url) }.map(\.url)
        guard !archives.isEmpty else {
            NSSound.beep()
            return
        }

        let operation = ArchiveExtractOperation(archives: archives)
        let what = archives.count == 1 ? "«\(archives[0].lastPathComponent)»" : "\(archives.count) архивов"
        let progressWindow = OperationProgressWindowController(title: "Распаковка", subtitle: "\(what) → \(panel.directory.path)")
        progressWindow.onCancel = { operation.cancel() }

        var finished = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if !finished { progressWindow.show(over: self?.window) }
        }

        operation.onProgress = { progressWindow.update($0) }
        operation.resolveConflict = { [weak self] conflict, reply in
            progressWindow.show(over: self?.window)
            guard let sheetWindow = progressWindow.window else { return reply(.cancel, false) }
            Self.askConflict(conflict, mode: .copy, on: sheetWindow, reply: reply)
        }
        operation.askPassword = { [weak self] name, retry, reply in
            progressWindow.show(over: self?.window)
            guard let sheetWindow = progressWindow.window else { return reply(nil) }
            Self.askArchivePassword(name, retry: retry, on: sheetWindow, reply: reply)
        }
        operation.onFinish = { [weak self] result in
            finished = true
            progressWindow.close()
            guard let self else { return }
            self.refreshPanels(nil)
            if let created = result.created.last, created.deletingLastPathComponent().standardizedFileURL == panel.directory {
                panel.select(named: created.lastPathComponent)
            }
            panel.focus()
            self.reportFailures(result.failures, verb: "распаковать")
        }
        operation.start()
    }

    private static func askArchivePassword(_ name: String, retry: Bool, on window: NSWindow, reply: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = retry ? "Неверный пароль для «\(name)»" : "Архив «\(name)» защищён паролем"
        alert.informativeText = retry ? "Попробуйте ещё раз:" : "Введите пароль:"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Распаковать")
        alert.addCancelButton()
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            reply(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}

// MARK: - Архивы: упаковка (⌥F5)

extension MainWindowController {
    func filePanel(_ panel: FilePanelViewController, requestsPackOf targets: [FileItem]) {
        guard let window, window.attachedSheet == nil, !targets.isEmpty else { return }

        let baseName: String
        if targets.count == 1, let item = targets.first {
            let stem = (item.name as NSString).deletingPathExtension
            baseName = item.kind == .directory || stem.isEmpty ? item.name : stem
        } else {
            baseName = panel.directory.path == "/" ? "Архив" : panel.directory.lastPathComponent
        }
        let otherPanel = oppositePanel(of: panel)
        let dialog = ArchiveDialog(
            baseName: baseName,
            kind: state.value.lastArchiveKind,
            encryption: state.value.lastZipEncryption,
            toOtherPanel: state.value.archiveToOtherPanel,
            otherPanelPath: otherPanel.directory.path
        )

        let alert = NSAlert()
        alert.messageText = targets.count == 1 ? "Упаковать «\(targets[0].name)»" : "Упаковать \(targets.count) объектов"
        alert.accessoryView = dialog.view
        alert.addButton(withTitle: "Упаковать")
        alert.addCancelButton()
        alert.window.initialFirstResponder = dialog.nameField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else {
                panel.focus()
                return
            }
            let kind = dialog.kind
            let toOther = dialog.toOtherPanel
            let encryption = dialog.encryption
            self.state.update {
                $0.lastZipEncryption = encryption
                $0.lastArchiveKind = kind
                $0.archiveToOtherPanel = toOther
            }

            var name = dialog.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = baseName }
            if !name.lowercased().hasSuffix("." + kind.fileExtension) {
                name = ArchiveKind.stripExtension(name) + "." + kind.fileExtension
            }
            guard !name.contains("/") else {
                NSSound.beep()
                panel.focus()
                return
            }
            let directory = toOther ? otherPanel.directory : panel.directory
            let destination = directory.appendingPathComponent(name)
            let password = kind.supportsPassword ? dialog.passwordField.stringValue : nil

            self.resolveExistingArchive(destination, kind: kind) { finalURL in
                guard let finalURL else {
                    panel.focus()
                    return
                }
                self.startPacking(targets.map(\.url), into: finalURL, kind: kind, password: password, encryption: encryption, from: panel)
            }
        }
    }

    /// Архив с таким именем уже есть: «Заменить» / «Оставить оба» (с номером) / отмена.
    private func resolveExistingArchive(_ url: URL, kind: ArchiveKind, completion: @escaping (URL?) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path), let window else { return completion(url) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "«\(url.lastPathComponent)» уже существует"
        alert.informativeText = "Заменить его новым архивом или сохранить оба?"
        alert.addButton(withTitle: "Оставить оба")
        alert.addButton(withTitle: "Заменить").hasDestructiveAction = true
        alert.addCancelButton()
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                // «Проект 2.tar.gz», а не «Проект.tar 2.gz».
                let stem = ArchiveKind.stripExtension(url.lastPathComponent)
                var index = 2
                var candidate = url
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem) \(index).\(kind.fileExtension)")
                    index += 1
                }
                completion(candidate)
            case .alertSecondButtonReturn:
                completion(url)
            default:
                completion(nil)
            }
        }
    }

    private func startPacking(_ sources: [URL], into destination: URL, kind: ArchiveKind, password: String?, encryption: ZipEncryption, from panel: FilePanelViewController) {
        let operation = ArchiveCreateOperation(sources: sources, destination: destination, kind: kind, password: password, encryption: encryption)
        let progressWindow = OperationProgressWindowController(title: "Упаковка", subtitle: "→ \(destination.path)")
        progressWindow.onCancel = { operation.cancel() }

        var finished = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if !finished { progressWindow.show(over: self?.window) }
        }
        operation.onProgress = { progressWindow.update($0) }
        operation.onFinish = { [weak self] result in
            finished = true
            progressWindow.close()
            guard let self else { return }
            self.refreshPanels(nil)
            if let archive = result.archive {
                for target in [panel, self.oppositePanel(of: panel)] where target.directory == archive.deletingLastPathComponent().standardizedFileURL {
                    target.select(named: archive.lastPathComponent)
                }
            }
            panel.focus()
            self.reportFailures(result.failures, verb: "упаковать")
        }
        operation.start()
    }
}
