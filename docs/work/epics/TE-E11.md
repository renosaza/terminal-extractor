---
id: TE-E11
type: epic
status: draft
task_status: backlog
scope: verification
---
# Проверки контракта и реальные GUI-сценарии

## Результат

Fixtures, unit/integration tests, настоящая матрица двух приложений, нагрузка/chaos и независимый интегрированный gate.

## Завершён, когда

AT-01..18 имеют evidence с revision/versions. Mocks не заменяют GUI proof. FAIL/UNSUPPORTED/NOT_RUN не скрыты; native full-control gate не закрыт managed-тестом. Бюджеты измерены с reproducible corpus.

## Ограничения

TE-C01..09; только безопасные тестовые сессии. Секреты синтетические, production/network config не меняется.

## Задачи

[TE-T041](../tasks/TE-T041.md), [TE-T042](../tasks/TE-T042.md), [TE-T043](../tasks/TE-T043.md), [TE-T044](../tasks/TE-T044.md).

[Приёмка](../../guides/acceptance.md).
