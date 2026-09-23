---
type: acceptance-plan
status: draft
---
# Приёмка: реальные окна и проверяемые результаты

Текущий результат всех runtime-сценариев: **NOT_RUN**. Таблица ниже — план, не отчёт о выполнении. Требования и IDs: [PRD](../product/prd.md).

## Стенд и evidence

Тестировать на вошедшем GUI-пользователе macOS с Apple Silicon. Записывать OS build, CPU/architecture, RAM, Terminal.app/Ghostty версии и dictionary hash, zsh/tmux versions, server commit, SDK/protocol negotiation и версии двух MCP-клиентов. Установленная машина владельца в этой поставке не обследована.

Использовать только отдельные тестовые окна и временный каталог с синтетическими данными. Не вводить команды в существующие рабочие SSH/production-сессии. Для Existing пользователь сам заранее открывает безопасный fixture-процесс; сервер подключается после этого. Секреты — синтетические маркеры, не реальные credentials. Никаких разрушающих команд ради демонстрации.

Матрица: Terminal.app native existing/new, Ghostty native existing/new, managed в обоих приложениях, повторное подключение existing managed. Каждый case отмечать PASS/FAIL/NOT_RUN/UNSUPPORTED с причиной и artifact reference. UNSUPPORTED нельзя превращать в PASS обязательного full-control требования.

## Функциональные сценарии

| ID / FR | Процедура | Критерий |
|---|---|---|
| AT-01 / FR-01 | По очереди выбрать terminal и ghostty в config/env; открыть новую сессию; сделать app unavailable | Открывается ровно выбранное приложение; изменение default не переносит старую сессию; unavailable даёт ошибку |
| AT-02 / FR-02 | Existing fixture хранит переменную и counter; подключить агента; отдельно проверить new/ask и неверный target | Existing продолжает тот же shell/PID/state; new создаёт другой только явно; ask не действует; ошибки не создают окно |
| AT-03 / FR-03 | Открыть 3 окна, вкладки и Ghostty split на нескольких мониторах; показать список и явно выбрать одну строку; повторить с одинаковыми titles, без выбора, после смены focus, переноса окна между дисплеями, переключения tab/split, rename/reorder и close/recreate | Каждая доступная сессия различима; без выбора нет attach; ввод не уходит соседу; монитор и focus не меняют target; closed/reused binding даёт STALE_GENERATION/TARGET_NOT_FOUND; no fallback |
| AT-04 / FR-04 | Читать screen/changes в каждом backend; менять content между чтениями; отключить clipboard opt-in | Только текст/структура, source и observed_at; native snapshot не назван stream; disabled export не трогает clipboard |
| AT-05 / FR-05 | Короткая успешная, ненулевая, длинная без вывода и длительная с прогрессом команды; poll | Known code точен; running не становится completed от silence; wait timeout не убивает; poll не повторяет execute |
| AT-06 / FR-06 | zsh aliases/functions/cd/export/pipeline/multiline/continuation/exec/exit; конфликтующие prompt hooks | Состояние shell сохраняется; `$?` снят до helper; нет двойного rc; потеря boundary => unknown, не 0 |
| AT-07 / FR-07 | Команда человека, агента, ещё работающая команда, queued item и старый history без integration | last_started/last_completed различаются; origin/evidence точны; historical output/code не выдуманы |
| AT-08 / FR-08 | Большой журнал, страницы до high watermark, новые записи во время чтения, search, export, rotation | Все доступные bytes выбранного interval восстанавливаются; нет пропуска/дубля cursor; gaps/expired явно обозначены |
| AT-09 / FR-09 | REPL, SSH в тестовый host, less/vim, prompts, no-Enter paste, Tab/Shift+Tab/arrows/Escape/Ctrl+C; Ghostty Cmd+D/Cmd+W и Control/Option/Command/Shift combinations в disposable split | Managed работает интерактивно в том же pane; native отклоняет неподдерживаемое до dispatch; app shortcut не выдаётся за terminal bytes; соседний split не получает ввод; nested input не получает fake local exit code |
| AT-10 / FR-10 | Два агента, read-only grant, отсутствие grant, local takeover/revoke при очереди | Один writer; unauthorized read/search/retrieve/write запрещены; недоставленная очередь удаляется, чужие окна не видны |
| AT-11 / FR-11 | Повтор request_id с тем же/другим digest; crash до/после physical input и до ack | Та же заявка не исполняется дважды; конфликт отклонён; неоднозначность => indeterminate без auto replay |
| AT-12 / FR-12 | Отключить MCP, перезапустить gateway; отдельно broker/recorder, закрыть app view | Shell survival и capture gaps различаются; права не воскресают; без видимого разрешённого окна ввод приостановлен |
| AT-13 / FR-13 | Корпус compact/Headroom, ошибка в середине, уникальные числа, paths, retrieval исходника | Protected metadata неизменны; exact original совпадает в разрешённом interval; нет обещания fixed savings; timeout bounded |
| AT-14 / FR-14 | Private pause до synthetic secret; запросы read/export/cache; resume при видимом secret | Секрет не передан и не записан в private interval; нет автоматического reimport; diagnostics без contents; gap отражён |
| AT-15 / FR-15 | Кириллица/emoji/wide/combining characters, narrow/wide resize, CR progress, alt screen | Нет corruption/codepoint split; dimensions/cursor/attributes честны; user scrollback viewport отделён от live screen |
| AT-16 / FR-16 | Выполнить одинаковую цепочку list/attach/execute/get/read/release в Codex и втором клиенте | Negotiated version и schemas работают; generic config example не считается тестом; отмена tool не убивает shell |
| AT-17 / FR-17 | Старый/новый Ghostty dictionary, Terminal.app limitations, пропавший tmux/hook | Version-specific capability report; verified/unsupported/not_tested различаются; SDK не заявляет неподдерживаемую protocol revision |
| AT-18 / FR-18 | Install/update/uninstall с уже существующими rc/profiles/tmux config и живой unrelated session | Нет скрытых изменений и чужих kill; TCC стандартный; retention/delete выбирает пользователь; signatures/paths проверены |

