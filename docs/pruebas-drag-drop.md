# Pruebas manuales de drag & drop

Esta checklist verifica el criterio de aceptación de la fase 0: la matriz de pruebas del §8 del `PLAN.md` en verde. "El arrastre nunca falla" es la métrica de calidad número uno del shelf (§1).

Pruébalo en los dos Macs: el **MacBook con notch** y el **Mac mini con monitor externo** (isla virtual, sin notch físico).

**Cómo compilar y arrancar:**
1. `xcodegen generate` en la raíz del repo.
2. Abre `Altillo.xcodeproj`, esquema **Altillo**, Run. O bien abre directamente la app ya compilada.

**Cómo abrir el registro:** icono de la barra de menú (`square.stack.3d.up`) → "Registro de pruebas de arrastre…". Se abre la ventana "Registro de pruebas", con entradas con marca de tiempo, filtro por categoría, botones "Copiar todo" y "Limpiar", y auto-scroll.

La ventana tiene también una franja "Herramientas": "Probar Quick Look" (previsualiza un archivo de prueba generado), una miniatura arrastrable "Archivo de prueba" (para probar el drag-out sin pasar por el shelf) y "Abrir Inbox" (abre `~/Library/Application Support/Altillo/Inbox` en el Finder).

**Truco:** pulsa "Limpiar" antes de cada caso, para que el registro de ese caso quede limpio. Si algo falla, pulsa "Copiar todo" y pega el registro en el issue o en tus notas.

## Qué mirar en el registro

| Categoría | Qué muestra |
|---|---|
| `drag-start` | Empieza un arrastre con contenido soltable en cualquier punto de la pantalla. App de origen y lista completa de tipos del pasteboard. |
| `drag-end` | Se suelta el botón del ratón al final de ese arrastre. |
| `drop` | Algo se soltó en el notch: app de origen, operación ofrecida, cuántos ítems de cada tipo se leyeron (promesas, archivos, enlaces, imágenes, texto). |
| `ingest` | Por archivo: decisión "referencia" o "copia", motivo (temporal, Mail, Safari/cachés, Papelera, inbox propio) y ruta. |
| `promise` | Promesas de archivo (Fotos, Mail, Safari, Chrome…): tiempo por archivo y total hasta resolver todas, o el error/timeout. |
| `drag-out` | Arrastre desde el shelf: inicio (nº de ítems, tipos, máscara de operación ofrecida) y fin (operación elegida por el destino, punto de destino, si el archivo original sigue existiendo ~0,5 s después). |
| `quicklook` | Resultado de abrir Quick Look. |

## Entrada: fuentes → notch

Para cada fuente, comprueba además que el notch reacciona **en cuanto empieza el arrastre** (aparece `drag-start`), no solo al pasar por encima del notch.

| Fuente | Cómo | Resultado esperado | MacBook | Mac mini |
|---|---|---|---|---|
| Finder, un archivo | Arrastra un archivo estable al notch | Referencia (no copia); `drag-start` con `public.file-url` | ☐ | ☐ |
| Finder, varios archivos | Selecciona varios y arrastra | Referencia para cada uno; `drop` con el nº correcto de archivos | ☐ | ☐ |
| Finder, una carpeta | Arrastra una carpeta | Referencia a la carpeta completa | ☐ | ☐ |
| Escritorio | Arrastra un archivo del Escritorio | Referencia (ruta estable) | ☐ | ☐ |
| Fotos | Arrastra una foto/vídeo | Promesa de archivo (`com.apple.NSFilePromiseItemMetaData` / `com.apple.pasteboard.promised-file-url`); tras resolver, copia en el Inbox | ☐ | ☐ |
| Adjunto de Mail | Arrastra un adjunto de un correo | Promesa de archivo; copia en el Inbox (motivo: Mail) | ☐ | ☐ |
| Imagen de Safari | Arrastra una imagen de una página | `public.tiff`/`public.png` o promesa; copia en el Inbox (motivo: Safari/cachés) | ☐ | ☐ |
| Imagen de Chrome | Arrastra una imagen de una página | Igual que Safari: copia en el Inbox | ☐ | ☐ |
| Miniatura flotante de captura | Arrastra la miniatura que aparece tras hacer una captura | Copia en el Inbox (motivo: temporal) | ☐ | ☐ |
| Texto seleccionado | Selecciona texto en cualquier app y arrástralo | `public.utf8-plain-text`; se crea un ítem de texto | ☐ | ☐ |
| URL de la barra de direcciones (Safari) | Arrastra el icono de la URL | `public.url` (+ título de la página si está disponible); ítem de enlace | ☐ | ☐ |
| URL de la barra de direcciones (Chrome) | Arrastra el icono de la URL | Igual que Safari | ☐ | ☐ |
| Slack | Arrastra un archivo adjunto en un canal | Referencia o copia según si el archivo está en una ruta estable o en caché | ☐ | ☐ |
| VS Code | Arrastra un archivo del árbol de proyecto | Referencia (ruta estable) | ☐ | ☐ |
| Xcode | Arrastra un archivo del navegador de proyecto | Referencia (ruta estable) | ☐ | ☐ |
| Descargas del Dock | Arrastra un archivo desde la pila de Descargas | Referencia (ruta estable) | ☐ | ☐ |

