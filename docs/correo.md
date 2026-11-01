# Correo en Altillo

**Versión publicada 0.13.0:** usa el puente opcional de Apple Mail descrito más abajo. **R61 en desarrollo, todavía sin publicar:** incorpora Google, Microsoft, iCloud e IMAP con lectura, envío y gestión. Las pruebas sintéticas no acreditan aún OAuth con cuentas reales ni una actualización distribuida.

## Cuentas directas: desarrollo de R61

Google y Microsoft se conectan mediante la autorización del proveedor; iCloud y otro IMAP mediante los datos de servidor y una contraseña específica cuando esté disponible. No requieren Apple Mail. Solo aparecen los conectores OAuth configurados por el distribuidor; la [guía OAuth](mail-oauth.md) es para desarrollar/distribuir Altillo, no un trámite para cada usuario.

El alcance ampliado aprobado incluye los últimos 50 mensajes de Inbox por cuenta, vista conjunta/selector, lector de texto, **redactar/enviar y responder**, Cc/Cco, adjuntos y acciones de **leído/no leído, archivar y trasladar a Papelera**. Abrir el lector no marca automáticamente como leído. Papelera pide confirmación y no borra permanentemente; la retención posterior depende del proveedor. Búsqueda, todas las carpetas, conversaciones completas, IA y sincronización entre dispositivos quedan para otra ampliación.

### Conectar una cuenta

