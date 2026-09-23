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

Текущий промежуточный host принимает same-UID IPC и может показать локальный выбор Ghostty по запросу такого процесса. Выбор записывается только за этим connection и не открывает терминальный read/input (`terminal_access=false`). Перед включением этих операций нужны authenticated gateway, локальный Stop и проверка grants/epoch у dispatch.

## Grants и writer lease

Read и control выдаются отдельно; close и clipboard export — отдельные permissions. Не выдавать доступ ко всем окнам одной галочкой по умолчанию. Срок и scope grant видны локально. Любая операция заново проверяет target generation, client grant, privacy state и lease epoch непосредственно перед side effect.

Один агент-writer на session, несколько authorized readers допустимы. Для managed mode проверить explicit handoff через read-only user attach-client на время agent control и обратное включение после Take control. Не называть tmux read-only доказанным механизмом до TE-T020; проверить все attached clients, а не только один. Если backend не обеспечивает exclusive human/agent input, capability `exclusive_input_enforced=false` и UI описывает ручной режим.

Нельзя обещать автоматический отзыв при любом физическом нажатии клавиши без фактического input event source. Baseline — надёжное **явное** локальное Take control/Stop, не незаметный global event tap. Управление человеком всегда может быть возвращено вне MCP, даже если модель/компрессор зависли.

Revoke сначала атомарно увеличивает lease/grant epoch и блокирует новые dispatch, затем отменяет очередь и cleanup. Не ждать долгого Apple Event/Headroom. Уже переданные bytes и уже запущенную команду не отзывают; emergency interrupt — отдельное действие пользователя, не default kill. После revoke hidden queued input никогда не возобновляется.

## Privacy mode

Privacy pause прекращает agent input, capture, API reads/exports, command-text persistence и compression для выбранной сессии. До ввода секрета пользователь получает подтверждение переключения epoch. Уже отправленное модели удалить из её контекста через этот сервер невозможно.

После выхода нельзя автоматически reimport screen/scrollback с ещё видимым секретом: пользователь подтверждает безопасное состояние, либо screen read остаётся заблокирован. Recording resume создаёт gap/private omission. Не очищать историю терминала или shell history без отдельного разрешения. Пароль без echo не даёт полной гарантии: сама программа может позднее его напечатать.

Default diagnostics — IDs, durations, versions, state transitions, counts; без command text, terminal contents, env values и clipboard data. Explicit content recording требует согласия и retention notice. Redaction best-effort не называется гарантией обнаружения любого секрета. Raw originals находятся в private store; raw означает разрешённый исходный поток, не обязательное сохранение всего.

## Native export risks

Ghostty clipboard bridge использует только проверенные API/actions и явно сообщается. Clipboard backup — только локальная память helper, не tool output. Не читать путь из clipboard без ownership/fstat/path validation. На конфликт fail closed. Обнаружение чужого файла не даёт прав агенту его читать. Ограничить частоту и размер export. Perfect clipboard restoration не гарантировать из-за внешних writers и watchers.

## Недоверенный terminal output

Текст может содержать инструкции агенту, OSC title changes, clipboard OSC52, fake completion markers и бесконечные sequences. Хост не исполняет их как policy или code. Проекция текста нейтрализует управляющие последовательности и опасные control chars вне явного raw-export режима. Нормализатор bounded, защищён от огромной строки/UTF-8 fragmentation и parser DoS. Обычный терминал продолжает обрабатывать свои escape sequences по собственным настройкам; наш read path не должен повторно воспроизводить их на другом терминале.

Completion markers принимаются только в зарегистрированном shell epoch и с ожидаемым sequence, а не по похожей строке. При ошибке evidence unknown. Чтение лога модели сопровождается provenance и границей недоверенных данных, но prompt annotation сама по себе не считается защитой.

## Проверки

Обязательны: unauthorized read/write/search/retrieve; target reuse; clipboard race/path attack; stale grant; concurrent agents; delayed dispatch after revoke; private-mode cache leaks; same request replay; hostile OSC/fake hooks; malformed frames; terminal crash; storage full. Реальный macOS TCC/GUI тест отделяется от unit mocks. См. [приёмку](../guides/acceptance.md).
