# Proveedores de uso de IA

Altillo consulta directamente los servicios de cada proveedor. No necesita una instalación de OpenUsage ni de ai-limits, ni lee sus datos o APIs. Parte de los mappers y reglas se adaptó de [OpenUsage](https://github.com/robinebers/openusage) (MIT, © 2026 Robin Ebers); el JSON-RPC histórico de Codex procede de [ai-limits](https://github.com/XusBadia/ai-limits). La procedencia y las licencias se conservan en [ThirdPartyNotices](../ThirdPartyNotices/README.md).

La revisión de cambios es **manual**, cuando Xus lo solicite. No hay workflow programado, manifiesto de seguimiento ni creación automática de issues. Las referencias de este documento permiten revisar los contratos y mantener la atribución del código adaptado.

## Alcance

Uso de IA muestra cuotas comunicadas por el proveedor, fechas de reinicio y antigüedad de la lectura. No convierte gasto en cuota ni muestra saldos monetarios, tokens o predicciones. OpenRouter está fuera del catálogo por ofrecer únicamente gasto/créditos. Una respuesta ausente o malformada no equivale a cero; los fallos conservan las últimas cifras junto con su fecha y problema.

## Conexión en Ajustes

Los interruptores activan el seguimiento del uso; no inician ni cierran sesiones. Un proveedor apagado
muestra «Seguimiento desactivado», aunque todavía no tenga datos o conserve un error anterior.

Grok, Copilot y Gemini ofrecen «Cómo conectar…» tanto en la lista de herramientas detectadas como en
la de herramientas sin configurar. La ayuda se despliega en el mismo panel:

- **Grok:** instalar la CLI, ejecutar `grok login` y completar el inicio de sesión en el navegador. El comando
  puede copiarse desde Ajustes. Una sesión en grok.com por sí sola no configura la CLI.
- **Copilot:** iniciar sesión en el editor o ejecutar `gh auth login` con la cuenta que tiene Copilot.
- **Gemini:** iniciar sesión en Antigravity. Si está instalado en Aplicaciones, Ajustes permite abrirlo.
  El collector mide las cuotas de Antigravity, no el uso de la web de Gemini.

Después de iniciar sesión, activar el seguimiento y pulsar «Comprobar de nuevo». Estas acciones no crean
una sesión propia de Altillo ni renuevan los tokens de las herramientas.

Una conexión OAuth propia de GitHub requiere una app registrada y verificar que su token permita consultar
las cuotas de Copilot; un login genérico no garantiza ese acceso. Referencia:
[Authorizing OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps).
Para Grok y Antigravity, este cambio conserva las fuentes de sesión que ya soportan sus collectors.

## Claude y Codex: cuentas de Altillo

El flujo en desarrollo conecta una cuenta seleccionada por proveedor desde Ajustes › Secciones › Uso de IA. Conectar abre el navegador del sistema; Reconectar sustituye esa autorización y Desconectar elimina la credencial local. Altillo guarda y renueva su propia sesión en el Keychain privado de este Mac. Estos dos collectors dejan de leer las credenciales CLI y de lanzar `codex app-server` para consultar cuotas. No se modifica la sesión de Claude Code, Codex ni la detección de agentes/hooks.

| Proveedor | Credenciales y peticiones |
|---|---|
| Claude | OAuth con PKCE y scope `user:profile`. Autoriza en `claude.ai`, canjea y renueva en `platform.claude.com`; perfil y cuota en `api.anthropic.com/api/oauth/profile` y `/api/oauth/usage`. El perfil proporciona identidad, organización y plan. |
| Codex / ChatGPT | OAuth con PKCE y scopes `openid profile email offline_access` en `auth.openai.com`. Cuota en `chatgpt.com/backend-api/wham/usage`, con bearer e identificador de cuenta. Callback local en puerto 1455; si está ocupado, se informa para terminar el otro inicio de sesión y reintentar. |

La revisión manual de estos contratos usa [OpenUsage v0.8.0-beta.5](https://github.com/robinebers/openusage/releases/tag/v0.8.0-beta.5), commit `f7e38d7608da061e609e6d0c8285531e56c2f950` (8 noviembre 2026): `Services/BrowserProviderLogins.swift`, `Services/OAuthLoginSupport.swift`, `Providers/AccountProviderRuntime.swift` y los clientes/mappers Claude y Codex. Se mantienen los endpoints de cuota anteriores: el cambio independiza la autorización, no demuestra una precisión mayor. Son flujos compatibles con clientes instalados de los proveedores, no una garantía de APIs públicas estables para terceros. Véase [diseño, privacidad y validación](usage-accounts.md).

## Otros proveedores

Cursor, GitHub Copilot, Gemini/Antigravity, Grok, Z.ai, Devin y OpenCode mantienen sus fuentes locales actuales: sesión del editor/CLI o clave API del proveedor. Altillo las lee sin renovarlas ni sobrescribirlas. Cada collector presenta una pista de configuración. No se importa automáticamente ninguna de estas credenciales al nuevo almacén OAuth.

La clasificación de errores de Copilot distingue un `403` de rate limit (`X-RateLimit-Remaining: 0` o `Retry-After`) de un rechazo real. La espera usa `Retry-After`, después `X-RateLimit-Reset` futuro y, si faltan, un plazo de seguridad; conserva las cifras previas sin pedir otra autenticación.

## Referencias técnicas anteriores

Los contratos de otros proveedores y las reglas de alertas se revisaron contra `4ce788775e0cb3ec779d353b2ac9f9d7e8765bb4` (23 septiembre 2026). Los mappers iniciales y las fuentes locales se documentan con sus commits en los comentarios de cada collector y en ThirdPartyNotices. La proyección `UsagePace` se retiró el 26 de octubre; las alertas actuales responden a umbrales observados, límite alcanzado y reposición.

## Revisión manual de un proveedor

1. Consultar sus notas y fuentes oficiales y, cuando resulte útil, los cambios de la implementación de referencia. Registrar la versión y el contrato concreto que afecta a Altillo.
2. Adaptar el cambio en el collector correspondiente sin importar datos ni depender de la ejecución de otra app de uso. Conservar las atribuciones cuando se adapte código.
3. Añadir fixtures que reproduzcan el contrato y sus fallos, y ejecutar los tests de AltilloUsage. Las pruebas sintéticas no sustituyen un login o una renovación real.
4. Actualizar esta guía y ThirdPartyNotices si cambia la procedencia o el flujo de datos. La validación real y la publicación se registran por separado.
