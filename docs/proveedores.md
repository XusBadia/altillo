# Proveedores de uso de IA: seguimiento de openusage

Altillo es independiente: nunca lee datos de otra app (ni de OpenUsage ni de ai-limits). Cada proveedor de uso
en `Packages/AltilloKit/Sources/AltilloUsage/` está reimplementado desde cero — credenciales propias, requests
propias, mapeo propio. [openusage](https://github.com/robinebers/openusage) (MIT, © Robin Ebers) se usa solo
como **referencia**: para saber qué endpoint llamar, dónde vive la credencial y cómo cambia la forma de la
respuesta. Este documento lleva la cuenta de qué fichero de Altillo está basado en qué fichero de openusage, y
en qué commit se revisó por última vez, para poder detectar cuándo openusage arregla algo (un endpoint que
cambió, un caso límite en el mapeo) que Altillo debería copiar a mano.

El seguimiento automático vive en [`script/openusage-upstream.sh`](../script/openusage-upstream.sh) + el
manifiesto [`script/openusage-upstream.json`](../script/openusage-upstream.json), y corre cada semana en
[`.github/workflows/openusage-upstream.yml`](../.github/workflows/openusage-upstream.yml) (además de a mano con
`workflow_dispatch`). Cuando detecta cambios abre o actualiza un único issue "Upstream openusage: cambios en
proveedores" con la etiqueta `upstream`.

Ver también [`ThirdPartyNotices/README.md`](../ThirdPartyNotices/README.md), que es la fuente legal de qué
código se adaptó de dónde; esta tabla es la vista operativa (qué endpoint, qué credencial, qué revisar).

## Claude

| | |
|---|---|
| Collector de Altillo | [`ClaudeCollector.swift`](../Packages/AltilloKit/Sources/AltilloUsage/ClaudeCollector.swift), [`ClaudeCredentials.swift`](../Packages/AltilloKit/Sources/AltilloUsage/ClaudeCredentials.swift) |
| Rutas de openusage en que se basa | `Sources/OpenUsage/Providers/Claude/ClaudeUsageMapper.swift` (ventanas, `limits[]` con `weekly_scoped`, `extra_usage` en centavos, formato del plan), `Sources/OpenUsage/Providers/Claude/ClaudeAuthStore.swift` (orden de búsqueda, sufijo del servicio de llavero con `CLAUDE_CONFIG_DIR`, fallback hex) |
| Credenciales | Llavero `Claude Code-credentials` primero (vía `/usr/bin/security find-generic-password -w`, sin prompt porque el ACL del item confía en ese binario), luego `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json`. Solo lectura: Altillo nunca refresca ni reescribe el token (el refresh token rota; refrescarlo aquí cerraría la sesión de Claude Code) |
| Endpoint | `GET https://api.anthropic.com/api/oauth/usage`, cabeceras `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<versión instalada>` |
| Revisado contra upstream | `4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4` (2026-09-23) |

## Codex

| | |
|---|---|
| Collector de Altillo | [`CodexCollector.swift`](../Packages/AltilloKit/Sources/AltilloUsage/CodexCollector.swift) (el JSON-RPC de `app-server` en [`CodexAppServer.swift`](../Packages/AltilloKit/Sources/AltilloUsage/CodexAppServer.swift) viene de [ai-limits](https://github.com/XusBadia/ai-limits), no de openusage — no está en este seguimiento) |
| Rutas de openusage en que se basa | `Sources/OpenUsage/Providers/Codex/CodexUsageMapper.swift` (clasificación de ventanas por duración, nombre del plan, mapeo de `wham/usage`) |
| Credenciales | Primero `codex app-server --listen stdio://` (JSON-RPC, `account/rateLimits/read`), que usa el propio token de Codex CLI siempre fresco. Si no hay binario `codex`, fallback HTTP con el token de `$CODEX_HOME/auth.json` (o `~/.codex/auth.json`): `tokens.access_token` + `tokens.account_id`. Solo lectura en ambos casos |
| Endpoint | Fallback: `GET https://chatgpt.com/backend-api/wham/usage`, cabeceras `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <account_id>` |
| Revisado contra upstream | `4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4` (2026-09-23) |

## Núcleo compartido: ritmo y alertas

No es un proveedor, pero todos los collectors dependen de esta lógica y también viene de openusage, así que se
sigue igual.

| | |
|---|---|
| Ficheros de Altillo | [`AltilloCore/Usage.swift`](../Packages/AltilloKit/Sources/AltilloCore/Usage.swift) (`UsagePace`), [`AltilloCore/UsageAlerts.swift`](../Packages/AltilloKit/Sources/AltilloCore/UsageAlerts.swift) |
| Rutas de openusage en que se basa | `Sources/OpenUsage/Support/Pace.swift` (proyección de ritmo de consumo), `Sources/OpenUsage/Support/PaceNotificationLogic.swift` (tolerancia de jitter en el reset, aviso de "se va a agotar"), `Sources/OpenUsageMobileCore/MobileQuotaNotifications.swift` → `MobileQuotaNotificationEvaluator` (umbrales, límite alcanzado, una vez por ventana, solo el umbral más alto cruzado) |
| Revisado contra upstream | `4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4` (2026-09-23) |

## Proveedores pendientes

Cursor, Copilot, OpenRouter, Z.ai, Grok, Gemini/Antigravity, Devin y OpenCode se están escribiendo ahora mismo
en `Packages/AltilloKit/Sources/AltilloUsage/` (otro trabajo en curso; no tocar esos ficheros desde aquí).
Cuando un collector nuevo aterrice, añádele una entrada en `script/openusage-upstream.json` y una fila en este
documento siguiendo el mismo formato — ver "Cómo actualizar un proveedor" más abajo, paso 0.

## Cómo actualizar un proveedor

0. **Proveedor nuevo:** añade una entrada en [`script/openusage-upstream.json`](../script/openusage-upstream.json)
   (`altillo_files`, `upstream_paths` en el fork de openusage, `last_reviewed_sha` = el HEAD actual de
   `robinebers/openusage`) y una fila en este documento. A partir de ahí sigue el seguimiento igual que Claude
   o Codex.
1. **Detectar el cambio:** `script/openusage-upstream.sh <proveedor>` (o sin argumento, para todos) imprime los
   commits y ficheros de openusage que cambiaron desde la última revisión, con enlaces. También corre solo cada
   semana y abre/actualiza el issue con la etiqueta `upstream` — normalmente se entera ahí primero.
2. **Leer el cambio:** abre los commits enlazados en GitHub, o mira el fichero en el fork local
   (`~/Documents/GitHub/openusage`, remoto `origin` = `robinebers/openusage`). openusage es solo referencia:
   nunca se copia ni se importa su código, así que hay que entender qué cambió (endpoint nuevo, campo que
   cambió de forma, caso límite corregido) y decidir si Altillo necesita el mismo arreglo.
3. **Portar el cambio a mano** en el fichero de Altillo correspondiente (columna "Collector de Altillo" de la
   tabla de arriba), con el mismo estilo defensivo que ya tiene (`UsageParsing`, fallos que degradan a
   `previous` en vez de tirar la sesión).
4. **Tests:** añade o actualiza un caso en `Packages/AltilloKit/Tests/AltilloUsageTests/` (p. ej.
   [`ClaudeCollectorTests.swift`](../Packages/AltilloKit/Tests/AltilloUsageTests/ClaudeCollectorTests.swift),
   [`CodexCollectorTests.swift`](../Packages/AltilloKit/Tests/AltilloUsageTests/CodexCollectorTests.swift)) con
   una respuesta fija que reproduzca el caso nuevo. `swift test` en `Packages/AltilloKit`.
5. **Actualiza este documento:** si cambió qué se lee o de dónde, ajusta la fila del proveedor.
6. **Marca como revisado:** `script/openusage-upstream.sh --mark-reviewed <proveedor>` (o `all` si revisaste
   varios a la vez) pone `last_reviewed_sha` al HEAD actual de openusage. Commitea el manifiesto junto con el
   arreglo y, si aplica, la fila nueva/actualizada de
   [`ThirdPartyNotices/README.md`](../ThirdPartyNotices/README.md).
