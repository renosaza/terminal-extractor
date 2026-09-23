---
id: TE-E08
type: epic
status: draft
task_status: backlog
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
