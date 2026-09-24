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
2. **Transición opcional:** Altillo escribe también `openusage.mobile.v1` en `iCloud.me.badia.ailimits`, para que la app actual de TestFlight siga funcionando. Así se retiran ya el bridge y el watchdog (`launchctl bootout` del LaunchAgent).
3. **Altillo para iOS**, desde cero, con el contenedor nuevo `iCloud.me.badia.altillo` y CloudKit (`CKSyncEngine`).
4. **Retirar:** cuando Altillo para iOS esté en TestFlight, se archivan el fork y ai-limits y se da de baja la app `me.badia.ailimits`.
5. **Marca:** nada con el nombre "OpenUsage".

## Independencia (24-09-2026)

Decisión tuya: **Altillo es una app independiente y lee cada proveedor por sí mismo.** No se leen datos de otras apps de uso (no hay acuerdos con ellas) y nadie tiene que instalar otra app para ver sus límites.

- **Se retira la fuente opcional "compatible with OpenUsage"** (la API local `127.0.0.1:6736`): fuera `OpenUsageCompatibleSource`, su interruptor en Ajustes (la clave `usageShowsOpenUsageSource` se queda en los defaults, ignorada) y el estado «Conectado a través de OpenUsage».
- **openusage (MIT) es solo una referencia** de cómo funciona cada proveedor (qué fichero o llavero guarda la sesión, qué endpoint da el uso). Cuando se adapta código, va con atribución en `ThirdPartyNotices`.
- **Cada proveedor es un `UsageCollector`** con su `UsageProviderID`, registrado en `UsageCollectors.all()`. Lee lo que las herramientas del propio proveedor ya guardan en este Mac (la sesión de un CLI o de un editor, una API key que añades tú), nunca refresca ni reescribe credenciales ajenas, y trae un `setupHint` de una línea («Sign in to Cursor») para quien aún no lo tiene configurado.
- **Por defecto** todos los proveedores que se encuentran en este Mac están activados; cada uno se puede apagar en Ajustes › Secciones › Uso. Los que no están configurados se agrupan en «Not set up on this Mac», cada uno con su pista.
- **Límites que no son sesión/semana:** cuotas mensuales, contadores de peticiones y saldos (créditos, dólares) se muestran igual de bien. La tarjeta lleva como anillo la sesión o, si no hay, el límite más lleno (`headline`); si un proveedor solo tiene saldo, la cifra grande es el saldo («$7.50 left»).
- **Lo que se mantiene:** el escritor del formato antiguo para tu propia app de iPhone (`OpenUsageMobilePublisher`, abajo). No lee nada de otras apps: escribe un fichero para tu app.

## Transición: Altillo escribe el formato antiguo (fase 3)

Hecho el 24-09-2026. Las builds de **release** de Altillo escriben `openusage.mobile.v1` en `iCloud.me.badia.ailimits`, así que la app de TestFlight (`me.badia.ailimits`) sigue recibiendo datos sin el bridge.

- **Código:** `Apps/macOS/Modules/Usage/Legacy/` (`OpenUsageMobilePublisher`, que implementa `UsageSnapshotPublisher`). El mapeo es una función pura (`OpenUsageMobileExport`), con tests en `Tests/AltilloMacTests/OpenUsageMobileExportTests.swift`.
- **Qué escribe:** `OpenUsage/Mobile/v1/<deviceID>.json` en la raíz del contenedor. Escritura coordinada (`NSFileCoordinator`, `.forReplacing`) y atómica, 3 s después de cada tanda de refresco y fuera del hilo principal. Nunca escribe por ruta directa en `~/Library/Mobile Documents`: si el sistema no le da la URL del contenedor, no escribe nada.
- **Mismos ids que el bridge:** `claude.session`, `claude.weekly`, `claude.<modelo>` (p. ej. `claude.fable`), `codex.credits`, `codex.rate-limit-resets`… El iPhone guarda por id qué métricas se ven, cuál es la principal y las alertas, así que todo eso se conserva. Las ventanas van en porcentaje (`used` 0–100, `limit` 100, `periodDurationMilliseconds`) y los saldos como valores (dólares o contador).
- **Estado:** sin problema → `available` (`attention` si los datos tienen más de 15 min). Rate limit, red o respuesta rara → `attention` si quedan números, si no `unavailable`. Sesión caducada, llavero denegado → `unavailable`. Un proveedor sin configurar no aparece.
- **Device id:** se reutiliza el del bridge (`openusage.mobileBridge.deviceID.v1` en el dominio `me.badia.ailimits.collector`; en este Mac, `e69aee15-a3b9-4448-94a0-db20fe6e0e38`) y se guarda en `legacyMobileExport.deviceID`. Así Altillo sustituye el fichero del bridge y el iPhone no ve dos Macs. En un Mac donde nunca corrió el bridge se genera un UUID nuevo.
- **Cuándo está activo:** `isEnabled` = ajuste `legacyMobileExport` (UserDefaults, `true` por defecto) **y** la app firmada con el entitlement del contenedor **y** sesión de iCloud iniciada. Las builds de desarrollo (Debug, Apple Development, sin perfil) nunca lo tienen, así que ahí no hace nada. El entitlement solo lo pone `script/release.sh`, y solo si hay perfil (ver [release.md](release.md#icloud-transición)).
- **Lo que no se migra:** el bridge también copiaba el historial de OpenUsage a `OpenUsage/History/v1/`; Altillo no lo escribe, así que las gráficas de historial del iPhone se quedan congeladas. Se exportan los proveedores que Altillo lee de forma nativa: cada uno aparece en el iPhone cuando Altillo tiene su collector.
- **Comprobar una build firmada:** `open -g -n dist/Altillo.app --args -legacyMobileExportSelfTest altillo-selftest` escribe un documento de prueba con ese id y cierra la app; el resultado queda en `~/Library/Logs/Altillo/legacy-mobile-export-selftest.json`. `-legacyMobileExportSelfTestDelete altillo-selftest` lo borra (borrado coordinado, se propaga a iCloud).

### Retirar el bridge y el watchdog

Cuando tengas instalada una release de Altillo con iCloud (y el iPhone muestre datos frescos de este Mac con Altillo abierto), en este orden:

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

# 5. Comprobar: no queda nada corriendo y el fichero lo escribe Altillo (se actualiza con cada refresco).
launchctl print "gui/$(id -u)/me.badia.ailimits.collector.watchdog" 2>&1 | head -1   # "Could not find service"
pgrep -x openusage-mobile-bridge || echo "bridge parado"
ls -l "$HOME/Library/Mobile Documents/iCloud~me~badia~ailimits/OpenUsage/Mobile/v1/"
```

No hace falta borrar el fichero `e69aee15-….json`: Altillo escribe en ese mismo fichero. Solo si Altillo acabara usando otro id (un Mac donde nunca corrió el bridge), el fichero viejo del bridge se borra, ya retirado el bridge, con `open -g -n /Applications/Altillo.app --args -legacyMobileExportSelfTestDelete <id-viejo>` (borrado coordinado, se propaga al iPhone).

Mientras convivan (bridge y Altillo con iCloud a la vez) los dos escriben el mismo fichero y el iPhone alternará entre ambos (por ejemplo, Grok aparece y desaparece). Por eso conviene retirar el bridge nada más instalar la release.

