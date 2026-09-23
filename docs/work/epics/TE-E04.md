---
id: TE-E04
type: epic
status: draft
task_status: backlog
scope: ghostty-native
---
# Адаптер Ghostty

## Результат

Выбор конкретной Ghostty surface, addressed paste/key input, явный new и text extraction с объявленными clipboard/coverage ограничениями.

## Завершён, когда

Stable binding выдерживает split/reorder/restart, клавиши не зависят от focus, экспорт не использует screenshot/OCR/paste filepath. Clipboard path проверяется и операции конфликта fail closed. Версии перечислены фактически.

## Ограничения

TE-C01..07, TE-C09; clipboard export только opt-in. Текущий main dictionary не равен установленному релизу.

## Задачи

[TE-T013](../tasks/TE-T013.md), [TE-T014](../tasks/TE-T014.md), [TE-T015](../tasks/TE-T015.md), [TE-T016](../tasks/TE-T016.md).

[Native contract](../../architecture/capture-and-commands.md), [privacy](../../architecture/security.md).
