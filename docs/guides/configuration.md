---
type: configuration-design
status: draft
---
# Проект настройки MCP-сервера

Product CLI host/gateway и локальный JSON config уже существуют как foundation. Installer, menu UI и terminal session tools ещё отсутствуют; примеры установки клиента ниже пока не являются готовой командой.

## Что выбирает пользователь

`terminal_app`: `ghostty` или `terminal`. `attach_policy`: `existing`, `new` или `ask`. `new_session_backend`: `managed_tmux` или `native`. Эти параметры независимы. Default: terminal_app=terminal, allowed_apps=[terminal, ghostty], attach_policy=ask, new_session_backend=managed_tmux. Выбор Ghostty не требует менять весь MCP protocol.

Приложение по умолчанию — не автоматический выбор target. Existing attach всё равно требует конкретную разрешённую вкладку/панель. Если приложение не установлено или запрещено TCC, вернуть явную ошибку, а не запустить другое.

## JSON config проекта

Предлагаемый локальный файл: `~/Library/Application Support/TerminalExtractor/config.json`.

```json
{
  "schema_version": 1,
  "terminal_app": "ghostty",
  "allowed_apps": ["terminal", "ghostty"],
  "attach_policy": "ask",
  "new_session_backend": "managed_tmux",
  "shell_integration": "zsh_opt_in",
  "native_ghostty_clipboard_export": false,
  "recording": {
    "consent_required": true,
    "session_limit_bytes": 268435456,
    "total_limit_bytes": 2147483648,
    "retention_days": 7
  },
  "output": {
    "default_representation": "compact",
    "target_estimated_tokens": 4000,
    "hard_max_bytes": 65536,
    "compressor": "builtin",
    "headroom_enabled": false
  },
  "execution": {
    "default_wait_ms": 1000,
    "max_wait_ms": 20000,
    "busy_queue_enabled": false
  }
}
```

Числа — текущие defaults модели. Существующий файл требует `schema_version: 1`; пропущенные поля получают defaults, unknown keys и неверные enum отклоняются. Файл читается только как regular file текущего пользователя с приватными правами; запись идёт атомарной заменой в каталоге `0700`, файл `0600`. Старой развёрнутой схемы нет: другие версии пока отклоняются без миграции. Agent tools не редактируют этот файл и не могут сами включить clipboard/recording permissions.

## Подключение к Codex

[Официальная основа конфигурации](../research/sources.md#s12--codex-как-mcp-клиент). После реализации/установки предполагается такая запись; путь заменяется installer на фактический:

```toml
[mcp_servers.terminal_extractor]
command = "/Applications/TerminalExtractor.app/Contents/MacOS/terminal-extractor"
args = ["mcp"]
startup_timeout_sec = 15
tool_timeout_sec = 30

[mcp_servers.terminal_extractor.env]
TERMEX_TERMINAL = "ghostty"
TERMEX_ATTACH_POLICY = "ask"
TERMEX_NEW_BACKEND = "managed_tmux"
```

Для Terminal.app изменить только TERMEX_TERMINAL на `terminal`. Это **наши** env variables, не встроенный dropdown MCP. Произвольный MCP-клиент не обязан рисовать настройки; выбор реализуется config/env и локальным меню.

Для MCP-клиентов с JSON mcpServers после реализации:

```json
{
  "mcpServers": {
    "terminal_extractor": {
      "command": "/Applications/TerminalExtractor.app/Contents/MacOS/terminal-extractor",
      "args": ["mcp"],
      "env": {
        "TERMEX_TERMINAL": "ghostty",
        "TERMEX_ATTACH_POLICY": "ask",
        "TERMEX_NEW_BACKEND": "managed_tmux"
      }
    }
  }
}
```

Формат конкретного второго клиента проверяется TE-T032; generic example не доказывает его настройку. Два server aliases для двух приложений допустимы, но broker остаётся один, grants различаются и state не дублируется.

## Приоритет настроек и запреты

Host `--config` выбирает локальный абсолютный JSON path; иначе используется путь выше. Приоритет выбора: env preferences gateway -> локальный JSON host -> documented defaults. Host применяет `TERMEX_TERMINAL`, `TERMEX_ATTACH_POLICY`, `TERMEX_NEW_BACKEND` и возвращает результат через `terminal_capabilities`. `TERMEX_TERMINAL` обязан входить в локальный `allowed_apps`; другие `TERMEX_*` сейчас отклоняются. Env не меняет `allowed_apps`, limits, clipboard/recording consent или grants. `attach_policy=new` и backend `native` являются запросом режима, а не разрешением: создание окна потребует отдельного локального grant, когда session runtime появится.

`--config` принимает только абсолютный путь при локальном запуске host; отсутствующий явно указанный файл — ошибка без fallback на defaults. Path не берётся из terminal output или MCP tool. Host environment whitelist не наследует все credentials агента и не переносит их в новые shell sessions. Shell окружение сохраняется по явно описанной launch policy; audit не содержит values.

## Doctor

Будущий doctor выводит OS/arch, app paths/versions, dictionary fingerprints, TCC readiness, Swift/SDK build revision, tmux capabilities/path, registered shell integration и real test status. Он не снимает TCC, не меняет app config и не запускает команды в чужих открытых окнах. Проверка side effects только в созданной тестовой сессии с разрешением пользователя.
