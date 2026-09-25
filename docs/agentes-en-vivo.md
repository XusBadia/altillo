# Agentes en vivo: investigación (septiembre 2026)

Hay que volver a verificar los campos exactos contra la versión instalada de cada CLI antes de implementar, porque cambian rápido.

## Verificado contra las CLI instaladas (25-09-2026)

Claude Code **2.1.281** y Codex **0.152.0**, con la documentación actual ([Claude](https://code.claude.com/docs/en/hooks), [Codex](https://developers.openai.com/codex/hooks), [esquemas de Codex](https://github.com/openai/codex/tree/main/codex-rs/hooks/schema/generated)). Los payloads reales están en `Packages/AltilloKit/Tests/AltilloAgentsTests/Fixtures/` (anonimizados; los `*.docs.json` siguen el esquema documentado para los eventos que una ejecución headless no puede disparar). Se capturaron con `claude -p … --settings <temporal> --setting-sources local` y `codex exec --dangerously-bypass-hook-trust -c 'hooks.<Evento>=[…]'`, sin tocar `~/.claude/settings.json` ni `~/.codex/`.

### Claude Code

- **Configuración:** `~/.claude/settings.json` (usuario), `.claude/settings*.json` (proyecto), `--settings` y plugins. Handlers `command` (forma shell o exec con `args`), `http`, `mcp_tool`, `prompt`, `agent`.
- **Entrada común (capturada):** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `prompt_id` (desde el primer prompt), `permission_mode` (casi todos). Dentro de un subagente, también `agent_id` y `agent_type`.
- **Por evento (capturado salvo donde se indica):**
  - `SessionStart`: `source` (`startup|resume|clear|compact|fork`), `model` opcional.
  - `UserPromptSubmit`: `prompt`.
  - `PreToolUse` / `PostToolUse`: `tool_name`, `tool_input`, `tool_use_id`; `PostToolUse` añade `tool_response` y `duration_ms`. `PostToolUseFailure`: `error`, `is_interrupt`.
  - `PermissionRequest`: `tool_name`, `tool_input`, **sin** `tool_use_id`, y `permission_suggestions` (p. ej. `addDirectories` + `setMode acceptEdits`, ya con `destination: "session"`).
  - `Stop`: `last_assistant_message`, `stop_hook_active`, `background_tasks`, `session_crons`. `SubagentStart`/`SubagentStop`: `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`.
  - `SessionEnd`: `reason` (`clear|resume|logout|prompt_input_exit|other`). Presupuesto de 1,5 s.
  - Según la documentación: `StopFailure` (`error`: `rate_limit`, `overloaded`, `authentication_failed`…; `last_assistant_message` es el texto del error) y `Notification` (`notification_type`: `permission_prompt` tras ~6 s sin teclear, `idle_prompt` ~60 s después de terminar, `agent_needs_input`, `elicitation_dialog`…, más `message` y `title`).
- **Respuesta a `PermissionRequest` (probada en vivo con `altillo-hook`):** `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`; para denegar, `"behavior":"deny","message":"…"`. El `permissionDecision` de la versión anterior de este documento es de **`PreToolUse`**, no de `PermissionRequest`.
- **«Permitir en esta sesión»:** `decision.updatedPermissions` con las `permission_suggestions` que Claude propuso, forzando `destination: "session"` (nunca se escribe en los ficheros de ajustes), solo `addRules` (allow), `addDirectories` y `setMode acceptEdits`, más una regla exacta para el comando Bash. Probado: el segundo `touch` idéntico ya no pidió permiso.
- **Sin decisión** (timeout, Altillo cerrado): el hook no imprime nada. En la TUI, Claude pregunta como siempre; en `-p`, lo deniega. `exit 2` no decide en `PermissionRequest`.
- **Timeouts:** 600 s por defecto (30 s en `UserPromptSubmit`). Un hook cancelado por timeout no decide nada.
- **Entorno del hook:** los hooks corren sin terminal de control. Claude exporta `CLAUDE_PID`, `CLAUDE_PROJECT_DIR`, `CLAUDE_CODE_ENTRYPOINT`; el entorno heredado trae `__CFBundleIdentifier` de la app que lanzó el terminal (p. ej. `com.googlecode.iterm2`), `TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`…
- **Sin verificar:** si la TUI muestra su propio diálogo mientras un `PermissionRequest` espera (una carpeta sin confianza en la CLI bloqueó la prueba). El diseño funciona en ambos casos: si el usuario contesta en la terminal y Claude mata el hook, el hub ve el cierre de la conexión y retira la petición.

### Codex

- **Configuración:** `~/.codex/hooks.json` o `[hooks]` en `config.toml` (usuario o `<repo>/.codex/`). **Los hooks que no son gestionados solo se ejecutan si el usuario los ha revisado y marcado como de confianza en `/hooks`** (se guarda el hash; si cambia el comando, hay que volver a confiar). `--dangerously-bypass-hook-trust` lo salta en una sola invocación.
- **Eventos:** `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`. No hay `Notification` ni `StopFailure`: una sesión que falla por la API no dispara `Stop` (comprobado).
- **Entrada (capturada `SessionStart`, `UserPromptSubmit`, `SessionEnd`; el resto según los esquemas):** `session_id` (el mismo UUID que el nombre del rollout), `transcript_path` (el rollout), `cwd`, `hook_event_name`, `model`, `permission_mode`, y `turn_id` en los de turno. `Bash` y `apply_patch` usan `tool_input.command` (en `apply_patch`, el parche entero). `Stop` trae `last_assistant_message`.
- **Respuesta a `PermissionRequest`:** `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny","message":"…"}}}`. `updatedPermissions`, `updatedInput` e `interrupt` están reservados y **fallan en cerrado**, así que «permitir en esta sesión» se envía como `allow` normal. Si nadie decide, Codex sigue con su aprobación normal.
- **Salida:** `Stop`, `SubagentStop` e `Interrupt` rechazan texto plano en stdout; salir con 0 y sin salida es válido.
- **Timeouts:** 600 s por defecto; `SessionEnd` e `Interrupt`, 1 s (máximo 3).
- **No se pudo probar en vivo:** `PreToolUse`, `PostToolUse`, `PermissionRequest` y `Stop` de Codex, porque la cuenta llegó al límite de uso hasta el 26-09-2026. Hay fixtures del esquema documentado.

### Ficheros de sesión (detección pasiva, sin hooks)

- **Claude Code:** `~/.claude/projects/<cwd con / y . cambiados por ->/<session id>.jsonl`. Entradas `user`/`assistant` con `message.content` (texto o bloques `text`, `thinking`, `tool_use`, `tool_result`), `message.stop_reason` (`tool_use`, `end_turn`…), `cwd`, `timestamp`, `isSidechain` y `entrypoint` (`cli`; `sdk-ts` para apps como T3 Code; `sdk-cli` para `claude -p`). El resto (`attachment`, `system`, `last-prompt`, `ai-title`, `cost-state`, `queue-operation`, `mode`…) es contabilidad. Los subagentes van en `<session>/subagents/` y se ignoran.
- **Codex:** `~/.codex/sessions/AAAA/MM/DD/rollout-<fecha>-<session id>.jsonl`. La primera línea es `session_meta` (`id`, `cwd`, `originator`: `codex_exec`, `codex_cli_rs`, apps; `source`: `exec`/`cli`/`vscode` o `{"subagent":…}`; `thread_source`: `user`, `automation` o `subagent`). Después vienen `turn_context` (`cwd`), `response_item` (`message` con `phase` `commentary`/`final_answer`, `function_call`, `custom_tool_call`, sus `*_output`, `reasoning`) y `event_msg` (`task_started`, `task_complete` con `last_agent_message`, `turn_aborted`, `item_completed`, `token_count`).
- **Fase inferida:** trabajando si lo último es un prompt, una llamada a herramienta o su resultado; esperando respuesta tras un mensaje final (`end_turn` / `task_complete`); inactiva tras una interrupción. `claude -p` y `codex exec` pasan a terminadas. Se ignoran los subagentes y las automatizaciones de Codex. Solo se lee la cola (192 KB) del fichero que cambió.

## Otros agentes (fase posterior)

| Agente | Mecanismo |
|---|---|
| Gemini CLI | Hooks en `settings.json`: `BeforeTool`, `AfterAgent`, `Notification` (inactivo, espera respuesta o confirmación), `SessionStart/End` |
| Copilot CLI | Hooks en `~/.copilot/hooks/*.json`: `preToolUse`, `permissionRequest`, `notification`, `agentStop`, `sessionStart/End` |
| OpenCode | `opencode serve`, con SSE en `/event`: `session.idle`, `session.status`, `permission.asked` |
| Cursor CLI | Sin hooks en la CLI (solo en el IDE); `cursor-agent acp` (JSON-RPC) como alternativa |

## Apps existentes (competencia y referencia)

| App | Licencia | Transporte | ¿Permite aprobar? |
|---|---|---|---|
| Vibe Island (antes Claude Island / vibe-notch) | Cerrada (la antigua era Apache 2.0) | Socket Unix | Sí, y revisión de planes |
| ClaudeNotch | PolyForm Noncommercial | HTTP a localhost con la conexión abierta hasta decidir; si hay timeout o la app está cerrada, se vuelve al prompt | Sí (con Touch ID en comandos arriesgados) |
| Notchi | GPL-3 | Socket Unix | — |
| NotchStatus | MIT | Fichero JSON por sesión + FSEvents | No |
| NotchAgent | MIT | Socket `/tmp/notch-agent.sock`, sin esperar respuesta | No |

Es un nicho con mucha actividad. Lo que diferencia a Altillo es combinarlo con el shelf, el uso de IA, la app de iOS y la Dynamic Island, y la calidad de la UX.

## Live Activities (iPhone)

- **Push:** requiere APNs con **autenticación por token** (`.p8`), con las cabeceras `apns-push-type: liveactivity` y `apns-topic: <bundle>.push-type.liveactivity`, y prioridad 5 o 10. *Push-to-start* existe desde iOS 17.2.
- **El Mac puede ser el proveedor:** basta con firmar un JWT ES256 con la `.p8` y hacer un POST HTTP/2 a `api.push.apple.com`. La clave va en el llavero y nunca en el binario ni en el repo.
- **CloudKit:** las suscripciones llegan como push silencioso, que es limitado y no apto para una respuesta en menos de 5 s.
- **Límites:** 8 h de actividad más 4 h en la pantalla de bloqueo, y presupuesto de pushes con prioridad 10. Solo se envían las **transiciones de fase**, nunca cada tick.
- **Fuentes:** [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [Christian Selig](https://christianselig.com/2024/09/server-side-live-activities/).

## Diseño para Altillo (implementado)

```
agente → hook (command) → "<~/Library/Application Support/Altillo/bin/altillo-hook>" <agente> <evento> [--timeout N]
        → socket Unix ~/Library/Application Support/Altillo/agents.sock (0600, carpeta 0700) → AgentHub (app)
        ← solo en PermissionRequest: espera la decisión hasta N s (120 por defecto); si no llega, no imprime nada
```

- **Protocolo:** una conexión por llamada y JSON por líneas. Hook → app: `{"v":1,"agent","event","payload":<stdin>,"env":{TERM_PROGRAM, ITERM_SESSION_ID, TERM_SESSION_ID, KITTY_WINDOW_ID, WEZTERM_PANE, TMUX_PANE, VSCODE_PID, __CFBundleIdentifier, CLAUDE_PID…},"ppids":[…],"tty","agentPID","waitsForDecision","requestID","timeout"}`. App → hook: `{"requestID","decision":"allow|allowForSession|deny|none"}`. Cada lado ignora los campos que no conoce, y una decisión desconocida cuenta como `none`. `ALTILLO_AGENTS_SOCKET` cambia la ruta del socket y `ALTILLO_HOOK_TIMEOUT` el tiempo de espera.
- **`altillo-hook`** siempre sale con 0 y siempre lee stdin entero. Si no hay socket o nadie escucha, termina al momento sin salida. Solo imprime algo en `PermissionRequest` y cuando el usuario ha decidido. Arranca en ~5 ms (mediana; p95 < 9 ms con la app escuchando). Enlaza `AltilloAgents` sin problema.
- **Motor** (`Packages/AltilloKit/Sources/AltilloAgents`): parsers tolerantes, máquina de estados, clasificador de comandos peligrosos, lectores de ficheros de sesión y protocolo. **Hub** (`Apps/macOS/Modules/Agents`): servidor del socket en su propia cola, FSEvents sobre las dos carpetas, fusión por id de sesión (ganan los hooks) y un único temporizador para la siguiente caducidad (inactiva a los 10 min y fuera de la lista a los 30). No sondea nada.
- **Ir a la terminal:** activa la app anfitriona (cadena de procesos o `__CFBundleIdentifier`). En Terminal e iTerm2 selecciona la pestaña por tty o `ITERM_SESSION_ID` con AppleScript, solo si Automatización ya está permitida o preguntando una única vez.
- Nunca aprueba automáticamente. Los comandos peligrosos se marcan para pedir una confirmación extra.
