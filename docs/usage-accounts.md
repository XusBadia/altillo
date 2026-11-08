# Cuentas propias para Uso de IA

Estado de desarrollo: 8 noviembre 2026. Claude y Codex permiten conectar una cuenta seleccionada de cada proveedor desde Ajustes › Secciones › Uso de IA. La conexión real, la renovación real y la distribución todavía requieren QA; los tests con fixtures no acreditan esos recorridos.

## Experiencia

Conectar abre el login del proveedor en el navegador del sistema; la contraseña se introduce allí. Reconectar reemplaza la cuenta seleccionada después de obtener una autorización válida. Desconectar borra la identidad y los tokens locales de ese proveedor. No se afirma revocación remota: se gestiona en las conexiones/sesiones del propio proveedor. Desactivar la sección conserva la credencial para volver a usarla.

Hay una cuenta seleccionada por proveedor, no una bandeja multicuenta. Claude Code y Codex CLI conservan sus sesiones independientes. Los collectors de cuotas Claude/Codex no leen sus archivos ni sus elementos de Keychain, ni arrancan `codex app-server`. Los hooks y la detección de agentes son otro módulo y mantienen sus integraciones locales.

## Datos y renovación

La identidad, el token de acceso, el de renovación y su caducidad forman un registro atómico por proveedor en el Data Protection Keychain privado de Altillo: no sincronizable y `WhenUnlockedThisDeviceOnly`. No se incluyen en snapshots, historial, logs ni ajustes. Las peticiones autentican directamente con el proveedor, con sesiones efímeras sin cookies persistentes ni caché de disco. El navegador mantiene sus propias reglas de sesión y cookies.

La sesión se renueva con su propio refresh token, antes de caducar; las lecturas concurrentes de una cuenta comparten la renovación. Los cambios de cuenta y la desconexión invalidan las respuestas tardías para impedir que restauren una sesión anterior. La rotación pendiente de persistir se conserva temporalmente en memoria si el Keychain no está disponible. Los errores temporales no se presentan como una contraseña incorrecta. El collector permite un único reintento autorizado ante un `401`; un rechazo definitivo exige Reconectar.

## Contratos de proveedor

Referencia técnica manual: [OpenUsage v0.8.0-beta.5](https://github.com/robinebers/openusage/releases/tag/v0.8.0-beta.5), commit `f7e38d7608da061e609e6d0c8285531e56c2f950`. [BrowserProviderLogins.swift](https://github.com/robinebers/openusage/blob/f7e38d7608da061e609e6d0c8285531e56c2f950/Sources/OpenUsage/Services/BrowserProviderLogins.swift) y [OAuthLoginSupport.swift](https://github.com/robinebers/openusage/blob/f7e38d7608da061e609e6d0c8285531e56c2f950/Sources/OpenUsage/Services/OAuthLoginSupport.swift) documentan los contratos usados. La atribución MIT se conserva en [ThirdPartyNotices](../ThirdPartyNotices/README.md).

| | Claude | Codex / ChatGPT |
|---|---|---|
| Autorizar | `https://claude.ai/oauth/authorize` | `https://auth.openai.com/oauth/authorize` |
| Token y renovación | `https://platform.claude.com/v1/oauth/token`, POST JSON | `https://auth.openai.com/oauth/token`, POST form |
| Scope | `user:profile` | `openid profile email offline_access` |
| Callback | HTTP solo loopback, puerto efímero | HTTP solo loopback, puerto 1455, `/auth/callback` |
| Cuota | `https://api.anthropic.com/api/oauth/usage` | `https://chatgpt.com/backend-api/wham/usage` |
| Identidad | `/api/oauth/profile`: cuenta/organización y email | Claims de los tokens recibidos: cuenta ChatGPT y email; el proveedor valida el bearer en las peticiones |

Se usa PKCE S256 y `state`. El canje Claude incluye `state` y su autorización añade `code=true`; el de Codex usa los parámetros de compatibilidad del cliente instalado. Los client IDs son identificadores públicos de esos flujos, no secretos de Altillo. El puerto fijo de Codex puede estar ocupado por otro login: la app lo explica para que se termine y se reintente. No se ha implementado el fallback device-code de OpenUsage en esta entrega.

Estos servicios y clientes instalados no equivalen a una API pública estable para terceros ni a una aprobación del proveedor de Altillo. Las cuotas proceden de los mismos endpoints que antes: la nueva sesión elimina la dependencia del CLI para estas dos lecturas; no implica que el porcentaje sea más exacto ni garantiza que nunca haya que reconectar. No se solicitan capacidades de inferencia para Claude ni se consumen créditos o resets de cuota.

## Otros proveedores y revisión

Cursor, Copilot, Gemini/Antigravity, Grok, Z.ai, Devin y OpenCode mantienen sus fuentes locales y peticiones documentadas en [proveedores.md](proveedores.md). No se renuevan ni reescriben credenciales ajenas. No hay seguimiento programado de proyectos de referencia ni issues automáticos: las revisiones son manuales.

## Validación pendiente antes de distribuir

Comprobar con cuentas autorizadas: consentimiento, callback de ambas cuentas, cancelación, reinicio de la app y recuperación Keychain, renovación real con token rotado, rechazo del refresh y reconexión, cambio de cuenta sin mezclar cifras, desconexión durante una petición y ausencia de secretos en logs/archivos. Confirmar que no se ejecuta el CLI ni se toca su sesión. Registrar el build y los resultados reales por separado de los tests sintéticos.

## Evidencia local — 8 noviembre 2026

Validación final: **954 tests macOS en 75 suites** correctos, incluidos cambio de cuenta y las fronteras Cancel/commit. Paquete AltilloKit completo: **515 tests** (123 de AltilloUsage), más el test añadido para nombres de planes del perfil Claude; los 32 tests Claude se repitieron tras ese ajuste. Validador español: **0 de 1636 cadenas sin traducir**. Son pruebas sintéticas; no se han concedido permisos OAuth a cuentas reales durante esta implementación. Release universal compilada con Developer ID: firma estricta/perfil válidos, sin permiso de depuración. El helper sintético con sus entitlements exactos pasa add/read/delete en Keychain privado con `WhenUnlockedThisDeviceOnly`. iOS compila para simulador genérico. Artefacto local: `~/Library/Developer/BuildCache/altillo/Build/Products/Release/Altillo.app`; no instalado sobre la versión pública ni publicado.
