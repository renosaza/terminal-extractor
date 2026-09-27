---
id: TE-E08
type: epic
status: draft
task_status: active
scope: mcp-interface
---
# MCP tools и совместимость клиентов

## Результат

Реализовать typed terminal API с bounded responses и обычным polling, работающий в Codex и втором MCP-клиенте.

## Завершён, когда

Схемы и ошибки проверены fixtures, права применяются на сервере, read/status не исполняют команды. Version negotiation реальное, Tasks extension необязателен. Generic config примеры заменены проверенными client-specific инструкциями.

## Ограничения

TE-C03..07. Никаких больших дублирующихся output blocks, stdout logs или client-side-only authorization.

## Задачи

[TE-T029](../tasks/TE-T029.md), [TE-T030](../tasks/TE-T030.md), [TE-T031](../tasks/TE-T031.md), [TE-T032](../tasks/TE-T032.md).

[API contract](../../architecture/mcp-contract.md).

Foundation MCP уже содержит `terminal_capabilities`, локальный запрос read grant, bounded Ghostty snapshot и точный `terminal_release`. Синтетические проверки release и schema rejection прошли; живой screen read подтверждён, live scrollback — нет. `open`/`attach`/`execute`/`send`/`close`, command evidence, полный read/status/log и приёмка двух клиентов остаются будущей работой. Поэтому эпик `active`, но его общий результат не достигнут.
