---
type: api-contract
status: draft
---
# MCP API v1: проект контракта

Имена `terminal_*` принадлежат этому проекту, а не стандарту MCP. Реализованный foundation описан отдельно ниже; остальной каталог — проект, не фактический tools/list. Стандарт задаёт tools/list, tools/call, schemas, content и error envelopes [S10](../research/sources.md).

## Сравнение со штатным исполнением Codex

Проверено 2026-09-24: исходная ревизия проекта `86ef0b6`, схемы доступных в этой задаче `exec_command`/`write_stdin`, синтетические вызовы и официальная документация. Это наблюдение текущего интерфейса, не описание скрытой реализации всех версий Codex.

`exec_command` принимает shell command, `workdir`, shell/login, `tty`, ограничение вывода и время ожидания. В этой сессии `tty` по умолчанию false; PTY включается явно. Явный workdir дал каталог worktree, без него использовался исходный cwd задачи `/Users/renosaza/Documents/GitHub/terminal-extractor`, а не продолженный worktree. При `login=false` наблюдался `/bin/zsh`. Export переменной в одном завершённом вызове не сохранился в следующем: это не обещание общей интерактивной shell-сессии между запусками.

Короткий synthetic процесс вернул объединённый текст stdout/stderr и `exit_code=7`; порядок двух потоков не гарантируется. Долгий процесс после 250 мс вернул начальный текст и `session_id`, а последующий `write_stdin` с пустым `chars` — только оставшийся текст и `exit_code=3`, без повторного запуска. PTY `read` получил synthetic строку через тот же handle и завершился с 0. Отправка Ctrl-C тестовому PTY со `sleep` дала `^C` и exit code 1; это наблюдение конкретного процесса, не универсальный код сигнала. Повторное чтение завершённого handle получило `Unknown process id`. Несуществующая команда дала 127; несуществующий cwd — ошибку создания процесса, а не exit code shell. Проверки не читали пользовательские терминалы или clipboard.

По схеме tool `yield_time_ms` ограничивает ожидание ответа, `max_output_tokens` — возвращаемый объём; это не таймаут жизни команды и не гарантия полного лога. Повторное обращение к ещё живому handle проверено; восстановление после перезапуска Codex/соединения и длительное хранение output **не проверены и не обещаются**. Отдельного terminate tool в этой паре нет; Ctrl-C — ввод в PTY, эффект зависит от режима программы. Отмена turn, закрытие терминала и подтверждённое завершение процесса не эквивалентны.

