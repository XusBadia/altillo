# Kit de Product Hunt

Todo en inglés (audiencia de Product Hunt). Los textos son **borradores** para revisar antes de publicar.

## Archivos

| Qué | Archivo | Especificación |
|---|---|---|
| Miniatura (animada) | `thumbnail.gif` | 240×240, bucle de 3 s, 0,6 MB (límite 3 MB); se anima al pasar el ratón, sin destellos |
| Miniatura (estática) | `thumbnail.png` | 240×240 |
| Vídeo de galería | `altillo-producthunt.mp4` | 32 s, 1920×1080, 60 fps, con música; se entiende sin sonido. Product Hunt lo enlaza: **súbelo a YouTube** y pega la URL en el primer hueco de la galería |
| Galería | `gallery/01…08.png` | 1270×760 |

Orden de la galería (tras el vídeo) y texto alternativo:

1. `01-hero.png`: "Your Mac already had an attic. It just needed a door."
2. `02-drop-into-the-notch.png`: dragging a PDF onto Altillo's box in the notch.
3. `03-drag-it-out.png`: dragging the file from the notch into a Mail message.
4. `04-ai-usage.png`: Claude and Codex quotas with time to refill.
5. `05-ask.png`: Ask, the on-device assistant, answering about today and the clipboard.
6. `06-agents.png`: a Claude Code permission request answered from the notch.
7. `07-everything.png`: Now Playing, Calendar, Drawer, Glances, Limits, Shelf.
8. `08-free-open-source.png`: free forever, open source, native, private.

Las capturas 01–06 salen del anuncio en inglés; la 07, la 08 y la miniatura, de `src/anuncio/ProductHunt.tsx` (composiciones `PHFeatures`, `PHOpen` y `PHThumb`). Todas usan la interfaz real de la app.

## Ficha

- **Name:** Altillo
- **Tagline** (máx. 60 caracteres). Recomendada:
  - **A shelf, AI usage and live agents in your Mac's notch** (53)
  - Alternativas: *Turn your Mac's notch into a shelf, AI meter and more* (53) · *Your Mac already had an attic. Now it has a door* (48, más marca que descripción)
- **Description** (máx. 260; esta tiene 255):
  > Altillo turns your MacBook's notch into a small attic. Drop files there and drag them out in any window, see how much Claude and Codex you have left, and answer your coding agents from the top. Plus music, calendar and on-device Ask. Free and open source.
- **Links:** https://altillo.app · https://github.com/XusBadia/altillo
- **Pricing:** Free
- **Topics:** Mac · Productivity · Developer Tools (alternativa: Open Source)
- **Platforms:** macOS (26 or later)

## Primer comentario del creador (borrador)

> Hi Product Hunt! 👋 I'm Xus, and Altillo is the app I wanted every day on my Mac.
>
> The notch was just a black bar I worked around. Then I realised it's the one spot that's always on screen and never in the way, so I turned it into an *altillo*, the little attic every Spanish home has for the things you want out of sight but within reach.
>
> What it does today: drop a file on the notch and drag it out later into any window; see how much Claude and Codex you have left (and when it refills); get a knock when your coding agent needs permission and answer it right there. Altillo never approves anything on its own. There's also music controls, your calendar, a Drawer for menu bar icons, and Ask, an assistant that runs on your Mac with Apple Intelligence.
>
> It's native (Swift 6, macOS 26), free forever and open source (MIT). No analytics, and your files and credentials stay on your Mac. It's still pre-1.0, so I'd love to hear what feels rough and what you'd put up there next.

## Checklist del lanzamiento

- [ ] Subir `altillo-producthunt.mp4` a YouTube (puede ser «no listado») y pegar la URL en la galería.
- [ ] Revisar y ajustar la tagline, la descripción y el primer comentario.
- [ ] Programar el lanzamiento a las 00:01 PT (09:01 en la España peninsular) de un martes, miércoles o jueves.
- [ ] Añadir a los makers y enlazar la web y GitHub.
- [ ] Publicar el primer comentario en cuanto se abra el lanzamiento y responder los comentarios durante el día.
- [ ] Los posts de lanzamiento en redes pueden reutilizar `../videos/altillo-anuncio.mp4` (ES) y `../videos/altillo-anuncio-en.mp4` (EN).

## Regenerar

```sh
cd promo
npm run render:anuncio:en && cp videos/altillo-anuncio-en.mp4 producthunt/altillo-producthunt.mp4
npx remotion still src/index.ts PHFeatures producthunt/gallery/07-everything.png
npx remotion still src/index.ts PHOpen producthunt/gallery/08-free-open-source.png
npx remotion still src/index.ts PHThumb producthunt/thumbnail.png --frame=45
```

Las capturas 01–06 se extraen del vídeo inglés con ffmpeg (`scale=-2:760,crop=1270:760`) en los segundos 4,9 · 8,15 · 11,35 · 16,6 · 19,6 y 24,25.
