---
id: TE-E05
type: epic
status: draft
task_status: backlog
scope: managed-terminal
---
# Общая managed-сессия в обычном окне

## Результат

Долгоживущий tmux backend, отображаемый в Terminal.app или Ghostty; человек и агент работают с тем же pane, а не с копиями.

## Завершён, когда

Capture готов до shell workload, view binding подтверждён до ввода, GUI resize имеет одного authority, takeover проверен для всех attach-clients. Gateway disconnect не убивает shell; recorder loss явно создаёт gap. Пользовательские tmux settings/сессии не затронуты.

## Ограничения

TE-C01..04, TE-C06..07. Нет собственной terminal UI и обещания идентичности терминалу без tmux.

## Задачи

[TE-T017](../tasks/TE-T017.md), [TE-T018](../tasks/TE-T018.md), [TE-T019](../tasks/TE-T019.md), [TE-T020](../tasks/TE-T020.md).

[Архитектура](../../architecture/README.md).
