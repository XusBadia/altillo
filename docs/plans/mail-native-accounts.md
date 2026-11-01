# Correo con cuentas nativas en Altillo

Revisión: **1 de noviembre de 2026**. **R61 en curso, sin publicar**. Xus aprobó ampliar la primera dirección de lectura a envío/respuestas, gestión de leído/archivo/papelera, adjuntos e iCloud/IMAP. Las pruebas de la baseline anterior no acreditan esta ampliación ni OAuth/SMTP reales.

## Dirección y alcance aprobados

Conectar cuentas directamente sustituye el onboarding principal de reglas/AppleScripts, conservando el puente de 0.13.0 como alternativa reversible. La [guía de correo](../correo.md) describe ambos modos y la [guía OAuth](../mail-oauth.md) los registros del distribuidor.

| Proveedor | Autorización y transporte | Alcance |
| --- | --- | --- |
| Google | AppAuth, navegador del sistema y loopback; Gmail API | Leer, enviar/responder, leído/no leído, archivar, papelera y archivos adjuntos |
| Microsoft | MSAL y ASWebAuthenticationSession; Microsoft Graph | Mismas operaciones en Outlook.com y buzón principal Exchange Online, nube pública |
| iCloud | Contraseña específica de aplicación; IMAP/SMTP con TLS | Mismas operaciones, sujetas a capacidades y carpetas del servidor |
| Otro IMAP | Servidores explícitos, usuario y contraseña/app password; IMAP/SMTP con TLS | Servidores que admitan los métodos de autenticación y operaciones implementados; sin promesa de compatibilidad universal |

Bandeja de los últimos **50 mensajes de Inbox por cuenta**, vista conjunta y selector, lector de texto, compositor con Para/Cc/Cco, asunto y adjuntos, respuesta al Reply-To si existe y vínculo al hilo original. Abrir el lector **no marca como leído**; hay una acción explícita para cambiarlo. No se implementa eliminación permanente ni vaciado de papelera.

La primera entrega sigue excluyendo búsqueda, navegación por todas las carpetas, conversaciones completas, resúmenes IA y sincronización entre dispositivos. No se necesita un backend de correo de Altillo.

## Permisos y registros

### Google

