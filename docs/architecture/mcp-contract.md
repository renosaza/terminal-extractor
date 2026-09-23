---
type: api-contract
status: draft
---
# MCP API v1: проект контракта

Все имена `terminal_*`, поля, CLI и resource URI ниже **проектируются для этого репозитория**. Они не являются стандартными методами MCP и ещё не реализованы. Стандарт задаёт tools/list, tools/call, schemas, content и error envelopes [S10](../research/sources.md).

## Transport и совместимость

Baseline — local stdio, negotiated protocol version из реально поддерживаемых SDK/client. Tool responses bounded; stateful command engine не зависит от MCP request lifetime. MCP Tasks extension — opt-in enhancement после conformance, не обязательное условие polling. Client disconnect/cancel не вызывает terminate terminal command. stdout gateway только JSON-RPC; logs в stderr без содержимого пользовательских команд.

Объявить inputSchema/outputSchema, `additionalProperties: false` для контрактных объектов, bounds, enum и nullable поля. Structured content — канонический result; для старых клиентов минимальный text projection того же result, без дублирования большого output в двух representations. Exact shape SDK проверяется перед реализацией. Tool annotations — hints для клиента, не контроль прав. Ненулевой exit code не означает `isError: true`.

## Общие модели

`TargetRef = {session_id: UUID, generation: integer >=1}`. Native discovery target — отдельный краткоживущий opaque handle, выданный локально для разрешённого выбора. Нельзя принять произвольный PID, TTY, AppleScript, window title или socket path от модели вместо target.

Mutation context: `request_id` длиной 1..128, `session_id`, `generation`; client identity и grant хранятся на стороне gateway/host и не доверяют строке clientInfo. Lease epoch связывается с этим authenticated local connection, не предоставляется агентом как право самому себя разрешить.

`Coverage = {kind, capture_epoch, since, until, history_start_known, complete_for_interval, gaps, earliest_available_cursor, retention_applied}`. `kind`: `continuous_stream|retained_scrollback|snapshot_only|none`. Native values не повышаются от установки hooks.

`ReadResult = {schema_version:1, session_id, generation, snapshot_id, content, next_cursor, more_available, truncated, coverage, provenance, compression}`. `snapshot_id` может быть null для stream page; provenance содержит источник, observed_at и source version. Dynamic log query фиксирует high_watermark на первую страницу.

`Command = {command_id, session_id, generation, shell_epoch, origin, text, text_redacted, state, delivery, started_at, ended_at, exit_code, success, evidence, interaction, output_refs, output_completeness, attribution}`. Unknown values — null или явный enum, не 0/пустая строка. exit_code nullable; timestamps UTC плюс внутренний monotonic duration. Command IDs не переиспользуются.

## Tools

| Tool | Input и поведение | Основной output |
|---|---|---|
| terminal_capabilities | Необязательный TargetRef; общие либо per-session возможности | Версии, supported/probed/not_tested, capture/status/input limitations |
| terminal_list | Фильтр разрешённого app, bounded cursor | Только разрешённые для discovery targets/sessions, не все пользовательские окна |
| terminal_open | request_id; app из allowed set или default; backend managed_tmux/native; initial_cwd optional | New session, binding, capabilities; не сообщает ready до проверки окна |
| terminal_attach | request_id; конкретный разрешённый target handle; requested read/control scope | Existing session и фактически выданные права; новый shell не создаётся |
| terminal_execute | TargetRef, request_id, command; wait_ms=1000, 0..20000; queue=false default | Command + bounded incremental output, wait_expired |
| terminal_command_get | TargetRef, command_id, optional output_cursor/limit | Статус без повторного запуска; output page |
| terminal_last_command | TargetRef; origin=any/agent/human; selection=last_started/last_completed | Command или unavailable с reason; не угадывает старую history |
| terminal_read | TargetRef; view=screen/changes; cursor optional; format=text/cells | Screen или changes с source, cursor/attributes при наличии |
| terminal_log_read | TargetRef; cursor/range; representation=exact/compact; limits | Сохранённый log page + manifest/coverage/high_watermark |
| terminal_log_search | TargetRef; literal query; time/command filters; limit | Совпадения, offset refs и bounded context; regexp в v1 не нужен |
| terminal_content_get | TargetRef; opaque content_id; offset/limit | Разрешённый оригинал; ACL проверяется заново; нет arbitrary path read |
| terminal_send | TargetRef, request_id; operations text/paste/key; no implicit Enter | Delivered count, delivery state, optional observation; не fake command exit |
| terminal_wait | TargetRef; condition output_changed/command_changed/session_closed; after; timeout_ms<=20000 | Наблюдённое изменение или wait_expired; не kill |
| terminal_release | TargetRef, request_id | Отзыв прав текущего агента; shell сохраняется |
| terminal_close | TargetRef, request_id; scope=session или view, explicit local close grant | Отдельный lifecycle result; не вызывает kill-server |
| terminal_log_export | TargetRef; range, format=text/jsonl; bounded local policy | Opaque export/content ref и manifest; произвольный output path запрещён |

