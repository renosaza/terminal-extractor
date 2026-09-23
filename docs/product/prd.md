---
id: TE-PRD-001
type: prd
status: draft
scope: macos-terminal-app-ghostty-v1
---
# Технический PRD: Terminal Extractor для macOS

Дата проектирования: 2026-09-23. Владелец требований: renosaza. Канонический репозиторий: `renosaza/terminal-extractor`. Реализация отсутствует; все описания ниже — требования и предлагаемые решения, если явно не обозначены как проверенный внешний факт.

## 1. Задача и ценность

Дать Codex и другим MCP-клиентам доступ к тому же живому терминалу, который видит пользователь в Terminal.app или Ghostty. Агент должен продолжать существующий процесс, читать текст, вводить команды и управляющие клавиши, получать состояние выполнения и обращаться к истории без повторной передачи огромного лога.

Продукт не является SSH-клиентом, новым терминальным эмулятором или системой computer use. SSH, Python REPL, psql, debugger, less, vim и интерактивный установщик — программы внутри выбранной сессии, а не отдельные специальные транспорты.

Главный инвариант: пользователь и агент взаимодействуют с **одним** терминальным backend и одним деревом процессов. Отдельное окно с копией логов этим требованиям не соответствует.

## 2. Уточнение терминов

**MCP — не «улучшенный API» и не исполнитель команд.** Это протокол обнаружения и вызова tools, передачи контекста и согласования возможностей. JSON Schema описывает запросы/ответы, но состояние терминала, права, журнал и доказательство завершения реализует наш сервер. MCP response сообщает результат вызова инструмента; shell-команда может продолжаться после него. Базовый контракт строится на обычных tools; MCP Tasks — необязательное расширение после проверки совместимости клиента [S09–S12](../research/sources.md).

**Ghostty** — корректное название приложения. Под «headrom» здесь принят **Headroom** из указанного в источниках проекта; это интерпретация опечатки, не отдельная установленная зависимость. Его сжатие рассматривается как опциональная локальная обработка уже собранного текста, а не способ получить доступ к терминалу [S13](../research/sources.md).

**Терминал** в API — конкретная shell/TUI-сессия. GUI window, tab и Ghostty surface — представления и адреса привязки. У одной managed-сессии может смениться представление без смены процессов, но новое окно должно быть явно привязано и разрешено.

**Полный лог** — весь доступный и сохранённый журнал в объявленном capture interval. Нельзя восстановить удалённый scrollback, прошлый stdout, который никто не сохранял, или достоверный exit code старой команды из одного shell history.

## 3. Scope

Обязательный v1: macOS, Apple Silicon, штатный Terminal.app и установленный Ghostty; локальный MCP stdio; zsh как первая shell с подтверждённым учётом команд. Цель сборки — macOS 14+ как проектное решение; фактическая поддержка публикуется только после матрицы испытаний. Версии macOS, Ghostty, zsh, tmux и MCP-клиентов определяет doctor, а не предположение о машине владельца.

Intel macOS, bash/fish instrumentation и дополнительные MCP-транспорты — отдельные расширения после обязательных сценариев. Linux, Windows, WSL, iTerm2, облачный relay, собственный LLM и новый терминальный UI не входят в v1.

Разрешены служебные native helper-процессы, tmux и optional Headroom worker. Запрещён новый рабочий shell на каждый вызов. Шрифт, тема, prompt и пользовательские конфиги не изменяются автоматически.

## 4. Две независимые оси выбора

### Приложение

Локальная настройка `terminal_app: terminal|ghostty` определяет приложение по умолчанию для **создания** и фильтр discovery. Переданная существующая сессия сохраняет собственный app binding. Изменение настройки не переносит её в другое приложение.

При желании пользователя оба приложения могут быть разрешены локальной политикой, но каждая операция всё равно адресная. Значение настройки не даёт агенту права читать все окна выбранного приложения.

### Подключение

`existing` подключает к конкретному локально выбранному target; при невозможности возвращает ошибку. `new` создаёт новую видимую сессию. `ask` требует выбора пользователем и не действует сам. По умолчанию нельзя использовать поведение «не нашёл старую — открыл новую».

Когда открыто несколько окон, вкладок или Ghostty split, пользователь видит список доступных ему сессий с приложением, окном/вкладкой/панелью и различимыми метаданными и явно указывает одну. Совпадающие названия не объединяют targets. `terminal_attach` принимает handle выбранной строки; без однозначного выбора возвращает ошибку и не выбирает frontmost/первую сессию. Handle проверяется повторно при подключении и перед вводом.

