# mTC

Клон Total Commander для macOS на Swift + AppKit, для пользователя и его команды. Общаемся на русском, UI приложения тоже на русском.

**Статус и следующий шаг: [docs/ROADMAP.md](docs/ROADMAP.md).** Прочитай его в начале сессии и обновляй после каждого завершённого шага.

## Жёсткие ограничения
- **Portable:** приложение не устанавливается (в организации это запрещено), запускается из любой папки и распространяется zip-архивом.
- **Никакой платной подписи, нотаризации и App Store.** Только ad-hoc (`CODE_SIGN_IDENTITY = "-"`). Про карантин и `xattr` написано в README.
- **Только arm64** (у всех M1+), macOS 14+.
- **Всё пишем в `mTC-data/` рядом с `.app`.** В `~/Library` ничего не пишем: никаких `UserDefaults` для своих данных, autosave окон и state restoration.
- **Без внешних зависимостей**, только системные фреймворки и библиотеки (архивы — системная libarchive через свои объявления в `mTC/Support/libarchive.h`).

## Как работаем
- Шаги делаем по одному. После каждого пересобираем, перезапускаем пробную копию, пользователь проверяет руками и даёт замечания.
- **Git:** ветка `master`, репозиторий локальный. После того как пользователь проверил и подтвердил шаг — коммит этого шага (сообщение на русском, по смыслу). До подтверждения не коммитим.
- Сборка для проверки ошибок:
  `xcodebuild -project mTC.xcodeproj -scheme mTC -configuration Debug -destination "generic/platform=macOS" -derivedDataPath build/DerivedData build 2>&1 | grep -E "error:|warning:|BUILD"`
- Пересобрать и перезапустить пробную копию (её `mTC-data` сохраняется):
  ```bash
  osascript -e 'tell application id "dev.mtc.mTC" to quit'
  scripts/dist.sh
  ditto --norsrc --noextattr build/stage/mTC/mTC.app build/try/mTC/mTC.app.new && rm -rf build/try/mTC/mTC.app && mv build/try/mTC/mTC.app.new build/try/mTC/mTC.app
  open build/try/mTC/mTC.app
  ```
- `build/stage/` каждый раз стирается скриптом, поэтому не запускай оттуда.
- Новые `.swift` файлы в `mTC/` подхватываются проектом сами (synchronized group), править `project.pbxproj` не нужно.
- Горячие клавиши: новая команда = случай в `PanelCommand` + строка в `CommandCatalog` ([mTC/Core/Hotkeys.swift](mTC/Core/Hotkeys.swift)) с сочетаниями по умолчанию; пункты меню создавай через `MainMenu.item(_:_:)`, подсказки — через `Hotkeys.shared.hint(for:)`. Не хардкодь клавиши в `keyDown` и в названиях. Клавиши без ⌘ нельзя ставить пунктам меню (меню перехватит их в полях ввода) — `KeyCombo.menuKeyEquivalent` это учитывает.
- В диалогах (`NSAlert`) кнопку отмены добавляй через `alert.addCancelButton()` ([TextPrompt.swift](mTC/UI/TextPrompt.swift)): так она закрывается по Esc. Обычный `addButton(withTitle: "Отмена")` Esc не ловит.
- README.md служит инструкцией для коллег (он кладётся в zip). Таблицу клавиш в нём держим актуальной.

## Структура
- `mTC/App`: `main.swift`, `AppDelegate` (жизненный цикл, строка меню, автозагрузка, диалоги проблем с папкой данных), `MainMenu`.
- `mTC/Core`: `DataLocation`, `JSONStore` (слияние с умолчаниями, атомарная отложенная запись), `Models` (`AppSettings` → `settings.json`, `AppState` → `state.json`), `KeyCombo`, `Hotkeys` (+ `CommandCatalog`, → `hotkeys.json`), `InstanceLock`.
- `mTC/System`: `StatusBarController`, `GlobalHotKey` (Carbon), `LoginItem`, `FloppyIcon`.
- `mTC/FileSystem`: `FileItem`, `DirectoryLister`, `DirectorySize` (+ `CancellationFlag`), `FileMask`, `IconProvider`, `DirectoryWatcher` (FSEvents), `Volumes`, `FileOperations` (создание папок, `uniqueURL`, разбор пути копирования, удаление), `CopyOperation` (фоновое копирование и перемещение), `ArchiveExtractor` (`ArchiveFormats`, `ArchiveExtractOperation`), `ArchiveCreator` (`ArchiveKind`, `ArchiveCreateOperation`).
- `mTC/UI`: `MainWindowController` (+`+Copy`, `+Edit`, `+Archive`: две стороны в `NSSplitView`, панель F-клавиш, диалоги маски/удаления/копирования), `PanelSideViewController` + `TabBarView` (вкладки), `FilePanelViewController` (курсор, отметки, размеры папок, контекстное меню), `DriveBar`, `PanelTableView` + `PanelCellView`, `PanelCommand` (команды и клавиши), `FunctionKeyBar`, `TextPrompt` (+ `addCancelButton`), `OperationProgressWindowController`, `ActionMenuItem`, `HotkeysWindowController`, `ArchiveDialog`.
