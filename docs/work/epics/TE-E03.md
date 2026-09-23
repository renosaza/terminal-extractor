---
id: TE-E03
type: epic
status: draft
task_status: backlog
scope: terminal-app-native
---
# Адаптер штатного Terminal.app

## Результат

Адресный existing/native-new access к Terminal.app: enumeration, retained text, binding и подтверждённые операции ввода.

## Завершён, когда

Existing fixture продолжает тот же процесс; new создаётся только явно. Native snapshot coverage честна. Line submission протестирован, а произвольные keys либо доказаны безопасным API, либо объявлены unsupported без focus fallback. Последний случай не закрывает требование full native interactive control.

## Ограничения

TE-C01..04, TE-C09. Нельзя подменять native managed-сессией и выдавать managed test за native PASS.

## Задачи

[TE-T009](../tasks/TE-T009.md), [TE-T010](../tasks/TE-T010.md), [TE-T011](../tasks/TE-T011.md), [TE-T012](../tasks/TE-T012.md).

[Native contract](../../architecture/capture-and-commands.md).
