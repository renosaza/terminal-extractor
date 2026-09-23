---
id: TE-E02
type: epic
status: draft
task_status: active
scope: host-and-registry
---
# Host, настройки и идентичность сессий

## Результат

Минимальный Swift host/gateway foundation, независимый выбор app/mode, проверенные локальные grants и registry, не зависящий от focus/title.

## Завершён, когда

Config валидируется и не расширяет локальные права; процессы клиента отделены от владельца сессии; registry различает generations/epochs/view bindings; stale/unauthorized операции отклоняются до dispatch.

## Ограничения

TE-C03, TE-C06, TE-C07. Без root/cloud/web dashboard и выдуманных build commands.

## Задачи

[TE-T005](../tasks/TE-T005.md), [TE-T006](../tasks/TE-T006.md), [TE-T007](../tasks/TE-T007.md), [TE-T008](../tasks/TE-T008.md).

## Текущее состояние

TE-T005 и TE-T006 начаты после проверок SDK/tmux в TE-E01. Product SwiftPM package содержит отдельные CLI host и MCP gateway с private Unix IPC, локальный versioned config и read-only `terminal_capabilities` для выбранных настроек. Grants/registry и GUI host ещё не реализованы. Это foundation, не готовый terminal control.

[Архитектура](../../architecture/README.md), [настройки](../../guides/configuration.md).
