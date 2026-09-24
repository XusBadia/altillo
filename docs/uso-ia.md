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
| Altillo (propuesto) | `me.badia.altillo` (Mac, Developer ID) y `me.badia.altillo.ios`, con el contenedor nuevo `iCloud.me.badia.altillo`. Independiente: nunca toca `iCloud.me.badia.ailimits` |
| Altillo (creado el 24-09-2026) | App ID `me.badia.altillo` (`TR82WL9H6Y`) con iCloud activado. Perfil Developer ID "Altillo Developer ID iCloud" (lo crea `script/icloud-profile.py`). Mac de desarrollo registrado: "Copen mini" (`6MK7N94YM9`) |

## openusage (upstream robinebers/openusage, MIT)

- **Marca:** `TRADEMARK.md` prohíbe usar "OpenUsage" como nombre de un derivado. Sí se permite decir "compatible with OpenUsage".
- **Proveedores (11):**
  - Claude: llavero `Claude Code-credentials` → `api.anthropic.com/api/oauth/usage`.
  - Codex: `wham/usage`.
  - El resto: Cursor, Copilot, Antigravity, Devin, Grok, OpenCode, OpenRouter, pi y Z.ai.
- **Reutilización:** el código de proveedores es `internal`, `@MainActor` y está acoplado a `AppContainer`, así que no sirve como librería. Los contratos estables son la **API local** `127.0.0.1:6736/v1/limits` (esquema `openusage.limits.v1`) y el CLI. Altillo no usa ninguno de los dos (ver [Independencia](#independencia-24-09-2026)).
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

1. **`AltilloUsage`** (en `Packages/AltilloKit`): collectors de Claude (llavero primero, sin refrescar nunca el token) y Codex (`app-server`). Después, collectors nativos para el resto (Cursor, Copilot, OpenRouter, Z.ai, Grok, Gemini/Antigravity, Devin, OpenCode…), uno a uno.
2. **Altillo para iOS**, desde cero, con el contenedor nuevo `iCloud.me.badia.altillo` y CloudKit (`CKSyncEngine`). No hay transición: el fork y ai-limits no se leen ni se sustituyen por un puente, y la app de TestFlight `me.badia.ailimits` no es una dependencia de Altillo.
3. **Marca:** nada con el nombre "OpenUsage".

## Independencia (24-09-2026)

Decisión tuya: **Altillo es una app independiente y lee cada proveedor por sí mismo.** No se leen datos de otras apps de uso (no hay acuerdos con ellas) y nadie tiene que instalar otra app para ver sus límites.

- **Se retira la fuente opcional "compatible with OpenUsage"** (la API local `127.0.0.1:6736`): fuera `OpenUsageCompatibleSource`, su interruptor en Ajustes (la clave `usageShowsOpenUsageSource` se queda en los defaults, ignorada) y el estado «Conectado a través de OpenUsage».
- **openusage (MIT) es solo una referencia** de cómo funciona cada proveedor (qué fichero o llavero guarda la sesión, qué endpoint da el uso). Cuando se adapta código, va con atribución en `ThirdPartyNotices`.
- **Cada proveedor es un `UsageCollector`** con su `UsageProviderID`, registrado en `UsageCollectors.all()`. Lee lo que las herramientas del propio proveedor ya guardan en este Mac (la sesión de un CLI o de un editor, una API key que añades tú), nunca refresca ni reescribe credenciales ajenas, y trae un `setupHint` de una línea («Sign in to Cursor») para quien aún no lo tiene configurado.
- **Por defecto** todos los proveedores que se encuentran en este Mac están activados; cada uno se puede apagar en Ajustes › Secciones › Uso. Los que no están configurados se agrupan en «Not set up on this Mac», cada uno con su pista.
- **Límites que no son sesión/semana:** cuotas mensuales, contadores de peticiones y saldos (créditos, dólares) se muestran igual de bien. La tarjeta lleva como anillo la sesión o, si no hay, el límite más lleno (`headline`); si un proveedor solo tiene saldo, la cifra grande es el saldo («$7.50 left»).

## El fork y ai-limits ya no son parte de Altillo

Decisión del 24-09-2026: el stack antiguo (el fork de openusage con su app de TestFlight `me.badia.ailimits` y su bridge/watchdog, y el propio ai-limits) **no es una dependencia de Altillo**. Altillo no escribe `openusage.mobile.v1`, no toca el contenedor `iCloud.me.badia.ailimits` y no tiene ningún código de transición o compatibilidad con esa app. La futura companion de iPhone/iPad es una app de Altillo hecha desde cero, con sus propias features por definir contigo (PLAN.md fase 5, §6).

Si sigues teniendo el bridge y su watchdog corriendo en este Mac (de cuando usabas el fork), puedes retirarlos cuando quieras: es limpieza tuya, sin relación con Altillo.

### Apéndice opcional: retirar el bridge y el watchdog

```sh
# 1. Que el watchdog no vuelva a lanzar el bridge: marca de "desactivado" y fuera el LaunchAgent.
touch "$HOME/Library/Application Support/OpenUsage Mobile Bridge/disabled"
launchctl bootout "gui/$(id -u)/me.badia.ailimits.collector.watchdog"
rm -f "$HOME/Library/LaunchAgents/me.badia.ailimits.collector.watchdog.plist"

# 2. Cerrar el bridge.
pkill -x openusage-mobile-bridge

# 3. Quitarlo del arranque: System Settings → General → Login Items → "OpenUsage Mobile Bridge" → "−"
#    (se registró con SMAppService; al borrar la app macOS también acaba quitando la entrada).

# 4. Borrar la app, su estado y sus logs.
rm -rf "/Applications/OpenUsage Mobile Bridge.app" \
  "$HOME/Library/Application Support/OpenUsage Mobile Bridge" \
  "$HOME/Library/Logs/OpenUsage Mobile Bridge"

# 5. Comprobar: no queda nada corriendo.
launchctl print "gui/$(id -u)/me.badia.ailimits.collector.watchdog" 2>&1 | head -1   # "Could not find service"
pgrep -x openusage-mobile-bridge || echo "bridge parado"
```

Una vez retirado el bridge, la app de TestFlight `me.badia.ailimits` deja de recibir datos nuevos (nadie escribe ya en `iCloud.me.badia.ailimits`); eso es lo esperado hasta que exista la companion de Altillo.

