---
id: TE-E12
type: epic
status: draft
task_status: backlog
scope: distribution
---
# Установка, подпись и выпуск

## Результат

Поставить проверяемый macOS app/CLI/helper комплект, сохраняющий пользовательское окружение, с честной инструкцией и матрицей поддержки.

## Завершён, когда

Signing/notarization проверены для фактической identity, install/update/uninstall не меняют несвязанные настройки/сессии. Published claims соответствуют acceptance report; versions/dependencies закреплены. Выпуск не скрывает unresolved Existing ограничения.

## Ограничения

TE-C06..09. Не придумывать signing keys/Team ID/formula; публикация и credential use требуют соответствующих прав.

## Задачи

[TE-T045](../tasks/TE-T045.md), [TE-T046](../tasks/TE-T046.md), [TE-T047](../tasks/TE-T047.md), [TE-T048](../tasks/TE-T048.md).

[Разработка](../../guides/local-development.md), [приёмка](../../guides/acceptance.md).
