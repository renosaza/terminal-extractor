---
type: development-guide
status: draft
---
# Разработка и выпуск: текущее состояние

Сейчас в репозитории документация, task cards и feasibility probes. Нет продуктового runtime, installer, release binary или CI. `probes/mcp/Package.swift` собирает только тестовый MCP stdio server; это не готовый Terminal Extractor. Предлагаемый стек — [архитектура](../architecture/README.md), запуск реализации — [TE-E01](../work/epics/TE-E01.md).

## Начало реализации

Прочитать AGENTS.md, [ограничения](../constraints.md), PRD и свою карточку. Первый шаг — capability probes на отдельном безопасном macOS стенде. Записать версии, права, exact API и результат до выбора minimum supported versions. Feasibility результаты затем обновляют ADR-002, capabilities и карточки.

Для повторения TE-T004 на macOS с tmux 3.7c и Swift 6.4: `sh probes/tmux/probe.sh`, `swift build --package-path probes/mcp -c release`, `python3 probes/mcp/check.py`. Swift SDK закреплён в probe `Package.resolved`; `.build` локальный и игнорируется Git. Другие probes: `python3 probes/dictionaries.py`, `python3 probes/zsh/probe.py`. Эти команды проверяют только записанные fixture-сценарии.

Будущие области кода: core/session-registry, adapters/terminal-app, adapters/ghostty, adapters/tmux, shell-integration, journal, compression, mcp, host-ui и tests. Это план модулей, не существующее продуктовое дерево. Product manifest/build commands вводятся с runtime реализацией, а не копируются из probe.

## Документация

Карточки задач — канонический tracker. В каждой есть scope, dependencies, критерии и проверка. Перед done записать observed result, команды реально выполненных проверок и commit. Не ставить PASS из чтения чужого README. Новый runtime API должен обновить contract/schema fixtures/acceptance в той же ветке.

## Release boundaries

Подпись/notarization, app identity, helper permissions, автоматическая установка и удаление — задачи TE-T045..048, не выполненные настройки. Не придумывать Team ID, bundle signature, Homebrew formula или version pins. Нельзя менять user rc, терминальные профили и global AGENTS без отдельного согласия.

## Диагностика

Первое расследование: version/capability report, binding/generation, grants/lease, capture coverage, shell integration evidence. Только после локального согласия извлекать содержимое выбранного тестового журнала. Диагностика по умолчанию metadata-only. Отсутствующий API означает unsupported/not_tested, а не необходимость обходить TCC или нажимать клавиши в активное окно.
