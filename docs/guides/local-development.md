---
type: development-guide
status: draft
---
# Разработка и выпуск: текущее состояние

В репозитории есть документация, feasibility probes и начальная product SwiftPM foundation: CLI host, MCP gateway, AppKit helper выбора Ghostty, локальные настройки и `terminal_capabilities`/`terminal_request_access`/`terminal_screen`. Последний — opt-in ограниченный снимок одной выбранной surface через clipboard; по умолчанию config закрывает этот путь. Живой MCP-тест подтвердил чтение трёх surface и восстановление доступных clipboard types/bytes в одном вызове; конкурентные случаи остаются открытыми. Input и полноценный GUI host отсутствуют. Installer, release binary и CI отсутствуют. `probes/mcp/Package.swift` собирает отдельный тестовый MCP stdio server. Предлагаемый стек — [архитектура](../architecture/README.md), текущее состояние — [TE-E02](../work/epics/TE-E02.md).

## Начало реализации

Прочитать AGENTS.md, [ограничения](../constraints.md), PRD и свою карточку. Первый шаг — capability probes на отдельном безопасном macOS стенде. Записать версии, права, exact API и результат до выбора minimum supported versions. Feasibility результаты затем обновляют ADR-002, capabilities и карточки.

Для повторения TE-T004 на macOS с tmux 3.7c и Swift 6.4: `sh probes/tmux/probe.sh`, `swift build --package-path probes/mcp -c release`, `python3 probes/mcp/check.py`. Swift SDK закреплён в probe `Package.resolved`; `.build` локальный и игнорируется Git. Другие probes: `python3 probes/dictionaries.py`, `python3 probes/zsh/probe.py`. Эти команды проверяют только записанные fixture-сценарии.

Для foundation TE-T005/006: `swift build`, `swift run TermexConfigCheck`, затем `python3 Tests/integration/check.py`. Для export file validation: `swift run TermexExportFileCheck`; для IPC frame >255 байт: `swift run TermexIPCCheck`. Product `Package.resolved` закрепляет зависимости отдельно от probe. Host использует private `~/Library/Application Support/TerminalExtractor/Run/host.sock`; опция `--socket` предназначена для отдельного приватного каталога при проверке, `--config` — для локального абсолютного JSON path. `terminal_request_access` вызывает AppKit выбор Ghostty. Для отдельного screen read нужны `native_ghostty_clipboard_export=true` в private config и локальная отметка clipboard export в dialog; одного read scope недостаточно. `termex-host --stop` отзывает grants через private socket; для отдельного host используйте `termex-host --stop --socket <private-path>`. Stop не завершает host или терминал.

Для локальной проверки Ghostty discovery: `swift build`, `.build/debug/termex-host --list-ghostty`, `python3 Tests/integration/ghostty_discovery.py`. Список содержит IDs и названия **всех** открытых Ghostty surfaces и предназначен для локального пользователя; MCP/IPC его не возвращают. `.build/debug/termex-host --resolve-ghostty <app-instance-id> <window-id> <tab-id> <surface-id>` перепроверяет выбранную строку и отклоняет закрытую цель. Эти команды не выдают grant и не подключают session.

Для отдельной GUI-проверки ввода: `python3 probes/ghostty/keys_probe.py`. Требуются уже запущенный Ghostty, локально собранный `termex-host` и разрешённый macOS Automation. Probe создаёт и закрывает собственное окно, направляет события по ID только в нём, печатает hex введённых байтов и результаты действий split/tab; пользовательское содержимое других окон не читает. Это исследовательская проверка, а не MCP/IPC input.

`swift run TermexRegistryCheck` проверяет in-memory модель выбора Ghostty на синтетических ID: одноразовый handle, инвалидирование и смену session ID. Он не запрашивает macOS Automation и не выдаёт согласие. При реальном `terminal_request_access` AppKit helper показывает окна/вкладки/splits, требует явного выбора, возвращает выбранный handle, read scope и отдельную отметку clipboard export; host повторно разрешает точные IDs. Результат хранится до закрытия IPC connection. Без config opt-in и отдельной отметки экран закрыт; input остаётся закрыт.

Аналогично для Terminal.app: `.build/debug/termex-host --list-terminal`, `python3 Tests/integration/terminal_discovery.py`, `.build/debug/termex-host --resolve-terminal <app-instance-id> <window-id> <tty>`. Если Terminal.app не запущен, список пуст и приложение не запускается. TTY может переиспользоваться: `resolve` — локальная диагностика, не право на read/input и не устойчивый session binding.

Будущие области кода: session-registry, adapters/terminal-app, adapters/ghostty, adapters/tmux, shell-integration, journal, compression и host-ui. Это план модулей, не существующее продуктовое дерево.

## Документация

Карточки задач — канонический tracker. В каждой есть scope, dependencies, критерии и проверка. Перед done записать observed result, команды реально выполненных проверок и commit. Не ставить PASS из чтения чужого README. Новый runtime API должен обновить contract/schema fixtures/acceptance в той же ветке.

## Release boundaries

Подпись/notarization, app identity, helper permissions, автоматическая установка и удаление — задачи TE-T045..048, не выполненные настройки. Не придумывать Team ID, bundle signature, Homebrew formula или version pins. Нельзя менять user rc, терминальные профили и global AGENTS без отдельного согласия.

## Диагностика

Первое расследование: version/capability report, binding/generation, grants/lease, capture coverage, shell integration evidence. Только после локального согласия извлекать содержимое выбранного тестового журнала. Диагностика по умолчанию metadata-only. Отсутствующий API означает unsupported/not_tested, а не необходимость обходить TCC или нажимать клавиши в активное окно.
