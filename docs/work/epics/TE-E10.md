---
id: TE-E10
type: epic
status: draft
task_status: active
scope: safety-and-recovery
---
# Локальное согласие, Stop и защита данных

## Результат

Видимый per-session consent, отзыв управления без модели, privacy epochs и воспроизводимое поведение при отказах.

## Завершён, когда

TCC не обходится, Stop не ждёт helper/worker, уже доставленный ввод не объявляется отменённым. Privacy не реимпортирует секреты, logs metadata-only. Stale identity/markers/clipboard paths не дают доступ к чужим данным.

## Ограничения

TE-C03..07, TE-C09. Не обещать sandbox или автоматический перехват любого human key без реального источника событий.

## Задачи

[TE-T037](../tasks/TE-T037.md), [TE-T038](../tasks/TE-T038.md), [TE-T039](../tasks/TE-T039.md), [TE-T040](../tasks/TE-T040.md).

[Security design](../../architecture/security.md).

Промежуточный локальный Stop и grant epoch реализованы в [TE-T038](../tasks/TE-T038.md). Синтетическая проверка подтвердила отзыв при блокированном export action и прекращение обмена через текущие client sockets. В живом screen request Stop подтвердился после создания файла экспорта и до ответа MCP; текст не выдан. Пересечение с ещё выполняющимся Apple Event не доказано. Menu-bar UI и privacy mode отсутствуют; bounded Ghostty screen read существует только с отдельным локальным согласием.
