---
type: technical-spec
status: draft
---
# Подключение, ввод и command state

## 1. Native Terminal.app

Во время doctor прочитать scripting dictionary установленного Terminal.app, записать app/OS version и hash dictionary. Проверить enumeration windows/tabs, TTY mapping, получение доступных `contents`/`history` и поведение адресного `do script` на тестовой вкладке. Имена свойств до probe — кандидатные, не обещание всех версий [S03](../research/sources.md).

Не путать AppleScript `do shell script` с Terminal.app `do script ... in target`: первый не является гарантированным вводом в выбранную живую вкладку. Helper использует фиксированный скомпилированный handler и argument descriptors, а не интерполяцию команд/TTY в исполняемый AppleScript source.

`do script` исследуется как **line submission**, включая его автоматический terminator. Его нельзя без теста использовать для no-Enter paste, Escape, Ctrl+C или работы редактора. Если безопасный addressed raw input не найден, `raw_input=false`, `key_input=false`; high-level execute допускается только в подтверждённо idle/instrumented shell. Никаких CGEvent «в активное окно» или TIOCSTI fallback. Полная интерактивность остаётся доступна через managed pane того же Terminal.app.

Native capture — retained text snapshots. Polling может пропустить краткую перерисовку/очищенный текст. Нативный адаптер не объявляет stream_complete даже после установки shell hooks.

## 2. Native Ghostty

Использовать hierarchy application/windows/tabs/terminals и stable IDs из установленного scripting dictionary. Документированный API появился в 1.3.0; наличие свежих свойств вроде pid/tty в текущем исходнике не означает их наличие во всех релизах. Каждый capability проверяется отдельно [S04–S05](../research/sources.md).

Ввод: `input text ... to terminal` для literal paste; `send key ... to terminal` для keys; Enter — отдельная операция. Перевод key names/modifiers учитывает документированную семантику и текущую раскладку. Команду передавать как paste text, а не печатать посимвольно через раскладку. Возвращаемый success Apple Event означает доставку API-вызова, не исполнение shell-команды.

Локальный probe Ghostty 1.3.1 с раскладкой RussianWin подтвердил адресный Tab/Shift+Tab и отдельный literal Unicode paste. AppleScript `send key` с Command+D/Command+W принял вызов, но не создал/закрыл split; `perform action new_split:right/close_surface` с явным surface ID сработал. Обычные печатные A/E/digit2, Shift+A и проверенные Option-сочетания не дали байтов за окно наблюдения 0,2 с; отдельный эффект Option этим probe не доказан. Поэтому capability для сочетания объявлять только по проверенному эффекту на target; пользовательские GUI shortcuts и PTY bytes различать. Поведение физической клавиатуры и иных раскладок остаётся непроверенным.

Чтение без image/OCR: `perform action` на **выбранной surface** вызывает `write_screen_file:copy` или `write_scrollback_file:copy`. Документированные действия copy/paste/open относятся к пути временного файла [S06](../research/sources.md). `paste` запрещён для extraction: он вводит путь в работающую программу. `open` не использовать: запускает сторонний editor.

Clipboard bridge — отдельный opt-in capability и глобально сериализованная операция. Сохранить прежние pasteboard representations только в памяти helper, записать changeCount, вызвать адресный export, ждать ограниченно, проверить новый changeCount и path. Допускать только новый regular file в ожидаемом private temp context, с owner пользователя, без symlink, с безопасным размером; читать через открытый FD с fstat, не через shell. При несоответствии вернуть CLIPBOARD_CONFLICT/EXPORT_INVALID, не читать произвольный файл.

Восстанавливать прежний clipboard только когда он всё ещё принадлежит нашей операции; изменение человеком не перезаписывать. Между проверкой changeCount и записью нет универсального атомарного CAS: гонка остаётся, должна быть описана и tested. Watchers могут заметить временный путь; perfect clipboard privacy не обещать. Deferred providers/неподдерживаемые clipboard types -> отказ с предложением managed mode, а не потеря пользовательских данных. Не удалять чужие temp files. Без доказанного ownership безопаснее оставить OS cleanup, чем удалить по строке из clipboard.

