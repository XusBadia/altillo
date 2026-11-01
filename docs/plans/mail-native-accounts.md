# Correo con cuentas nativas en Altillo

Fecha de revisión: **1 de noviembre de 2026**. Estado: **R61 en curso, implementación autorizada; sin publicar y pendiente de OAuth real y validación de distribución**.

## Recomendación ejecutiva

**Sí: Altillo puede ofrecer un cliente de correo sencillo con conexión directa de cuentas. Es una mejor dirección de producto que pedir al usuario que configure reglas y AppleScripts.**

La integración de 0.13.0 es un **puente temporal funcional**, no la mejor base para el onboarding definitivo. Su recepción real está validada y el problema de consultas externas a las reglas ya fue retirado. La objeción es de experiencia y alcance: instalación manual, dependencia de Mail abierto y ausencia de una bandeja de lectura.

Dirección aprobada:

- **Gmail API y Microsoft Graph**, con autorización del proveedor y procesamiento exclusivamente local.
- Primera entrega macOS: conectar cuentas, ver mensajes recientes de Inbox, leerlos y utilizar códigos/enlaces reconocidos.
- **Sin backend de correo, envío ni caché persistente de contenido.**
- iCloud e IMAP genérico en una fase posterior, con sus excepciones visibles.
- Conservar el puente existente como compatibilidad durante la transición.

No hay un botón universal que funcione igual con cualquier proveedor. Gmail requiere verificación; algunas empresas bloquean el consentimiento; iCloud puede exigir una contraseña específica.

## Opciones, permisos y coste real

### Gmail: opción recomendada para Google

