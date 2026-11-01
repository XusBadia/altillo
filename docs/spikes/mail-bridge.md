# R01 Prueba de correo desde Apple Mail

1 de noviembre de 2026 · macOS 27.0, build 26A428 · Swift 6.

**Resultado: puente local viable con instalación manual de la regla.** Se ha
comprobado Mail → regla → helper nativo → socket → tarjeta temporal y la apertura
del mismo mensaje mediante su Message-ID. La muestra era un correo sintético
importado, aplicado mediante **Mensaje → Aplicar reglas**. No se ha probado
todavía una llegada nueva por red ni integrado la tarjeta en Altillo.app.

R01 sigue **En investigación**. Este resultado permite continuar con un piloto;
no acredita una función de correo lista para publicar.

## Qué se ha construido

- [Helper Swift](../../script/mail-spike/Main.swift): receptor por eventos,
  validación, deduplicación en memoria, extracción de un código o magic link y
  tarjeta temporal. Se compila reutilizando `AltilloAgents/UnixSocket.swift`.
- [Handler de Mail](../../script/mail-spike/MailRule.applescript): AppleScript
  sin Foundation para resolver correctamente los mensajes que entrega Mail.
- [Puente Foundation](../../script/mail-spike/Bridge.applescript): recibe valores
  escalares del handler y serializa JSON hacia el helper por stdin, con NSTask y
  NSPipe. No usa `do shell script` con el contenido del mensaje.
- [Runner](../../script/mail-spike/probe.py): compilación, pruebas, demo y
  preparación/retirada de los scripts. Python es solo la herramienta de
  desarrollo; el proceso que recibe los eventos es nativo.

El prototipo está bajo `script/`, fuera de los targets de la app y del binario
distribuible. No se han cambiado módulos, preferencias ni permisos de Altillo.

## Evidencia

| Prueba | Resultado |
| --- | --- |
| Mail abierto y Apple Events | Responde; dos cuentas configuradas. Solo se consultó su número. |
| Compilación del helper con Swift 6 | Correcta, sin compilar el proyecto Xcode completo. |
| Parser | Códigos en inglés/español, ambigüedad, longitudes, URLs, Unicode, Message-ID y fechas validados con fixtures. |
| Socket local | Entrega y ACK, duplicados, caducidad, entradas malformadas/grandes y desconexión comprobados. |
| Peer bloqueado | Un cliente que no envía se rechaza; un receptor que no responde no bloquea el helper indefinidamente. |
| Permisos y vida del socket | Directorio privado, socket 0600, un segundo listener no reemplaza al primero; retirada al terminar. La comprobación de mismo usuario está en código, sin prueba entre dos cuentas del sistema. |
| AppleScript → Foundation → helper | Probado automáticamente con datos sintéticos y el script compilado. |
| Host real de reglas de Mail | Regla creada desde Ajustes y aplicada a un mensaje sintético importado: `delivered=true`; receptor: `received code=true link=true`. |
| Caducidad dentro de Mail | La muestra anterior produjo `expired` y no llegó a la tarjeta. |
| Tarjeta | Inspeccionada mediante accesibilidad y captura: remitente, asunto, copiar código, dominio del enlace, abrir en Mail y cerrar. |
| Abrir el mismo mensaje | «Ver en Mail» abrió una ventana con el asunto del fixture desde su Message-ID. |
| Nueva llegada por red | Pendiente; no se envió correo ni se modificaron cuentas. |
| Copiar y abrir un magic link real | Pendiente; no se usaron códigos reales ni se abrió el dominio ficticio. |

Los tres mensajes importados usan direcciones `example.invalid`, códigos y
tokens sintéticos. No se leyó contenido del correo normal para estas pruebas.

## Dos problemas encontrados y resueltos para el piloto

### La asignación automática del script no es fiable

En esta versión de Mail, asignar el archivo mediante `run script` guardó una
ruta duplicada bajo `~/Library/Application Scripts/com.apple.mail/`. La interfaz
de reglas no pudo validar correctamente esa regla. Crear una regla nueva desde
Mail y seleccionar el script en su menú sí guardó un alias correcto y funcionó.

El runner **prepara los scripts, pero no instala ni habilita una regla**.
No modificar el plist privado de reglas para eludir este problema. El piloto
requiere un paso manual; una instalación de producto necesita diseñar y validar
ese paso, o evaluar MailKit por separado.

### Resolver mensajes antes de cargar Foundation