AX text API допускается как дополнительный read-only адаптер после доказанной адресации surface и проверки alternate screen. Он не является baseline-гарантией и не превращается в global key injection.

## 3. Managed sessions

Backend ID: dedicated tmux namespace + pane ID + generation. Pipe/control stream читается от владельца PTY; нельзя читать `/dev/ttys...` в надежде получить копию уже выведенного текста. PTY slave не является журналом вывода.

Локальный ручной fixture на Ghostty подтвердил, что выбранную существующую тестовую pane можно временно использовать как attach-client к **новой** private tmux session: после detach исходный shell сохранился; маркер был виден в tmux screen и дошёл до заранее включённого pipe. Это не ретроактивный захват исходного shell/scrollback и не product view binding. Первый живой запуск не подтвердил pipe marker, хотя маркер был виден; точная причина не установлена. См. [TE-T017](../work/tasks/TE-T017.md) и [TE-T018](../work/tasks/TE-T018.md).

При запуске обеспечивается gate: recorder готов до exec shell. Первоначальная регистрация, geometry и первый snapshot согласуются по sequence/watermark; double counting импортированного scrollback исключается или помечается. Recorder restart создаёт новый capture_epoch и возможный gap, не фиктивную непрерывность.

Screen использует tmux state. Сохранять rows/cols, cursor, alternate buffer, wrap flags и доступные attributes; если backend не даёт атрибут — unknown. Строить VT parser с нуля не требуется. Нормализатор journal не должен отвечать приложению на terminal queries; существует только один authoritative responder, иначе DSR/DA replies продублируются.

## 4. Zsh integration и boundaries

Namespaced integration использует preexec/precmd; `$?` снимается первым действием precmd, до subprocess, logging, prompt helper и любых команд. Устанавливать hook arrays аддитивно, не заменять чужие hooks; сохранять порядок и результат. Существующие Oh My Posh/Starship/другие prompt setups — fixtures, не зависимости продукта. Контракт hooks описан zsh [S07](../research/sources.md).

Managed bootstrap — per-session startup shim, который сохраняет реальный порядок пользовательских startup files, login/interactivity и пользовательский ZDOTDIR. Не source rc дважды и не переходить молча на `zsh -f`. Несовместимый startup/exec другого shell -> capability downgrade и диагностика. Выбор точного bootstrap подтверждается TE-T003/021, а не притворной рабочей командой в этом документе.

Existing native shell подключает integration только после явного локального согласия на **idle shell**. Пользовательский bootstrap не вводится в SSH/REPL/редактор и не прерывает процесс. Уже работающую команду нельзя ретроспективно объявить отслеживаемой с известным start/code.

События start/end идут в отдельный private IPC с session generation, shell PID/start identity, shell_epoch и monotonically increasing event sequence. Команды не подставляются в shell helper source. Для managed output alignment helper добавляет bounded private stream fences, связанные с зарегистрированным event; журнал читает их в том же byte stream. Out-of-band событие без stream fence само по себе не доказывает границы output из-за порядка доставки разных каналов.

Fences не используются как самостоятельное доказательство доверия: обычный terminal output может содержать похожие OSC/строки. Проверять registration, sequence, generation и непредсказуемый correlation nonce; секреты не попадут в exposed command text. Это защита от случайной/внешней подделки вывода, не sandbox против процесса с теми же правами пользователя. На неполном fence/потере канала -> unknown/partial. Детальная реализация framing требует fuzz tests и лимитов длины.

## 5. Readiness и submission

Для terminal_execute требуются write grant, writer lease, совпадающая generation, живое разрешённое view и подтверждённый prompt epoch. Idle подтверждается integration, а не regexp по `$`/`>`. Непустой input buffer, shell continuation prompt, interactive foreground process или неизвестное состояние -> NOT_AT_PROMPT/BUSY/UNSUPPORTED_CAPABILITY. Не стирать пользовательский незавершённый ввод.

