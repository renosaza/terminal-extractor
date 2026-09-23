---
type: development-guide
status: draft
---
# Разработка и выпуск: текущее состояние

В репозитории есть документация, feasibility probes и начальная product SwiftPM foundation: отдельные CLI host и MCP gateway с локальными настройками и read-only `terminal_capabilities`; session tools, grants и GUI отсутствуют. Installer, release binary и CI отсутствуют. `probes/mcp/Package.swift` собирает отдельный тестовый MCP stdio server. Предлагаемый стек — [архитектура](../architecture/README.md), текущее состояние — [TE-E02](../work/epics/TE-E02.md).

## Начало реализации

Прочитать AGENTS.md, [ограничения](../constraints.md), PRD и свою карточку. Первый шаг — capability probes на отдельном безопасном macOS стенде. Записать версии, права, exact API и результат до выбора minimum supported versions. Feasibility результаты затем обновляют ADR-002, capabilities и карточки.

Для повторения TE-T004 на macOS с tmux 3.7c и Swift 6.4: `sh probes/tmux/probe.sh`, `swift build --package-path probes/mcp -c release`, `python3 probes/mcp/check.py`. Swift SDK закреплён в probe `Package.resolved`; `.build` локальный и игнорируется Git. Другие probes: `python3 probes/dictionaries.py`, `python3 probes/zsh/probe.py`. Эти команды проверяют только записанные fixture-сценарии.

Для foundation TE-T005/006: `swift build`, `swift run TermexConfigCheck`, затем `python3 Tests/integration/check.py`. Product `Package.resolved` закрепляет зависимости отдельно от probe. Host использует private `~/Library/Application Support/TerminalExtractor/Run/host.sock`; опция `--socket` предназначена для отдельного приватного каталога при проверке, `--config` — для локального абсолютного JSON path. `terminal_capabilities` сообщает выбор с `terminal_access=false`; подключение не даёт доступа к терминалу.

Для локальной проверки Ghostty discovery: `swift build`, `.build/debug/termex-host --list-ghostty`, `python3 Tests/integration/ghostty_discovery.py`. Список содержит IDs и названия **всех** открытых Ghostty surfaces и предназначен для локального пользователя; MCP/IPC его не возвращают. `.build/debug/termex-host --resolve-ghostty <app-instance-id> <window-id> <tab-id> <surface-id>` перепроверяет выбранную строку и отклоняет закрытую цель. Эти команды не выдают grant и не подключают session.

Для отдельной GUI-проверки ввода: `python3 probes/ghostty/keys_probe.py`. Требуются уже запущенный Ghostty, локально собранный `termex-host` и разрешённый macOS Automation. Probe создаёт и закрывает собственное окно, направляет события по ID только в нём, печатает hex введённых байтов и результат действий split; пользовательское содержимое других окон не читает. Это исследовательская проверка, а не MCP/IPC input.

Аналогично для Terminal.app: `.build/debug/termex-host --list-terminal`, `python3 Tests/integration/terminal_discovery.py`, `.build/debug/termex-host --resolve-terminal <app-instance-id> <window-id> <tty>`. Если Terminal.app не запущен, список пуст и приложение не запускается. TTY может переиспользоваться: `resolve` — локальная диагностика, не право на read/input и не устойчивый session binding.

Будущие области кода: session-registry, adapters/terminal-app, adapters/ghostty, adapters/tmux, shell-integration, journal, compression и host-ui. Это план модулей, не существующее продуктовое дерево.

## Документация

Карточки задач — канонический tracker. В каждой есть scope, dependencies, критерии и проверка. Перед done записать observed result, команды реально выполненных проверок и commit. Не ставить PASS из чтения чужого README. Новый runtime API должен обновить contract/schema fixtures/acceptance в той же ветке.

## Release boundaries

Подпись/notarization, app identity, helper permissions, автоматическая установка и удаление — задачи TE-T045..048, не выполненные настройки. Не придумывать Team ID, bundle signature, Homebrew formula или version pins. Нельзя менять user rc, терминальные профили и global AGENTS без отдельного согласия.

## Диагностика

Первое расследование: version/capability report, binding/generation, grants/lease, capture coverage, shell integration evidence. Только после локального согласия извлекать содержимое выбранного тестового журнала. Диагностика по умолчанию metadata-only. Отсутствующий API означает unsupported/not_tested, а не необходимость обходить TCC или нажимать клавиши в активное окно.
