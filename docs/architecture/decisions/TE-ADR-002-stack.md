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

## Проверка осуществимости 2026-09-23

На стенде macOS 27.0 (26A428, Apple M5) доступен Swift 6.4, tmux отсутствует. Установленные Terminal.app 2.15 и Ghostty 1.3.1 имеют scripting dictionaries; адресное выполнение и capture в живых окнах ещё не проверены. Ghostty 1.3.1 не объявляет surface `pid`/`tty`, хотя текущий upstream dictionary уже объявляет: capability определяется установленным bundle, не текущим source. Изолированный zsh 5.9 probe подтвердил часть command boundaries и startup order ([TE-T003](../../work/tasks/TE-T003.md)).

[Swift MCP SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1) — кандидат для проверки: tag commit `a0ae212ebf6eab5f754c3129608bc5557637e605`, Swift tools минимум 6.1, заявленные protocol revisions до `2025-11-25`. Ни SDK roundtrip, ни tmux capture не запускались; pin, minimum app versions и `decision_status` остаются proposed. [Текущее состояние TE-T004](../../work/tasks/TE-T004.md).

## Пересмотреть, когда

TE-T004 докажет blocker SDK/packaging либо native API предоставит более сильный поток/command interface. Принять стек после прототипа на обоих приложениях и документированной оценки альтернатив. До этого `decision_status: proposed`.

## Связи

[Архитектура](../README.md), [источники](../../research/sources.md), [TE-T004](../../work/tasks/TE-T004.md).