Подтверждение пустого ZLE buffer/editor revision и отсутствие одновременного human writer — отдельный технический gate. Если backend не предоставляет атомарный guard, применяется явное локальное exclusive handoff; нельзя заявлять устранение гонок одним скриншотом перед вводом. Не защищать execute сравнением всего screen hash: часы/progress меняют экран и не означают смену цели.

Принимаемый `command` — literal shell input, выполняемый в **текущем shell**, без subprocess-per-request, subshell wrapper, `eval`, добавления `cd`, отключения terminal режима или подмены env. `cd`, export, функции и aliases должны сохранять обычную семантику. New session может иметь initial cwd; execute не имеет скрытого cwd override.

Многострочный input допускается только после отдельной проверки submission boundary/continuation. Одна заявка может быть foreground shell block/pipeline, не обязательно одним process. `exit`/`exec` требуют lifecycle reconciliation; без end event code не выдумывается. Не узнавать старый exit code отдельным `echo $?` после других команд.

## 6. State machine

```text
validated -> queued -> running -> completed
                ├-> cancelled (только до доставки)
                └-> unknown   (неоднозначная доставка)
running -> unknown            (потеря evidence / shell epoch)
unknown -> running|completed  (только при найденном подтверждении)
```

`queued` обычно краткая внутренняя стадия. Пользовательская очередь busy-команд disabled по умолчанию; при busy возвращается ошибка, а не вводится следующий command в текущую программу. При explicit queue request состояние возвращается отдельно, очередь bounded и очищается при revoke/смене epoch.

`running` требует подтверждённого command-start event, а не только write(bytes). Delivery имеет собственные значения `prepared|sent|acknowledged|indeterminate`. `completed` требует end event/lifecycle evidence. `success = exit_code == 0`, если code известен; иначе null. Ненулевой exit code — обычный результат инструмента, не MCP transport error.

`interaction` отдельно: `none|possible|confirmed|unknown`, с evidence. Silence не означает idle/completed и не доказывает stdin wait. Bounded wait timeout возвращает `wait_expired=true`, но не завершает job.

## 7. Exactly-once: граница обещания

Каждая mutation имеет client request_id. До dispatch атомарно сохранить intent с digest аргументов, target generation и lease. Повтор того же key/digest возвращает existing record; другой digest -> IDEMPOTENCY_CONFLICT. После crash между physical delivery и durable ack результат indeterminate; автоматическая повторная отправка запрещена.

Невозможно обещать exactly-once для произвольного GUI/PTY side effect только SQLite-транзакцией. Recover reconciliation использует shell event, command record, journal и epoch; при недостатке evidence требует ручного решения. Запись доставленного ввода нельзя отменить задним числом.

## 8. Последняя команда и output attribution

Command record хранит origin `agent|human|unknown`, literal command text или redacted marker, shell epoch, status evidence и output span references. Last query по умолчанию выбирает последний confirmed started record; queued доступен явно. Не подменять его history entry неизвестного времени.

Background jobs могут писать во время следующей команды. PTY уже объединил stdout/stderr. Поэтому per-command output — temporal interval с `attribution: foreground_interval|interleaved|unknown`, а не гарантированное владение каждым байтом конкретным PID. Native snapshots дополнительно `output_completeness: partial|unknown`. Exit status и полнота вывода независимы.

В SSH без remote integration локальная tracked-команда — сам ssh process. `ls`, набранный внутри SSH, является interaction, не новым независимо отслеженным local command. Аналогично REPL/DB/debugger. Запрос remote exit status не должен исполняться скрыто.

## 9. Input contract

terminal_send принимает массив операций text/paste/key, строгие размеры, явный terminator. text не добавляет Enter; key Enter отдельный. Коды Ctrl+C/Ctrl+D/Ctrl+Z передаются backend в текущем режиме, не заменяются SIGKILL. Unsupported backend key -> ошибка до доставки. Успешный send подтверждает только delivery. Multi-operation dispatch не объявлять атомарным; возвращать delivered operation count и неоднозначность при частичном сбое.

Все ограничения проверяются ещё раз непосредственно перед каждой операцией. Протокол, privacy и acceptance — [MCP](mcp-contract.md), [security](security.md), [tests](../guides/acceptance.md).
