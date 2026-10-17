# YouTube · vídeos de Casa / Home

Canal **Altillo**, @Altilloapp (ver `promo/youtube/README.md` en `main`). Propuesta:
- **Lunes 26/10:** subir los dos vídeos como **no listados**.
- **Martes 27/10, 13:30 Madrid (12:30 UTC):** pasarlos a **públicos**, antes del post del foro, que incrusta el EN.

Nada subido ni programado por este kit.

| Vídeo | Archivo | Especificación | Miniatura |
|---|---|---|---|
| EN | `promo/videos/altillo-casa-en.mp4` | 1920×1080, 60 fps, 24 s | `altillo-casa-en.png` (fotograma 250) |
| ES | `promo/videos/altillo-casa.mp4` | 1920×1080, 60 fps, 24 s | `altillo-casa.png` |

Rutas relativas a `~/Developer/altillo-h2` (rama `release/home-0.11.0`).

**Rótulo de 13–16 s:** ya corregido a «Straight from your Home Assistant.» / «Desde tu Home Assistant.» (antes «Anything in Home Assistant.» / «Todo lo que tengas en Home Assistant.», ver [COPY-REVIEW.md](COPY-REVIEW.md#vídeo)). Subir los MP4 actuales: un vídeo de YouTube no se puede reemplazar sin perder la URL.

**Capítulos: no.** YouTube exige al menos tres marcas de tiempo, empezando en 00:00, y capítulos de al menos 10 segundos. En 24 s no caben tres capítulos de 10 s. No poner marcas de tiempo en la descripción.

**Shorts (opcional, no por defecto):** los verticales (`altillo-casa-vertical-en.mp4`, `altillo-casa-vertical.mp4`) pueden subirse como Shorts. Duplicarían el mismo contenido en el mismo canal; decidirlo después de ver cómo responde el foro.

## EN

Title (49):
```text
Altillo Home: Home Assistant in your Mac's notch
```

Description:
```text
Home Assistant, in your notch. Altillo 0.11.0 adds Home, a beta section that controls your Home Assistant from the MacBook notch.

• Lights: click to toggle, drag to dim; tiles glow in each bulb's real colour. Brightness, white temperature and colour presets in the detail view.
• Switches, plugs, fans (on/off), blinds and covers with position, scenes and scripts.
• Sensors at a glance, rooms from your Home Assistant areas, your own pages and tile names.
• Doorbell peek: when it rings, the notch shows a still snapshot from the camera you choose.
• Finds Home Assistant on your network and signs in with its own login page. The token stays in your Mac's Keychain.

Altillo talks directly to your Home Assistant: on your local network, or at an https address you enter. No Altillo account, server or analytics.

Not yet supported: climate, locks, alarm panels, garage door control, media players, live camera, multiple servers. Apple Home on the Mac is planned through Shortcuts.

The video uses Altillo's built-in demo home; the doorbell picture is an illustration.

Free · MIT open source · macOS 26+ · Signed and notarized · Pre-1.0
Altillo is an independent project, not affiliated with or endorsed by Home Assistant or the Open Home Foundation.

Download: https://altillo.app/
Source: https://github.com/XusBadia/altillo
Privacy: https://altillo.app/privacy/
```

Tags:
```text
altillo, home assistant, home assistant mac, mac notch, macbook notch app, macos 26, smart home mac, home automation, open source mac app
```

## ES

Título (51):
```text
Altillo Casa: tu Home Assistant en el notch del Mac
```

Descripción:
```text
Tu casa, en el notch. Altillo 0.11.0 trae Casa, una sección en beta para controlar tu Home Assistant desde el notch del MacBook.

• Luces: clic para encender o apagar, arrastrar para atenuar; cada baldosa brilla con el color real de su bombilla. Brillo, temperatura de blanco y colores en el detalle.
• Interruptores, enchufes, ventiladores (encender/apagar), persianas con posición, escenas y scripts.
• Sensores de un vistazo, estancias de tus áreas de Home Assistant, páginas y nombres propios.
• Timbre: cuando suena, el notch asoma con una foto fija de la cámara que elijas.
• Encuentra Home Assistant en tu red e inicia sesión con su propia página de acceso. El token se guarda en el Llavero del Mac.

Altillo habla directamente con tu Home Assistant: en tu red local o en una dirección https que tú indiques. Sin cuentas, servidores ni analítica de Altillo.

Aún no: clima, cerraduras, alarmas, control de la puerta del garaje, reproductores, cámara en directo ni varios servidores. Apple Home en el Mac está previsto mediante Atajos.

El vídeo usa la casa de demostración de Altillo; la foto del timbre es una ilustración.

Gratis · Código abierto MIT · macOS 26+ · Firmada y notarizada · Pre-1.0
Altillo es un proyecto independiente, sin relación ni respaldo de Home Assistant ni de la Open Home Foundation.

Descarga: https://altillo.app/es/
Código: https://github.com/XusBadia/altillo
Privacidad: https://altillo.app/es/privacidad/
```

Etiquetas:
```text
altillo, home assistant, home assistant mac, notch mac, app notch macbook, macos 26, domótica mac, domótica, app mac código abierto
```

`https://altillo.app/es/` y `/es/privacidad/` responden 200 el 17/10. La sección de privacidad de Casa **todavía no está en producción** (la página pública no contiene «Home (optional)»): dependencia del día 26.

## Campos comunes

- **Categoría:** Science & Technology / Ciencia y tecnología.
- **Para niños:** No.
- **Idioma del vídeo:** inglés / español.
- **Promoción pagada:** no.
- **Lista de reproducción:** opcional, «Altillo» con el anuncio principal.
- **Contenido alterado o sintético: «No».** YouTube pide declarar contenido *«AI-generated or altered content that seems realistic»* y exime explícitamente la animación, los efectos especiales y los retoques estéticos. Este vídeo no tiene imágenes generadas:
  - La interfaz son fotogramas reales de la app con datos de demostración.
  - La foto del porche es un SVG dibujado a mano (`Porch.tsx`, `promo/CASA.md`: «No usa imágenes generadas»).
  - La música son Apple Loops.

  El aviso de la descripción («demo home», «illustration») cubre la transparencia. Esto difiere del anuncio principal, que sí declaró uso de IA por imágenes generadas. No copiar esa casilla por inercia.
- **Visibilidad:** no listado hasta el 27, después público. Verificar reproducción sin sesión y miniatura.
