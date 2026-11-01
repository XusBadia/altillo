# Mail 0.13.0 — validación y publicación

Fecha: 1 de noviembre de 2026. **0.13.0 publicada** en [GitHub Releases](https://github.com/XusBadia/altillo/releases/tag/v0.13.0), desde el merge de PR #12 (`431d13c48a1767df10fbd22be1955944bd7186d8`).

## Recorrido real confirmado

- La cuenta Google conecta por IMAP/SMTP; Connection Doctor también confirma iCloud.
- Se envió un mensaje sintético desde la cuenta iCloud a `altillo@badia.me`, con el marcador `clean-host-06`. Gmail lo confirmó en Inbox y Mail lo descargó mediante **Obtener correo nuevo**. Esta acción solicita recepción normal por red; no aplica reglas a mensajes anteriores.
- La regla de QA, limitada a un asunto sintético, ejecutó el handler automáticamente. El mensaje apareció en el notch con su asunto, el código sintético `482913` y el botón **Abrir en Mail**. Este botón abrió el original del mismo mensaje.
- No se aplicaron reglas manualmente ni se inyectó el socket en este recorrido. Mail se había reiniciado y no se habían ejecutado consultas externas a sus reglas antes de recibir el mensaje.
- Segunda prueba real con el marcador `settings-fixed-07`: se reinició Mail para cargar el handler final y se abrieron **Ajustes → Correo** y **Comprobar archivos de scripts** antes del arribo. Un nuevo envío iCloud → `altillo@badia.me` quedó en Inbox de Gmail y la configuración de Altillo mostró **Apple Mail ha entregado un mensaje nuevo a Altillo**. Tampoco se aplicaron reglas manualmente ni se inyectó el socket.
- Prueba con la candidata firmada instalada en `/Applications/Altillo.app`, marcador `installed-final-10`: el nuevo correo llegó por red y Ajustes confirmó **Apple Mail ha entregado un mensaje nuevo a Altillo**. Después se probó **Desconectar**: recepción apagada y scripts conservados para retirada manual. La regla de QA quedó apagada y guardada al cerrar los ajustes de Mail.
- Los intentos `08` y `09` no recibieron porque la regla de QA había quedado apagada tras reiniciar Mail. Se corrigió esa preparación de la prueba; no era un bloqueo del código publicado.
- Estas pruebas confirman recepción y apertura; no acreditan que una regla de usuario cubra todos los mensajes, ni la cobertura de otras cuentas. La llegada instalada se verificó en una candidata firmada anterior al último empaquetado público del mismo código; no se afirma que ambos binarios sean idénticos byte a byte.

## Fallos encontrados y cambios finales

Las consultas externas a las reglas agotaban el tiempo de espera (`-1712`), incluso con **Altillo → Mail** activado por autorización expresa del usuario, candidata firmada con Developer ID y reinicios de Mail. Existencia y versión respondían, pero no acreditaban lectura funcional de propiedades. Una muestra de proceso observó esperas de Apple Events en `designatedCodeRequirementsCacheQueue`; no se da por confirmada la causa interna de macOS.

La versión publicada elimina las consultas externas del instalador. La preparación solo verifica archivos locales. La llegada de un mensaje válido confirma recepción durante la sesión activa, sin afirmar que las condiciones de la regla sean correctas. Desconectar detiene el receptor y borra la memoria, pero conserva siempre scripts y reglas para su retirada manual. Esta integración ya no necesita el permiso **Altillo → Mail**. No se concedieron permisos a Terminal, Finder ni otros emisores.

El handler también descartaba toda la entrega si el cuerpo faltaba o fallaba su lectura. Ahora cuerpo y cuenta son opcionales: se conservan remitente, asunto e identificador, y solo se reconocen acciones en el texto disponible. Los tests nuevos ejecutan el handler compilado con objetos sintéticos locales para cubrir esos casos. El lote deja de iniciar mensajes al alcanzar cinco segundos; la operación en curso conserva sus límites de tiempo.

Los diagnósticos temporales solo registraron etiquetas, estado y longitud de respuesta, nunca contenido de correo, y se retiraron del código y scripts instalados. No se borraron reglas ni mensajes adicionales. Al cerrar la QA quedaron apagados la regla y el módulo de prueba, y se restauraron las preferencias temporales de arranque. Se verificó en la interfaz la desconexión y el aviso de conservación de scripts; los dos archivos y el manifiesto permanecen presentes.

## Verificación del código final

- Suite macOS: **900 pruebas en 70 suites, sin fallos**, en la candidata final.
- Handler focal: **5 tests y 7 casos pasan** después de añadir el límite de cinco segundos por lote.
- Localización extraída: **0 de 1521 cadenas sin español en Debug** y **0 de 1515 en Release**.
- Puertas de publicación: todos los casos de `script/release-gates-test.sh` pasan.

## Evidencia anterior conservada

Estos resultados corresponden a revisiones previas a la retirada final de consultas; no sustituyen la validación del último código.

- Suite macOS: **898 pruebas en 69 suites, sin fallos**. Localización extraída: **0 de 1517 cadenas sin español**.
- Suite AltilloKit completa: sin fallos, incluida validación de entradas, límites, sockets privados, timeouts y deduplicación. Se repitió tras endurecer enlaces y caducidad de identificadores.
- Instalador anterior: 14 pruebas focales pasan. Sus pruebas de inspección de reglas pertenecían a la implementación que ahora se retira.
- Web: **252 pruebas pasan**, 36 omisiones declaradas en cuatro proyectos; sin reintentos ni pruebas exclusivas. Build de producción correcto.
- Dependencias web: lockfile actualizado a Vite corregido; auditoría con cero vulnerabilidades.
- Puertas de publicación: todos los casos de `script/release-gates-test.sh` pasan.
- Interfaz inicial: Mail apagado por defecto, preparación de scripts, entrega por helper embebido, tarjeta, copia de código y limpieza verificadas con contenido sintético.
- El [spike](../spikes/mail-bridge.md) verificó la regla aplicada a un mensaje importado y apertura del original. Sus tres buzones se retiraron con permiso del usuario.
- CI de `62c01ed`: seis checks correctos, incluido iOS. Es evidencia histórica; la CI del código publicado figura abajo.
- Una candidata previa a los últimos cambios del instalador y su DMG superaron firma Developer ID y notarización. No se confunde este artefacto anterior con el empaquetado público final.

## Publicación y artefacto verificados

- [CI de main](https://github.com/XusBadia/altillo/actions/runs/41300052463): **seis checks pasan** para el código publicado, incluido iOS.
- El flujo canónico `script/release.sh 0.13.0 --publish` terminó con código **0** sobre `431d13c48a1767df10fbd22be1955944bd7186d8`. Apple aceptó la notarización de **app y DMG**.
- Smoke final correcto: montaje del DMG, firma, helper y recursos embebidos, y arranque de la app durante cinco segundos.
- [GitHub Releases](https://github.com/XusBadia/altillo/releases/tag/v0.13.0) muestra `v0.13.0` como última versión. Los appcasts públicos de [altillo.app](https://altillo.app/appcast.xml) y [GitHub Pages](https://xusbadia.github.io/altillo/appcast.xml) anuncian **0.13.0**.
- La descarga pública del DMG desde GitHub tiene **17 913 885 bytes** y SHA-256 `77fd47b97c5c6560dcbb1c3a6f7f2b432124875dd8c05faee2e9a48e0f62d4a3`, igual al DMG local final.
- Comunicación preparada en las cuentas correctas: borrador nativo de X en **@XusBadia** guardado y borrador del perfil personal de LinkedIn guardado con confirmación **Draft successfully saved**. Los posts no se han publicado.

El módulo permanece beta opcional. No se abrieron los enlaces sintéticos ni se usaron los códigos para autenticar en servicios externos. R01 queda cerrado y publicado; R02 y R03 permanecen pendientes para otra sesión.

## Comprobaciones finales de distribución

- La firma Ed25519 del DMG final se verificó con CryptoKit contra `SUPublicEDKey` de la app distribuida.
- La instalación en `/Applications/Altillo.app` se actualizó al empaquetado público final: firma Developer ID, aceptación de Gatekeeper, arranque y Mail apagado verificados. Su ejecutable coincide byte a byte con el del bundle exportado de la publicación. Esta comprobación no sustituye ni reetiqueta la prueba de llegada de la candidata anterior.
- El enlace estable de `altillo-hook` quedó restaurado a la instalación de Aplicaciones y apunta a un ejecutable existente. Los scripts de Mail permanecen conservados; la regla de QA y el receptor quedaron apagados.
