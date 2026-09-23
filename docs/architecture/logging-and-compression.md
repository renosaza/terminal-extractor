---
type: technical-spec
status: draft
---
# Журнал, последняя команда и сжатие

## Три разные вещи

Текущий **screen** — состояние терминальной сетки. **Scrollback** — сохранённая приложением история строк, которая могла быть очищена/ограничена. **Journal** — события и разрешённый поток, записанные нашим recorder в указанном интервале. Их нельзя смешивать в одно обещание «всё, что когда-либо было в окне».

Native attach импортирует доступный scrollback отдельно от нового recording. Не назначать каждой импортированной строке текущий timestamp как время выполнения. Сохранять imported_at и `original_time: unknown`. Shell history может быть дополнительной неподтверждённой справкой, но не источником output/exit codes.

## Модель хранения

SQLite таблицы проектируются для sessions, view_bindings, grants, command_records, capture_epochs, segments, gaps, compact_objects и schema_version. Raw/output bytes лежат в bounded append-only segment files. Для каждого сегмента: session/generation, capture_epoch, first/last sequence, byte length, content hash, encoding metadata, creation/seal time и policy version.

События имеют `seq`, `observed_at`, monotonic ordering внутри процесса, source, privacy epoch и payload type. Byte offset не равен номеру Unicode-символа. Cursor opaque и versioned; он привязан к session/generation/representation/filter/high_watermark. Нельзя применить cursor другой сессии и получить её данные.

Одно SQLite writer соединение сериализует metadata changes; segment flush/DB commit согласуются через recovery journal. После crash незавершённый segment проверяется/truncated только до подтверждённой границы записи; потерянный interval отображается как gap. Не утверждать fsync per byte или zero-loss после power failure без benchmark/реализации.

## Проекции

1. Разрешённый исходный terminal stream — контрольное представление в пределах recording interval, за исключением явно исключённых private ranges.
2. Нормализованный transcript — readable text с source offsets; CR/backspace/erase semantics сохраняются в provenance. Он не заменяет screen state.
3. Screen snapshot — сетка, cursor, buffers, wrap/attributes при доступности backend.
4. Command output view — ссылки на intervals между зарегистрированными boundaries, с temporal/interleaved attribution.
5. Compact view — производное представление плюс доступ к оригиналу.

stdout/stderr после PTY не разделяются достоверно. Поздний background output не приписывается автоматически последней foreground-команде. Native screen + scrollback snapshots не конкатенируются без проверки overlap; при изменениях между export сохраняются отдельные observed_at и non-atomic snapshot marker.

## Полнота и retention

`complete_for_interval=true` допустим только при непрерывном recorder stream внутри объявленного интервала и отсутствии gaps/private omissions. Это не означает полноту «за всю жизнь терминала». При attach к старому managed pane до старта recorder прошлые данные также ограничены доступным scrollback.

Quota/age limits показываются до recording. При ротации возвращаются earliest_available_cursor, deleted ranges и reason. Попытка прочитать старое => CURSOR_EXPIRED/CONTENT_EXPIRED, а не пустой успешный результат. Активные command metadata не удаляются молча вместе с сегментом; output_refs становятся expired с tombstone.

Disk full/slow consumer/recorder restart имеют явные события. Предлагается bounded buffering с pause recording или маркированным loss согласно локальной policy; никогда не блокировать Stop и не скрывать потерю. Нельзя автоматически удалять чужие terminal logs, Shell History или пользовательские файлы для освобождения места.

## Чтение всего лога

Первая страница фиксирует snapshot high_watermark и возвращает manifest. Далее paging выдаёт полный доступный диапазон до него. Новые события читаются новой cursor-chain; бесконечный log не мешает закончить экспорт. Range можно ограничить command_id, capture_epoch, timestamps и offsets. Search v1 literal, bounded и с cancellation; регулярные выражения/неограниченный grep не нужны.

Local export создаётся только в управляемом private каталоге; tool получает opaque ID и content metadata, а не arbitrary filesystem capability. Экспорт в выбранный пользователем каталог — отдельное локальное действие. Диагностика не прикладывает содержимое export автоматически.

## Сжатие контекста

ZIP/gzip уменьшает байты на диске/транспорте, но само по себе не даёт читаемый короткий контекст модели. Нужны **ограничение объёма, выбор нужного диапазона, представление и retrieval**.

Default compact pipeline: проверить права -> определить representation -> применить privacy policy -> закрепить оригинал и его hash -> выбрать head/tail/window/error contexts -> свернуть точные повторения с count и offset ranges -> выдать compact text и original content_id. Это отбор/представление, а не обещание математически lossless краткого текста. Exact mode всегда paginated.

Всегда сохранять без потерь поля status, exit_code, success, command/session IDs, generation, request IDs, uncertainty, coverage, warnings, counts и cursor. Текущий интерактивный экран, точные пути/команды для следующего действия, приглашение пароля/подтверждения и patch/code, который будут исполнять, не пропускать через lossy compressor. Не вставлять summary назад в терминал.

Ошибки и stack traces защищаются правилами, но regex по ERROR/FATAL не гарантирует сохранение всех значимых данных. Поэтому automatic compression не получает статус «без потерь» и проходит task-oriented fidelity corpus. При low confidence отдавать bounded exact excerpt и возможность дочитать.

## Headroom

Headroom исследован как существующая локальная библиотека/инструмент с retrieval исходников [S13](../research/sources.md). Маркетинговые проценты экономии не являются SLA этого проекта. Не копировать их в README как наши измерения.

Adapter — optional isolated worker, вызываемый на выбранном output body, а не proxy всей переписки/всех API credentials. Core metadata никогда не передаётся на преобразование. Вход worker: schema_version, request_id, authorized text fragment, allowed policy и budget. Выход: transformed text, algorithm/version, warnings, reported metrics. Наш archive остаётся authoritative для original retrieval независимо от внутреннего CCR store Headroom.

Зафиксировать проверенный package release, зависимости и hashes после TE-T034. Base algorithms без ML — предпочтительный первый эксперимент. Любые веса, сеть, auto-download, cross-agent memory и обучение на логах disabled по умолчанию. Ошибка/timeout worker -> безопасное bounded представление, а не отправка всего мегабайтного лога в контекст. Падение compressor не останавливает терминал.

Cache key включает content hash, session/generation, privacy/grant epoch, policy version, algorithm version и budget. Никакого cross-session cache hit, раскрывающего наличие чужих данных. При revoke/delete/private-mode invalidation удаляются соответствующие compact entries, retrieval заново проверяет ACL. Headroom ID не заменяет наши права.

## Метрики и критерии

Отдельно измерять original/returned bytes, measured tokens с указанным tokenizer либо estimated_tokens с методикой, CPU/RSS, warm/cold latency и retrieval rate. Не сравнивать tokens одного tokenizer с другим и не называть char/4 точным счётом для русского/кода.

Corpus: повторяющиеся build logs; уникальная ошибка в середине; русские сообщения; Unicode; большие JSON; shell table; длинный stack trace; background output; повторяющиеся строки, различающиеся одним числом; secret markers. Для каждого задания проверяются сохранение ответообразующих фактов, ошибки, пути, коды, порядок событий и восстановление exact original.

Процент экономии — результат benchmark, не обязательное фиксированное обещание. Условие приемлемости: все protected-field tests pass; exact retrieval совпадает с source bytes в разрешённом диапазоне; нет silent truncation; regression budget опубликован. Связанные задачи: TE-T025..028, TE-T033..036.
