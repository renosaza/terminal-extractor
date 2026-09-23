---
id: TE-E07
type: epic
status: draft
task_status: backlog
scope: journal
---
# Журнал, поиск и оригиналы

## Результат

Локальный bounded archive с provenance, command intervals, paging/search/export и explicit retention/gaps.

## Завершён, когда

Exact available interval восстанавливается по страницам без пропусков/дублей; native retained scrollback не назван полным stream; background attribution обозначен. Recovery/quota/private gaps видны, expired refs не возвращают вымышленный текст.

## Ограничения

TE-C04..07. Full log означает available interval, не восстановление несуществующей истории.

## Задачи

[TE-T025](../tasks/TE-T025.md), [TE-T026](../tasks/TE-T026.md), [TE-T027](../tasks/TE-T027.md), [TE-T028](../tasks/TE-T028.md).

[Journal contract](../../architecture/logging-and-compression.md).
