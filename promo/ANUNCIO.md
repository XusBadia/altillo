# Anuncio — «hola» + Altillo en acción

Entrega (32 s, 1920×1080, 60 fps), con la música B (indie-pop):

- `videos/altillo-anuncio.mp4`: español
- `videos/altillo-anuncio-en.mp4`: inglés

## Dirección

- **Cámara suave y sin cortes:** entre encuadres siempre hay un movimiento continuo con suavizado quíntico (velocidad y aceleración nulas al arrancar y al parar). Entra en la pantalla, se acerca a la caja, se aleja directamente hacia Mail y se acerca al notch. El cursor usa el mismo suavizado, y el arrastre sigue una ligera curva. Solo se corta en seco en el montaje final y en la firma.
- **El notch se abre una vez y cambia de sección con clics en sus pestañas** (Altillo → Uso → Pregunta), como en la app. Solo se cierra para dar paso al aviso «Toc, toc» del agente.
- **El protagonista es arrastrar y soltar:** se coge «Propuesta Altillo v2.pdf» de una ventana del Finder y se sube al notch («Súbelo ↑», zona de soltar con la caja, estante). Después se saca del estante y se suelta en un correo de Mail, que muestra el adjunto. Finder y Mail son recreaciones de Tahoe en `src/anuncio/windows.tsx`.
- Todo cae en la rejilla de la música: 120 BPM, 1 compás = 2 s = 120 fotogramas.

| Compás | Tiempo | Plano |
|---|---|---|
| 1 | 0–2 s | «hola» escrito a mano (1,2 s) |
| 2–3 | 2–6 s | El MacBook entra: «Tu Mac / ya tenía / un altillo.» y «Solo le faltaba una puerta.» |
| 4–5 | 6–10 s | Un solo plano: se arrastra el PDF desde el Finder hasta el notch («Súbelo ↑», zona de soltar). Zoom a la caja justo cuando el archivo llega y las solapas se abren. Se suelta, el documento cae dentro, aparece el estante y la cámara vuelve al plano medio. «Súbelo al notch.» |
| 6–7 | 10–14 s | Plano medio notch + Mail: sacarlo del estante y soltarlo en el correo. «Bájalo donde lo necesites.» |
| 7½–9 | 13–18 s | Primer plano: el notch se abre y un clic en la pestaña Uso muestra Claude y Codex |
| 10 | 18–20 s | Clic en ✦: Pregunta |
| 11 | 20–22 s | «Toc, toc.»: la música se para y el notch avisa del `git push` |
| 12–13 | 22–26 s | Agentes: clic en Permitir |
| 14 | 26–28 s | Montaje a toda velocidad, un corte seco cada medio tiempo (0,25 s) con estados reales: Música · Agenda · Avisos (reunión) · Cajón · Límites · Suelta y pregunta · Vistazos · Y más |
| 15–16 | 28–32 s | Firma |

## Música

Se usa la **B** (`public/anuncio/audio/score-b.wav`, indie-pop), compuesta con `scripts/anuncio-music-variants.py` a partir de **Apple Loops**. Su licencia permite usarlos en composiciones propias, no redistribuir los loops sueltos. El script también genera las variantes descartadas A (disco-funk) y C (electro-pop): `python3 scripts/anuncio-music-variants.py a c`. Loops, tonalidades y arreglo por compás están en `public/anuncio/audio/README-variantes.md`. Mide −14 LUFS y un pico de −1,5 dBTP o menos.

El script recorta el *priming* AAC de 2112 muestras de cada loop; sin ese recorte, cada repetición tiene un hueco de unos 48 ms.

Nadie ha escuchado las pistas; están verificadas solo con medidas.

## De dónde sale la interfaz

No es una réplica: son los **estados de diseño reales de la app** (`DesignScenario`, los mismos del menú «Design review» y de `-designScenario`), renderizados desde `NotchRootView` con un test.

1. Copia `scripts/ScenarioExportTests.swift` en `Tests/AltilloMacTests/` de un worktree limpio y ejecuta `xcodegen generate`.
2. Ejecuta el test **con los datos derivados fuera de `~/Documents`**. Si no, macOS pide permiso de Documentos a la app de pruebas:
   ```sh
   TEST_RUNNER_ALTILLO_EXPORT_DIR=/tmp/anuncio-ui/es xcodebuild test -project Altillo.xcodeproj -scheme Altillo \
     -destination 'platform=macOS' -derivedDataPath /tmp/dd-anuncio \
     -only-testing:AltilloMacTests/ScenarioExportTests -testLanguage es -testRegion ES
   ```
   Repite con `en`.