## Salida: notch → destinos

| Destino | Cómo | Resultado esperado | MacBook | Mac mini |
|---|---|---|---|---|
| Finder, mismo disco | Arrastra un ítem del shelf a una carpeta del mismo volumen | `drag-out` operación `move`; el original ya no existe en su ruta | ☐ | ☐ |
| Finder, mismo disco con ⌥ | Igual, sujetando ⌥ | Operación `copy`; el original sigue existiendo | ☐ | ☐ |
| Finder, disco externo | Arrastra a un volumen externo | Operación `copy` por defecto; el original sigue existiendo | ☐ | ☐ |
| Escritorio | Arrastra un ítem al Escritorio | Igual que Finder mismo disco: `move` por defecto | ☐ | ☐ |
| Mail (redactar) | Arrastra a una ventana de redacción | Se adjunta una copia | ☐ | ☐ |
| Mensajes | Arrastra a una conversación | Se adjunta una copia | ☐ | ☐ |
| Slack | Arrastra a un canal o mensaje | Se adjunta una copia | ☐ | ☐ |
| WhatsApp | Arrastra a una conversación | Se adjunta una copia | ☐ | ☐ |
| `<input type=file>` en Chrome | Arrastra sobre el campo de subida | Se adjunta una copia | ☐ | ☐ |
| `<input type=file>` en Safari | Arrastra sobre el campo de subida | Se adjunta una copia | ☐ | ☐ |
| Terminal | Arrastra a una ventana de Terminal | Se pega la ruta (copia, no se mueve el archivo) | ☐ | ☐ |
| Papelera del Dock | Arrastra al icono de la Papelera | `drag-out` operación `delete`; el archivo acaba en la Papelera | ☐ | ☐ |
| Varios ítems a la vez | Selecciona varios en el shelf y arrástralos juntos | Todos se mueven o copian según el destino, sin perder ninguno | ☐ | ☐ |
| Texto | Arrastra un ítem de texto a TextEdit o Notas | Se pega el texto | ☐ | ☐ |
| Enlace | Arrastra un ítem de enlace a la barra de direcciones de Safari o a Notas | Se abre/pega la URL (con título si lo tiene) | ☐ | ☐ |

## Casos límite

- ☐ Arrastre que no va al notch (otra ventana, otro destino): el notch no debe quedarse abierto.
- ☐ Cancelar el arrastre con Esc.
- ☐ Soltar fuera del notch.
- ☐ Promesa lenta (vídeo grande de Fotos o en iCloud): se ve progreso, timeout a los 120 s, y si falla parcialmente se entrega igualmente lo que sí se resolvió.
- ☐ Fallo parcial: varios ítems arrastrados juntos y uno de ellos falla.
- ☐ Soltar un ítem del propio shelf sobre el notch: se rechaza, no se duplica.
- ☐ Los clics simples en una miniatura siguen seleccionando, y el menú contextual sigue funcionando después de añadir el arrastre.
- ☐ Quick Look se abre aunque el panel del notch no pueda ser key.
- ☐ Pantalla completa: el shelf sigue accesible o se comporta de forma predecible.
- ☐ Varios Spaces: cambiar de Space no rompe el notch ni el shelf.
- ☐ Monitor externo sin notch: la isla virtual aparece y se comporta igual que el notch real.

## Cómo reportar un fallo

1. Caso que falla.
2. Mac (MacBook o Mac mini) y versión de macOS.
3. Pulsa "Copiar todo" en el registro y pega el resultado.
