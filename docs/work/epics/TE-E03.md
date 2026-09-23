---
id: TE-E03
type: epic
status: draft
task_status: active
scope: terminal-app-native
---
# Адаптер штатного Terminal.app

## Результат

Адресный existing access к Terminal.app: enumeration, retained text, binding и подтверждённые операции ввода. Native-new зависит от доказанного пути создания и проверки новой вкладки на установленной версии.

## Завершён, когда

Existing fixture продолжает тот же процесс; new создаётся только явно и получает PASS лишь после успешного создания/binding без пустого orphan window. Native snapshot coverage честна. Line submission протестирован, а произвольные keys либо доказаны безопасным API, либо объявлены unsupported без focus fallback. Последний случай не закрывает требование full native interactive control.

## Ограничения

TE-C01..04, TE-C09. Нельзя подменять native managed-сессией и выдавать managed test за native PASS.

## Задачи

[TE-T009](../tasks/TE-T009.md), [TE-T010](../tasks/TE-T010.md), [TE-T011](../tasks/TE-T011.md), [TE-T012](../tasks/TE-T012.md).

## Текущее состояние

В TE-T009 начат локальный read-only discovery Terminal.app по PID, window ID и tab TTY. MCP не выдаёт список и terminal access остаётся закрытым. Из-за возможного переиспользования TTY требуется host-owned generation до чтения/ввода.

[Native contract](../../architecture/capture-and-commands.md).
