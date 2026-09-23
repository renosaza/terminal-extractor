---
id: TE-ADR-003
type: adr
status: draft
decision_status: proposed
scope: command-state-and-output
date: 2026-09-23
supersedes: null
---
# Доказательные статусы, явная полнота и восстановление оригинала

## Контекст

Пользователь просит completed/running, последнюю команду, её вывод и весь лог. Одного текста экрана недостаточно для достоверного exit code, прошлого журнала или привязки всех байтов к одному process. Сжатие добавляет риск потери значимой строки.

## Предлагаемое решение

Разделить command state, delivery state, interaction hints, evidence и output completeness. Допустить unknown/indeterminate, а не выдумывать бинарный ответ. Использовать shell events для начала/конца, session/shell/capture epochs для привязки и gap manifest для потерь. Выдавать log по bounded pages с high watermark. Оригинал хранится в разрешённом локальном archive; compact view всегда производная с reference и повторной ACL-проверкой.

## Почему

Тишина не означает завершение; возврат prompt может быть нарисован приложением; shell history не хранит output. Background processes смешивают поток с foreground-командой. Компрессор не должен определять exit status или управлять терминалом вместо command engine.

## Последствия

Ответы сложнее, чем boolean done, но не дают ложного успеха. Exact retrieval требует квот, privacy policy и явного истечения данных. Unknown не повод автоматически повторять dispatch. Legacy native capture не получает managed guarantees от простого включения shell hooks.

## Пересмотреть, когда

Появится проверенный официальный API command records/stream конкретного терминала; новое evidence может повысить capability только для протестированного backend. Нельзя убирать unknown до доказательства покрытия всех заявленных сценариев.

## Связи

[Command engine](../capture-and-commands.md), [журнал](../logging-and-compression.md), [MCP](../mcp-contract.md).
