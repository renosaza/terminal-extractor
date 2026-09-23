---
type: configuration-design
status: draft
---
# Проект настройки MCP-сервера

Ниже будущий интерфейс. Binary и installer пока отсутствуют; примеры не являются командой, которую уже можно запустить.

## Что выбирает пользователь

`terminal_app`: `ghostty` или `terminal`. `attach_policy`: `existing`, `new` или `ask`. `new_session_backend`: `managed_tmux` или `native`. Эти параметры независимы. Default: terminal_app=terminal, attach_policy=ask, new_session_backend=managed_tmux. Выбор Ghostty не требует менять весь MCP protocol.

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

Числа — предложенные defaults. Unknown keys и неверные enum отклоняются. Config version required. Secure local file update atomic; policy changes invalidate grants/caches при необходимости. Agent tools не редактируют этот файл и не могут сами включить clipboard/recording permissions.

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

CLI/config path -> env overrides -> local config -> documented defaults, но локальные security limits/allowed_apps/permissions не расширяются env из MCP. Env может сузить приложение/режим, не разрешить новые окна или снять consent. Per-call app override допускается только внутри локально разрешённого allowed set.

Предлагаемая CLI опция --config указывает локально разрешённый absolute path; path не берётся из terminal output. Host environment whitelist не наследует все credentials агента и не переносит их в новые shell sessions. Shell окружение сохраняется по явно описанной launch policy; audit не содержит values.

## Doctor

Будущий doctor выводит OS/arch, app paths/versions, dictionary fingerprints, TCC readiness, Swift/SDK build revision, tmux capabilities/path, registered shell integration и real test status. Он не снимает TCC, не меняет app config и не запускает команды в чужих открытых окнах. Проверка side effects только в созданной тестовой сессии с разрешением пользователя.
