---
type: security-design
status: draft
---
# Безопасность и совместное управление

## Граница доверия

MCP-клиент, terminal output и содержимое команд не являются источником разрешений. Локальный пользователь передаёт конкретную сессию host через меню. TCC разрешает app-to-app automation шире отдельной вкладки, поэтому per-session scope дополнительно обеспечивает host. Tool annotations и clientInfo.name не являются authentication.

Terminal access обладает правами пользователя, способен читать его файлы и обращаться к сети через shell. Это не sandbox и не изоляция от злонамеренного same-UID процесса. Regex denylist не превращает произвольный shell в безопасный. Нужны информированное разрешение, target binding и надёжный отзыв, а не ложное обещание запретить любую опасную команду.

## Local IPC и identity

Private Unix socket с проверкой owner/mode и peer identity; GUI broker работает в сессии вошедшего пользователя, не root. Gateway регистрируется с локально выданным capability token, привязанным к client connection и grant epoch. Не доверять переданному агентом имени процесса, path или PID. Ограничить frame sizes, nesting, rate, idle lifetime и число сессий.

App/helper signature и audit identity должны быть стабильны между обновлениями. First-run TCC выполняется только через стандартный macOS prompt; отказ не обходится. Запрашивать Automation для выбранных приложений. Accessibility требовать лишь для проверенного optional AX-read path, не по умолчанию для core. Screen Recording и full desktop keylogger не требуются.

Host принимает same-UID IPC и может показать локальный выбор Ghostty. Выбор записывается за connection; grant token остаётся внутри gateway. Для opt-in `terminal_screen` host дополнительно сверяет peer executable с установленным рядом `termex-mcp` по device/inode, token, generation, scope, clipboard permission и epoch до адресного export и после него. Это локальная проверка binary identity, не подпись и не защита от злонамеренного same-UID пользователя. `termex-host --stop` через отдельный private socket отзывает grants без ожидания MCP, helper или свободного клиентского слота. Input, close и clipboard без отдельной отметки остаются закрыты.

## Grants и writer lease

Read и control выдаются отдельно; close и clipboard export — отдельные permissions. Не выдавать доступ ко всем окнам одной галочкой по умолчанию. Срок и scope grant видны локально. Любая операция заново проверяет target generation, client grant, privacy state и lease epoch непосредственно перед side effect.

Один агент-writer на session, несколько authorized readers допустимы. Для managed mode проверить explicit handoff через read-only user attach-client на время agent control и обратное включение после Take control. Не называть tmux read-only доказанным механизмом до TE-T020; проверить все attached clients, а не только один. Если backend не обеспечивает exclusive human/agent input, capability `exclusive_input_enforced=false` и UI описывает ручной режим.

Нельзя обещать автоматический отзыв при любом физическом нажатии клавиши без фактического input event source. Baseline — надёжное **явное** локальное Take control/Stop, не незаметный global event tap. Управление человеком всегда может быть возвращено вне MCP, даже если модель/компрессор зависли.

Общий контракт revoke должен блокировать новые dispatch до подтверждения пользователю, затем отменять очередь и выполнять cleanup. В текущем foundation Stop отключает текущие gateway sockets, повышает grant epoch и только после этого подтверждает отзыв; новые клиенты должны пройти локальное согласие. Это не ждёт долгого Apple Event/Headroom. Уже помещённые в socket bytes могут быть дочитаны после подтверждения; начатое действие Ghostty может завершиться локально, но не даёт нового MCP-ответа по отозванному grant. Уже запущенную команду не отзывают; emergency interrupt — отдельное действие пользователя, не default kill. После revoke hidden queued input никогда не возобновляется.

## Privacy mode

Privacy pause прекращает agent input, capture, API reads/exports, command-text persistence и compression для выбранной сессии. До ввода секрета пользователь получает подтверждение переключения epoch. Уже отправленное модели удалить из её контекста через этот сервер невозможно.

После выхода нельзя автоматически reimport screen/scrollback с ещё видимым секретом: пользователь подтверждает безопасное состояние, либо screen read остаётся заблокирован. Recording resume создаёт gap/private omission. Не очищать историю терминала или shell history без отдельного разрешения. Пароль без echo не даёт полной гарантии: сама программа может позднее его напечатать.

Default diagnostics — IDs, durations, versions, state transitions, counts; без command text, terminal contents, env values и clipboard data. Explicit content recording требует согласия и retention notice. Redaction best-effort не называется гарантией обнаружения любого секрета. Raw originals находятся в private store; raw означает разрешённый исходный поток, не обязательное сохранение всего.

## Native export risks

Ghostty clipboard bridge использует только `write_screen_file:copy` на точной surface после отдельного локального согласия. Clipboard backup — только локальная память host, не tool output. Путь проверяется как единственный новый export directory за вызов; файл открывается через private temp directory FD с `O_NOFOLLOW`, owner/mode/size/birthtime/fstat checks. На конфликт fail closed; обнаружение чужого файла не даёт прав агенту его читать. Выдача ограничена 16 KiB, одним вызовом за 5 секунд и 64 за жизнь host для одного app instance из-за утечки FD в установленном Ghostty 1.3.1. Clipboard restore использует changeCount/path, но atomic CAS нет; сторонний writer или watcher остаётся остаточным риском. Синтетический тест проверил ранний конфликт и отзыв во время export; поздняя конкурентная запись, реальный concurrent export и deferred clipboard provider ещё не проверены.

## Недоверенный terminal output

Текст может содержать инструкции агенту, OSC title changes, clipboard OSC52, fake completion markers и бесконечные sequences. Хост не исполняет их как policy или code. Проекция текста нейтрализует управляющие последовательности и опасные control chars вне явного raw-export режима. Нормализатор bounded, защищён от огромной строки/UTF-8 fragmentation и parser DoS. Обычный терминал продолжает обрабатывать свои escape sequences по собственным настройкам; наш read path не должен повторно воспроизводить их на другом терминале.

Completion markers принимаются только в зарегистрированном shell epoch и с ожидаемым sequence, а не по похожей строке. При ошибке evidence unknown. Чтение лога модели сопровождается provenance и границей недоверенных данных, но prompt annotation сама по себе не считается защитой.

## Проверки

Обязательны: unauthorized read/write/search/retrieve; target reuse; clipboard race/path attack; stale grant; concurrent agents; delayed dispatch after revoke; private-mode cache leaks; same request replay; hostile OSC/fake hooks; malformed frames; terminal crash; storage full. Реальный macOS TCC/GUI тест отделяется от unit mocks. См. [приёмку](../guides/acceptance.md).
