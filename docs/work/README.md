---
type: roadmap
status: draft
---
# План реализации: 12 эпиков, 48 задач

Каноническое состояние работы находится в `tasks/TE-T*.md`, состояние эпиков — в `epics/TE-E*.md`. Эта страница описывает порядок и связи, а не вторую изменяемую доску. GitHub Issues пока не используются. Все runtime outcome требуют фактической проверки; документация не означает реализованную функцию.

## Эпики

| Эпик | Результат | Карточки |
|---|---|---|
| [TE-E01](epics/TE-E01.md) | Проверенные возможности API и feasibility gate | TE-T001–004 |
| [TE-E02](epics/TE-E02.md) | Native host, настройки, grants и registry | TE-T005–008 |
| [TE-E03](epics/TE-E03.md) | Existing/new adapter Terminal.app | TE-T009–012 |
| [TE-E04](epics/TE-E04.md) | Existing/new adapter Ghostty | TE-T013–016 |
| [TE-E05](epics/TE-E05.md) | Общая видимая managed-сессия | TE-T017–020 |
| [TE-E06](epics/TE-E06.md) | Команды, evidence, last command и recovery | TE-T021–024 |
| [TE-E07](epics/TE-E07.md) | Журнал, paging, search и retention | TE-T025–028 |
| [TE-E08](epics/TE-E08.md) | MCP-контракт и два клиента | TE-T029–032 |
| [TE-E09](epics/TE-E09.md) | Сжатие и восстановление оригинала | TE-T033–036 |
| [TE-E10](epics/TE-E10.md) | Consent, Stop, privacy и отказоустойчивость | TE-T037–040 |
| [TE-E11](epics/TE-E11.md) | Fixtures, real GUI, chaos и release gates | TE-T041–044 |
| [TE-E12](epics/TE-E12.md) | Подписанная поставка, установка и выпуск | TE-T045–048 |

## Этапы и критерии перехода

**M0 — проверить осуществимость.** TE-T001..004 исследуют API, hooks и stack. Результат — версия-зависимая capability matrix, прототипы и открытые blockers. Native Terminal.app arbitrary keys не закрываются предположением. Переход к core допускает явно ограниченный native mode; формулировка полного Existing остаётся заблокированной до доказательства.

**M1 — вертикальный срез.** Host/registry, оба app adapters и managed pane. Открыть окно выбранного приложения, продолжить existing fixture без смены процесса, выполнить одну команду с достоверным статусом и прочитать её текст. T041 fixtures стартует рано, не после завершения всех функций.

**M2 — устойчивый контракт.** Commands/journal/MCP, ACL/Stop/privacy и два клиента. Poll не исполняет команду, страницы восстанавливают available interval, unknown не маскируется под успех. Runtime input не использует текущий focus.

**M3 — экономия контекста и нагрузка.** Builtin bounded views обязательны; Headroom экспериментируется отдельным worker и не блокирует базовый запуск. Публикуются fidelity/retrieval/performance результаты. При провале Headroom сохраняется builtin без скрытой отправки полного лога.

**M4 — продуктовая поставка.** Реальный GUI acceptance на обоих приложениях, signing/install/uninstall, версия-зависимая документация, release audit. Публиковать ограниченный релиз можно только с точным перечнем unsupported capabilities; он не закрывает невыполненные требования полного Existing.

После проверки PR #6 ближайшие независимые gates таковы: TE-T015 должен получить положительный scrollback export на контролируемой Ghostty pane с подтверждённой retained history; TE-T038 — живой Stop во время работающего screen export. Три живых screen reads и синтетическая гонка уже проверены, но не заменяют эти два результата. Параллельно можно готовить managed shared-pane capture и command evidence (TE-T017/019/021/025/041): именно они нужны для достоверного exit status, пока native snapshot даёт только текст. Managed-путь не закрывает требования к уже видимой native-сессии; Terminal.app no-Enter/input gate и Ghostty input/scrollback gate остаются отдельными. MCP read/status и двухклиентная приёмка следуют за реальным command/journal evidence, а не за одними схемами.

## Параллельная работа

После M0 допустимы независимые writers: Terminal.app adapter, Ghostty adapter, core/journal, shell integration и MCP schemas. Общие schema/registry файлы имеют одного владельца; интерфейсы согласуются до параллельной реализации. Compression начинается после нормализованного output contract, packaging — после решения по host identity/TCC. Security design входит с начала, а не добавляется после API.

Точная DAG хранится в `depends_on` карточек. Последовательность критического пути проходит feasibility -> core/identity и локальные grants/Stop -> app bindings + managed capture -> доказательные command/journal reads -> MCP -> реальные GUI/race checks -> integrated acceptance -> release audit. Optional Headroom не блокирует builtin fidelity/retrieval gate. Это порядок зависимостей, не обещание календарных сроков.

## Работа с карточкой

Назначить owner, проверить dependencies и применимые TE-C IDs. Реализовать bounded scope, приложить тесты. Перед done заполнить Result: observed outcome, checks, checked commit. Не переносить все эпики в done после одной демонстрации. Для нового blocker сохранить evidence и изменённый следующий шаг в карточке, не заводить второй tracker.

Связи: [PRD](../product/prd.md), [приёмка](../guides/acceptance.md), [правила](../style.md).
