---
type: research
status: draft
---
# Источники и границы проверки

Проверено чтением документации/исходников 2026-09-23. Runtime-проверки на Mac в этой поставке не выполнялись. Внешние возможности ниже не равны подтверждению реализации в terminal-extractor.

## S01 — стандарт владельца

[renosaza/codex-proj-docs-OKF, commit 500c09c2af92c238b36d475ee773ad051875603a](https://github.com/renosaza/codex-proj-docs-OKF/tree/500c09c2af92c238b36d475ee773ad051875603a). Прочитаны project/AGENTS.md, project-docs-init/maintain/migrate SKILL.md и references/layout.md. Из них взяты bundle layout, типы, lifecycle/workflow distinction, one tracker, требования к ссылкам и evidence. Глобальные файлы пользователя не меняются.

## S02 — OKF

[GoogleCloudPlatform/knowledge-catalog: OKF SPEC](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md). Используется как upstream specification, указанный S01. Bundle root docs/, concepts с type, index отдельно. Проектные workflow fields не выдаются за обязательные поля OKF.

## S03 — Terminal.app

[Apple: Automate tasks using AppleScript and Terminal](https://support.apple.com/guide/terminal/automate-tasks-using-applescript-and-terminal-trml1003/mac). Подтверждает scriptable Terminal.app и необходимость смотреть его dictionary. Страница не доказывает безусловный адресный arbitrary-key API, непрерывный PTY capture или точный command exit status. Эти вопросы оставлены для установленной версии и TE-T001.

## S04 — Ghostty automation

[Ghostty AppleScript docs](https://ghostty.org/docs/features/applescript). Подтверждены hierarchy, стабильные IDs в object model, new window/tab/split, input text, send key, perform action, configuration record и Automation/TCC. Документация указывает появление AppleScript в 1.3.0; не трактовать это как достаточную minimum version для всего нашего контракта.

## S05 — Ghostty dictionary

[macos/Ghostty.sdef](https://github.com/ghostty-org/ghostty/blob/main/macos/Ghostty.sdef), прочитанный blob SHA `edf1c7e151b5387480f7ba560fe223fa513e6e81`. В прочитанном исходнике есть terminal id/name/working directory/pid/tty, addressed input text/send key и perform action. Прямой stream-read интерфейс из этого dictionary не подтверждён. Ссылка main изменяемая; blob hash записан для сопоставления. Новые поля из main нельзя обещать уже установленному релизу.

## S06 — Ghostty text export

[Keybind Action Reference](https://ghostty.org/docs/config/keybind/reference). write_screen_file/write_scrollback_file создают temporary text file; copy/paste/open работают с его путём. Это основание opt-in clipboard bridge, а не гарантия atomic snapshot/stream полноты/clipboard restoration.

## S07 — Zsh hooks

[Zsh Functions / Hook Functions](https://zsh.sourceforge.io/Doc/Release/Functions.html). preexec/precmd и hook arrays — механизм shell integration. Не подтверждает нашу bootstrap strategy и совместимость с любым prompt; она проверяется отдельными fixtures.

## S08 — tmux

[tmux Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode) и [официальный tmux manual](https://github.com/tmux/tmux/blob/master/tmux.1). Control mode предоставляет программное управление tmux и output notifications. Контрольные response boundaries относятся к tmux commands, не shell workload. Конкретный pipe-pane/control capture, loss/backpressure и input handoff требуют выбранной версии и runtime-теста.

## S09 — Swift MCP SDK

[modelcontextprotocol/swift-sdk README](https://github.com/modelcontextprotocol/swift-sdk/blob/main/README.md). Официальный Swift SDK, Swift 6+, StdioTransport, server support. Прочитанный README заявляет protocol 2025-11-25 и macOS library minimum 13.0. Это не проверенный release pin проекта и не доказательство поддержки новой protocol revision.

## S10 — MCP tools

[MCP tools, 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/server/tools). Основание tools discovery/call, schemas, structured output и различения tool/transport errors. Ни одна наша terminal_* операция не является стандартным методом MCP.

## S11 — новые версии и Tasks

[MCP specification 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28), [Tasks extension](https://tasks.extensions.modelcontextprotocol.io/). Версии/расширения согласовываются по capabilities. Не предполагать, что каждый Codex/MCP-клиент принимает task handles вместо обычного result. Основной terminal contract работает через execute/get/wait без этого расширения.

## S12 — Codex как MCP-клиент

[Официальная документация Codex MCP](https://developers.openai.com/codex/mcp/) (на дату чтения переадресована на ChatGPT Learn). Используется для local stdio и server configuration/env. Предлагаемые TERMEX_* переменные принадлежат terminal-extractor, не Codex. Рабочая конфигурация проверяется после появления binary в двух клиентах.

## S13 — Headroom

[headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom). Проект описывает локальное сжатие tool outputs, library/proxy/MCP режимы и retrieval исходников. Эти возможности обосновывают optional adapter, не наши гарантии качества/процентов экономии. Exact Python API, dependencies, version и latency фиксируются в TE-T034/036. В этой поставке Headroom не установлен и не запускался.

## Evidence policy

Прочитанный текст, код, выполненный прототип и real GUI conformance — четыре разных уровня evidence. Записи tested_version и PASS появляются только после реального теста. Unknown/unsupported/not_tested различаются. Чужие README claims не импортируются в наш README как измеренные результаты. Все новые API/tool names и numerical budgets в PRD являются проектными.
