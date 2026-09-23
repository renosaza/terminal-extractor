---
id: TE-ADR-002
type: adr
status: draft
decision_status: proposed
scope: runtime-and-adapters
date: 2026-09-23
supersedes: null
---
# Swift host, адресные native adapters и managed tmux

## Контекст

Оба целевых приложения работают на macOS. Их scripting API не дают одинаковых гарантий чтения и интерактивного ввода. Полный непрерывный журнал требует владельца/наблюдателя терминального потока, а не только периодического чтения scrollback. Runtime-код и измерения отсутствуют.

## Предлагаемое решение

Swift 6/SwiftPM, официальный MCP Swift SDK, AppKit menu-bar host, signed Apple Events helper, private Unix IPC, SQLite metadata и сегментированные файлы. Native adapter сохраняет существующий процесс приложения; managed backend использует отдельный tmux namespace и отображается в обычном окне выбранного приложения. Zsh integration обеспечивает command boundaries; Headroom — необязательный локальный Python worker, не обязательный runtime core.

## Почему

Swift снижает число мостов к AppKit/TCC/Apple Events. tmux уже имеет PTY/screen state и управление долгоживущими сессиями. Это меньше новой инфраструктуры, чем собственный terminal emulator. Native mode сохраняет возможность подключиться к старой вкладке, но честно публикует ограничения.

## Альтернативы

Node/TypeScript требует native helper для тех же macOS API. Rust остаётся возможным core при доказанном Swift SDK blocker, но добавляет bridge/UI complexity. Python удобен для Headroom, однако не должен становиться обязательной зависимостью terminal core. Только AppleScript snapshots не обеспечивают непрерывный journal; только managed tmux не выполняет arbitrary Existing.

## Последствия

Managed mode добавляет tmux dependency и терминальные различия, которые нужно тестировать. Native Terminal.app full interactive support остаётся feasibility gate. Core не зависит от ML, web service или облака. Protocol revision выбирается по фактической совместимости SDK/client, а не по слову latest.

## Пересмотреть, когда

TE-T004 докажет blocker SDK/packaging либо native API предоставит более сильный поток/command interface. Принять стек после прототипа на обоих приложениях и документированной оценки альтернатив. До этого `decision_status: proposed`.

## Связи

[Архитектура](../README.md), [источники](../../research/sources.md), [TE-T004](../../work/tasks/TE-T004.md).
