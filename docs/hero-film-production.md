# Vídeo del hero para scroll

## Toma seleccionada, 20 de septiembre de 2026

Proveedor: Grok Build, herramienta nativa `image_to_video`, con el acceso ya autenticado del usuario. Sesión `01a0bf85-cd79-7190-bddb-e6cba9d73089`, salida `videos/2.mp4`.

Fuente: `promo/public/film/01-door.png`. Se animó la imagen original del hero, sin fijar otro fotograma final. Solicitud: 10 segundos, 720p.

Prompt exacto:

> A continuous physical camera move rises and dollies toward the tiny rectangular oak door fixed at the TOP EDGE of the laptop screen, inside its black camera notch. The laptop stays rigid and completely stationary while the CAMERA advances upward to the little door; the door stays exactly the same size relative to the top screen edge and swings inward on its hinge as we approach, revealing a warmly lit miniature wooden attic, then the camera passes through that small doorway into golden darkness with a glimpse of wooden shelves. Single graceful forward camera shot, premium macro cinematography, the door remains a small rectangular inset in the upper screen bezel, unchanged object geometry, calm atmosphere, no text.

Original seleccionado: `docs/assets/hero-scroll-source.mp4`, H.264, 1264 × 720, 24 fps, 241 fotogramas, 10,041667 segundos, 4.470.060 bytes. Se conserva fuera del directorio público. Incluye audio AAC generado; la web solo utiliza fotogramas, sin audio.

### Recursos publicados

`website/public/media/hero-sequence/` contiene 120 fotogramas WebP a 12 fps, 1264 × 720, calidad 76 y compresión 6, unos 3 MB en total. FFmpeg extrajo PNG a 12 fps y `cwebp` realizó la conversión; `manifest.json` define dimensiones, frecuencia y número de imágenes.

El scroll selecciona el fotograma en ambas direcciones. El último plano permanece visible mientras aparece la explicación del estante. En móvil se recentra progresivamente la puerta. Movimiento reducido, ahorro de datos o un fallo inicial de carga conservan la presentación estática.

### Comprobación de la toma seleccionada

- Decodificación completa con FFmpeg, sin errores.
- Contact sheet a un fotograma por segundo de toda la toma.
- Muestreo más denso a cuatro fotogramas por segundo entre los segundos 6 y 9, alrededor de la apertura y entrada.
- La puerta conserva su posición en el notch mientras la cámara se acerca. Se abre aproximadamente a los siete segundos y la cámara entra en el desván hacia el segundo ocho.
- La habitación final tiene madera cálida y estantes vacíos; no es la imagen `02-attic.png`. Es un interior nuevo generado como continuación del plano.

No se contrató ningún servicio ni se utilizaron APIs externas de pago. La toma es vídeo generado, no una fotografía real ni una grabación de la app.

## Primer intento descartado

Proveedor: Grok Build, herramienta nativa `reference_to_video`, con el acceso ya autenticado del usuario. No se contrató ningún servicio ni se utilizaron APIs externas de pago.

Sesión: `01a0bf85-cd79-7190-bddb-e6cba9d73089`.

Referencias fijadas:

- Primer fotograma: `promo/public/film/01-door.png`.
- Último fotograma: `promo/public/film/02-attic.png`.

Solicitud: 10 segundos, 720p, relación 16:9.

Prompt exacto:

> The camera makes one continuous cinematic forward dolly toward the tiny oak doorway in the top notch of this graphite laptop. The door swings inward as the camera approaches, and we pass through the golden doorway into the warm miniature wooden attic, arriving at the final interior frame; tactile handmade materials, stable laptop geometry, physically coherent perspective and slow graceful camera movement throughout, clear clean frame with no text or logos.

Resultado descartado: `promo/public/film/source/hero-scroll/rejected-reference-door-morph.mp4`, H.264, 1280 × 720, 24 fps, 241 fotogramas, 10,041667 segundos, 4.839.256 bytes, con audio AAC generado.

La primera llamada se canceló automáticamente porque el CLI no interactivo no podía mostrar la solicitud de permiso. Se reanudó la misma sesión autorizando únicamente `reference_to_video`; solo una generación llegó a ejecutarse.

### Revisión visual

El primer fotograma coincide con la referencia y la cámara termina dentro del altillo. Sin embargo, durante los primeros segundos la puerta cambia de forma, baja desde el notch y crece sobre la pantalla. Esta toma se considera **descartada para publicación sin corrección**: la transición existe, pero pierde la relación espacial con el notch.

El original se conserva fuera de los archivos públicos de la web para trazabilidad; no está aprobado para publicación.
