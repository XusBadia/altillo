# Mail 0.13.0 — validación de la candidata

Fecha: 1 de noviembre de 2026. Esta ficha registra pruebas, no una publicación.

## Evidencia local

- Suite macOS inicial: 890 pruebas, 68 suites, sin fallos. Resultado en el `.xcresult` de la ruta estable de BuildCache de Altillo.
- Suite AltilloKit completa: sin fallos, incluida la validación de entradas, límites, sockets privados, timeouts y deduplicación de Mail. Se repitió tras endurecer enlaces y caducidad de identificadores.
- Web: 252 pruebas pasan, 36 omisiones declaradas por la suite en sus cuatro proyectos; sin reintentos ni pruebas exclusivas. Build de producción correcto. Playwright necesitó instalar sus navegadores locales antes de ejecutar la suite.
- Dependencias web: actualización del lockfile a Vite corregido; `npm audit fix` termina con cero vulnerabilidades.
- Puertas de publicación: todos los casos de `script/release-gates-test.sh` pasan.
- Recursos reales: los dos templates `.txt` y el helper ejecutable están en el bundle de desarrollo.
- Interfaz real: Mail aparece apagado por defecto; activación, preparación de ambos scripts compilados, estado vacío, entrega por el helper embebido, tarjeta con remitente/asunto, código `482913`, dominio `example.invalid`, botón de copia y limpieza verificados con contenido sintético. El helper termina con código 0 y no imprime contenido.
- La prueba previa del host Mail (regla aplicada a mensaje sintético importado y apertura del original) está en [el spike](../spikes/mail-bridge.md). Sus tres buzones de prueba se retiraron con permiso del usuario.

- Suite macOS final tras las correcciones: **898 pruebas en 69 suites, sin fallos**. Localización extraída final: **0 de 1517 cadenas sin español**.
- Pruebas focales posteriores del instalador: **13 pasan** en la suite completa final, incluida compilación real de ambas inspecciones contra el diccionario público de Mail y cancelación de un script que espera 30 segundos; la inspección completa tiene un límite de 12 segundos.

## Permisos comprobados en macOS

Ajustes del Sistema → Privacidad y seguridad → Automatización muestra **Altillo → Mail activado**, después de la autorización expresa del usuario. Se verificó el interruptor encendido. La cuenta Google también conecta; son controles distintos. No se concedieron permisos adicionales a Terminal, Finder ni otros emisores.

El instalador ahora distingue un fallo de conexión/automatización de archivos modificados, explica el permiso también en errores de timeout y conserva los scripts. Las **14 pruebas focales del instalador pasan**, incluida la comprobación de que el error no expone detalles del script ni acusa cambios de archivos. La suite macOS completa anterior suma 898 pruebas; CI del commit 62c01ed pasó sus seis checks.

## Cierre requerido antes de publicar
- **Reconexión confirmada:** después de la intervención del usuario, Connection Doctor confirma conexión e inicio de sesión correctos de Google por IMAP/SMTP, además de iCloud. La sincronización inicial terminó; el fallo persistió después.
- **Entrega al servidor confirmada:** Chrome/Gmail muestra en Inbox un mensaje sintético enviado desde la cuenta iCloud configurada. Los envíos desde Gmail al propio alias no mostraron etiqueta Inbox; se usó otra cuenta para comprobar una entrada real. Mail también muestra el mensaje sintético descargado.
- **Pendiente:** confirmar entrega automática de ese mensaje nuevo al notch, sin aplicar reglas manualmente ni inyectar el socket. La tarjeta no apareció durante la revisión de la sincronización inicial. No se da por validado el flujo completo por comprobar solo Gmail/Mail.
- Inspección de reglas: incluso con el permiso activo, al lanzar la candidata desde Finder y tras reiniciar Mail sin consultas pendientes, las lecturas de reglas siguen agotando el tiempo de espera (`-1712`). Las comprobaciones escalares de existencia y versión responden, pero no acreditan que funcione la lectura de propiedades. Una muestra de proceso observa esperas de Apple Events en `designatedCodeRequirementsCacheQueue`; esto es evidencia del bloqueo, no una causa raíz confirmada. Los diagnósticos solo registraron etiquetas, estado y longitud de respuesta, nunca contenido de correo, y se retiraron del código y de los scripts instalados. Los scripts originales conservan sus hashes. La preferencia temporal de arranque se restauró. La consulta de producción mantiene su límite de 12 segundos y conserva los archivos ante el fallo.
- Los mensajes y la regla temporal se conservan para la siguiente comprobación; la regla de QA y el módulo Mail quedan apagados al cerrar la prueba. El permiso Altillo → Mail permanece activado según lo autorizado. No se borraron reglas ni mensajes adicionales.
- CI de 62c01ed: seis checks correctos, incluido el build de iOS; repetir sobre cualquier cambio posterior de código.
- Archive firmado, notarización de app y DMG, smoke del artefacto final y comprobación de appcast/descarga públicos.

El módulo permanece beta opcional. La regla se crea y se retira en Mail; Altillo solo elimina sus scripts propios sin cambios cuando ninguna regla los referencia. No se envían códigos o enlaces sintéticos a sitios externos durante la revisión.
