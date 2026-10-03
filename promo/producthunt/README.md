# Kit de Product Hunt · Altillo

Textos EN y fecha aprobados por Xus el 03/10. **Martes 20/10/2026, 00:01 Pacific (America/Los_Angeles, PDT): 07:01 UTC / 09:01 Europe/Madrid.** Programación confirmada por Product Hunt el 03/10: `Successfully Scheduled!` y panel `Scheduled`. [Panel de prelaunch](https://www.producthunt.com/products/altillo/altillo/prelaunch). Usar la cuenta personal de Xus ya usada para Aurio y una ficha independiente. Aurio está programada el 14; no modificar sus publicaciones. Estado real en [EXECUTION.md](../launch/EXECUTION.md).

## Archivos

| Qué | Archivo | Especificación |
|---|---|---|
| Miniatura recomendada para subir | `thumbnail-600.png` | 600×600, estática |
| Miniatura estática alternativa | `thumbnail.png` | 240×240 |
| Miniatura animada | `thumbnail.gif` | 240×240, 3 s, 0,6 MB; límite 3 MB, animación al pasar el ratón |
| Vídeo de galería | `altillo-producthunt.mp4` | 32 s, 1920×1080, 60 fps; vídeo existente en YouTube, registrado no listado |
| Galería | `gallery/01…08.png` | 1270×760; subir al menos dos imágenes |

**URL completa del vídeo:** https://www.youtube.com/watch?v=L33ophXDYUM. La guía oficial exige URL completa; no pegar `youtu.be`. No puede estar privado; el estado no listado permite compartirlo y el cambio a público queda para el lanzamiento tras aprobación.

Orden y alt text de galería tras el vídeo:

1. `01-hero.png`: “Your Mac already had an attic. It just needed a door.”
2. `02-drop-into-the-notch.png`: A PDF is dragged onto Altillo's file shelf in the notch.
3. `03-drag-it-out.png`: The file is dragged from the notch into a Mail message.
4. `04-ai-usage.png`: Claude and Codex quotas with time to refill.
5. `05-ask.png`: Ask uses an on-device model to answer about calendar and clipboard context. Web lookups use external services.
6. `06-agents.png`: A Claude Code permission request answered explicitly by the user.
7. `07-everything.png`: Music, Calendar, Drawer, Glances, Limits and Shelf. Drawer hides icons on macOS 27; on 26 originals remain visible.
8. `08-free-open-source.png`: Free, MIT open source, native. No Altillo backend; usage checks connect directly to their provider.

01–06 salen del anuncio EN; 07/08 y miniatura de `src/anuncio/ProductHunt.tsx`. La galería muestra interfaz de la app; el vídeo incluye piezas visuales generadas y no debe describirse como una captura íntegra sin edición.

## Ficha para pegar

**Name:** Altillo

**Tagline · 53 caracteres, máximo oficial 60:**

```text
A shelf, AI usage and live agents in your Mac's notch
```

**Description · recomendada, ≤500 según guía oficial:**

```text
Altillo puts a file shelf, Claude/Codex usage and coding-agent requests in your Mac's notch or a virtual island. Drop files at the top and drag them out later. Agent permissions stay your decision. Native for macOS 26+, free and MIT open source. Ask uses an on-device model; web lookups contact external services. Optional usage checks authenticate directly with the relevant provider. Drawer hides icons on macOS 27; on 26 originals stay visible.
```

**Fallback ≤260 si el editor sigue usando el límite anterior:**

```text
Altillo puts a file shelf, Claude/Codex usage and coding-agent requests in your Mac's notch or a virtual island. Drop files at the top and drag them out later. Agent permissions stay your decision. Native for macOS 26+, free and MIT open source.
```

- URL principal: https://altillo.app/ (sin acortador ni UTM).
- Enlace adicional: https://github.com/XusBadia/altillo.
- Pricing: Free. Sin promo code necesario.
- Hasta tres tags sugeridos: Mac, Productivity, Developer Tools; usar Open Source como alternativa si el formulario no ofrece alguno.
- Platform: macOS 26+. Release universal: Intel x86_64 y Apple Silicon arm64. Ask depende de Apple Intelligence.
- Maker: Xus Badia, seleccionando el perfil personal real en el editor; no inventar username.

## Primer comentario del creador

```text
Hi Product Hunt! I'm Xus, and Altillo is the app I wanted on my Mac.

I needed somewhere to put a file down while finding the window where it belonged. The notch became that place. “Altillo” is Spanish for a small attic: things out of sight, but within reach.

Drop a file at the top, switch windows, then drag it out. You can also see Claude/Codex usage and respond when a coding agent needs permission. Every approval or denial is your decision; Altillo never approves automatically.

It's native for macOS 26+, free and MIT open source, signed and notarized. On a display without a notch, it uses a virtual island. There are music controls, calendar, timers and reminders too. Ask runs its model on your Mac when Apple Intelligence is available; web lookups contact external services.

There is no Altillo backend or app analytics. Optional usage checks present the credential already stored by the provider's own tool directly to that same provider. Drawer needs Accessibility, hides selected icons on macOS 27, and opens them without hiding the originals on 26. Screen Recording is optional for showing the actual menu bar icon images.

It's still pre-1.0. I'd love feedback on the first file drop and the agent permission flow, especially if you use an external display.
```

## Checklist

- [x] Vídeo existente registrado en YouTube; miniatura propia preparada.
- [x] Copy, compatibilidad de Drawer y privacidad corregidos en el kit.
- [x] Miniatura 600×600 y galería preparadas.
- [x] Fecha, texto y acciones externas aprobados por Xus el 03/10; no repetir la aprobación.
- [x] Ficha Altillo independiente creada desde @xusbadia, sin duplicados.
- [x] Miniatura 600×600, ocho imágenes y URL completa YouTube guardadas; comprobar reproducción el día de lanzamiento.
- [x] Descripción de 447 caracteres aceptada; editor confirma 20/10 12:01am PT / 09:01am GMT+2 (PDT en Los Ángeles).
- [x] Xus Badia @xusbadia como maker/hunter único, precio Free, ficha programada y confirmada.
- [ ] El día del lanzamiento: comprobar página pública, maker comment y vídeo; pasar YouTube a público tras aprobación.
- [ ] Compartir el enlace real y pedir feedback, nunca votos; responder preguntas humanas.

Fuentes: [guía oficial](https://www.producthunt.com/launch), [preparación y campos](https://www.producthunt.com/launch/preparing-for-launch), verificadas 03/10. Más calendario, perfiles y textos en [launch/README.md](../launch/README.md).

## Regenerar si cambia el producto

```sh
cd promo
npm run render:anuncio:en
cp videos/altillo-anuncio-en.mp4 producthunt/altillo-producthunt.mp4
npx remotion still src/index.ts PHFeatures producthunt/gallery/07-everything.png
npx remotion still src/index.ts PHOpen producthunt/gallery/08-free-open-source.png
npx remotion still src/index.ts PHThumb producthunt/thumbnail.png --frame=45
npx remotion still src/index.ts PHThumb producthunt/thumbnail-600.png --frame=45 --scale=2.5
```

No es necesario regenerar teasers del usuario. Las capturas 01–06 se extraen del anuncio EN con ffmpeg (`scale=-2:760,crop=1270:760`) a 4,9 · 8,15 · 11,35 · 16,6 · 19,6 · 24,25 segundos.