La versión de autorización 2 solicita `openid`, `email` y `https://www.googleapis.com/auth/gmail.modify`. `gmail.modify` es **restringido** y cubre lectura, gestión y envío sin borrado permanente; no se pide `gmail.send` por separado porque sería redundante. La conexión de solo lectura anterior debe volver a autorizarse: el token antiguo no acredita acceso de escritura. No se solicita `https://mail.google.com/`, ni la contraseña de Google. [Scopes oficiales](https://developers.google.com/workspace/gmail/api/auth/scopes), [permisos de envío](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send).

Cliente OAuth Desktop público, PKCE S256, `state`, nonce y listener loopback efímero mediante AppAuth. No distribuir client secrets. Los client IDs pertenecen al distribuidor, no a cada usuario. [OAuth de escritorio](https://developers.google.com/identity/protocols/oauth2/native-app).

Una aplicación pública debe completar la verificación aplicable a estos permisos salvo exención real. Verificación y evaluación adicional de seguridad son distintas; el uso de servidores de terceros para datos restringidos puede exigir evaluación. La arquitectura local no garantiza una exención formal. Declarar uso real de envío, adjuntos y borradores, además de lectura. IMAP de Gmail tampoco evita OAuth/verificación y pide un scope más amplio; se mantiene Gmail API. [Verificación restringida](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

### Microsoft

Permisos delegados **`User.Read`, `Mail.ReadWrite` y `Mail.Send`**. MSAL añade `openid`, `profile` y `offline_access`; no pasarlos como scopes de recurso. No hay permisos de aplicación ni acceso a buzones ajenos. `Mail.ReadBasic` y el token anterior `Mail.Read` no cubren esta ampliación. [Permisos Graph](https://learn.microsoft.com/en-us/graph/permissions-reference).

Aplicación multitenant y cuentas personales, autoridad `common`, callback `msauth.<bundle-id>://auth` registrado y declarado en la app. La configuración exacta figura en la [guía OAuth](../mail-oauth.md). Las políticas empresariales pueden exigir consentimiento administrativo o impedir el acceso. Verificar el editor no elimina esas restricciones. Buzones compartidos, nubes soberanas y Exchange local quedan fuera de esta cobertura. [Verificación del editor](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview).

### iCloud y otros servidores

iCloud usa `imap.mail.me.com:993` con TLS y `smtp.mail.me.com:587` con STARTTLS. Requiere una **contraseña específica de aplicación y 2FA**; no se pide la contraseña principal del Apple Account. La configuración usa la dirección completa para SMTP; algunos buzones pueden necesitar ajustar el usuario IMAP. Cambiar la contraseña principal revoca las específicas. Sign in with Apple no concede acceso al correo. [Servidores iCloud](https://support.apple.com/en-us/102525), [contraseñas específicas](https://support.apple.com/en-us/102654).

Otro IMAP requiere indicar dirección, usuario, host/puerto IMAP y SMTP y seguridad SMTP: TLS implícito o STARTTLS obligatorio. El adaptador IMAP usa TLS desde la conexión; no ofrece IMAP en texto plano. SMTP autentica únicamente después de TLS y rechaza un servidor que no anuncie STARTTLS cuando se ha elegido ese modo. No hay autodiscovery que reciba contraseñas ni degradación a conexiones inseguras. Deben usarse datos oficiales del proveedor y una contraseña específica cuando la ofrezca.

La compatibilidad depende de IMAP autenticado y SMTP AUTH soportados; un proveedor que exige OAuth propio no se convierte en compatible mediante una contraseña normal. Gmail/Microsoft deben usar sus conectores dedicados. Archivar/papelera requieren carpetas de uso especial y una operación de traslado segura; se informa si el servidor no la soporta, sin sustituirla por borrado/expunge.

## Arquitectura y sincronización

`AltilloMail` contiene contratos `NativeMailAccount`, `NativeMailMessageKey` (cuenta + ID remoto), `NativeMailSummary`, `NativeMailContent`, `NativeMailProvider` y operaciones de composición/adjuntos. `NativeMailSynchronizer` separa carga inicial de llegadas; `NativeMailBodyCache` comparte una RAM acotada. `NativeMailMIME` valida destinatarios/cabeceras y escribe MIME, evitando inyección y excluyendo Cco de las cabeceras SMTP (sus destinatarios van en el envelope).

En macOS, `MailAuthCoordinator` y `MailCredentialStore` gestionan identidad/autorización; `NativeMailController` coordina bandeja, lector, compositor y acciones. AppAuth y MSAL quedan aislados del núcleo compartido. Se conserva el helper del puente, que las reglas existentes pueden seguir invocando.

- **Gmail:** snapshot inicial de 50 con `historyId` previo al listado; historial paginado y comprobación del estado final de Inbox. Cursor perdido provoca reconstrucción silenciosa.
- **Graph:** snapshot completo de los 50 más recientes en cada refresco, IDs inmutables y cursor interno `snapshot-v1`. **Ajuste frente al plan inicial de Astra:** no se usa delta para evitar recorrer el histórico completo al obtener el primer deltaLink. Es una ventana acotada, no un archivo completo; una llegada que entra y sale entre consultas puede no detectarse. Los nextLink se validan contra el host y la ruta de Inbox permitidos. [Listado Graph](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0), [delta](https://learn.microsoft.com/en-us/graph/delta-query-messages).
- **IMAP:** snapshot reciente con IDs compuestos por UIDVALIDITY/UID; cambios de validez reconstruyen la línea base y no reutilizan IDs de una época anterior.
- Carga inicial, reinicio, desbloqueo y recuperación no generan avisos históricos. Solo altas posteriores y recientes pueden avisar.
- Refresco de 30 segundos con bandeja abierta, 120 en segundo plano y 300 en bajo consumo. Sin polling al bloquear, dormir o desactivar.
- HTTP respeta Retry-After y renueva tras un 401 una sola vez. No hay bucles ocultos de reintentos ni promesa de push instantáneo.

## Envío, gestión y adjuntos

Enviar y responder requieren una acción explícita. Gmail incluye In-Reply-To/References y resuelve threadId; Graph usa createReply cuando se dispone del mensaje original. SMTP preserva cabeceras de respuesta. Un éxito de API/SMTP acredita **aceptación por el proveedor**, no entrega final al destinatario.

**Envío incierto:** si se pierde la conexión o aparece un error ambiguo tras poder haberse enviado, Altillo no reenvía automáticamente. Comprobar Enviados en el proveedor y, si hace falta, confirmar con el destinatario antes de repetir. En iCloud/IMAP, **Guardar una copia en Enviados mediante IMAP** está activado por defecto: tras la aceptación SMTP se intenta IMAP APPEND con el mismo Message-ID. Desactívalo si tu servidor SMTP ya guarda la copia para evitar duplicados. Si falla solo la copia, se informa de que el mensaje fue enviado y **no debe reenviarse**; no se convierte en un fallo de entrega. Un envío incierto anterior a la aceptación no provoca APPEND ni reintento.

La interfaz limita los adjuntos de salida a **18 MiB en total por composición** (por tanto también por archivo), hasta 50 archivos y **25 MiB para el MIME completo**, incluyendo cuerpo y expansión base64. El encoder valida además el tamaño final. Graph crea un borrador y sube adjuntos individualmente; para archivos grandes usa uploadSession y rangos de menos de 4 MB. La capability URL debe ser HTTPS del host Outlook permitido y nunca recibe el bearer token Graph. No se envía el borrador hasta completar las subidas. [Adjuntos grandes Graph](https://learn.microsoft.com/en-us/graph/outlook-large-attachments).

Las descargas requieren seleccionar un adjunto y una ruta de guardado; límite **20 MiB decodificados**. El archivo guardado es persistente y queda bajo control del usuario: bloquear o desconectar no lo elimina. No se descargan automáticamente, no hay previsualización activa ni ejecución de adjuntos. Se descartan rutas del servidor como rutas de destino.

Archivar quita Inbox o traslada a Archivo; Papelera utiliza trash/move, nunca eliminación permanente. El contenido queda sujeto después a las políticas de retención del proveedor. Las operaciones se aplican a la cuenta y mensaje seleccionados, sin cambiar otros buzones.

## Datos y privacidad

- Cuenta y credenciales/referencias se conservan en el **Keychain privado de este Mac**, no sincronizable; Microsoft usa su caché MSAL privada. Para IMAP se guarda la contraseña/app password necesaria. La [guía de firma](../native-mail-signing.md) explica los requisitos del Data Protection Keychain.
- Bandeja y cuerpos permanecen en RAM: 50 resúmenes por cuenta, 1 MiB por cuerpo, caché compartida de 10 MiB. El cuerpo se obtiene bajo demanda, con hasta dos llegadas por ciclo para acciones automáticas. HTML se convierte a texto sin WebView, píxeles, fuentes ni scripts.
- Avisos de cinco minutos y bandeja de sesión son distintos. Bloquear, dormir o desactivar cancela red y limpia lectores, avisos y compositor. Sin caché de correo offline después de reiniciar.
- **La persistencia elegida no es caché local:** destinatarios reciben mensajes/adjuntos enviados; Gmail/Graph pueden conservar Enviados y Graph puede dejar un borrador sin enviar si falla la subida. Borrar el compositor local o desconectar no borra esas copias. Las descargas guardadas por el usuario también persisten.
- No se envía contenido a Pregunta ni a un servidor de Altillo, ni se escribe en logs, Spotlight, errores o breadcrumbs. El tráfico va al proveedor elegido y, al abrir enlaces/originales, al navegador tras la acción explícita.
- Pausar conserva credenciales; desconectar elimina estado local de esa cuenta sin afirmar revocación remota. Google/Microsoft se revocan en sus portales; iCloud desde contraseñas específicas; otros servidores según su administración.

## Convivencia y puertas de distribución

R01 sigue **Hecho, publicado en 0.13.0**. R61 sigue **En curso**, ahora con alcance ampliado autorizado. Puente y cuentas directas son fuentes mutuamente excluyentes; cambiar no elimina reglas ni scripts. El usuario puede volver al puente y limpiar manualmente cuando quiera. No consultar reglas externas de Mail ni necesitar Automatización Altillo → Mail para este flujo.

Antes de publicar: registros y revisión Google, registro/consentimiento Microsoft, perfil Developer ID/Keychain y callbacks en app instalada; QA real de cada proveedor con buzones sintéticos autorizados. Además de lectura y renovación: envío/respuesta (incluidos Cc/Cco y Reply-To), incertidumbre sin duplicados, leído/archivo/papelera reversible, subida/descarga y cancelación, UIDVALIDITY, capacidades IMAP, TLS/STARTTLS y credenciales revocadas. Confirmar ausencia de contenido en logs/cache y purga al bloquear/reposo. No usar pruebas sintéticas como sustituto de estas comprobaciones.

No se ha publicado esta actualización ni se han programado/publicado los posts existentes.

### Evidencia anterior: baseline de solo lectura — 1 noviembre 2026

Los siguientes resultados corresponden a los **1.386 tests de la baseline anterior de lectura**, no a envío, gestión, adjuntos ni iCloud/IMAP. La ampliación requiere evidencia nueva.

- `swift test --package-path Packages/AltilloKit`: **465 tests**, todos correctos; 50 corresponden a AltilloMail. Incluyen proveedores HTTP sintéticos, paginación, snapshots, identidad, HTML/MIME, límites, caché compartida y respuestas tardías.
- Suite completa macOS con firma ad hoc: **921 tests en 72 suites**, todos correctos. Incluye OAuth con driver/vault inyectados, renovación y cancelación, cuentas múltiples, purga al bloquear/pausar/desconectar y migración de ajustes. La suite con la firma local de desarrollo también pasó antes del último caso de reactivación (920 tests).
- Localización en esa baseline: **0 de 1571 cadenas sin español**. `actionlint`, validación YAML, sintaxis del script de release, gates de publicación y rechazo de builds de correo sin perfil/registros: correctos. Licencias AppAuth/MSAL incluidas en los recursos compilados.
- Compilación de `AltilloiOS` para simulador genérico sin firma: correcta; el nuevo código compartido no rompe el companion.
- Los tests alojados ya no arrancan servicios reales del usuario; la prueba de reglas consume la plantilla distribuida en el bundle, sin leer el checkout protegido por Documentos.
- En esa baseline no había client IDs de Altillo configurados ni perfil macOS válido para `me.badia.altillo`. La sesión CLI Google Cloud exigía reautenticación y el control de interfaz no estaba disponible. La evidencia actualizada figura a continuación.
- El pipeline de publicación exige ambos client IDs válidos, un perfil Developer ID embebido y su identificador autorizado. Instala el perfil en CI, genera el mapping de exportación y comprueba de nuevo el artefacto exportado. Los registros externos y la aprobación de proveedores no se crean automáticamente.

### Ampliación implementada y verificada — 1 noviembre 2026

- **499 tests de AltilloKit** correctos; **84 de AltilloMail**. Fixtures de API y protocolo cubren envío, respuestas/hilos, Cc/Cco, MIME, adjuntos grandes Graph, leído/archivo/papelera, UIDVALIDITY, literales y cancelación. SMTP nunca reenvía tras un resultado incierto; APPEND Enviados usa los mismos bytes/Message-ID y no transforma un fallo de copia en un fallo de envío.
- **940 tests macOS en 74 suites** correctos. Se prueban migración de permisos, conexión IMAP/iCloud, rollback Keychain, redactor y adjuntos, doble clic, respuestas tardías, aislamiento por cuenta y limpieza al pausar/bloquear. La escritura de adjuntos prepara un archivo privado con cuarentena antes de reemplazar la ruta elegida. Se corrigió también una carrera entre dos escritores del archivo de historial en un test de UsageStore; no cambia la lógica de uso.
- `AltilloiOS` compila para simulador genérico. Localización: **0 de 1625 cadenas sin español** tras compilar la ampliación.
- Conexión real, **sin credenciales ni correos**: saludo público de `imap.mail.me.com:993` sobre TLS y EHLO cifrado tras STARTTLS de `smtp.mail.me.com:587`, correctos. Esto no acredita login, entrega SMTP ni operaciones sobre un buzón real.
- QA visual con una aplicación DEBUG separada (`me.badia.altillo.mail-review`): bandeja, lector, Reply-To, redactor, aceptación de envío simulada, leído/no leído, papelera confirmada y opciones iCloud/IMAP. El banner advierte que son cuentas sintéticas sin red. Se corrigió un recorte de campos/puertos en el formulario de servidor; la revisión usa su propia configuración y no arranca módulos, hooks ni credenciales reales. Este entorno no entra en Release.
- Xus reautenticó Google Cloud en Chrome. Creado el proyecto **Altillo (`altillo-513418`)**, organización badia.me; la pantalla Billing confirma **sin cuenta de facturación vinculada** y Gmail API figura **Enabled**. Identidad OAuth externa creada **en modo de pruebas**, soporte/contacto `xus@badia.me`; aceptación de la política de datos autorizada explícitamente por Xus. Creado el cliente público de escritorio **Altillo macOS**, configurado localmente sin secreto. Añadido `xus@badia.me` como único usuario de pruebas y guardados los scopes `openid`, `userinfo.email` y `gmail.modify`; no se ha publicado la aplicación ni concedido todavía acceso al buzón. Recompilada Release 0.14.0 con el client ID real: firma/perfil válidos y prueba sintética Keychain add/read/delete correcta.
- Firma resuelta: el App ID `me.badia.altillo` ya estaba registrado en el equipo `9L2TD7KVV9`. Emitido e instalado el perfil **Altillo Developer ID Native Mail**, UUID `1f3026de-69ef-45e8-9722-b2f8c79a7b82`, certificado Developer ID existente y vencimiento 1 febrero 2027. Configuración local solo Release, conservando Apple Development en Debug. Release compila y pasa firma estricta, App ID/equipo/certificado autorizados por el perfil y ausencia de `get-task-allow`; el verificador usa XML explícito en macOS moderno. Un ejecutable de QA con ese perfil y los entitlements exactos de Release ha creado, leído y eliminado un registro sintético del Data Protection Keychain, verificando `WhenUnlockedThisDeviceOnly`, sin enumerar credenciales reales.
- QA de formularios en español: campos, puertos y etiquetas largas caben tras sustituir el formulario en columnas por etiquetas verticales; el texto de ayuda permite varias líneas. El código de revisión sintética no figura en el binario Release.
- La comprobación real de Keychain queda automatizada en `script/check-mail-keychain.py` y `script/mail-keychain-smoke.swift`; el proceso de release la ejecuta después de exportar cuando hay perfil. Usa los entitlements exactos del artefacto, un servicio aleatorio y datos sintéticos, sin leer registros de cuentas. Validada localmente contra la Release Developer ID.
- Xus ha indicado `xus@badia.me` como propietario del registro Microsoft. Iniciado el cambio de cuenta desde la sesión corporativa, sin modificar ese tenant; Microsoft reconoce la cuenta personal; tras solicitar el inicio de sesión, muestra alta de Authenticator para una identidad invitada de `gencat.onmicrosoft.com`. No se configura ese método ni se registra Altillo en ese directorio ajeno. Siguen pendientes completar la autenticación por el propietario, acceso a un directorio propio y registro Microsoft, consentimiento OAuth y pruebas reales completas con cuentas autorizadas. No hay envío real ejecutado ni nueva versión publicada.
