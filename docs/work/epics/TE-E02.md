---
id: TE-E02
type: epic
status: draft
task_status: backlog
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

[Архитектура](../../architecture/README.md), [настройки](../../guides/configuration.md).
