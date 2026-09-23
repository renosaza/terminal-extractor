---
id: TE-E06
type: epic
status: draft
task_status: backlog
scope: command-engine
---
# Command engine и доказательные статусы

## Результат

Execute/get/last поверх текущего zsh с command IDs, start/end evidence и честным recovery без повторного запуска.

## Завершён, когда

Aliases/cd/export сохраняют смысл; code снят корректно; silence не завершает job; delivery отличается от execution. Last учитывает origin и running. Crash-after-dispatch не вызывает replay, SSH/REPL interaction не получает выдуманные локальные command records.

## Ограничения

TE-C02..04, TE-C07. Не использовать eval/subshell wrapper как замену вводу и prompt regex как доказательство.

## Задачи

[TE-T021](../tasks/TE-T021.md), [TE-T022](../tasks/TE-T022.md), [TE-T023](../tasks/TE-T023.md), [TE-T024](../tasks/TE-T024.md).

[State contract](../../architecture/capture-and-commands.md).
