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

- Suite macOS final tras las correcciones: **895 pruebas en 69 suites, sin fallos**. Localización extraída final: **0 de 1517 cadenas sin español**.
- Pruebas focales posteriores del instalador: **12 pasan**, incluida cancelación de un script que espera 30 segundos; la inspección completa tiene un límite de 12 segundos.

## Cierre requerido antes de publicar
- **Bloqueo de entorno:** enviado un único mensaje sintético a la dirección propia autorizada mediante Gmail; Mail devuelve cero resultados para su identificador. Connection Doctor informa fallo de inicio de sesión IMAP y SMTP para Google, y la cuenta configurada aparece Offline. iCloud conecta. La llegada nueva por red sigue sin validar. Es necesario recuperar la sesión Google de Mail antes de dar esta etapa por pasada.
- La inspección real de reglas devolvió un error genérico; se añadió límite de proceso y ayuda para denegación de automatización. Hay que revalidarla con Mail conectado antes de publicar.
- La regla temporal queda desactivada y el módulo Mail vuelve a estar apagado; sus scripts se conservan mientras la regla los referencia. No se borran reglas mediante automatización.
- CI completa del SHA definitivo, incluido el build de iOS.
- Archive firmado, notarización de app y DMG, smoke del artefacto final y comprobación de appcast/descarga públicos.

El módulo permanece beta opcional. La regla se crea y se retira en Mail; Altillo solo elimina sus scripts propios sin cambios cuando ninguna regla los referencia. No se envían códigos o enlaces sintéticos a sitios externos durante la revisión.
