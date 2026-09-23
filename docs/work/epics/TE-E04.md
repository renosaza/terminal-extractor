---
id: TE-E04
type: epic
status: draft
task_status: active
scope: ghostty-native
---
# Адаптер Ghostty

## Результат

Выбор конкретной Ghostty surface, addressed paste/key input, явный new и text extraction с объявленными clipboard/coverage ограничениями.

## Завершён, когда

Stable binding выдерживает split/reorder/restart, клавиши не зависят от focus, экспорт не использует screenshot/OCR/paste filepath. Clipboard path проверяется и операции конфликта fail closed. Версии перечислены фактически; surface `pid`/`tty` не заявляются для установленного Ghostty 1.3.1.

## Ограничения

TE-C01..07, TE-C09; clipboard export только opt-in. Текущий main dictionary не равен установленному релизу.

## Задачи

[TE-T013](../tasks/TE-T013.md), [TE-T014](../tasks/TE-T014.md), [TE-T015](../tasks/TE-T015.md), [TE-T016](../tasks/TE-T016.md).

## Текущее состояние

В TE-T013 начат read-only discovery запущенного Ghostty 1.3.1 через PID-targeted Apple Events. Локальные CLI list/resolve различают окна по ID; MCP не выдаёт список и terminal access остаётся закрытым. Input, export, grants и устойчивый session binding не реализованы.

[Native contract](../../architecture/capture-and-commands.md), [privacy](../../architecture/security.md).