## Дополнительные failure cases

Clipboard: конкурентная запись человеком и clipboard manager, deferred data provider, export timeout, stale path, symlink, файл другого owner, чрезмерный размер, изменение файла после проверки. Проверять по FD, не shell path. Нельзя обещать атомарное восстановление clipboard без API, которого нет.

Input: delayed Apple Event после timeout, partial operation array, непустой ZLE buffer, continuation prompt, смена shell epoch после `exec`, потеря integration, background output одновременно с command end. Искусственная строка вида completion marker не меняет command state.

Storage/IPC: disk full, malformed/truncated JSON frame, invalid UTF-8 fragments, гигантская строка, незакрытая escape sequence, slow MCP consumer, journal segment crash/recovery, expired cursor другого session/generation. Не разглашать содержимое чужой сессии в ошибке.

Human control: закрыть последнее окно во время long command; Stop при зависшем helper/Headroom; несколько user attach-clients; sleep/wake. Измерять момент последнего разрешённого dispatch, а не обещать отзыв уже доставленного ввода.

## Нагрузочные и компрессионные измерения

Профиль и цели заданы в PRD. Публиковать raw measurements и p50/p95/p99 отдельно для core, tmux и optional worker. Четыре сессии, steady/burst output, 10000 status polls с bounded memory, серия resize. Замер token reduction сопровождается названием tokenizer/методикой estimate и fidelity corpus, а не только ratio.

## Условия допуска к релизу

В отчёте должны быть tested revision, матрица версий, результаты AT, известные ограничения, ссылки на evidence и отсутствие необъяснённых FAIL. Для native Existing Terminal.app arbitrary interactive control gate остаётся открытым, пока адресный путь не доказан; managed success его не закрывает. Не публиковать формулировку «полный захват любых старых окон» при partial matrix.

Screenshots допустимы как **человеческий artifact приёмки**, но не как runtime input серверу/агенту. Продуктовый путь capture не содержит OCR/images. Для автоматизированной проверки сравнивать текст/процессы/PTY state; финальная проверка общего видимого окна требует реального GUI-сеанса.
