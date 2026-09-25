---
type: architecture
status: draft
---
# Архитектура и стек

Это проект архитектуры с частичной SwiftPM foundation: CLI host/gateway с private Unix socket и локальными настройками, private tmux owner с capture gate/sink и синтетическим shell fixture. Product recorder/journal, GUI view binding, consent-integrated input и session control отсутствуют. Требования: [PRD](../product/prd.md). Решение по стеку: [TE-ADR-002](decisions/TE-ADR-002-stack.md).

## Слои

```text
Codex / другой MCP-клиент
             │ MCP stdio
             ▼
terminal-extractor mcp       (короткоживущий gateway на клиента)
             │ private Unix socket, bounded JSON frames
             ▼
Terminal Extractor host     (один GUI-user broker + menu-bar control)
  ├─ consent / session registry / writer leases / command engine
  ├─ metadata SQLite + segmented journal + compact cache
  ├─ native Terminal.app adapter ── Apple Events helper
  ├─ native Ghostty adapter      ── Apple Events / opt-in export bridge
  ├─ managed tmux adapter        ── dedicated socket / pane / recorder
  │                                      ▲
  │                      обычное окно Terminal.app или Ghostty
  └─ optional local Headroom worker (только отобранный текст)
```

MCP gateway не владеет shell-процессами. Managed pane принадлежит tmux server и переживает потерю gateway. Broker владеет политикой и журналом. Потеря recorder/broker может создать gap даже при живом tmux; survival процесса не означает непрерывность записи. Native session принадлежит выбранному приложению и остаётся в нём.

## Конкретный стек

| Узел | Выбор | Причина и проверка |
|---|---|---|
| Core, gateway, CLI | Swift 6 + SwiftPM | Один native runtime для macOS; зависимости фиксируются в Package.resolved при реализации |
| MCP | modelcontextprotocol/swift-sdk | Официальный SDK; tools/stdio и реальное version negotiation проверяются TE-T004/029 |
| GUI host | AppKit, небольшой menu-bar UI | Выбор сессии, consent, Stop и privacy; без нового терминального UI |
| Automation | Apple Events через signed helper, typed descriptors/fixed handlers | Не конкатенировать ввод агента с AppleScript source; helper не блокирует Stop/main UI |
| Registry / commands | SQLite system library | Транзакции, stable IDs, schema migration, one writer; нет отдельного DB service |
| Большие логи | Append-only bounded segments + SQLite indexes | Поток не хранится одним растущим DB value; offsets и checksum |
| Managed terminal | tmux dedicated socket/config | Готовый PTY/screen backend; не реализуем свой эмулятор и не используем пользовательский tmux server |
| Shell events | namespaced zsh integration | preexec/precmd + authenticated local events; не парсить prompt как доказательство |
| Compression | deterministic local transforms; optional Headroom Python worker | Core независим от ML/Python; worker version pin и bounded IPC |
| Tests | Swift Testing/XCTest + macOS integration fixtures | SwiftPM manifest и локальные fixture checks есть; CI и полная product suite ещё отсутствуют |

Основания внешних возможностей: [S03–S09, S13](../research/sources.md). Конкретные patch versions, signing identity и Homebrew package name проекта пока не утверждены; не придумывать их в installer docs.

## Размещение и упаковка

Предлагается один `.app` bundle с GUI broker и подписанными CLI/helper binaries. CLI имеет будущие команды `mcp`, `doctor`, `host`, `shell-event`; это проект интерфейса, не работающие сегодня команды. Gateway подключается к запущенному GUI-user host; явная установка настраивает per-user автозапуск. Не использовать root LaunchDaemon или общедоступный TCP listener.

Данные: `~/Library/Application Support/TerminalExtractor/`; config, state database и sessions разделены. Runtime socket — private per-user directory с проверенными owner/mode и ограничением длины пути Unix socket; не делать имя из пользовательского window title. Directory 0700, regular data files 0600. Миграции atomic, с backup и несовместимой версией -> fail closed. Никаких токенов/логов в repository.

## Session registry

Модель разделяет `session_id`, `generation`, `capture_epoch`, `shell_epoch` и `view_binding`. `session_id` случайный UUID, сохраняемый в DB; generation меняется при потере идентичности backend. Ghostty surface ID и Terminal.app TTY — элементы binding, не полный security identity. Дополнительно проверяются app instance identity/start time, process identity, pane ID/socket namespace и разрешение пользователя.

Терминальные индексы и titles меняются и используются только для отображения. Нативный target повторно разрешается перед каждой записью. Нет автоматического перехода на front window. Managed session допускает перепривязку нового видимого окна только явно; команда не становится новой от смены renderer.

## Managed backend

Создать tmux server в отдельном namespace с собственной минимальной config, не читать/менять пользовательскую tmux config. Предлагаемый интерфейс скрывает status bar, но не обещает полную идентичность терминалу без tmux: TERM, клавиши, clipboard и графические протоколы отличаются и тестируются. Не копировать произвольно user config, не заменять prompt и font.

Capture запускается до shell workload. Прототип должен выбрать recorder: pipe-pane output stream либо проверенный control-mode stream с учётом его backpressure. Screen reads используют backend state; normalized transcript не является текущим экраном. Нельзя считать %begin/%end control command completion завершением команды внутри pane [S08](../research/sources.md).

Для создания видимого окна адаптер запускает attach-client к выбранному pane, проверяет связь и размеры. Не выдавать commands до подтверждённого view binding. Private socket path задаётся только локальной config, не аргументом агента. Existing arbitrary tmux pane не присваивается автоматически: пользователь сначала регистрирует допустимый namespace и pane.

## Привязка GUI и выбор размеров

Один разрешённый user view — основной источник rows/cols. MCP control client не должен своими размерами уменьшать пользовательскую панель. Второй user view либо явно read-only и non-authoritative по размерам, либо требует смены primary view. Resize меняет layout revision, но не инвалидирует execution lease сам по себе.

Закрытие последнего user view при живом pane приостанавливает агентский ввод. Окно можно восстановить отдельным действием. Закрытие приложения, broker, gateway и pane — разные lifecycle events; нельзя один close превращать в уничтожение всего tmux server.

## Конкурентность и отказоустойчивость

Один serial command actor на session. Чтение journal асинхронно и paginated. Вывод не блокируется долгим MCP request или Headroom worker. Native Apple Events выполняются отдельным helper с timeout; main UI и revoke path не ждут его завершения. In-flight delivery после timeout может быть indeterminate.

Journal writer имеет bounded queues и explicit overload policy; при потере данных записывается gap. Stdio stdout содержит только протокол; diagnostics идут в stderr/локальные metadata-only events. Gateway disconnect не автоматически завершает job. Leases не восстанавливаются после restart без проверки локального разрешения.

## Почему не другие стеки

Node/TypeScript удобен для MCP, но macOS automation/clipboard/TCC всё равно потребуют native bridge. Rust уменьшает runtime footprint, но для menu UI/Apple Events добавляет второй основной язык. Python облегчает Headroom, но делает необязательный compressor частью обязательного runtime. Для macOS-only выбран Swift; пересмотр допустим после измеренного SDK/packaging blocker, а не заранее ради переносимости.

Не добавлять web server, message broker, telemetry backend, контейнеры, embeddings DB, own VT renderer или auto-updater до доказанной необходимости. [Границы источников](../research/sources.md) и [приёмка](../guides/acceptance.md).
