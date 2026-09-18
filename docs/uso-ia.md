# Uso de agentes de IA: estado actual y migración

Análisis de `~/Documents/GitHub/openusage` (fork) y `~/Documents/GitHub/ai-limits` (18-09-2026).

## Identificadores (team 9L2TD7KVV9)

| Cosa | Valor |
|---|---|
| App iOS (TestFlight) | `me.badia.ailimits`. Hoy es el companion del fork, con el nombre "OpenUsage" ⚠️ |
| Widgets | `me.badia.ailimits.widgets` |
| Collector de Mac (ai-limits / bridge del fork) | `me.badia.ailimits.collector` |
| Contenedor de iCloud | `iCloud.me.badia.ailimits` (CloudKit en ai-limits, iCloud Documents en el fork) |
| App Group | `group.me.badia.ailimits` |
| Perfiles | "AI Limits App Store v2", "AI Limits Widgets App Store v2", "AI Limits Collector Developer ID v1" |
| Altillo (propuesto) | `me.badia.altillo` (Mac, Developer ID) y `me.badia.altillo.ios`, con el contenedor nuevo `iCloud.me.badia.altillo`. Durante la transición también tiene acceso a `iCloud.me.badia.ailimits` |

## openusage (upstream robinebers/openusage, MIT)

- **Marca:** `TRADEMARK.md` prohíbe usar "OpenUsage" como nombre de un derivado. Sí se permite decir "compatible with OpenUsage".
- **Proveedores (11):**
  - Claude: llavero `Claude Code-credentials` → `api.anthropic.com/api/oauth/usage`.
  - Codex: `wham/usage`.
  - El resto: Cursor, Copilot, Antigravity, Devin, Grok, OpenCode, OpenRouter, pi y Z.ai.
- **Reutilización:** el código de proveedores es `internal`, `@MainActor` y está acoplado a `AppContainer`, así que no sirve como librería. Los contratos estables son la **API local** `127.0.0.1:6736/v1/limits` (esquema `openusage.limits.v1`) y el CLI.
- **Fork:**
  - `OpenUsageMobileCore`: modelo `openusage.mobile.v1`, con reader y writer de iCloud Documents.
  - App iOS con widgets y alertas (umbrales 50/80/90/95 % y reset).
  - **Bridge** (lee la API local y escribe en iCloud) empaquetado a mano y vigilado por un watchdog de launchd que corre cada minuto. Es la parte frágil.
- **Ruta en iCloud:** `OpenUsage/Mobile/v1/<deviceID>.json`, más el historial en `OpenUsage/History/v1/`.

## ai-limits (tuyo, MIT)

| Paquete | Estado |
|---|---|
| core | `SnapshotEnvelope` v1, `UsageWindow`, `BalanceMetric`… Faltan `SpendMetric` y `Clock` |
| collectors | Codex ✅ (`codex app-server`, JSON-RPC). Claude ❌: solo lee el fichero (no el llavero) y no guarda el token rotado. Modo Swift 5 |
| sync | CloudKit: zona `AILimitsPrivateV1`, un solo registro `current-snapshot`. El último que escribe gana (no admite varios Macs) |
| apps | Collector `MenuBarExtra` (notarizado, v0.1.0), dashboard iOS simple y un widget. Sin alertas |
| tests | Mínimos |
| plans | 001-006. Del 001 al 003 están a medias; del 004 al 006 pendientes |

## Sandbox

Ninguna de las dos apps de Mac usa sandbox. Leer `~/.claude`, `~/.codex` o el llavero de otras apps y lanzar `codex app-server` no funciona de forma fiable dentro del sandbox, así que **Altillo se distribuye sin sandbox** (Developer ID + hardened runtime).

## Plan (decisión del 18-09-2026: monorepo `altillo` y app de iOS desde cero)

ai-limits y el fork **no se usan como base**. Se aprovechan ideas y fragmentos puntuales, con atribución MIT en `ThirdPartyNotices`:
- de openusage: los mappers de proveedores, el cálculo de ritmo y los umbrales de alerta;
- de ai-limits: el collector de Codex vía `app-server` y la configuración de XcodeGen y la notarización.

1. **`AltilloUsage`** (en `Packages/AltilloKit`): collectors de Claude (llavero primero, sin refrescar nunca el token) y Codex (`app-server`). Después, Cursor, Copilot, Gemini y OpenRouter, uno a uno.
2. **Transición opcional:** Altillo escribe también `openusage.mobile.v1` en `iCloud.me.badia.ailimits`, para que la app actual de TestFlight siga funcionando. Así se retiran ya el bridge y el watchdog (`launchctl bootout` del LaunchAgent).
3. **Altillo para iOS**, desde cero, con el contenedor nuevo `iCloud.me.badia.altillo` y CloudKit (`CKSyncEngine`).
4. **Retirar:** cuando Altillo para iOS esté en TestFlight, se archivan el fork y ai-limits y se da de baja la app `me.badia.ailimits`.
5. **Marca:** nada con el nombre "OpenUsage". Solo se permite decir "compatible with OpenUsage".
