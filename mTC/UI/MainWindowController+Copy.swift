import AppKit

// MARK: - Копирование (F5) и перемещение (F6)

extension MainWindowController {
    func filePanel(_ panel: FilePanelViewController, requestsCopyOf targets: [FileItem]) {
        requestTransfer(targets, mode: .copy, from: panel)
    }

    func filePanel(_ panel: FilePanelViewController, requestsMoveOf targets: [FileItem]) {
        requestTransfer(targets, mode: .move, from: panel)
    }

    private func requestTransfer(_ targets: [FileItem], mode: CopyOperation.Mode, from panel: FilePanelViewController) {
        guard let window, window.attachedSheet == nil, !targets.isEmpty else { return }
        let destinationDirectory = oppositePanel(of: panel).directory
        let defaultPath = destinationDirectory.path == "/" ? "/" : destinationDirectory.path + "/"
        let verb = mode == .copy ? "Копировать" : "Переместить"

        TextPrompt.present(
            on: window,
            title: targets.count == 1 ? "\(verb) «\(targets[0].name)»" : "\(verb) \(targets.count) объектов",
            message: targets.count == 1
                ? "Куда. Можно указать новое имя: …/папка/новое имя"
                : "В папку (если её нет — она будет создана):",
            defaultValue: defaultPath,
            okTitle: verb
        ) { [weak self] input in
            guard let self, let input,
                  let destination = FileOperations.copyDestination(for: input, sourceCount: targets.count, relativeTo: panel.directory) else {
                panel.focus()
                return
            }
            self.startTransfer(targets.map(\.url), to: destination, mode: mode, focusing: panel)
        }
    }

    /// Перетаскивание: сразу копируем/перемещаем в `directory`, без диалога «Куда».
    func filePanel(_ panel: FilePanelViewController, requestsDropOf urls: [URL], into directory: URL, move: Bool) {
        guard !urls.isEmpty else { return }
        startTransfer(urls, to: .into(directory), mode: move ? .move : .copy, focusing: panel)
    }

    /// Запускает копирование/перемещение с окном прогресса. После — обновляет панели и снимает выделение
    /// со скопированного в той панели, где лежат исходники.
    private func startTransfer(_ sources: [URL], to destination: CopyOperation.Destination, mode: CopyOperation.Mode, focusing panel: FilePanelViewController) {
        let sourceDirectory = sources[0].deletingLastPathComponent().resolvingSymlinksInPath().path
        let operation = CopyOperation(sources: sources, destination: destination, mode: mode)

        let destinationName: String
        switch destination {
        case .into(let url): destinationName = url.path
        case .renamed(let url): destinationName = url.path
        }
        let what = sources.count == 1 ? "«\(sources[0].lastPathComponent)»" : "\(sources.count) объектов"
        let progressWindow = OperationProgressWindowController(
            title: mode == .copy ? "Копирование" : "Перемещение",
            subtitle: "\(what) → \(destinationName)"
        )
        progressWindow.onCancel = { operation.cancel() }

        var finished = false
        // Короткие операции проходят без мелькания окна.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if !finished { progressWindow.show(over: self?.window) }
        }

        operation.onProgress = { progressWindow.update($0) }
        operation.resolveConflict = { [weak self] conflict, reply in
            progressWindow.show(over: self?.window)
            guard let sheetWindow = progressWindow.window else {
                reply(.cancel, false)
                return
            }
            Self.askConflict(conflict, mode: mode, on: sheetWindow, reply: reply)
        }
        operation.onFinish = { [weak self] result in
            finished = true
            progressWindow.close()
            guard let self else { return }
            self.refreshPanels(nil)
            let completed = Set(result.completedSources.map(\.lastPathComponent))
            for sourcePanel in [panel, self.oppositePanel(of: panel)] where sourcePanel.directory.resolvingSymlinksInPath().path == sourceDirectory {
                sourcePanel.unmark(completed)
            }
            panel.focus()
            self.reportFailures(result.failures, verb: mode == .copy ? "скопировать" : "переместить")
        }
        operation.start()
    }

    private static func askConflict(
        _ conflict: CopyOperation.Conflict,
        mode: CopyOperation.Mode,
        on window: NSWindow,
        reply: @escaping (CopyOperation.ConflictChoice, Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "«\(conflict.destination.lastPathComponent)» уже есть в «\(conflict.destination.deletingLastPathComponent().lastPathComponent)»"

        let existing = describe(conflict.destination)
        let incoming = describe(conflict.source)
        var existingNote = "", incomingNote = ""
        if let existingDate = existing.date, let incomingDate = incoming.date, existingDate != incomingDate {
            if existingDate > incomingDate { existingNote = " — новее" } else { incomingNote = " — новее" }
        }
        let incomingTitle = mode == .copy ? "Копируемый" : "Перемещаемый"
        alert.informativeText = "Существующий: \(existing.text)\(existingNote)\n\(incomingTitle): \(incoming.text)\(incomingNote)"

        alert.addButton(withTitle: "Заменить")
        alert.addButton(withTitle: "Пропустить")
        alert.addButton(withTitle: "Оставить оба")
        alert.addCancelButton(title: mode == .copy ? "Остановить копирование" : "Остановить перемещение")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Применить ко всем"

        alert.beginSheetModal(for: window) { response in
            let applyToAll = alert.suppressionButton?.state == .on
            switch response {
            case .alertFirstButtonReturn: reply(.replace, applyToAll)
            case .alertSecondButtonReturn: reply(.skip, applyToAll)
            case .alertThirdButtonReturn: reply(.keepBoth, applyToAll)
            default: reply(.cancel, false)
            }
        }
    }

    private static func describe(_ url: URL) -> (text: String, date: Date?) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let date = values?.contentModificationDate
        let dateText = date.map(formatter.string(from:)) ?? "—"
        if values?.isDirectory == true {
            return ("папка, \(dateText)", date)
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return ("\(size), \(dateText)", date)
    }
}
