---
id: TE-E09
type: epic
status: draft
task_status: backlog
scope: context-compression
---
# Экономия контекста и Headroom

## Результат

Builtin bounded compact view и исследованный optional Headroom adapter с ACL-checked original retrieval и измеренной fidelity.

## Завершён, когда

Статусы/IDs/uncertainty защищены, current screen не сжат с потерями, оригинал воспроизводим. Worker failure/timeout не ломает terminal и не отправляет весь лог. Savings опубликованы только как измерения конкретного corpus/tokenizer, не обещание.

## Ограничения

TE-C05..07. Не обязательны ML/Python для core; никаких скрытых weight downloads или proxy всей переписки.

## Задачи

[TE-T033](../tasks/TE-T033.md), [TE-T034](../tasks/TE-T034.md), [TE-T035](../tasks/TE-T035.md), [TE-T036](../tasks/TE-T036.md).

[Compression contract](../../architecture/logging-and-compression.md).
