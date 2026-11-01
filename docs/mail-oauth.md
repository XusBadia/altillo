# OAuth de correo: configuración del distribuidor

R61 está en desarrollo y **no forma parte de 0.13.0**. Esta guía describe el código actual; no acredita registros creados, aprobación de proveedores ni OAuth real validado. La persona que conecta su buzón no debe registrar aplicaciones ni introducir client IDs. Altillo nunca pide su contraseña de Google o Microsoft.

## Configuración local y firma

El distribuidor configura sus **client IDs públicos** en el archivo ignorado `Config/Local.xcconfig`, partiendo de `Config/Local.xcconfig.example`:

```xcconfig
ALTILLO_GOOGLE_MAIL_CLIENT_ID = <desktop-client-id>.apps.googleusercontent.com
ALTILLO_MICROSOFT_MAIL_CLIENT_ID = <application-client-UUID>
```

No introducir client secrets, contraseñas ni tokens. Los valores se incluyen en Info.plist mediante `project.yml`. Los proveedores sin client ID válido no se ofrecen para conectar; no hay un formulario OAuth avanzado destinado al usuario final. Para distribución, estos valores deben estar disponibles en la configuración del runner, no depender del archivo local de un desarrollador.

Las credenciales usan el Data Protection Keychain privado de esta app, no sincronizable. Una compilación ad hoc útil para CI no acredita acceso real a Keychain. La app que conecte cuentas necesita firma y perfil de aprovisionamiento autorizados para su App ID exacto: consulta [firma de cuentas nativas](native-mail-signing.md). Las opciones configurables son `ALTILLO_MAC_ENTITLEMENTS` y `ALTILLO_MAC_PROVISIONING_PROFILE`; no reutilizar un perfil de otra app. Mantener los certificados/perfiles fuera de Git.

## Google: aplicación de escritorio

Estado local (1 noviembre 2026): proyecto `altillo-513418`, Gmail API habilitada y cliente **Altillo macOS** creado. OAuth permanece en **Testing**, con `xus@badia.me` como único usuario de pruebas y scopes `openid`, `userinfo.email` y `gmail.modify` guardados. Xus autorizó la aceptación de la política de datos. El identificador público está en la configuración local ignorada; no se usa un secreto. Esto todavía no acredita consentimiento del buzón ni verificación para producción.

1. Crear o usar un proyecto del distribuidor en Google Cloud y habilitar **Gmail API**. Configurar Google Auth Platform: nombre, soporte, audiencia, dominio verificado, web y política de privacidad públicas.
2. Registrar un cliente OAuth de tipo **Desktop app**, no Web ni iOS. Copiar su client ID a `ALTILLO_GOOGLE_MAIL_CLIENT_ID`.
3. Declarar exactamente los scopes que solicita el adaptador: `openid`, `email`, `https://www.googleapis.com/auth/gmail.modify`. Identifican la cuenta, permiten leer/gestionar correo y enviar. No se solicita `profile` ni `https://mail.google.com/`; no hay borrado permanente.
4. Para QA, mantener el proyecto en modo de pruebas y añadir explícitamente las cuentas autorizadas como test users. Las restricciones de prueba y caducidad de autorizaciones no equivalen a preparación para producción.
5. AppAuth abre el navegador del sistema, genera `state`, nonce y PKCE S256 y arranca un listener HTTP **solo loopback con puerto efímero**. El callback lo genera `OIDRedirectHTTPHandler`; no se pega una URL de servidor de Altillo ni se registra el esquema Microsoft para Google. Se pide acceso offline para renovar sin guardar una contraseña.
6. Tras autorizar, Altillo consulta UserInfo y el perfil Gmail. Usa `sub` como identidad estable y verifica que hay un buzón Gmail accesible antes de guardar la cuenta.

