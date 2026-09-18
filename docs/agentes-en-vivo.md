# Agentes en vivo: investigación (septiembre 2026)

Hay que volver a verificar los campos exactos contra la versión instalada de cada CLI antes de implementar, porque cambian rápido.

## Claude Code: hooks

- **Configuración:** `~/.claude/settings.json` (usuario), `.claude/settings*.json` (proyecto) y plugins (`hooks/hooks.json`).
- **Tipos de handler:** `command`, `http` (POST de JSON a una URL), `mcp_tool`, `prompt` y `agent`.
- **Eventos útiles para Altillo:**
  - `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `StopFailure`.
  - `PermissionRequest`: hace falta una decisión de permiso.
  - `Notification`, con los tipos `permission_prompt`, `idle_prompt`, `agent_needs_input` y `agent_completed`.
  - `SubagentStart` y `SubagentStop`.
- **Entrada por stdin:** `session_id`, `transcript_path`, `cwd`, `permission_mode` y `hook_event_name`, más `tool_name`, `tool_input` y `tool_use_id` en los eventos de herramientas.
- **Decisión de vuelta:**
  - En `PreToolUse` y `PermissionRequest`, el hook devuelve por stdout `{"hookSpecificOutput": {"hookEventName": …, "permissionDecision": "allow|deny|ask", …}}`.
  - En `PermissionRequest` **el exit 2 no bloquea**: la decisión tiene que ir en el JSON.
- **Timeouts:** 600 s por defecto (configurable por hook). `SessionEnd` tiene un presupuesto de 1,5 s. Si el hook excede el timeout, se cancela y la acción sigue adelante (falla en abierto).
- **Dónde se disparan:**
  - En la CLI y en VS Code/JetBrains (envuelven la CLI), aunque en VS Code los hooks de plugins tienen un bug.
  - En Claude Desktop hay reportes de que no se disparan: no es fiable.
- **Statusline:** recibe un JSON con `model`, `cost`, `context_window.used_percentage`, etc. Es un posible extra (el % de contexto de cada sesión).
- **Fuentes:** [hooks](https://code.claude.com/docs/en/hooks), [guía](https://code.claude.com/docs/en/hooks-guide), [statusline](https://code.claude.com/docs/en/statusline).

## Codex CLI

- **`notify`** (`~/.codex/config.toml`): solo tiene el evento `agent-turn-complete`, con el payload `thread-id`, `turn-id`, `cwd`, `input-messages` y `last-assistant-message`.
- **Hooks** (`~/.codex/hooks.json` o `[hooks]` en el config):
  - Eventos: `SessionStart/End`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest` (con `behavior: allow|deny`), `PostToolUse`, `Stop`, `Subagent*` e `Interrupt`.
  - Entrada: `session_id`, `cwd`, `transcript_path` y `hook_event_name`.
- **`codex app-server`:** JSON-RPC con los eventos `turn/started`, `turn/completed`, `item/*`, y aprobaciones `execCommandApproval` / `applyPatchApproval`. Solo cubre las sesiones que abre el propio cliente, así que para observar la terminal del usuario se usan los hooks.
- **Fuentes:** [hooks](https://developers.openai.com/codex/hooks), [app-server](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md).

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

## Diseño para Altillo

```
agente → hook (command) → altillo-hook <agente> <evento>  (CLI dentro de Altillo.app)
        → socket Unix ~/Library/Application Support/Altillo/agents.sock → AgentHub (app)
        ← solo en PermissionRequest: espera la decisión hasta N s; si no llega → "sin decisión" (prompt normal)
```

- `altillo-hook` no tiene dependencias y arranca en < 20 ms. Si el socket no existe, termina al instante con exit 0 y sin salida.
- Instalador: diff visible, copia de seguridad, escritura atómica, entradas marcadas como `altillo` para poder desinstalarlas y es idempotente.
- Nunca aprueba automáticamente. Los comandos peligrosos piden una confirmación extra.
