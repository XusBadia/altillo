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

1. Crear o usar un proyecto del distribuidor en Google Cloud y habilitar **Gmail API**. Configurar Google Auth Platform: nombre, soporte, audiencia, dominio verificado, web y política de privacidad públicas.
2. Registrar un cliente OAuth de tipo **Desktop app**, no Web ni iOS. Copiar su client ID a `ALTILLO_GOOGLE_MAIL_CLIENT_ID`.
3. Declarar exactamente los scopes que solicita el adaptador: `openid`, `email`, `https://www.googleapis.com/auth/gmail.readonly`. `openid`/`email` identifican la cuenta; `gmail.readonly` permite listar y leer correo, sin escritura ni envío. El código no solicita `profile`, `gmail.modify` ni `https://mail.google.com/`.
4. Para QA, mantener el proyecto en modo de pruebas y añadir explícitamente las cuentas autorizadas como test users. Las restricciones de prueba y caducidad de autorizaciones no equivalen a preparación para producción.
5. AppAuth abre el navegador del sistema, genera `state`, nonce y PKCE S256 y arranca un listener HTTP **solo loopback con puerto efímero**. El callback lo genera `OIDRedirectHTTPHandler`; no se pega una URL de servidor de Altillo ni se registra el esquema Microsoft para Google. Se pide acceso offline para renovar sin guardar una contraseña.
6. Tras autorizar, Altillo consulta UserInfo y el perfil Gmail. Usa `sub` como identidad estable y verifica que hay un buzón Gmail accesible antes de guardar la cuenta.

Un cliente instalado es público; incorporar un secreto al binario no lo convierte en confidencial. [Flujo de escritorio de Google](https://developers.google.com/identity/protocols/oauth2/native-app).

`gmail.readonly` es restringido. Antes de ofrecerlo públicamente, completar la verificación aplicable salvo exención real: justificar scopes mínimos, aportar dominio/política y demostración del uso. La revisión de branding y la de acceso a datos no deben confundirse. Declarar que las solicitudes van directamente al proveedor y el contenido se procesa localmente. Si datos restringidos atraviesan servidores de terceros puede corresponder una evaluación adicional; no prometer su exención antes de la decisión de Google. [Scopes Gmail](https://developers.google.com/workspace/gmail/api/auth/scopes), [verificación restringida](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

## Microsoft: aplicación pública nativa

1. Registrar una aplicación Entra con audiencia **cuentas de cualquier directorio organizativo y cuentas personales Microsoft**, para la nube pública. El adaptador usa la autoridad `https://login.microsoftonline.com/common`.
2. Configurar la plataforma nativa/móvil-escritorio con el redirect URI exacto **`msauth.<PRODUCT_BUNDLE_IDENTIFIER>://auth`**. Para el bundle de distribución `me.badia.altillo`, es `msauth.me.badia.altillo://auth`. Si cambia el bundle de desarrollo, registrar su callback exacto también. `project.yml` declara el esquema `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` en CFBundleURLTypes; ambos lados deben coincidir.
3. Añadir permisos **delegados Microsoft Graph `User.Read` y `Mail.Read`**. No añadir permisos de aplicación, `Mail.ReadWrite` ni `Mail.Send`. `User.Read` obtiene identidad; `Mail.Read` cubre cuerpo y previsualización. `Mail.ReadBasic` no los cubre.
4. Copiar Application (client) ID a `ALTILLO_MICROSOFT_MAIL_CLIENT_ID`. No crear ni distribuir un client secret para este cliente público.
5. MSAL presenta `ASWebAuthenticationSession`, añade sus scopes de protocolo `openid`, `profile` y `offline_access` y gestiona renovación/caché. El adaptador pasa únicamente `User.Read` y `Mail.Read` como scopes de recurso; no añadir los scopes reservados a esa lista.
6. Probar una cuenta Outlook.com y una cuenta Exchange Online autorizadas. La identidad se resuelve mediante `/me` y el acceso a Inbox se verifica al sincronizar. Una identidad Microsoft sin buzón compatible no garantiza acceso a correo.

La caché MSAL es privada para el bundle de Altillo; no comparte tokens con otras apps. Verificar su funcionamiento en la app firmada/instalada, además del callback. [MSAL para Apple](https://github.com/AzureAD/microsoft-authentication-library-for-objc), [permisos Graph](https://learn.microsoft.com/en-us/graph/permissions-reference).

Las políticas empresariales pueden exigir consentimiento administrativo o bloquear la app incluso con permisos delegados. Completar identidad del editor y la verificación aplicable para distribución; no prometer que la verificación evita las políticas del tenant. La primera cobertura excluye buzones compartidos, Exchange local y nubes soberanas. [Verificación del editor](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview).

## Comprobación antes de distribuir

- App instalada y correctamente firmada: cancelar el navegador, completar consentimiento, comprobar identidad estable y rechazar reconexión a otra cuenta.
- Renovación real después de caducar el access token; denegación y revocación exigen reconectar sin bucles. No registrar tokens ni correos en logs.
- Inbox inicial sin avisos históricos; un correo sintético posterior llega por red y permite leer/código/enlace. Google usa historial; Microsoft refresca una ventana de 50 mensajes, sin recorrer todo el buzón ni usar delta.
- Bloqueo, reposo y desactivación limpian contenido y cancelan red; pausa conserva credenciales. Desconectar borra la identidad/credenciales locales y la entrada MSAL correspondiente. Para revocar el permiso del proveedor, usar Google Account → conexiones de terceros o el portal Microsoft de permisos; desconectar localmente no afirma revocación remota.
- Registrar en QA el build exacto, firma/perfil, cuentas sintéticas autorizadas, versión y resultado de ambos callbacks. Completar verificación Google y condiciones de consentimiento Microsoft antes del anuncio público.

Esta guía no sustituye la validación del artefacto ni autoriza una release. Los posts existentes siguen guardados sin publicar ni programar.