Для новой сессии `session_backend: managed_tmux|native`. Рекомендованный default — managed_tmux: выбранное приложение остаётся обычным Terminal.app/Ghostty, а внутри работает общий tmux backend с журналом и shell integration. Native new полезен без tmux, но наследует ограничения native capture.

## 5. Гарантии режимов

| Режим | Что сохраняется | Как читается | Статусы команд | Ограничение |
|---|---|---|---|---|
| Existing native Terminal.app | Уже работающий shell/процесс | Адресное чтение доступного текста через scripting adapter | Подтверждённые только после opt-in instrumentation; иначе unknown | Не гарантируются произвольные клавиши без Enter и непрерывный прошлый лог |
| Existing native Ghostty | Уже работающая surface | Текстовый export через API/action; clipboard bridge требует отдельного согласия | Те же ограничения instrumentation | Export — snapshot, не непрерывный PTY stream; свойства/API зависят от версии |
| Existing managed | Уже зарегистрированный tmux pane | Backend screen + записанный поток | Подтверждаются живой zsh integration в пределах shell epoch | Нельзя принять произвольную старую native сессию за managed |
| New managed в любом приложении | Новый долгоживущий shell | Захват начинается до пользовательской команды | Полный основной контракт | Нужен проверенный tmux; пользователь видит этот же pane |
| New native | Новый shell выбранного приложения | Как native existing | Только доказанные возможности | Не получает автоматически гарантий managed |

Подтверждённый внешний факт: Ghostty предоставляет адресные input/action APIs; write_screen_file/write_scrollback_file возвращают результат через действия copy/paste/open, а не готовый универсальный read stream [S04–S06](../research/sources.md). Terminal.app scriptable, но точный словарь установленной версии и семантика ввода требуют probe [S03](../research/sources.md).

Эта таблица не объявляет native limitations желаемым конечным UX. Она задаёт честную границу v1 и обязательные исследования. Если без ограничений Existing Terminal.app остаётся требованием выпуска, соответствующий acceptance gate остаётся открытым; нельзя закрыть его демонстрацией New managed.

## 6. Основные пользовательские сценарии

**U1 — передать старую вкладку.** Пользователь выбирает Terminal.app/Ghostty, видит список окон/вкладок/панелей, подтверждает одну сессию и права. Агент получает только её session_id, capabilities и доступную историю. Уже открытый SSH/REPL не перезапускается. Для недоказуемой истории выводится coverage, а не выдуманный результат.

**U2 — открыть рабочее окно.** Агент вызывает terminal_open в рамках локального разрешения создания. Сервер запускает managed backend, подключает обычное окно выбранного приложения, проверяет binding и только после этого разрешает ввод. Пользователь видит и команду, и её вывод.

**U3 — выполнить команду.** terminal_execute принимает command и session_id. Короткий wait возвращает completed с exit_code, если получено доказательство; иначе возвращает устойчивый command_id и running/unknown. Повторный status не запускает команду снова. Таймаут ожидания не убивает процесс.

**U4 — интерактивная программа.** Агент открывает REPL/редактор, читает экран и использует terminal_send. Не пытается выполнять новую shell-команду поверх текущей программы. Локальный учёт команды `ssh`/`python` продолжается до их завершения; вложенные команды не выдаются за независимо отслеживаемые shell jobs.

**U5 — последняя команда.** По запросу возвращаются последний наблюдаемый command record, origin, исходный текст, статус, timestamps, exit code при наличии и доступный вывод. Последняя по умолчанию — последняя начатая, включая running, а не только последняя успешная. Без записанных событий возвращается unavailable.

**U6 — весь журнал.** Пользователь/агент получает manifest, coverage и страницы по cursor либо локальный export. Нельзя требовать весь бесконечный лог одним MCP response. Search и bounded retrieval позволяют найти нужный диапазон без повторения всего контекста.

**U7 — вмешательство человека.** Локальное Take control/Revoke немедленно запрещает новый ввод агента, отменяет недоставленные операции и возвращает пользовательский ввод. Сама программа продолжает работать. Возврат агента требует свежего разрешения и чтения состояния.

**U8 — перезапуск клиента.** MCP disconnect не завершает managed shell. После подключения сверяются host/session generation, права и command records; неопределённый старый ввод не повторяется автоматически.

## 7. Функциональные требования