Un cliente instalado es público; incorporar un secreto al binario no lo convierte en confidencial. [Flujo de escritorio de Google](https://developers.google.com/identity/protocols/oauth2/native-app).

`gmail.modify` es restringido y también autoriza el envío; no solicitamos `gmail.send` por separado porque sería redundante. [Permisos de envío](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send). Antes de ofrecerlo públicamente, completar la verificación aplicable salvo exención real: justificar scopes mínimos, aportar dominio/política y demostración del uso. La revisión de branding y la de acceso a datos no deben confundirse. Declarar que las solicitudes van directamente al proveedor y el contenido se procesa localmente. Si datos restringidos atraviesan servidores de terceros puede corresponder una evaluación adicional; no prometer su exención antes de la decisión de Google. [Scopes Gmail](https://developers.google.com/workspace/gmail/api/auth/scopes), [verificación restringida](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

## Microsoft: aplicación pública nativa

1. Registrar una aplicación Entra con audiencia **cuentas de cualquier directorio organizativo y cuentas personales Microsoft**, para la nube pública. El adaptador usa la autoridad `https://login.microsoftonline.com/common`.
2. Configurar la plataforma nativa/móvil-escritorio con el redirect URI exacto **`msauth.<PRODUCT_BUNDLE_IDENTIFIER>://auth`**. Para el bundle de distribución `me.badia.altillo`, es `msauth.me.badia.altillo://auth`. Si cambia el bundle de desarrollo, registrar su callback exacto también. `project.yml` declara el esquema `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` en CFBundleURLTypes; ambos lados deben coincidir.
3. Añadir permisos **delegados Microsoft Graph `User.Read`, `Mail.ReadWrite` y `Mail.Send`**. No añadir permisos de aplicación. `User.Read` obtiene identidad; `Mail.ReadWrite` permite lectura, gestión, borradores y adjuntos, y `Mail.Send` envío. `Mail.ReadBasic` y el antiguo `Mail.Read` no cubren este alcance.
4. Copiar Application (client) ID a `ALTILLO_MICROSOFT_MAIL_CLIENT_ID`. No crear ni distribuir un client secret para este cliente público.
5. MSAL presenta `ASWebAuthenticationSession`, añade sus scopes de protocolo `openid`, `profile` y `offline_access` y gestiona renovación/caché. El adaptador pasa únicamente `User.Read`, `Mail.ReadWrite` y `Mail.Send` como scopes de recurso; no añadir los scopes reservados a esa lista.
6. Probar una cuenta Outlook.com y una cuenta Exchange Online autorizadas. La identidad se resuelve mediante `/me` y el acceso a Inbox se verifica al sincronizar. Una identidad Microsoft sin buzón compatible no garantiza acceso a correo.

La caché MSAL es privada para el bundle de Altillo; no comparte tokens con otras apps. Verificar su funcionamiento en la app firmada/instalada, además del callback. [MSAL para Apple](https://github.com/AzureAD/microsoft-authentication-library-for-objc), [permisos Graph](https://learn.microsoft.com/en-us/graph/permissions-reference).

Las políticas empresariales pueden exigir consentimiento administrativo o bloquear la app incluso con permisos delegados. Completar identidad del editor y la verificación aplicable para distribución; no prometer que la verificación evita las políticas del tenant. La primera cobertura excluye buzones compartidos, Exchange local y nubes soberanas. [Verificación del editor](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview).

## Cambio desde la baseline de lectura

La versión de autorización es **2**. Las cuentas Google/Microsoft conectadas con permisos anteriores requieren reconectar y consentir los nuevos permisos; guardar un token de lectura no habilita escritura. Actualizar también la declaración de scopes de las consolas y la demostración para revisión. No mostrar como validado un consentimiento que solo se ha simulado en tests.

## iCloud y otro IMAP: sin registro OAuth propio

iCloud y otro IMAP no necesitan estos client IDs. Sí necesitan el mismo almacenamiento Keychain autorizado de la app firmada. iCloud usa una contraseña específica generada en Apple Account → Inicio de sesión y seguridad → Contraseñas específicas; requiere **2FA**, no la contraseña principal. Revocar esa contraseña en Apple cierra su acceso. IMAP: `imap.mail.me.com:993` con TLS; SMTP: `smtp.mail.me.com:587` con STARTTLS obligatorio y dirección completa como usuario SMTP. [Apple: servidores](https://support.apple.com/en-us/102525), [contraseñas específicas](https://support.apple.com/en-us/102654).

Para otros servidores, introducir dirección/usuario, hosts y puertos IMAP/SMTP del proveedor, contraseña o app password y TLS SMTP implícito o STARTTLS. IMAP requiere TLS desde la conexión. No hay conexiones inseguras, degradación si falta STARTTLS ni sustitución de OAuth por contraseña cuando el servidor exige OAuth. La cobertura depende de autenticación/capacidades compatibles; no es un conector universal. No se envían contraseñas a un servidor de Altillo.

Envío, respuestas, leído/archivo/papelera y adjuntos están incluidos en el alcance ampliado, aún en desarrollo. Papelera traslada mensajes; nunca se vacía ni borra permanentemente. La interfaz limita los adjuntos de una composición a **18 MiB en total**, y el MIME completo a **25 MiB** tras base64. Descargas manuales hasta **20 MiB**, guardadas persistentemente en la ruta que el usuario elige.

Graph puede crear un borrador en el proveedor antes de adjuntar/enviar; un fallo de subida puede dejarlo sin enviar. Gmail/Graph conservan copias en Enviados según el servicio; iCloud/IMAP intentan guardar una copia mediante IMAP APPEND después de la aceptación SMTP, con el mismo Message-ID; la opción está activada por defecto y debe desactivarse si el servidor ya guarda Enviados. Un fallo de la copia produce una advertencia de mensaje enviado, sin reenvío. Un error de envío incierto exige comprobar Enviados/el destinatario antes de repetir: **no se reintenta automáticamente**. La purga local no borra borradores/Enviados ni los archivos descargados.

## Comprobación antes de distribuir

- App instalada y correctamente firmada: cancelar el navegador, completar consentimiento, comprobar identidad estable y rechazar reconexión a otra cuenta.
- Renovación real después de caducar el access token; denegación y revocación exigen reconectar sin bucles. No registrar tokens ni correos en logs.
- Inbox inicial sin avisos históricos; un correo sintético posterior llega por red y permite leer/código/enlace. Google usa historial; Microsoft refresca una ventana de 50 mensajes, sin recorrer todo el buzón ni usar delta.
- Bloqueo, reposo y desactivación limpian contenido y cancelan red; pausa conserva credenciales. Desconectar borra la identidad/credenciales locales y la entrada MSAL correspondiente. Para revocar el permiso del proveedor, usar Google Account → conexiones de terceros o el portal Microsoft de permisos; desconectar localmente no afirma revocación remota.
- Probar envío/respuesta con Cc/Cco, Reply-To/hilo, rechazo y fallo ambiguo sin duplicados; leído/no leído, archivo/papelera y adjuntos grandes. En IMAP/SMTP probar TLS/STARTTLS, capacidades, UIDVALIDITY, revocación de app password, APPEND a Enviados y fallo de copia posterior a aceptación sin reenviar.
- Registrar en QA el build exacto, firma/perfil, cuentas sintéticas autorizadas, versión y resultado de ambos callbacks. Completar verificación Google y condiciones de consentimiento Microsoft antes del anuncio público.

Esta guía no sustituye la validación del artefacto ni autoriza una release. Los posts existentes siguen guardados sin publicar ni programar.
