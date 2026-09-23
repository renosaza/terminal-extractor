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

Будущие области кода: session-registry, adapters/terminal-app, adapters/ghostty, adapters/tmux, shell-integration, journal, compression и host-ui. Это план модулей, не существующее продуктовое дерево.

## Документация

Карточки задач — канонический tracker. В каждой есть scope, dependencies, критерии и проверка. Перед done записать observed result, команды реально выполненных проверок и commit. Не ставить PASS из чтения чужого README. Новый runtime API должен обновить contract/schema fixtures/acceptance в той же ветке.

## Release boundaries

Подпись/notarization, app identity, helper permissions, автоматическая установка и удаление — задачи TE-T045..048, не выполненные настройки. Не придумывать Team ID, bundle signature, Homebrew formula или version pins. Нельзя менять user rc, терминальные профили и global AGENTS без отдельного согласия.

## Диагностика

Первое расследование: version/capability report, binding/generation, grants/lease, capture coverage, shell integration evidence. Только после локального согласия извлекать содержимое выбранного тестового журнала. Диагностика по умолчанию metadata-only. Отсутствующий API означает unsupported/not_tested, а не необходимость обходить TCC или нажимать клавиши в активное окно.