| ID | Требование | Обязательная проверка |
|---|---|---|
| FR-01 | Выбор Terminal.app/Ghostty в server config и создание в выбранном приложении | AT-01 |
| FR-02 | Явные existing/new/ask; отсутствие скрытого fallback | AT-02 |
| FR-03 | Устойчивая привязка app/window/tab/surface или pane + generation | AT-03 |
| FR-04 | Текстовый screen snapshot с provenance, bounds и capabilities | AT-04 |
| FR-05 | Execute с command_id, bounded wait, status и доказательством exit code | AT-05 |
| FR-06 | Подтверждённые zsh command start/end без изменения смысла команды | AT-06 |
| FR-07 | Last command и её available output, human/agent origin | AT-07 |
| FR-08 | Session log: pages, search, original retrieval, export, retention manifest | AT-08 |
| FR-09 | Отдельный интерактивный input без автоматического Enter | AT-09 |
| FR-10 | Read/write grants, single-agent writer, локальный отзыв | AT-10 |
| FR-11 | Идемпотентность с явным indeterminate после неоднозначного сбоя | AT-11 |
| FR-12 | Сессия переживает потерю MCP-клиента; state recovery без повторного ввода | AT-12 |
| FR-13 | Deterministic compact mode и optional Headroom с восстановлением оригинала | AT-13 |
| FR-14 | Приватный режим и исключение содержимого из диагностических логов | AT-14 |
| FR-15 | Корректная работа Unicode, resize, alternate screen и переноса строк | AT-15 |
| FR-16 | Codex и второй независимый MCP-клиент проходят один контракт | AT-16 |
| FR-17 | Capability report различает verified, unsupported и not_tested | AT-17 |
| FR-18 | Установка/удаление без скрытого редактирования user config | AT-18 |

## 8. Предлагаемый стек

Основной язык **Swift 6**, SwiftPM, официальный MCP Swift SDK, Foundation/AppKit, native Apple Events и небольшой macOS menu-bar host. SQLite через системную библиотеку для metadata/индексов, сегментированные локальные файлы для больших потоков. Для managed sessions — существующий tmux, отдельный socket и конфигурация только проекта. Shell integration — небольшой namespaced zsh plugin. Core не требует Node, Python, Electron или web dashboard.

Headroom подключается только опциональным локальным worker с зафиксированной Python dependency; никаких сетевых моделей, автозагрузок ML-весов или proxy всего трафика по умолчанию. Сначала реализуется собственное безопасное ограничение вывода и retrieval; Headroom не блокирует запуск терминального сервера.

Обоснование, альтернативы и точки пересмотра — [architecture](../architecture/README.md) и [ADR-002](../architecture/decisions/TE-ADR-002-stack.md). Выбор стека является предложением, а не результатом benchmark. SDK README и актуальная MCP specification расходятся по заявленной версии: реализация должна согласовывать реально поддерживаемую версию, а не печатать latest [S09–S11](../research/sources.md).

## 9. Семантика завершения

`accepted`, `running`, `completed` относятся к нашей execution state machine; `success` выводится из известного exit_code и не гарантирует достижения пользовательской цели. `unknown` нужен при отсутствии достоверного boundary, потерянной integration или неоднозначной доставке.

`waiting_for_input` не определяется надёжно для любой программы. Использовать отдельный interaction field `possible|confirmed|none|unknown` с evidence, а не менять running на completed по тишине. Signal request, MCP cancellation и process termination — разные события.

Для shell foreground block сохраняются исходный command text, shell epoch, start/end events и code, снятый немедленно в precmd до helper-команд. Background jobs и смешанный stdout получают temporal/interleaved attribution. Система не обещает разделённые stdout/stderr там, где терминальный поток уже их объединил.

Полный алгоритм — [capture-and-commands](../architecture/capture-and-commands.md).

## 10. Данные и приватность

Храним provenance и отдельные представления: разрешённый raw terminal stream, нормализованный текст, screen snapshots, command metadata, compact cache. Raw не означает разрешение сохранять секретный ввод. По умолчанию не вести keystroke log и не включать содержимое команд/вывода в диагностику.

Native import помечается retained_scrollback и historical_unknown; managed recording получает начало capture interval и явные gaps. Log deletion, retention и secret mode изменяют coverage. Права проверяются при чтении, поиске, сжатии и повторном извлечении, а не только при attach.

Модель может быть облачной: полученный ею текст уже покинул Mac. Локальное сжатие не делает последующую отправку модели локальной. Terminal access работает с правами пользователя и не является security sandbox.

## 11. UX без нового терминала

Небольшое меню Terminal Extractor показывает выбранное приложение, разрешённые сессии, reader/writer, recording/paused, capture limitations и состояние интеграции. Действия: Share existing, New session, Grant read, Grant control, Take control, Private mode, Revoke, Diagnostics. Основная работа остаётся в Terminal.app/Ghostty.

Идентификация окна не должна печатать служебный текст в чужую работающую программу. Использовать локальное отображение метаданных/подсветку собственного меню; фокусировать target только по отдельному пользовательскому действию. Выбор панели Ghostty точнее выбора всего окна.

