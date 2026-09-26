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

## Más agentes (fase 14, verificado el 25-09-2026)

Ninguna de estas CLI está instalada en el Mac de desarrollo. Se verificaron contra el código que publican (instalado en un prefijo temporal, sin tocar `~/.gemini`, `~/.copilot`, `~/.cursor` ni la configuración de OpenCode) y su documentación. OpenCode sí se probó en vivo, en un `HOME` aislado. Fixtures: `gemini/*.docs.json` (referencia incluida en el paquete), `copilot/*.docs.json` (docs.github.com), `cursor/*.source.json` (código del paquete) y `opencode/global-event.sse.txt` (captura real, anonimizada).

### Gemini CLI 0.61.0

- **Configuración:** `hooks` en `~/.gemini/settings.json` (también `.gemini/settings.json` del proyecto y `/etc/gemini-cli/settings.json`), con la misma forma que Claude: `hooks.<Evento>: [{"matcher"?, "hooks": [{"type":"command","command","timeout"}]}]`. **`timeout` va en milisegundos** (60 000 por defecto). `hooksConfig.enabled` (activado por defecto) los apaga todos; `hooksConfig.disabled` apaga hooks por nombre. Los hooks de proyecto se identifican por huella y avisan si cambian.
- **Entrada común:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`. Entorno: `GEMINI_PROJECT_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD` y el entorno del proceso (la redacción de variables es opcional).
- **Eventos:** `SessionStart` (`source`), `SessionEnd` (`reason`; no espera), `BeforeAgent` (`prompt`), `AfterAgent` (`prompt`, `prompt_response`, `stop_hook_active`), `BeforeTool`/`AfterTool` (`tool_name`, `tool_input`, `tool_response`), `BeforeModel`, `AfterModel`, `BeforeToolSelection`, `PreCompress` y `Notification` (`notification_type: "ToolPermission"`, `message`, `details`).
- **Permisos: solo observar.** `Notification` es de observación ("no puede conceder permisos") y `BeforeTool` se dispara con cada herramienta antes de la confirmación, así que esperar ahí frenaría al agente. Altillo muestra la petición (la herramienta del último `BeforeTool`) y se contesta en la terminal.
- **Responder:** `AfterAgent` con `{"decision":"deny","reason":"…"}` rechaza la respuesta y **envía el motivo al agente como un prompt nuevo**. Salida 0 sin nada = sigue normal; código 2 = reintento con stderr; otros códigos = aviso y sigue (falla en abierto).
- **Ficheros de sesión:** `~/.gemini/tmp/<proyecto>/chats/session-<fecha>-<id corto>.jsonl`, JSONL de solo añadir: primero los metadatos (`sessionId`, `projectHash`, `startTime`, `lastUpdated`, `kind`, `directories`), luego mensajes (`id`, `timestamp`, `type` `user`/`gemini`/`info`/`error`, `content`, `toolCalls` con `status` `validating|scheduled|awaiting_approval|executing|success|error|cancelled`), que se vuelven a escribir con el mismo `id` al cambiar, y actualizaciones `{"$set":…}`. `<proyecto>` es un nombre corto que `~/.gemini/projects.json` asocia a la ruta (`{"projects":{"/ruta":"nombre"}}`); las versiones antiguas usaban el SHA-256 de la ruta. `awaiting_approval` permite ver sin hooks que espera permiso.

### GitHub Copilot CLI 1.0.88

- **Configuración:** cada `~/.copilot/hooks/*.json` (o `$COPILOT_HOME/hooks/`), además de `.github/hooks/*.json` del repositorio, `hooks` en `~/.copilot/settings.json` y plugins. Todos se ejecutan. Forma: `{"version":1,"hooks":{"<evento>":[{"type":"command","bash":"…","timeoutSec":30}]}}` (también `command`, `powershell` o `exec` + `args`). Altillo escribe **su propio fichero**, `~/.copilot/hooks/altillo.json`, y al quitarlo lo borra (y la carpeta `hooks/` si la creó él).
- **Eventos en camelCase** (campos en camelCase): `sessionStart` (`source`, `initialPrompt`), `sessionEnd` (`reason`), `userPromptSubmitted` (`prompt`), `preToolUse`, `postToolUse`, `postToolUseFailure` (`toolName`, `toolArgs` objeto o texto JSON, `toolResult`, `error`), `permissionRequest`, `preCompact`, `agentStop` (`transcriptPath`, `stopReason`, `stop_hook_active`), `subagentStart`/`subagentStop` (`agentName`, `agentType`, `response`), `errorOccurred` (`error.message`, `error.name`, `recoverable`) y `notification` (asíncrono; `notification_type` `permission_prompt|agent_idle|agent_completed|elicitation_dialog|shell_completed…`). Todos traen `sessionId`, `timestamp` y `cwd`. Con nombres en PascalCase los campos van en snake_case.
- **Permisos: solo observar.** `permissionRequest` puede contestar `{"behavior":"allow"|"deny"}`, pero **se dispara con cada llamada, antes de las reglas y las aprobaciones de la sesión**, así que no dice si el usuario va a ver un aviso (hay integraciones que bloquean ~65 s por esperar ahí). Altillo lo usa para saber qué va a ejecutar y muestra el aviso real con `notification` `permission_prompt`, para contestarlo en la terminal.
- **`preToolUse` no se instala:** es el único que **falla en cerrado** (si el hook da error, Copilot deniega la herramienta), y un Altillo movido o borrado dejaría el agente sin herramientas. Los *timeouts* fallan en abierto en todos los eventos.
- **Responder:** `agentStop` con `{"decision":"block","reason":"…"}` fuerza otro turno con el motivo como prompt. Tras 8 bloqueos seguidos, Copilot termina el turno igualmente.
- **También lee `.claude/settings.json` y `.claude/settings.local.json` del repositorio** (hooks «cross-tool», según la referencia). Si uno de esos ficheros ejecuta `altillo-hook claude …`, `altillo-hook` reconoce a Copilot por su proceso (`copilot` como agente en la cadena) y trata el evento como de Copilot, solo para observar: nunca espera ahí.
- **Ficheros de sesión:** sin verificar (el binario lleva el JS comprimido), así que no hay detección pasiva para Copilot.

### Cursor CLI (`cursor-agent`, versión 2026.09.23)

- **Hooks, también en la CLI:** `~/.cursor/hooks.json` (usuario), `.cursor/hooks.json` (proyecto), `/Library/Application Support/Cursor/hooks.json` (empresa) y los del equipo. Forma plana: `{"version":1,"hooks":{"stop":[{"command":"…","timeout":30}]}}` (`timeout` en segundos, `loop_limit`, `failClosed` desactivado por defecto: **falla en abierto**). Entorno: `CURSOR_PROJECT_DIR`, `CURSOR_VERSION`, `CURSOR_TRANSCRIPT_PATH`, `CLAUDE_PROJECT_DIR`.
- **También ejecuta los hooks de Claude Code** (`~/.claude/settings.json` y los del proyecto), traduciendo `PreToolUse`, `PostToolUse`, `UserPromptSubmit`→`beforeSubmitPrompt`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd` y `PreCompact`, y descartando `PermissionRequest` y `Notification`. Esos eventos llegan a `altillo-hook claude …` con la carga de Cursor (`cursor_version`, `conversation_id`), así que `altillo-hook` los atribuye a Cursor y nunca espera en ellos.
- **Eventos:** `sessionStart`, `sessionEnd`, `beforeSubmitPrompt` (`prompt`), `preToolUse`/`postToolUse`/`postToolUseFailure` (`tool_name`, `tool_input`, `tool_use_id`), `beforeShellExecution`/`afterShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `afterFileEdit`, `afterAgentResponse` (`text`), `afterAgentThought`, `stop` (`status` `completed|aborted|error`, `loop_count`), `subagentStart`/`subagentStop` (`subagent_type`, `summary`) y `preCompact`. Comunes: `conversation_id`, `generation_id`, `model`, `session_id`, `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email`, `transcript_path`.
- **Permisos: solo observar.** `beforeShellExecution` decide antes de que Cursor pregunte (no hay un evento "va a preguntar al usuario"), así que Altillo no aprueba nada en Cursor.
- **Responder:** `stop` con `{"followup_message":"…"}` hace que el agente siga; `loop_limit` limita las continuaciones seguidas (Cursor aplica uno por defecto). Estos hooks también los ejecuta el editor Cursor.
- **ACP** (`cursor-agent acp`, JSON-RPC por stdio) solo sirve para sesiones que lanza el propio cliente: no permite ver una sesión abierta en una terminal. Por eso se usan los hooks.
- **Ficheros de sesión:** sin detección pasiva (transcripciones en `~/.cursor/projects/…/agent-transcripts/`, formato sin verificar).

### OpenCode 1.18.32 (probado en vivo)

- **Servidor:** `opencode serve` escucha en `127.0.0.1:4096` por defecto (`--port 0` = 4096 o, si está ocupado, cualquiera libre); también `opencode web` y la TUI con `--port`. **La TUI normal no abre ningún puerto.** `OPENCODE_SERVER_PASSWORD` activa autenticación básica: Altillo no la pide y deja ese servidor en paz.
- **Descubrimiento sin sondeo:** OpenCode escribe su log y su base de datos en `~/.local/share/opencode` (`$XDG_DATA_HOME`) al arrancar y mientras trabaja; **un `opencode serve` inactivo no escribe nada** (comprobado durante 90 s). Altillo vigila esa carpeta con FSEvents y, con cada ráfaga (como mucho cada 3 s), recorre los procesos (`proc_listallpids`), se queda con los `opencode` que sirven HTTP (argv `serve`/`web`/`--port`) y usa el puerto en el que escuchan de verdad (libproc); un `--port N` solo cuenta si el proceso escucha en N.
- **Sin OpenCode, nada:** si la carpeta no existe, no se vigila nada de forma recursiva. Una fuente vnode no recursiva sobre la carpeta existente más cercana (`~/.local/share`, si no `~/.local`, si no la carpeta personal) solo despierta cuando se añade una entrada ahí, y baja hasta que la carpeta aparece. Todo lo que Altillo envía a OpenCode va por una `URLSession` sin proxy.
- **Eventos:** `GET /global/event` (SSE) envuelve cada evento de cualquier proyecto en `{"directory","project","payload":{"id","type","properties"}}`; `/event?directory=` es lo mismo sin envolver. Tipos usados: `session.created|updated|deleted` (`info`: `id`, `directory`, `title`, `parentID` en subagentes), `session.status` (`busy|idle|retry`), `session.idle`, `session.error`, `message.updated` (`info.role`), `message.part.updated` (`text`, o `tool` con `state.status` e `input`), `permission.asked` (`id`, `sessionID`, `permission`, `patterns`, `metadata`, `always`, `tool`) y `permission.replied` (`requestID`, `reply`). Latido: `server.heartbeat`.
- **Contestar un permiso:** `POST /permission/<id>/reply?directory=<dir>` con `{"reply":"once"|"always"|"reject"}` → `true`. «Permitir en esta sesión» es `always` cuando OpenCode lo ofrece (`always` no vacío). La ruta antigua `POST /session/<id>/permissions/<permissionID>` (`{"response":…}`) sigue existiendo. Varias peticiones de una sesión se ponen en cola (la tarjeta muestra la más antigua). Si OpenCode no acepta la respuesta, la petición vuelve la primera, con el error en la tarjeta.
- **Al (re)conectar:** `GET /permission?directory=` (lista de peticiones pendientes) y `GET /session/status?directory=` (`{"<sesión>":{"type":"busy"|"idle"|"retry"}}`) para quitar lo que se contestó mientras Altillo no escuchaba y cerrar los turnos que acabaron. Como red de seguridad, una tarjeta de OpenCode sin contestar desaparece a la hora.
- **Responder:** `POST /session/<id>/prompt_async?directory=<dir>` con `{"parts":[{"type":"text","text":"…"}]}` → 204 y empieza un turno nuevo.
- **Prueba en vivo** (`OpenCodeLiveTests`, opcional): Altillo encuentra el servidor, ve la sesión trabajar y pedir permiso para `echo`, lo permite desde el hub, la ve esperar respuesta y le envía una respuesta que el agente contesta.

## Responder desde el notch (fase 14)

Cuando una sesión espera tu siguiente mensaje, la tarjeta de Agentes muestra «Reply to <agente>…» con respuestas rápidas («Continue», «Yes» y, si un hook espera, «No, stop»). `AgentHub.reply(_:to:)` lo envía (Pregunta también lo usa); `sendReply` dice por qué no se envió. Nunca se envía nada por iniciativa de Altillo.

- **Claude Code, Codex, Gemini CLI, Copilot CLI y Cursor:** a través del hook de fin de turno (`Stop`, `Stop`, `AfterAgent`, `agentStop`, `stop`). Es **opcional por agente** («Let me reply from the notch» en Ajustes). **Viene activado en instalaciones nuevas de Claude Code y Codex** (la primera instalación, también desde la bienvenida, lo incluye y la revisión del diff lo muestra); las instalaciones anteriores no se tocan ni se actualizan solas, y Gemini, Copilot y Cursor empiezan desactivados. El hook se instala con `--reply-wait N` (la misma espera que los permisos, 2 min por defecto) y un `timeout` de N + 30 s.
  - **Solo en una sesión interactiva de terminal:** el propio proceso del agente tiene terminal de control y su stdin es un terminal (libproc), `CLAUDE_CODE_ENTRYPOINT` (si existe) es `cli`, y el argv no es de ejecución sin interfaz (`-p`, `--print`, `--prompt`, `exec`, `app-server`… y, en Gemini, un prompt posicional sin `-i`/`--prompt-interactive`). En la duda, no espera.
  - **Solo si Altillo sabe en qué app corre:** sin `__CFBundleIdentifier` ni una app con interfaz subiendo desde el proceso del agente (tmux, SSH…), no espera, porque volver a la terminal no podría soltarlo.
  - **Solo mientras no estás en la terminal:** si al acabar el turno la app de la terminal (o del editor) es la app activa, el hook no espera: estás mirando y escribirás ahí. Mientras un hook espera, Altillo observa las activaciones de apps (`NSWorkspace.didActivateApplicationNotification`, suscrito solo entonces) y lo suelta en cuanto vuelves a la terminal de esa sesión. Abrir el notch no activa Altillo (el panel no es activante), así que responder desde el notch sigue funcionando.
  - Sin Altillo, con el módulo Agentes desactivado, sin respuesta o al acabar la espera, el hook sale sin imprimir nada y el agente termina como siempre. Si llega una respuesta, imprime el formato de cada agente: Claude, Codex y Copilot `{"decision":"block","reason":…}`, Gemini `{"decision":"deny","reason":…}`, Cursor `{"followup_message":…}`, con el texto precedido de «The user replied from Altillo (their notch):».
  - **Límites:** como mucho 16 KB por respuesta. Una respuesta a menos de 1 s del final de la espera cuenta como no entregada: el campo se queda en estado fallido («It stopped waiting. Answer in the terminal.») con el texto escrito, hasta que la sesión cambie. No se retiene el turno cuando el agente ya no aceptaría la continuación: Copilot tras 8 seguidas, Cursor al llegar `loop_count` a su `loop_limit` (5 por defecto).
  - «No, stop», «Ir a la terminal», descartar la sesión o cualquier señal de un turno nuevo sueltan el hook sin respuesta. Un segundo aviso del mismo final de turno (Cursor ejecuta también los hooks de Claude) no lo suelta. Si pulsas Esc en la terminal, el agente mata el hook y el campo desaparece.
  - **Verificado en vivo con Claude Code 2.1.281:** Claude recibe el motivo como un turno del usuario («Stop hook feedback: …»), sigue y el siguiente `Stop` trae `stop_hook_active: true`. Codex (0.152.0) está verificado en el esquema y el código (`reason` pasa a ser el prompt de continuación).
- **OpenCode:** a través de su API (`prompt_async`), sin espera ni ajuste.

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
agente → hook (command) → "<~/Library/Application Support/Altillo/bin/altillo-hook>" <agente> <evento> [--timeout N] [--reply-wait N]
        → socket Unix ~/Library/Application Support/Altillo/agents.sock (0600, carpeta 0700) → AgentHub (app)
        ← solo en PermissionRequest (Claude y Codex): espera la decisión hasta N s (120 por defecto); si no llega, no imprime nada
        ← con --reply-wait, en el evento de fin de turno de una sesión de terminal: espera una respuesta hasta N s
```

- **Protocolo:** una conexión por llamada y JSON por líneas. Hook → app: `{"v":1,"agent","event","payload":<stdin>,"env":{TERM_PROGRAM, ITERM_SESSION_ID, TERM_SESSION_ID, KITTY_WINDOW_ID, WEZTERM_PANE, TMUX_PANE, VSCODE_PID, __CFBundleIdentifier, CLAUDE_PID…},"ppids":[…],"tty","agentPID","waitsForDecision","requestID","timeout"}`. App → hook: `{"requestID","decision":"allow|allowForSession|deny|none"}`; para un hook que espera respuesta, `"waitsForReply":true` y `{"requestID","decision":"reply","text"}`. Cada lado ignora los campos que no conoce, y una decisión desconocida cuenta como `none`. `ALTILLO_AGENTS_SOCKET` cambia la ruta del socket y `ALTILLO_HOOK_TIMEOUT` el tiempo de espera.
- **`altillo-hook`** siempre sale con 0 y siempre lee stdin entero. Si no hay socket o nadie escucha, termina al momento sin salida. Solo imprime algo en `PermissionRequest` y cuando el usuario ha decidido. Arranca en ~5 ms (mediana; p95 < 9 ms con la app escuchando). Enlaza `AltilloAgents` sin problema.
- **Motor** (`Packages/AltilloKit/Sources/AltilloAgents`): parsers tolerantes (Claude, Codex, Gemini, Copilot y Cursor), máquina de estados, clasificador de comandos peligrosos, lectores de ficheros de sesión (Claude, Codex y Gemini), protocolo y la parte pura de OpenCode (`OpenCode.swift`). **Hub** (`Apps/macOS/Modules/Agents`): servidor del socket en su propia cola, FSEvents sobre las carpetas de sesiones, `OpenCodeMonitor`, fusión por id de sesión (ganan los hooks) y un único temporizador para la siguiente caducidad (inactiva a los 10 min y fuera de la lista a los 30). No sondea nada.
- **Ir a la terminal:** activa la app anfitriona (cadena de procesos o `__CFBundleIdentifier`). En Terminal e iTerm2 selecciona la pestaña por tty o `ITERM_SESSION_ID` con AppleScript, solo si Automatización ya está permitida o preguntando una única vez.
- Nunca aprueba automáticamente. Los comandos peligrosos se marcan para pedir una confirmación extra.
