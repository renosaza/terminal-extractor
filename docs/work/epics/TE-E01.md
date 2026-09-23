---
id: TE-E01
type: epic
status: draft
task_status: backlog
scope: feasibility
---
# Проверка API и осуществимости

## Результат

Получить доказательную матрицу версий Terminal.app/Ghostty, механизма shell events и минимального рабочего стека. Убрать из проекта предположения о якобы существующих API.

## Завершён, когда

Probe-артефакты воспроизводимы, known/unsupported/not_tested разделены, native no-Enter gate решён либо явно ограничен. Выбор SDK/protocol/tmux и стратегия hooks задокументированы с версиями; runtime claims опираются на тест, не README.

## Ограничения

TE-C01..04, TE-C06, TE-C09. Только тестовые окна; не менять рабочие rc/TCC автоматически.

## Задачи

[TE-T001](../tasks/TE-T001.md), [TE-T002](../tasks/TE-T002.md), [TE-T003](../tasks/TE-T003.md), [TE-T004](../tasks/TE-T004.md).

[Источники](../../research/sources.md), [ADR стека](../../architecture/decisions/TE-ADR-002-stack.md).
