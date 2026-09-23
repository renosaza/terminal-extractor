---
type: guide
status: draft
---
# Правила документации

`docs/` — bundle root OKF v0.2. Все Markdown-концепты, кроме `index.md` и `log.md`, имеют YAML `type`. `status` означает lifecycle `draft|stable|deprecated`, не состояние задачи. Корневые AGENTS.md и `.agents/skills/` находятся вне bundle.

Задачи: `id`, `type: task`, `task_status`, `scope`, `parent`, `depends_on`, `owner`. Состояния: `backlog|todo|doing|blocked|done|cancelled`. `parent` указывает эпик либо null; зависимости — только существующие task IDs, без циклов и self-reference.

Эпики: `id`, `type: epic`, `task_status`, `scope`; состояния `backlog|active|blocked|done|cancelled`. ADR: `id`, `type: adr`, `decision_status`, `scope`, `date`, `supersedes`; состояния `proposed|accepted|superseded|rejected`. Не объявлять предложенный стек принятым владельцем.

Карточка содержит результат, критерии приёмки и план проверки. До перевода в done добавить фактический Result: что выполнено, что проверено, результат, revision. Планируемые тесты обозначать NOT_RUN. Не создавать фиктивные записи техдолга в пустом проекте.

Один источник задач — `work/tasks/`; roadmap содержит ссылки, а не второй вручную обновляемый набор статусов. При переходе на Issues принять отдельное решение и мигрировать состояния, а не поддерживать две доски.

Использовать реальные относительные ссылки и явные источники внешних утверждений. Даты спецификации не выдавать за даты runtime-проверок. Nested YAML разбирать полноценным YAML parser. Проверять уникальность IDs, ссылки, frontmatter и DAG; структурная проверка не доказывает техническую осуществимость.

Шаблоны: [task](_templates/task.md), [epic](_templates/epic.md), [ADR](_templates/adr.md). Источник стандарта и фактическая проверка — [adoption](guides/documentation-adoption.md).