Read tools не должны менять clipboard без объявленного opt-in capability. Screen read через native Ghostty export имеет side effect; его annotation и description должны честно отражать это. Read/write policy различает content-read и clipboard side effect.

При нескольких targets `terminal_list` выдаёт отдельную строку для каждой доступной вкладки Terminal.app и каждой surface Ghostty вместе с app/window/tab/surface metadata для выбора человеком. Локально подтверждённый opaque handle выбранной строки передаётся в `terminal_attach`; title и порядковый номер служат только для отображения. Отсутствующий, неоднозначный или устаревший выбор — ошибка без fallback на focused/первый target.

## Пример: быстрая команда

Запрос terminal_execute:

```json
{"session_id":"11111111-1111-4111-8111-111111111111","generation":1,"request_id":"demo-001","command":"printf 'hello\\n'","wait_ms":1000,"queue":false}
```

Сокращённый синтетический ответ, не результат реального запуска:

```json
{"schema_version":1,"command_id":"cmd_demo_001","state":"completed","delivery":"acknowledged","exit_code":0,"success":true,"evidence":{"source":"zsh_hook","shell_epoch":1},"output":{"text":"hello\n","more_available":false,"output_completeness":"complete_for_interval","attribution":"foreground_interval"},"wait_expired":false}
```

Для длинной команды тот же tool возвращает `state: running`, `exit_code: null`, `success: null`, `command_id` и output cursor. Дальше terminal_command_get либо terminal_wait; terminal_execute повторно не вызывается с новым request_id ради status.

## Пример: native limitation

```json
{"state":"unknown","exit_code":null,"success":null,"evidence":{"source":"native_snapshot","reason":"no_registered_shell_boundary"},"coverage":{"kind":"retained_scrollback","history_start_known":false,"complete_for_interval":false},"recommended_action":"use_interactive_read_or_enable_integration_locally"}
```

Это illustration возможных полей. Final JSON Schema и полные fixtures — TE-T029; ни один неполный пример не служит заменой schema.

## Ошибки

До dispatch: PERMISSION_DENIED, CONSENT_REQUIRED, SELECTION_REQUIRED, TARGET_NOT_FOUND, STALE_GENERATION, BUSY, NOT_AT_PROMPT, UNSUPPORTED_CAPABILITY, TERMINAL_APP_UNAVAILABLE, INTEGRATION_REQUIRED, INVALID_ARGUMENT, IDEMPOTENCY_CONFLICT.

После попытки: DELIVERY_INDETERMINATE, TARGET_CHANGED, APP_UNRESPONSIVE, CLIPBOARD_CONFLICT, EXPORT_INVALID, CAPTURE_GAP, STORAGE_LIMIT, CURSOR_EXPIRED, CONTENT_EXPIRED, PRIVACY_PAUSED, HOST_RESTARTED.

Tool error содержит machine code, retryable, operation/request ID, безопасное explanation и возможный remedy. Нельзя ставить retryable=true для неизвестной доставки без правила reuse same request_id. Generic client retry не должен повторять input. JSON-RPC syntax/params ошибки остаются protocol errors; business/adapter errors — tool result с isError по SDK contract.

CURSOR_EXPIRED возвращает earliest_available_cursor и retention manifest. CONTENT_EXPIRED не создаёт вымышленный original. CAPTURE_GAP может быть warning вместе с частичным содержимым; это не превращает данные в complete.

## Resource и token discipline

Resources могут использовать `terminal-extractor://sessions/<session_id>/content/<content_id>`, но те же данные всегда доступны через bounded tools для клиентов без resource UX. URI не даёт права и не является file URL. Context budget enforced server-side; клиент вправе запросить больше страниц, но не снять server hard cap.

В initialize instructions объяснить: выбрать/получить разрешённую сессию; inspect capabilities; execute только idle shell; interactive ввод через send; status polling не execute; при unknown не предполагать успех; compact original можно дочитать. Агентская инструкция помогает выбору tools, но не заменяет server-side проверки.
