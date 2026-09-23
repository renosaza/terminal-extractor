---
type: development-guide
status: draft
---
# Разработка и выпуск: текущее состояние

Сейчас в репозитории документация и task cards. Нет Package.swift, runtime source, installer, release binary или CI. Поэтому здесь нет команды установки/запуска, которая выдавалась бы за уже работающую. Предлагаемый стек — [архитектура](../architecture/README.md), запуск реализации — [TE-E01](../work/epics/TE-E01.md).

## Начало реализации

Прочитать AGENTS.md, [ограничения](../constraints.md), PRD и свою карточку. Первый шаг — capability probes на отдельном безопасном macOS стенде. Записать версии, права, exact API и результат до выбора minimum supported versions. Feasibility результаты затем обновляют ADR-002, capabilities и карточки.

Будущие области кода: core/session-registry, adapters/terminal-app, adapters/ghostty, adapters/tmux, shell-integration, journal, compression, mcp, host-ui и tests. Это план модулей, не существующее дерево. Первую фактическую структуру и реальные build/test commands вводит TE-T005; минимально необходимые dependencies фиксируются вместе с lockfile.

## Документация

Карточки задач — канонический tracker. В каждой есть scope, dependencies, критерии и проверка. Перед done записать observed result, команды реально выполненных проверок и commit. Не ставить PASS из чтения чужого README. Новый runtime API должен обновить contract/schema fixtures/acceptance в той же ветке.

## Release boundaries

Подпись/notarization, app identity, helper permissions, автоматическая установка и удаление — задачи TE-T045..048, не выполненные настройки. Не придумывать Team ID, bundle signature, Homebrew formula или version pins. Нельзя менять user rc, терминальные профили и global AGENTS без отдельного согласия.

## Диагностика

Первое расследование: version/capability report, binding/generation, grants/lease, capture coverage, shell integration evidence. Только после локального согласия извлекать содержимое выбранного тестового журнала. Диагностика по умолчанию metadata-only. Отсутствующий API означает unsupported/not_tested, а не необходимость обходить TCC или нажимать клавиши в активное окно.
