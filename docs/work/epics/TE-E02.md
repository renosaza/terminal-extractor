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

TE-T005..008 начаты после проверок SDK/tmux в TE-E01. Product SwiftPM package содержит CLI host, MCP gateway и AppKit helper выбора Ghostty. Private Unix IPC проверяет peer UID; локальный config и `terminal_capabilities` работают. Host имеет локальные Ghostty/Terminal.app discovery diagnostics. `terminal_request_access` открывает host-owned выбор конкретной Ghostty surface; выбранная identity повторно проверяется и записывается только за текущим IPC connection. Непереданные строки остаются внутри host/UI. Этот промежуточный путь возвращает `terminal_access=false`: чтение, ввод, Stop, authenticated gateway, persistent registry и полноценный GUI host ещё не реализованы.

[Архитектура](../../architecture/README.md), [настройки](../../guides/configuration.md).