Официальный [App Server: Command execution](https://learn.chatgpt.com/docs/app-server#command-execution) отдельно документирует `command/exec`, cwd, PTY, потоковые уведомления, write/resize/terminate и exitCode/stdout/stderr. Это API клиента App Server, **не** доказательство, что модель здесь имеет эти методы или что `exec_command` устроен идентично. [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security) различает sandbox и approval policy. Здесь сессия явно задана как `danger-full-access`, approval `never`; проверка интерактивного approval не проводилась. Эти настройки не заменяют локальный grant terminal-extractor и macOS Automation/TCC.

[Integrated terminal](https://learn.chatgpt.com/docs/integrated-terminal) описывает терминал проекта/worktree и чтение его вывода в desktop app. Отдельный доступный app tool чтения такого терминала не означает возможность пары `exec_command`/`write_stdin` подключиться к произвольной существующей Terminal.app/Ghostty pane. У этой пары нет аргумента native app/window/tab/surface или local grant.

| Сценарий | Штатная пара Codex в этой задаче | Foundation проекта | Проектируемое поведение |
|---|---|---|---|
| Выполнить команду | Запуск процесса с явным cwd; новый exec не продолжает завершённый shell | Input отсутствует | Execute в уже выбранном idle shell, control grant, prompt evidence; никакого скрытого нового shell или `cd` |
| Вывод и exit status | Ограниченный output и фактический exit code процесса | Разовый Ghostty screen, partial history; нет command status | Bounded output отдельно от nullable exit/status evidence; snapshot не повышает уверенность |
| Продолжить длинную команду | `write_stdin` с пустым вводом и handle дочитывает результат | Можно повторить snapshot в пределах export limit; stream/command handle нет | Continue с cursor и bounded wait без повторного execute; timeout не kill |
| Интерактивный ввод | `write_stdin(chars)` в созданный PTY | Отсутствует | Continue с явным text/key, без implicit Enter, control grant и проверкой generation; delivery не exit |
| Наблюдать ввод человека | Пара видит output своих процессов; нет событий чужой native pane | Screen может содержать echo, но не доказывает автора или границы команды | Shell events с корреляцией agent submissions; одного события недостаточно для human attribution, неоднозначное остаётся unknown |
| Переключить точную сессию | Можно выбрать handle своего процесса; attach к native pane отсутствует | Новый локальный выбор возвращает exact session ID/generation; уже выданные grants сохраняются | Каждый вызов адресный; release старого grant при отказе от доступа; focus не route key |
| Отозвать доступ | Нет per-native-session grant/release; Ctrl-C не отзыв | Локальный Stop и очистка при disconnect; адресный release описан ниже | Отзыв caller grant сохраняет shell и чужие grants; экстренный Stop независим |

### Минимальная поверхность tools

Не нужно отдельного tool для каждого внутреннего действия. Для будущего command engine предпочтительна пара `terminal_execute` + `terminal_continue`: второй объединяет bounded status/output polling, ожидание изменения и optional explicit input operations. При отсутствии operations это чтение без control grant; при наличии — mutation с request_id, control grant, writer lease и повторной проверкой перед dispatch. TargetRef обязателен в обоих, command_id нужен для командного status/output; session-level interactive input не выдаётся за новую отслеживаемую команду. `wait_ms`, cursor и limit не обходят backend limits. Capability, schema и error contract этой пары ещё требуют TE-T029; сейчас она не рекламируется в tools/list.

`terminal_command_get`, `terminal_wait` и `terminal_send` в каталоге ниже сохраняют требуемую семантику, но не требуют трёх отдельных model-facing tools. Last-command можно сделать selector чтения после появления evidence; journal/search/export — добавлять по реальному сохранённому журналу и потребности. Не строить dispatcher со всеми будущими action enum заранее. Выбор/согласие и release остаются отдельными, так как меняют право доступа. `terminal_screen` остаётся отдельным snapshot: объединение его с command polling скрыло бы clipboard side effect и ограничения Ghostty 1.3.1.

Для обычных сборок/файловых команд достаточно штатного Codex exec. MCP нужен, когда существенно продолжить **эту уже видимую** сессию с её cwd, shell state, SSH/REPL и человеческим участием. Input ещё закрыт: высокоуровневый execute требует подтверждения prompt и защиты незавершённого человеческого ввода; `success` Apple Event не заменяет exit status. Следующий реализуемый срез — адресный release существующего grant без новой интеграции shell, native input или clipboard export ([TE-T031](../work/tasks/TE-T031.md)).

## Transport и совместимость

Baseline — local stdio, negotiated protocol version из реально поддерживаемых SDK/client. Tool responses bounded; stateful command engine не зависит от MCP request lifetime. MCP Tasks extension — opt-in enhancement после conformance, не обязательное условие polling. Client disconnect/cancel не вызывает terminate terminal command. stdout gateway только JSON-RPC; logs в stderr без содержимого пользовательских команд.

Объявить inputSchema/outputSchema, `additionalProperties: false` для контрактных объектов, bounds, enum и nullable поля. Structured content — канонический result; для старых клиентов минимальный text projection того же result, без дублирования большого output в двух representations. Exact shape SDK проверяется перед реализацией. Tool annotations — hints для клиента, не контроль прав. Ненулевой exit code не означает `isError: true`.

## Общие модели

`TargetRef = {session_id: UUID, generation: integer >=1}`. Native discovery target — отдельный краткоживущий opaque handle, выданный локально для разрешённого выбора. Нельзя принять произвольный PID, TTY, AppleScript, window title или socket path от модели вместо target.

Mutation context: `request_id` длиной 1..128, `session_id`, `generation`; client identity и grant хранятся на стороне gateway/host и не доверяют строке clientInfo. Lease epoch связывается с этим authenticated local connection, не предоставляется агентом как право самому себя разрешить.

`Coverage = {kind, capture_epoch, since, until, history_start_known, complete_for_interval, gaps, earliest_available_cursor, retention_applied}`. `kind`: `continuous_stream|retained_scrollback|snapshot_only|none`. Native values не повышаются от установки hooks.

`ReadResult = {schema_version:1, session_id, generation, snapshot_id, content, next_cursor, more_available, truncated, coverage, provenance, compression}`. `snapshot_id` может быть null для stream page; provenance содержит источник, observed_at и source version. Dynamic log query фиксирует high_watermark на первую страницу.

`Command = {command_id, session_id, generation, shell_epoch, origin, text, text_redacted, state, delivery, started_at, ended_at, exit_code, success, evidence, interaction, output_refs, output_completeness, attribution}`. Unknown values — null или явный enum, не 0/пустая строка. exit_code nullable; timestamps UTC плюс внутренний monotonic duration. Command IDs не переиспользуются.

## Каталог проектируемых операций

Таблица сохраняет scope семантики v1; это не требование объявить каждую строку отдельным tool. Для командного цикла предпочтителен объединённый continuation, описанный выше. Фактический foundation tools/list указан после таблицы.

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

Foundation `terminal_capabilities` возвращает выбранные `terminal_app`, `attach_policy`, `new_session_backend`, `runtime=foundation` и состояние `terminal_access` текущего gateway connection. `terminal_request_access` без аргументов вызывает локальный выбор одной Ghostty surface, read scope и отдельной опции clipboard export. Ответ содержит `session_id`, `generation`, `scope`, `clipboard_export`, `terminal_access`; token остаётся внутри gateway. Список непереданных targets в MCP не поступает. `terminal_screen` требует переданный session ID/generation и оба разрешения; необязательный `view=screen|scrollback` по умолчанию выбирает screen. Ответ содержит bounded text, `observed_at`, `history_complete=false` и `source=ghostty_screen_snapshot|ghostty_scrollback_snapshot` согласно view. Оба view — отдельные одноразовые, неатомарные снимки выбранной surface; scrollback означает доступный Ghostty retained history, а не доказанную полную историю или stream. Export свыше 16 КиБ отклоняется целиком. Опция выключена в config по умолчанию. Живой MCP-тест подтвердил screen read трёх разных surface; scrollback пока прошёл только синтетические проверки. Конкурентная запись clipboard и Stop во время реального export остаются непроверенными. Input и финальные `terminal_list`/`terminal_attach` пока отсутствуют.

Foundation `terminal_release` принимает только `session_id` (UUID), `generation` (положительное целое) и `request_id` (1..128 UTF-8 bytes). Gateway использует внутренний token; host атомарно сверяет connection, session/generation, token и epoch и удаляет только этот grant. Native target не разрешается заново: закрытая pane тоже допускает отказ от grant. Ни shell, ни registry binding, ни другой session/client, ни глобальный epoch не изменяются. Новое чтение требует нового локального согласия. В отличие от release, локальный `termex-host --stop` отзывает все grants через отдельный канал; release сериализован с запросами текущего gateway и не прерывает выполняющийся export.

Stop сначала shutdown всех текущих gateway sockets, затем повышает общий grant epoch и лишь после этого подтверждает отзыв. Host и видимые терминалы продолжают работать, новые подключения снова проходят локальное согласие. Начатый Ghostty Apple Event не отменяется; авторизация повторно проверяется после него, а экспортированный файл не читается при обнаруженном отзыве после восстановления clipboard. Байты, уже записанные в socket до shutdown, невозможно отозвать: клиент может дочитать их после подтверждения Stop. Синтетические проверки подтверждают закрытие idle/partial-request sockets и отказ при отзыве во время внедрённого export action; живой Stop одновременно с Ghostty export не проверен. Для clipboard нет атомарного compare-and-swap: обнаруженный конфликт не перезаписывается, поздняя конкурентная запись остаётся риском.

Ответ release: `{status, session_id, generation, request_id}`. `status=released` — подтверждённое снятие конкретного grant; `denied`, `unavailable`, `idempotency_conflict`, `request_limit` — tool error. `released` при replay — исторический результат этого request_id, не утверждение об отсутствии нового grant. Gateway хранит максимум 256 результатов release за своё соединение, без вытеснения: одинаковые request_id/TargetRef возвращают сохранённый исход, другое содержимое того же key отклоняется, новый key сверх лимита не исполняется. Повтор старого request_id после нового consent не отзывает свежий grant. При неопределённом IPC-исходе повтор не доставляет запрос заново. Cache не переживает gateway restart; host удаляет grants старого соединения при disconnect. Это ограниченная connection-local защита release, не реализованный durable command engine или exactly-once input.

Некорректный input release отклоняется до dispatch с `isError=true` и безопасным текстом; structured status относится к валидированному запросу. Время между выдачей consent host и сохранением token gateway ещё не единая атомарная операция: конкурирующий release может безопасно получить `denied`. Проверки release на `6f5fa60` используют synthetic grants/host, а не живое согласие; результаты — в TE-T031.

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