Для native Ghostty отдельно показывать согласие на clipboard export: путь к временному файлу кратко попадает в общий clipboard, сторонние clipboard managers могут это заметить. Snapshot export не запускать бесконечно в фоне. Альтернатива без clipboard — managed backend либо доказанный адресный API конкретной версии.

## 12. Нефункциональные требования

Ниже **целевые бюджеты**, не измеренные результаты. Профиль benchmark: Apple Silicon Mac с 16 GB RAM, 4 сессии, зафиксированные версии и corpus.

| Метрика | Цель | Условие |
|---|---|---|
| Пустой broker | <=1% CPU в среднем за 5 минут | Нет native snapshot polling; исключить целевые программы |
| Core memory | <=150 MiB RSS | Без tmux children и optional ML; публиковать total отдельно |
| Metadata/status/read cached page | p95 <=100 ms | Локальный warm path, страница до 64 KiB |
| Видимый ввод managed | p95 <=150 ms | От принятия dispatch до появления в backend; без времени команды |
| Native export | p95 <=1000 ms как исследовательская цель | TCC уже разрешён; не блокирует Stop |
| Stop/revoke | Новые dispatch прекращаются <=100 ms | Уже доставленные bytes не отзываются |
| Capture | 1 MiB/s на сессию, burst 10 MiB/s 5 s | 4 сессии; no silent loss; при перегрузке gap/backpressure |
| Response budget | 4000 estimated tokens default; hard bytes cap 64 KiB | Exact override тоже paginated |
| Ожидание execute | 0..20000 ms | Дольше — отдельные polls, не рост client timeout |
| Headroom budget | <=250 ms на compact request | Timeout => bounded lossless excerpt + original reference |

Disk defaults: 256 MiB на сессию, 2 GiB общий лимит и 7 дней — предлагаемые локальные настройки; пользователь видит tradeoff до включения recording. Активный log не обрезать молча при достижении лимита. Более длинное хранение требует явного изменения политики.

## 13. Критерии выпуска и приоритеты

P0: оба приложения открывают одну общую managed-сессию; existing discovery/attach не пересоздаёт процессы; точная адресация; zsh command state, last command, log pages; local consent/revoke; bounded outputs; честные native limitations. P1: hardening native adapters, дополнительная интерактивность по фактическим capabilities, Headroom, packaging и расширенная нагрузочная проверка. Все FR обязательны для полного v1, кроме поддержки дополнительных shell/архитектур вне scope.

Нельзя назвать v1 полностью соответствующим Existing full-control для Terminal.app, пока не доказан безопасный targeted no-Enter/control-key путь. До этого release notes обязаны называть Native Terminal.app limited, а full interactive — supported только для managed. Это открытый технический gate, а не замаскированное завершение требования.

Этапы: feasibility -> core/registry -> native + managed adapters -> command/log engine -> MCP -> compression/security -> real macOS acceptance -> packaging/release. Состояния и зависимости находятся только в [карточках](../work/README.md).

## 14. Основные риски и решения

R1: native Terminal.app arbitrary input не доказан. Сначала probe; ограничить capability вместо focus automation. R2: Ghostty snapshot использует clipboard и API меняется. Opt-in, version probe, bounded transaction; managed не использует этот путь. R3: неверное завершение и command attribution. Shell events, epochs, raw fences и unknown. R4: потери capture/retention. Gaps, durable offsets, backpressure и recovery tests. R5: неверная сессия после reorder/restart. Stable binding + generation + fail closed. R6: человек и агент печатают одновременно. Явная передача управления; auto-takeover не обещать без настоящего события ввода. R7: compression скрывает важную строку. Protected fields, fidelity tests, original retrieval. R8: command retry после crash. Persist-before-dispatch и indeterminate без auto replay.

Открытые вопросы решаются задачами TE-T001..004: установленный API и версии, непрерывный capture backend, shell hooks без конфликта с prompt, SDK compatibility. Они не требуют остановить создание PRD, но блокируют claims о готовом runtime.

## 15. Definition of Done

Каждое обязательное требование связано с AT-сценарием и task card; тесты реально выполнены на обоих приложениях и в двух MCP-клиентах; failures не скрыты за mocks. Публикуются tested versions, constraints, coverage semantics, original retrieval и reproducible fixture corpus. Нет незаявленного доступа к clipboard/окнам, скрытого изменения shell config, повторного запуска команд или выдуманного PASS.

Полная приёмка: [acceptance](../guides/acceptance.md). В текущей документационной поставке runtime DoD **не выполнен**.