- **Google:** consentimiento en el navegador; Gmail API solicita `gmail.modify` (restringido) y `gmail.send` (sensible), además de identidad. Una cuenta del prototipo de lectura necesita reconectar para ampliar permisos.
- **Microsoft:** consentimiento mediante MSAL; permisos delegados `User.Read`, `Mail.ReadWrite` y `Mail.Send`. Una organización puede bloquearlo o exigir autorización administrativa.
- **iCloud:** activar 2FA y generar una **contraseña específica de aplicación** en Apple Account → Inicio de sesión y seguridad. No introducir la contraseña principal. La app prepara `imap.mail.me.com:993` (TLS) y `smtp.mail.me.com:587` (STARTTLS); usa tu dirección completa y el usuario que indique el proveedor. [Instrucciones de Apple](https://support.apple.com/en-us/102654).
- **Otro IMAP:** proporcionar dirección, usuario, hosts y puertos IMAP/SMTP y contraseña/app password del proveedor. IMAP requiere TLS; SMTP admite TLS implícito o STARTTLS obligatorio. Si el proveedor solo permite OAuth, usar su conector dedicado si existe: una contraseña no lo sustituye. No se promete compatibilidad con todos los servidores ni sus carpetas especiales.

Las credenciales permanecen en el Keychain privado de este Mac. iCloud/IMAP no dependen de los client IDs Google/Microsoft, pero sí de una app correctamente firmada y autorizada para Keychain. No hay servidor de correo de Altillo que custodie la contraseña.

### Enviar y descargar adjuntos

Elegir cuenta, destinatarios y contenido y pulsar Enviar es una acción explícita. Se permiten hasta **18 MiB de adjuntos en total por composición**, y **25 MiB para el mensaje MIME completo**, contando cuerpo y expansión base64. Graph utiliza borradores/subidas por partes cuando hacen falta. El proveedor o destinatario puede imponer límites adicionales.

Un éxito indica aceptación por el proveedor, no entrega garantizada. Si Altillo dice que **el envío es incierto**, comprueba Enviados y, si es necesario, consulta al destinatario antes de repetir. No hay reenvío automático. Para iCloud/IMAP, **Guardar una copia en Enviados mediante IMAP** está activado por defecto; desactívalo si tu servidor saliente ya guarda los mensajes, para evitar duplicados. Después de la aceptación SMTP se intenta guardar la copia con el mismo identificador. Si solo falla esa copia, Altillo indica que el mensaje se ha enviado y que **no debes reenviarlo**. Graph puede dejar un borrador sin enviar cuando falla una subida. Esas copias son datos del proveedor, no se eliminan al cerrar el compositor o desconectar.

Los adjuntos recibidos se descargan solo a petición, hasta **20 MiB** cada uno. Elige la ruta de guardado; el archivo es persistente y no desaparece al bloquear, dormir o desconectar. Altillo no descarga ni abre automáticamente adjuntos.

### Datos de la sesión

- Comunicación directa con el proveedor y refresco periódico mientras Altillo está abierto; no es push instantáneo. Google usa historial; Graph e IMAP refrescan la ventana reciente de 50 mensajes. No se descarga todo el histórico.
- La bandeja y los cuerpos viven en RAM durante la sesión desbloqueada: 50 resúmenes por cuenta, cuerpo de hasta 1 MiB y caché compartida de 10 MiB. Hasta dos llegadas por ciclo obtienen cuerpo automáticamente para códigos/enlaces. El compositor permanece local en memoria hasta las acciones de envío, que pueden crear borradores en el proveedor.
- HTML se convierte a texto sin navegador, imágenes ni recursos remotos. El contenido no va a Pregunta ni se guarda como archivo local de correo. Abrir un original/enlace abre el navegador tras tu acción. Enviar sí comunica el contenido y los adjuntos al proveedor y destinatarios.
- Los avisos duran cinco minutos; esa caducidad no elimina la bandeja de la sesión. Bloquear, dormir o desactivar limpia bandeja, lector y compositor y cancela red. No hay correo offline tras reiniciar. La carga inicial y recuperación no generan avisos históricos. Los archivos guardados por ti y los mensajes/borradores del proveedor siguen existiendo.
- Pausar conserva la cuenta. **Desconectar** elimina estado/credenciales locales, sin afirmar revocación remota: revoca también desde el portal Google/Microsoft, contraseñas específicas de Apple o administración del servidor si lo deseas.
- Los filtros controlan avisos, sin esconder mensajes de la bandeja. Copiar código conserva la exclusión del historial de Clipboard de Altillo.

Puente y cuentas directas son fuentes mutuamente excluyentes. Preparar cuentas no elimina scripts/reglas; elige explícitamente la fuente y puedes volver al puente. No se consultan ni borran reglas de Mail. Para retirarlo, sigue la limpieza manual al final.

Pendientes antes de distribuir: registros/revisión OAuth, perfil y Keychain de producción, QA real de cada proveedor y validación de toda la ampliación. La baseline anterior de 1.386 pruebas solo cubre la entrega de lectura. [Plan y evidencia](plans/mail-native-accounts.md) · [Firma](native-mail-signing.md).

## Apple Mail: beta publicada en 0.13.0

La sección Correo muestra mensajes nuevos de Apple Mail durante cinco minutos.
Puedes abrir el mensaje en Mail y, cuando Altillo reconoce un único candidato,
copiar su código de acceso o abrir su enlace con el dominio visible.

Es una beta opcional. Mail debe permanecer abierto y recibir correo; Altillo
aprovecha las cuentas que ya tienes allí y no inicia sesión en ellas.

## Conectar

1. En Ajustes de Altillo → Secciones, activa Correo y abre su configuración.
2. Pulsa **Preparar scripts de Mail**. Altillo prepara dos scripts propios
   en la carpeta de scripts de Apple Mail. No cambia las reglas existentes.
3. Abre Mail → Ajustes → Reglas y crea una regla llamada **Altillo Mail**.
4. Elige **Todos los mensajes** y la acción **Ejecutar AppleScript → Altillo Mail**.
   El nombre del script auxiliar «Altillo Mail Bridge» también puede aparecer;
   elige «Altillo Mail».
5. Al guardar, elige **No aplicar** a los mensajes anteriores.
6. Espera un mensaje nuevo. Cuando llega a la sección Correo, Altillo confirma
   **Apple Mail ha entregado un mensaje nuevo a Altillo**. Esa confirmación dura
   solo durante la sesión activa; no certifica las condiciones de tu regla.
   **Comprobar archivos de scripts** verifica únicamente la preparación local.
   Altillo no consulta las reglas de Mail ni necesita el permiso de Automatización
   **Altillo → Mail** para esta integración.

Puedes indicar direcciones completas o nombres de cuentas separados por comas
en los filtros de Altillo. Déjalos vacíos para mostrar todos los mensajes nuevos.
Los filtros se aplican después de la entrega local, no en el servidor de correo.

## Datos y límites

- Los mensajes permanecen solo en memoria: hasta veinte mensajes recientes,
  durante cinco minutos desde su recepción. No se guardan en un archivo de
  correo ni se comparten con Pregunta.
- Desactivar Correo, bloquear la pantalla o poner el Mac en reposo borra los
  mensajes recientes. Al volver, Altillo espera mensajes nuevos.
- El botón de código marca la copia como privada para excluirla del historial
  de Clipboard de Altillo. No borra el portapapeles ni controla otros gestores.
- Los códigos reconocidos son numéricos y etiquetados en inglés o español.
  Los enlaces reconocidos usan HTTPS y un parámetro de acceso compatible;
  el parámetro genérico `token` exige además una ruta de acceso reconocida.
  Si hay varios candidatos, Altillo omite la acción. Comprueba el dominio;
  reconocer un enlace no verifica la identidad del remitente.
- La beta usa el principio del cuerpo del mensaje y limita el tamaño del evento
  y los lotes de entrega. Puede omitir códigos posteriores o aún no descargados,
  y partes de una entrega masiva. Si el cuerpo aún no está disponible,
  muestra el remitente y asunto; solo ofrece acciones reconocidas en el texto
  disponible. Usa **Abrir en Mail** en esos casos.
- Los avisos respetan la política de pantalla completa y no interrumpen un
  arrastre o el notch abierto. El mensaje puede estar disponible en su sección
  aunque no haya aparecido un aviso.

## Desconectar y desinstalar

Desactivar la sección detiene el receptor y borra sus mensajes. **Eliminar la
conexión de Correo de Altillo** también detiene la recepción y conserva tanto
los scripts como las reglas para su retirada manual: no consulta Mail ni intenta
eliminar archivos que una regla podría seguir usando.

Antes de eliminar Altillo o volver a una versión anterior a 0.13.0:

1. Desactiva Correo y retira la regla **Altillo Mail** de Mail → Ajustes → Reglas.
   Si has creado más reglas que ejecutan el script, retíralas también.
2. En la configuración de Correo de Altillo, pulsa **Mostrar scripts**. Retira
   manualmente solo **Altillo Mail.scpt** y **Altillo Mail Bridge.scpt**, una vez
   que ninguna regla los use. No borres otros scripts ni las reglas de tus cuentas.

Si ya has hecho el rollback, abre desde Mail su carpeta de scripts y sigue los
mismos pasos. Los mensajes de Altillo solo estaban en memoria.
