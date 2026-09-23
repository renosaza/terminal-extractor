---
type: code-discovery
status: draft
---
# Поиск кода и покрытие графа

Runtime source отсутствует; code graph не строился. Покрытие исходного кода: нет объектов для индексации. Не трактовать отсутствие индекса как доказательство отсутствия будущих зависимостей.

Сейчас навигация выполняется через [index](../index.md), [архитектуру](../architecture/README.md) и [task cards](../work/README.md). После появления кода использовать поиск по реальным именам пакетов, symbols и tests. Инструмент графа выбирать только после проверки поддержки Swift и фактического масштаба проекта. Не устанавливать graph service ради пустой схемы.

Если индекс будет введён, записать included/excluded paths, unsupported dynamic edges, build command и indexed revision/content fingerprint. Пока эти поля неприменимы; вымышленного graph artifact нет.
