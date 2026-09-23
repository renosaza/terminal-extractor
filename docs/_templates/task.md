---
type: template
status: draft
record_type: task
---
# Шаблон задачи

Создавать реальную карточку только для независимого результата. В frontmatter задать уникальный id, type: task, status: draft, task_status: backlog, scope, parent: epic ID либо null, depends_on: список существующих task IDs, owner: unassigned. Не переносить template metadata как task identity.

## Результат

Что должно измениться и где проходит граница задачи.

## Приёмка

Проверяемые условия, обязательные constraints и связанные FR/AT. Предложенный API отличать от уже реализованного.

## Проверка

Конкретные fixtures/сценарии и ожидаемый outcome. До выполнения: NOT_RUN. Команды записывать только когда они существуют.

## Result

Добавить перед done: что реально сделано, проверки и их результат, checked revision. Для handoff добавить текущий blocker/следующий шаг, не бесконечный журнал.

## Связи

Относительные ссылки на эпик, требования и технический контракт.