Usar `gmail.readonly`: permite leer cuerpos y reconocer códigos sin solicitar escritura o envío. Es un **scope restringido**. `gmail.metadata` tampoco evita esa clasificación y no permite leer cuerpos. Los permisos de complementos de Gmail no sirven como sustituto para un cliente independiente. [Scopes oficiales](https://developers.google.com/workspace/gmail/api/auth/scopes).

Para macOS, elegir cliente OAuth **Desktop**, authorization code con **PKCE S256**, `state` y retorno a una dirección loopback con puerto efímero. Google documenta el navegador del sistema y loopback como ruta para escritorio; no basar el diseño en un esquema personalizado aceptado por todos los proveedores. El client ID se distribuye con la app; un cliente instalado no puede custodiar un secreto confidencial. [OAuth de escritorio](https://developers.google.com/identity/protocols/oauth2/native-app).

**Verificación y evaluación de seguridad son trámites distintos.** Una app pública con `gmail.readonly` debe pasar la verificación correspondiente. La documentación de Google vincula la evaluación de seguridad adicional al acceso a datos restringidos desde o a través de servidores de terceros. La arquitectura local propuesta evita ese supuesto; no convierte la exención en una aprobación garantizada. Debe declararse y confirmarse durante la revisión. Un proxy, envío de contenido a IA o telemetría con mensajes cambiaría esa evaluación. [Revisión de scopes restringidos](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

La ayuda general de CASA tiene una redacción más amplia; por eso no presupuestaría una auditoría obligatoria ni prometería formalmente su exención antes de la clasificación de Google. Tampoco asignaría una tarifa inventada. [Evaluación de seguridad](https://support.google.com/cloud/answer/13465431?hl=en).

**IMAP no evita este trámite:** Gmail utiliza `https://mail.google.com/`, de alcance mayor; Google recomienda Gmail API cuando bastan permisos más precisos. [OAuth para IMAP/SMTP](https://developers.google.com/workspace/gmail/imap/xoauth2-protocol).

Coste principal: ingeniería, expediente de verificación y mantenimiento. El cliente también debe respetar cuotas y backoff; no necesita infraestructura propia para consultar periódicamente. [Cuotas de Gmail](https://developers.google.com/workspace/gmail/api/reference/quota).

### Outlook/Microsoft 365: Graph, con permisos delegados

Solicitar **`Mail.Read` y `User.Read` delegados**. `User.Read` permite resolver la identidad estable mediante `/me`; no concede escritura de correo. `Mail.ReadBasic` excluye cuerpo, previsualización y adjuntos: no cubre lectura ni códigos en el cuerpo. `Mail.Read` admite cuentas personales y profesionales; no exige consentimiento administrativo por definición, aunque las políticas del tenant pueden exigirlo o impedirlo. No solicitar permisos de aplicación, `Mail.ReadWrite` ni `Mail.Send`. [Permisos Graph](https://learn.microsoft.com/en-us/graph/permissions-reference).

Registrar una aplicación para cuentas personales y organizaciones. Usar **MSAL para macOS**, que utiliza autenticación del sistema y admite `ASWebAuthenticationSession`; obtener renovación mediante su caché de tokens. PKCE pertenece al flujo de autorización; `ASWebAuthenticationSession` es la presentación, no un sustituto de ese protocolo. [MSAL y navegador](https://learn.microsoft.com/en-us/entra/msal/objc/customize-webviews), [authorization code](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow).

Primera cobertura: Outlook.com y buzón principal Exchange Online. Excluir buzones compartidos, nubes soberanas y Exchange local del compromiso inicial. Una identidad Microsoft sin buzón compatible debe producir un error explicativo.

La verificación del editor ayuda en entornos empresariales, pero no anula las políticas del administrador. Algunas aplicaciones multitenant sin editor verificado no pueden recibir consentimiento del usuario. [Verificación del editor](https://learn.microsoft.com/en-us/azure/active-directory/develop/publisher-verification-overview).

### iCloud e IMAP genérico: ampliación, no atajo

iCloud documenta IMAP con TLS en `imap.mail.me.com:993` y contraseña específica de aplicación; requiere 2FA. Cambiar la contraseña principal revoca las contraseñas específicas. Apple también documenta autorización directa para **aplicaciones compatibles**, pero esa documentación no demuestra que Altillo pueda adoptar libremente ese mecanismo. Planificar con contraseña específica, sin confundirlo con Sign in with Apple. [Servidores iCloud](https://support.apple.com/en-us/102525), [contraseñas específicas](https://support.apple.com/en-us/102654).

IMAP ofrece cobertura amplia, pero exige gestionar conexiones, MIME, UID/UIDVALIDITY, reconexiones y diferencias entre servidores. OAuth2 sigue requiriendo registros y permisos por proveedor. En Microsoft, IMAP emplea permisos propios de Exchange, no tokens Graph intercambiables. [OAuth IMAP/SMTP Microsoft](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth/).

**SMTP no es necesario para leer.** Aplazarlo junto con componer y responder; no pedir credenciales o permisos de envío anticipadamente.

Para proveedores genéricos: configuración conocida incluida en la app y formulario avanzado de servidor/puerto/usuario. Autodiscovery puede sugerir datos, pero no prueba la identidad del destino ni sustituye OAuth. No enviar contraseñas a hosts descubiertos sin confirmación, ni usar HTTP o degradar TLS. La base de Thunderbird es una referencia real, no una garantía universal. [Autoconfiguración Thunderbird](https://support.mozilla.org/en-US/kb/automatic-account-configuration).

### MailKit: mejora posible del puente, no conexión independiente

MailKit ofrece extensiones de acciones, composición, seguridad y bloqueo de contenido. Una extensión puede pedir otra invocación con el cuerpo, pero sigue operando dentro del flujo de Mail y requiere habilitación. No constituye una API general para conectar cuentas y navegar su bandeja desde Altillo. [MailKit, Apple](https://developer.apple.com/la/videos/play/wwdc2021/10168/), [activación de extensiones](https://support.apple.com/en-mide/guide/mail/mlhla9a93cd5/mac).

Podría reducir parte de la configuración manual, pero invertir ahora en ella mantendría la dependencia que el usuario quiere eliminar.

### Dependencias verificadas

- **AppAuth-iOS/macOS**, Apache 2.0: candidato elegido para OAuth Google con navegador y loopback. Release consultada: **3.0.0, agosto de 2026**. Aislar sus objetos detrás del coordinador de autenticación. [Repositorio](https://github.com/openid/AppAuth-iOS).
- **MSAL**, MIT: elegido para Microsoft; release consultada **2.17.0, octubre de 2026**. Usar su almacenamiento de tokens, evitando una segunda copia propia. [Repositorio](https://github.com/AzureAD/microsoft-authentication-library-for-objc).
- **swift-nio-imap**, Apache 2.0: actividad reciente; última release consultada **0.3.0, julio de 2026**. `main` utiliza Swift 6.2 y ofrece una capa `async/await`, pero su README aún advierte que **no está listo para producción**. No asumir que las capacidades de `main` existen en esa release. Elegirlo para un spike IMAP, no comprometer su publicación todavía. [Repositorio](https://github.com/apple/swift-nio-imap), [manifest](https://raw.githubusercontent.com/apple/swift-nio-imap/main/Package.swift).
- **MailCore2**, BSD: alternativa con IMAP/SMTP/MIME y API asíncrona Objective-C/C++. No está archivado, pero su última release consultada es **0.6.4 de 2020** y su manifest SPM apunta a un XCFramework de 2020 alojado en un fork. No adoptarlo como dependencia directa sin reconstrucción y validación de arquitecturas, TLS y concurrencia. [Repositorio](https://github.com/MailCore/mailcore2), [manifest](https://raw.githubusercontent.com/MailCore/mailcore2/master/Package.swift).

La implementación integra AppAuth y MSAL; el resultado de compilación y las pruebas se registrará al cerrar QA. Esto no acredita todavía OAuth con cuentas reales ni callbacks en el artefacto distribuido. La [guía de registros OAuth](../mail-oauth.md) distingue configuración, consentimiento y verificación pública.

## Alcance aprobado y arquitectura

### Experiencia cerrada para la primera entrega

1. Ajustes → Correo → **Añadir cuenta** → Google o Microsoft.
2. Explicación breve: acceso de lectura, comunicación directa con el proveedor, contenido local.
3. Autorización del proveedor → cuenta conectada → últimos **50 mensajes de Inbox por cuenta**.
4. Selector de cuenta y vista conjunta; lectura en un panel de Altillo.
5. Actualizar, reconectar, desconectar y acciones de código/enlace.
6. Estados claros: conectando, conectado, sin red, sesión caducada y acceso bloqueado por la organización.

Leer en Altillo **no cambia el estado leído del servidor**. Los filtros existentes pasan a controlar avisos; no ocultan silenciosamente mensajes de la bandeja.

Aplazar: enviar, responder, archivar, borrar, marcar leído, descargar adjuntos, búsquedas, carpetas arbitrarias, conversaciones, resúmenes IA y sincronización entre dispositivos. No publicar botones de proveedores aún no disponibles.

### Separar bandeja y avisos

El `MailStore` actual combina socket, caducidad, filtros y presentación; `MailEnvelope` exige un evento reciente y construye `message://` desde el RFC Message-ID. No convertirlo en un almacén general quitando sus controles.

Dentro del target compartido **AltilloMail**:

- `NativeMailAccount`: identificador local estable, proveedor e identidad remota.
- `NativeMailMessageKey`: cuenta + identificador del proveedor; RFC Message-ID opcional y nunca clave única global.
- `NativeMailSummary` y `NativeMailContent`: separar listado y cuerpo.
- `NativeMailProvider: Sendable`: `bootstrap`, `changes`, `fetchContent`; respuestas paginadas con cursor opaco.
- `NativeMailSynchronizer` como actor: un flujo de sincronización por cuenta, cancelación y recuperación.
- `NativeMailBodyCache`: RAM acotada.
- Reutilizar `MailActionRecognizer` para códigos y enlaces, sin aceptar instrucciones del correo.
- `MailArrival`: evento explícito, distinto de un elemento recuperado para poblar la bandeja.

En el target macOS:

- `NativeMailController`, observable en `MainActor`, coordina cuentas, bandeja y lector.
- `MailAuthCoordinator`, `MailCredentialStore` y caché privada de MSAL para las credenciales.
- Convertir el `MailStore` existente en fachada de avisos/compatibilidad, conservando 20 avisos y cinco minutos.
- Reutilizar políticas del notch, revocación de tarjetas y exclusión de Clipboard.
- Actualizar Ajustes y `DesvanMail`; lectura nativa en texto, sin WebView en el MVP.
- Conservar `Apps/MailBridge`, protocolo del socket y recursos instalados durante la convivencia.
- Declarar dependencias y callbacks en `project.yml`; mantener el paquete compartido sin AppKit ni suposiciones de ejecución en segundo plano de iOS.

### Autenticación, sincronización y límites

Google usa AppAuth con navegador externo y loopback; Microsoft, MSAL con autenticación del sistema. No forzar un único mecanismo de callback para ambos.

Tokens y contraseñas en **Keychain**, no sincronizables entre dispositivos. Access tokens en memoria cuando sea posible; renovación serializada por cuenta. En Google, persistir el estado de autorización seguro; en Microsoft, usar la caché de MSAL configurada para Altillo.

Distinguir pausa del módulo y desconexión. Pausar cancela red y limpia contenido, conservando la cuenta; desconectar elimina credenciales y estado local. La desconexión actual es local; la revocación remota se realiza desde el portal del proveedor. Google puede revocar permisos de todo el proyecto para esa cuenta. No afirmar «permiso revocado» por haber borrado Keychain.

Sincronización implementada:

- Google: snapshot inicial de 50 mensajes de Inbox y checkpoint `historyId` obtenido antes del listado; después, historial paginado y comprobación del estado final de Inbox; cursor inválido → reconstrucción silenciosa. [Sincronización Gmail](https://developers.google.com/workspace/gmail/api/guides/sync).
- Microsoft: **snapshot completo de los últimos 50 mensajes de Inbox en cada refresco**, con identificadores inmutables, orden descendente por recepción y cursor interno `snapshot-v1`. Se reemplaza esa ventana y se comparan IDs para altas, cambios de leído y desapariciones. Los `nextLink` solo se siguen para completar esos 50 y deben apuntar a Inbox en `https://graph.microsoft.com`.

  **Ajuste deliberado frente al plan de Astra:** no se usa Graph delta en esta primera entrega. Establecer el `deltaLink` inicial normalmente requiere recorrer la carpeta; el snapshot acotado evita descargar el histórico para una interfaz que conserva 50 mensajes. No es un archivo sincronizado completo: una llegada que entre y desaparezca entre consultas puede no detectarse. Una futura bandeja histórica podrá justificar delta. [Listado Graph](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0), [delta de mensajes](https://learn.microsoft.com/en-us/graph/delta-query-messages).
- Inicialización, reinicio, desbloqueo y reconstrucción **nunca generan avisos históricos**.
- Solo avisar de altas posteriores a la línea base de la sesión y con fecha de recepción reciente. Movimientos de mensajes antiguos a Inbox no cuentan como llegada nueva.
- Refresco cada 30 segundos con la vista abierta y 120 segundos en segundo plano; 300 segundos en bajo consumo. Sin polling durante bloqueo, reposo o módulo apagado.
- Respetar `Retry-After` (segundos o fecha HTTP); sin reintentos de red ocultos. Un 401 provoca una única renovación y repetición, serializada por cuenta. Otros fallos se vuelven a comprobar en el siguiente ciclo; sesión caducada o acceso denegado requieren acción explícita.
- Sin backend, la recepción es periódica y exige Altillo ejecutándose; no prometer push instantáneo.

### Contenido y privacidad

Bandeja limitada a 50 resúmenes por cuenta; cuerpos bajo demanda. Para acciones automáticas, descargar únicamente cuerpos de nuevas llegadas elegibles. Límites iniciales: 1 MiB por cuerpo decodificado, 10 MiB de cuerpos totales y descarga automática del cuerpo de hasta dos llegadas por ciclo; las restantes conservan sus metadatos y el lector obtiene el cuerpo bajo demanda. Las respuestas de cuerpo tienen además un límite de 4 MiB en tránsito. Mostrar truncamiento; no descargar adjuntos.

Preferir `text/plain`; convertir HTML a texto mediante un parser sin ejecución ni red. Eliminar scripts, estilos, formularios e imágenes; no cargar píxeles, fuentes, previsualizaciones o recursos remotos. Enlaces solo por acción explícita y con dominio visible. El correo se trata como contenido no confiable, nunca como instrucciones.

Persistir únicamente identidad de cuentas y credenciales/referencias seguras en Keychain; los cursores de sincronización permanecen en RAM. No escribir asuntos, remitentes, cuerpos, códigos ni enlaces en disco, logs, errores, crash breadcrumbs, Spotlight o Pregunta. Usar sesiones de red sin caché persistente.

La promesa cambia: **los avisos** siguen durando cinco minutos; **la bandeja** permanece en RAM mientras la sesión está desbloqueada. Bloquear, dormir o apagar limpia ambas. Sin red se puede leer solo lo ya cargado en esa sesión; después de reiniciar no habrá correo offline.

Una caché persistente futura requeriría decisión separada: consentimiento, cifrado, retención, borrado, backups y cambios en la política de privacidad. «Local» no equivale a «no persistente».

## Fases, aceptación y transición

### Estimación inicial de la investigación

Referencia del plan inicial, no calendario ni estado actual de ejecución:

1. **Contrato, fixtures y diseño de privacidad: 2–4 días-persona.** Modelos, adaptadores simulados, estados y contenido hostil.
2. **Núcleo compartido, bandeja y avisos separados: 5–8 días-persona.** Implementable sin credenciales.
3. **Gmail y OAuth: 4–7 días-persona.** Preparar expediente de verificación en cuanto exista una demostración funcional.
4. **Graph y MSAL: 4–7 días-persona.** Puede avanzar durante la revisión externa de Google.
5. **Compatibilidad, endurecimiento y distribución: 4–7 días-persona.**

Total orientativo Gmail + Microsoft: **19–33 días-persona**, excluyendo esperas de proveedores y cambios de alcance.

iCloud/IMAP: **8–15 días-persona adicionales** tras un spike de dependencia, MIME y reconexión. Si la biblioteca no supera las pruebas de producción, no sustituirla silenciosamente: mantener esa ampliación fuera de la release.

Dependencias externas reales: titular del proyecto Google y registro Entra, client IDs, dominio y política de privacidad públicos, revisión Google, eventual verificación del editor Microsoft y cuentas sintéticas autorizadas para QA. No pedir al usuario final que registre su propia app OAuth. No se da por creado, aprobado o validado ninguno de esos registros por la implementación local. La [guía OAuth](../mail-oauth.md) recoge los pasos de distribución y la [guía de firma](../native-mail-signing.md) los requisitos de Keychain.

### Pruebas de aceptación

- **OAuth:** cancelar devuelve al estado anterior; `state`/PKCE incorrectos se rechazan; renovación concurrente no duplica peticiones; revocación/`invalid_grant` exige reconectar sin bucle; acceso denegado por tenant tiene explicación específica.
- **Desconexión:** borra credenciales y contenido de la cuenta; respuestas en vuelo no la recrean; no afecta a otras cuentas.
- **Sincronización:** paginación, duplicados, borrados, cambios de carpeta, cursor inválido, 429/5xx y desconexión de red. Dos cuentas con igual RFC Message-ID conservan mensajes independientes.
- **Llegadas:** importar 50 mensajes produce cero avisos; una llegada posterior produce uno; reinicio, cambio de reloj, desbloqueo y movimiento de correo antiguo no reproducen alertas.
- **Privacidad:** inspección de archivos, caché HTTP y logs con marcadores sintéticos confirma ausencia de contenido; lock/sleep limpia lectores, acciones y tarjetas.
- **Contenido hostil:** HTML con trackers/JS/forms, MIME malformado, codificación inválida, cuerpos enormes, enlaces ambiguos y dominios engañosos. Cero solicitudes a recursos embebidos.
- **Consumo:** temporizadores con reloj simulado; ninguna red con módulo apagado/bloqueado; sin crecimiento de RAM durante una sesión sintética prolongada.
- **Distribución:** concurrencia estricta, tests de paquete y macOS, compilación iOS, firma/notarización y callbacks OAuth en app instalada. La suite histórica de 900 tests acredita R01, no esta nueva arquitectura.

### Convivencia con 0.13.0

Mantener **R01 Hecho, publicado en 0.13.0**. Mantener **R61: Cuentas de correo nativas — En curso**, sin renumerar iniciativas ni confundir implementación con publicación.

Conservar ajustes, filtros, manifiesto, scripts y reglas existentes. El nuevo onboarding prioriza cuentas directas; la configuración antigua aparece como «Apple Mail — conexión existente».

En la primera transición, fuentes activas mutuamente excluyentes: puente o cuentas directas. Añadir una cuenta mientras funciona el puente prepara la conexión; el usuario elige «Usar cuentas directas». Esto evita duplicados cuando el nombre de cuenta del puente no permite una correspondencia fiable. El cambio detiene el receptor, conserva sus archivos y permite volver al modo anterior.

No consultar reglas de Mail ni borrar scripts automáticamente. No retirar el helper hasta una deprecación posterior explícita, porque las reglas instaladas podrían seguir invocándolo.

Texto propuesto: «Ahora puedes conectar Google o Microsoft directamente. Tu conexión actual con Apple Mail seguirá disponible hasta que elijas cambiar. Las reglas y scripts se retiran manualmente».

Los anuncios existentes de X/LinkedIn siguen **guardados, sin programar ni publicar**. No atribuir conexión directa a la release 0.13.0.

### Estado y puertas pendientes

Plan revisado con Astra y dirección aprobada por Xus el 1 de noviembre de 2026. R61 está **En curso**; R01 conserva su estado publicado en 0.13.0. Se implementan proveedores, OAuth, sincronización acotada, lector, controles de cuenta y convivencia del puente. Las pruebas sintéticas no acreditan inicio de sesión ni entrega por red en cuentas reales.

Antes de distribuir: configurar registros propios Google/Entra, comprobar firma y Keychain de la app instalada, ejecutar OAuth y renovación reales con cuentas autorizadas, completar el proceso Google aplicable, validar cancelación/revocación/lock/sleep y registrar QA del artefacto. La revisión empresarial de Microsoft depende del tenant. iCloud/IMAP, envío y operaciones de escritura siguen fuera de este alcance. No se ha publicado una actualización de cuentas directas ni se han programado anuncios.

### Verificación de la implementación — 1 noviembre 2026

- `swift test --package-path Packages/AltilloKit`: **465 tests**, todos correctos; 50 corresponden a AltilloMail. Incluyen proveedores HTTP sintéticos, paginación, snapshots, identidad, HTML/MIME, límites, caché compartida y respuestas tardías.
- Suite completa macOS con firma ad hoc: **921 tests en 72 suites**, todos correctos. Incluye OAuth con driver/vault inyectados, renovación y cancelación, cuentas múltiples, purga al bloquear/pausar/desconectar y migración de ajustes. La suite con Developer ID también pasó antes del último caso de reactivación (920 tests).
- Localización: **0 de 1571 cadenas sin español**. `actionlint`, validación YAML, sintaxis del script de release, gates de publicación y rechazo de builds de correo sin perfil/registros: correctos. Licencias AppAuth/MSAL incluidas en los recursos compilados.
- Compilación de `AltilloiOS` para simulador genérico sin firma: correcta; el nuevo código compartido no rompe el companion.
- Los tests alojados ya no arrancan servicios reales del usuario; la prueba de reglas consume la plantilla distribuida en el bundle, sin leer el checkout protegido por Documentos.
- No hay client IDs de Altillo configurados ni perfil macOS válido para `me.badia.altillo`. La sesión CLI Google Cloud exige reautenticación. El control de interfaz devolvió `aborted before dispatch` y no permitió QA visual ni gestionar las consolas. No se ha validado consentimiento, renovación, recepción por red ni Keychain de producción reales; no confundir los tests sintéticos con esos pasos.
- El pipeline de publicación exige ambos client IDs válidos, un perfil Developer ID embebido y su identificador autorizado. Instala el perfil en CI, genera el mapping de exportación y comprueba de nuevo el artefacto exportado. Los registros externos y la aprobación de proveedores no se crean automáticamente.