3. Copia el resultado a `public/anuncio/ui/{es,en}/` y ejecuta `python3 scripts/anuncio-manifest.py`, que mide el contorno de cada estado.

El test usa un `NSHostingView` en una ventana fuera de pantalla y `cacheDisplay` sobre un bitmap a 3×. Con `ImageRenderer`, las vistas de AppKit (estante, agentes, campo de Pregunta) salían vacías.

Los datos (archivos, agentes, eventos, canción, respuesta de Pregunta) son el contenido de demostración de la app (`DemoContent`). La apertura entre estados se anima en Remotion: la forma negra crece desde el notch con un muelle rápido (~150 ms) y un pequeño rebote.

## La caja al soltar

`scripts/DropExportTests.swift` exporta dos cosas. La primera es el panel real con el puntero sobre la caja (`dropTargetHover.png`, con el ajuste de depuración `prototypeHoverZone=shelf`). La segunda es `DesvanCardboardBox` sola en 29 aperturas, de 0 a 1,12 (`public/anuncio/box/`). La posición y la escala de la caja dentro del panel se midieron por correlación de plantillas (`position.json`: escala 0,795, en (140, 63) pt en español y (150, 63) en inglés). En el vídeo, las solapas siguen un muelle con rebote, como `Desvan.Motion.flaps`.

## Otros recursos

- **Hola manuscrito:** `src/anuncio/hello/`. Letras de Hershey Script Simplex (dominio público) unidas en un solo trazo y suavizadas. No usa el dibujo de Apple. `generator/` lo regenera.
- **MacBook y fondos:** `public/anuncio/product/`, generados con gpt-image (prompts en su `README.md`). El MacBook no lleva logotipo. La pantalla real se compone encima.
- **Tipografía:** fuente del sistema (SF) mediante `system-ui`.

## Teaser «Mira arriba»

`videos/altillo-teaser.mp4` (ES) y `videos/altillo-teaser-en.mp4` (EN): 16 s, 1920×1080, 60 fps, para X. Pieza propia (`src/anuncio/Misterio.tsx`), no un remontaje del anuncio. Es misteriosa: lleva el nombre, pero no la web.

| Compás | Tiempo | Plano |
|---|---|---|
| 1–2 | 0–4 s | El notch cerrado en la oscuridad; la luz cálida de la rendija crece despacio, sin parpadeos. «Llevas años mirándolo.» / «Pero nunca has mirado dentro.» |
| 3–4 | 4–8 s | Plano fijo: el notch se abre y cambia de pestaña cada dos tiempos (Altillo, Uso, Agentes, Cajón) |
| 5 | 8–10 s | Una pestaña por tiempo: Sonando, Pregunta, Agenda, Uso |
| 6 | 10–12 s | Una por medio tiempo, con la subida; el notch se cierra justo antes del silencio |
| 7 | 12–13 s | Silencio total: «Mira arriba.» |
| 7–8 | 13–16 s | Golpe final: notch con luz, «Altillo», «Muy pronto.» |

La cámara no salta: un solo plano con el borde de la pantalla arriba, empuje lento (2,05 → 2,4 px/pt) y un paneo de 20 pt. Los cambios de pestaña usan los muelles del anuncio (la forma se ajusta y el contenido cruza). La secuencia está en `TABS`.

Música: `public/anuncio/audio/teaser-misterio.wav`, generada con `python3 scripts/teaser-music.py`. Es la B del anuncio oída «a través del techo»: paso bajo que se abre de 260 Hz a 12 kHz, silencio en «Mira arriba» y golpe final sin filtro a los 13,000 s. Mide −13,9 LUFS y −2,1 dBTP.

## Product Hunt

Kit completo en `producthunt/` (miniatura, galería 1270×760, vídeo y textos): ver `producthunt/README.md`.

## Render

```sh
cd promo
npm run render:anuncio      # español
npm run render:anuncio:en   # inglés
npm run render:teaser       # teaser «Mira arriba», español
npm run render:teaser:en    # teaser, inglés
```
