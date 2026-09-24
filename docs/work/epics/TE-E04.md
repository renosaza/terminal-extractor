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

Read-only discovery и локальный выбор точной surface реализованы. В TE-T015 добавлен opt-in путь bounded screen/scrollback snapshots через адресный Apple Event и clipboard с server-side grant; живой MCP-тест подтвердил screen read трёх разных surface и точное восстановление доступных clipboard types/bytes в одном вызове. На контролируемой pane с визуально подтверждённой retained history живой scrollback вернул старый тестовый маркер и `history_complete=false`. Прежние отказы без clipboard path остаются без доказанной причины; положительный тест не обещает полную историю. Input и непрерывный захват отсутствуют. Установленный Ghostty 1.3.1 имеет source-confirmed FD leak на export, поэтому частый polling закрыт лимитом.

[Native contract](../../architecture/capture-and-commands.md), [privacy](../../architecture/security.md).
