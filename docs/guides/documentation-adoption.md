---
type: adoption-record
status: draft
---
# Перенос стандарта и границы этой поставки

## Источники

Канонический target: renosaza/terminal-extractor, исходный main commit `fb13a250eec9db3a368f52c9a913595fc59ba56c`; в нём только README-заголовок. Шаблон: [codex-proj-docs-OKF commit 500c09c2af92c238b36d475ee773ad051875603a](https://github.com/renosaza/codex-proj-docs-OKF/tree/500c09c2af92c238b36d475ee773ad051875603a).

Прочитаны project/AGENTS.md, project-docs-init/maintain/migrate и references/layout.md. Применён project-docs-init: существующий материал не требовал миграции или удаления. Требования взяты из уточнённой постановки владельца от 2026-09-23; прежняя широкая идея Linux/Windows не перенесена в обязательный scope.

## Сопоставление

Корневой AGENTS.md адаптирован под реальный docs-only проект, ссылки на constraints и selective index. docs/ — bundle root OKF v0.2; PRD и технические страницы — typed concepts. Task/epic/ADR workflow metadata отделены от lifecycle. Локальные карточки — единственный tracker; GitHub Issues не создаются зеркально.

Скилы проекта находятся в `.agents/skills/` вне bundle. Их текст сохраняет purpose и правила upstream; source pin фиксируется в локальном README. Общий layout используется как contract, не как разрешение менять global user files. Глобальный AGENTS.md, настройки рабочего Mac, shell rc и терминалов не изменялись.

## Оркестрация и ограничения инструментов

В доступной среде skill ponytail-chatgpt не удалось получить: поиск доступных skills/plugins не предоставил его; попытка прочитать через подключённое устройство закончилась timeout. Полный ponytail workflow поэтому **не выполнялся и не имитировался**. Независимые worker/subagent tools в этой сессии не предоставлены; исследование и документационные изменения выполнены напрямую. Нельзя считать это независимым code/security review.

Это запись фактически доступного процесса, а не изменение постоянного предпочтения владельца. AGENTS.md сохраняет требование использовать ponytail full mode, когда skill реально доступен, и не выдумывать проверки.

## Проверка поставки

Проверяются структура, ссылки, frontmatter, уникальность IDs и dependency graph карточек. Итог реально выполненных проверок и revision записывается в PR. Сам факт valid YAML не доказывает технические claims. Runtime- и real GUI-тесты, Swift build, MCP conformance, tmux/zsh/Headroom experiments в этой поставке **NOT_RUN**, поскольку исполняемой реализации нет.

Новый CI/validator service не добавляется только ради стандарта. Публикация — отдельная reviewable ветка/PR; merge не является побочным действием документационной задачи.