La versión con `use framework "Foundation"` en el propio handler falló al
resolver el asunto dentro del host real de reglas (`-1700` y después `-1728`),
aunque el acceso desde `osascript` funcionaba. Materializar la referencia y
separar lectura/coerción ayudó a identificar el fallo, pero no cerró el recorrido.

El handler final es AppleScript sin Foundation. Resuelve los campos y pasa
texto/fecha al segundo script; ese segundo script usa Foundation para serializar
y lanzar el helper. Esta variante sí se verificó dentro de Mail. El resultado
no demuestra que AppleScriptObjC falle en todos los handlers o versiones de Mail.

## Repetir las pruebas

Desde la raíz del repo:

```sh
python3 script/mail-spike/probe.py build
python3 script/mail-spike/probe.py test
python3 script/mail-spike/probe.py demo
```

La demo usa contenido sintético, no lee Mail y termina por sí sola. La tarjeta
se cierra a los 30 segundos y el proceso a los 35. Los binarios pequeños se
reutilizan bajo `~/Library/Developer/BuildCache/altillo-mail-spike/`; el margen
de disco comprobado antes de compilar era de 27 GiB. No se lanzó una compilación
pesada de Xcode.

Para un piloto con la regla real:

1. Abrir Apple Mail y ejecutar `python3 script/mail-spike/probe.py prepare`.
2. En Mail → Ajustes → Reglas, crear la regla con el nombre y asunto exclusivo
   que imprime el comando. Condición: el asunto contiene ese valor. Acción:
   Ejecutar AppleScript → **Altillo-R01-Spike**. No seleccionar el script Bridge.
3. Al guardar, elegir **No aplicar** al correo anterior.
4. Ejecutar `python3 script/mail-spike/probe.py status` para verificar el alias.
5. Ejecutar `python3 script/mail-spike/probe.py listen`. Termina a los cinco
   minutos. Usar un correo nuevo de prueba con ese asunto, sin credenciales reales.
6. Para reproducir el host sin envío por red, `fixture-mbox` genera un buzón
   sintético. Importarlo como mbox, seleccionar únicamente ese mensaje y aplicar
   reglas antes de cinco minutos. Es una prueba de ejecución manual, no de llegada.
7. `python3 script/mail-spike/probe.py remove` retira la regla propia y ambos
   scripts si siguen coincidiendo con el manifiesto. Los buzones importados se
   gestionan desde Mail, por separado.

No se deja un listener permanente ni se añade un agente de inicio de sesión. La
regla utilizada, los dos scripts instalados y el socket se han retirado y se ha
comprobado que ya no existen. Tras la confirmación de Xus, se eliminaron desde Mail los tres buzones locales
«Import», «Import-2» e «Import-3» y sus mensajes sintéticos. Se verificó que los
tres desaparecieron de la barra lateral.

## Límites antes de integrar en Altillo

- Probar llegada nueva real, varias cuentas, Mail cerrado, reinicios y errores
  de permisos. La regla requiere que Mail esté recibiendo mensajes.
- Diseñar alta/baja y explicación de permisos; verificar que quitar los scripts
  y la regla no depende de rutas que cambien con una actualización.
- Integrar una fuente de avisos y acciones en el notch de Altillo, opt-in y con
  filtros por cuenta/remitente. La tarjeta experimental es otra aplicación.
- Soportar cuerpo pendiente de descarga, HTML y mails grandes sin bloquear Mail.
  El piloto procesa hasta tres mensajes por invocación y solo el principio del
  cuerpo; puede omitir códigos o enlaces posteriores.
- Sustituir la heurística limitada de autenticación por casos comprobados. Ante
  varios códigos o enlaces candidatos no se ofrece una acción. HTTPS y dominio
  visible no prueban que un enlace sea legítimo.
- Validar expiración de acciones, teclado, VoiceOver y privacidad al compartir
  pantalla. El botón de copiar marca contenido oculto para Clipboard, pero no
  implica borrar un código del portapapeles ni controlar otros gestores.
- El transporte comprueba mismo usuario y permisos Unix; no autentica la firma
  del proceso emisor. Un piloto local no es una revisión de seguridad completa.

## Fuentes

- [Apple: automatizar Mail con reglas y scripts](https://support.apple.com/guide/mail/automate-mail-tasks-mlhlp1120/mac).
- [Apple: handlers de AppleScript](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/UseHandlersFunctions.html).
- Diccionario instalado: `/System/Applications/Mail.app/Contents/Resources/Mail.sdef`.
- El esquema `message` se comprobó mediante la apertura del fixture en Mail.
