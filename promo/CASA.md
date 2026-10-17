# Casa / Home: Home Assistant en el notch (borrador)

Entrega: 24 s a 60 fps con la música B recortada. Termina en la tarjeta de la cámara del timbre y corta a la firma con el golpe final (ya no sale Ajustes).

- `videos/altillo-casa.mp4` (ES) y `videos/altillo-casa-en.mp4` (EN): 1920×1080.
- `videos/altillo-casa-vertical.mp4` y `videos/altillo-casa-vertical-en.mp4`: 1080×1920, para X y Reels.
- Pósters: `videos/altillo-casa.png` y `videos/altillo-casa-en.png` (fotograma 250, todas las luces encendidas y la cuadrícula nítida).

Código: `src/casa/Casa.tsx` (composiciones `AltilloCasa`, `AltilloCasaEN`, `AltilloCasaVertical` y `AltilloCasaVerticalEN`), `src/casa/Porch.tsx` (la imagen de la cámara del timbre) y `src/casa/manifest.ts` (generado).

## Dirección

- **Enseña el producto:** todos los fotogramas del notch son la app real (`NotchRootView` con la casa de demostración), exportados por `scripts/HomeExportTests.swift`. Finder, Mail y el MacBook no salen; la pantalla es el fondo del anuncio con la barra de menús.
- **Cámara de cine, sin cortes:** la cámara se acerca a cada acción (la lámpara, «Peli», la persiana, el interruptor, el aviso, la tarjeta de la cámara) y se aleja para enseñar la cuadrícula entera. El zoom, la x y la y tienen cada uno sus propias claves (`cameraMoves` en `Casa.tsx`), así un paneo puede seguir mientras termina un zoom sin pararse. Entre claves, movimiento quíntico con el zoom en escala logarítmica. Encima, un pequeño empujón en algunos tiempos (`PULSES`: el clic de «Peli», la palanca, cada palabra del recorrido y la vuelta de la música a los 18 s): sube en 8 fotogramas y se asienta en 34, también quíntico. Solo cambian de escena el gancho (sobre negro) y la firma.
- **Foco (profundidad de campo):** el escritorio se pinta dos veces. Debajo, una copia desenfocada (9 px en el corte ancho, 7 px en el vertical), más oscura (−40 %) y algo menos saturada; encima, la nítida, recortada a un rectángulo con 30 pt de borde suave (`FOCUS` y `R`). El rectángulo se desliza de un sujeto a otro (enfoque de seguimiento) y la intensidad sube y baja con movimientos quínticos. El cursor va en su propia capa y siempre está nítido. Los rectángulos cubren elementos enteros, para que ningún texto quede medio enfocado.
- **Zoom máximo:** ≤ 3,4 sobre la interfaz rasterizada (exportada a 3×, se ve nítida). Solo pasan de ahí el aviso (4,0, como antes) y el empuje final sobre el porche (3,85), que es SVG.
- **El notch se abre** (muelle de unos 150 ms) y cambia de estado dentro: la cuadrícula, el detalle de la persiana, la cuadrícula otra vez y el detalle del interruptor. Se cierra con el golpe del break para dejar paso al aviso del timbre. Un clic en el aviso lo vuelve a abrir con la tarjeta de la cámara, que sigue abierta hasta el corte.
- **Movimiento 1:1:** el arrastre de la lámpara y el de la persiana usan fotogramas reales cada 2 % (28 y 29): se enseña el más cercano a la posición del cursor, sin fundir dos, para que las cifras («42 %») nunca salgan dobles bajo el zoom.
- **Ningún texto fundido:** en los cambios de estado (la escena «Peli» y el interruptor) las luces, la palanca y los colores se funden, pero las zonas donde cambia el texto (`MOVIE_TEXT`, `SWITCH_TEXT` en `Casa.tsx`) pasan de un fotograma real al otro a mitad del fundido. Las baldosas cambian mientras siguen desenfocadas (el foco solo se abre a la cuadrícula después) y el foco sobre «Peli» tiene un borde suave corto (8 pt) para que la etiqueta de «Mesita», justo encima, no se vea a medias. El encendido escalonado es el de la app: cada baldosa se ilumina con su `easeOut` de 0,35 s, una por semicorchea.
- **Rejilla:** 120 BPM; 1 compás = 2 s = 120 fotogramas.

| Tiempo | Plano | Cámara y foco |
|---|---|---|
| 0–2 s | Gancho sobre negro: «Tu casa, / ahora / en el notch.» («Your notch can now run your home.») | — |
| 2–3 s | Entra la pantalla con el *drop* y la cámara empuja hacia el notch mientras sube el cursor | De la pantalla entera (1,27) a la cuadrícula (2,6) |
| 3–4,3 s | Al pasar el cursor, el notch se abre y las baldosas se encienden una a una con el color real de cada bombilla. «Tus luces. Con su color real.» | Empuje lento (2,6 → 2,72), todo nítido |
| 4,1–5,5 s | Arrastre sobre «Lámpara de pie»: del 70 % al 16 %, 1:1. «Arrastra para atenuar.» | Acercamiento a la lámpara (3,3); el foco se cierra sobre su baldosa y el resto se desenfoca |
| 5,3–6,0 s | El cursor baja a la etiqueta «Peli» | La cámara se aleja a la cuadrícula entera, inclinada hacia «Peli»; el foco salta de la lámpara a la etiqueta |
| 6,0 s | Clic en «Peli»: la lámpara pasa a morado al 25 %, se apaga el resto y se baja la persiana. «Noche de peli. Un clic.» | Empujón en el golpe; el foco se abre a toda la cuadrícula para que se vea la escena entera |
| 6,5–7,5 s | Mantener pulsada «Persiana» (anillo de 0,6 s) | La cámara se inclina hacia la baldosa (3,0) y el foco la aísla |
| 7,5–10,3 s | Se abre su detalle y se sube el tirador de latón del 4 % al 60 % («Apertura 52 %»): la ventana se ilumina. Clic en «‹ Favoritos». «Sube la persiana.» | Acercamiento a la ventana y a la lectura (3,25 → 3,4 mientras sube); se aleja a la cuadrícula para el clic |
| 10,7–12,2 s | Mantener pulsado «Pasillo» | Deriva a la derecha (2,95) y foco en la baldosa |
| 12,0–13,6 s | Se abre el interruptor de baquelita y se acciona la palanca: el piloto se enciende. Vuelta a la cuadrícula. «Dale al interruptor.» | Acercamiento a la placa (3,4), foco en la placa y su estado; empujón en la palanca |
| 13,3–16 s | Recorrido por Luces, Enchufes, Persianas y Escenas, una palabra por tiempo. «Todo lo que tengas en Home Assistant.» | Se aleja a todo el panel (2,45), todo nítido; un empujón por palabra |
| 16 s | Break: el notch se cierra con el golpe y la música se para | Empieza a subir hacia el aviso |
| 16,5–17,2 s | «Ding… dong»: el aviso del timbre, centrado y de cerca. «Ding-dong.» | Aviso a 4,0; la barra de menús y el fondo se desenfocan |
| 17,25–18 s | Clic en el aviso: se abre Casa con la tarjeta de la cámara arriba (el estado real tras un timbrazo). «Ding-dong. Mira quién es.» («See who it is.») | Baja a la tarjeta (3,4); el foco se ensancha del aviso a la tarjeta |
| 18–20 s | La música vuelve. La tarjeta: el porche, «Han llamado · Timbre · ahora» | Empujón en la vuelta y empuje lento hacia el porche (3,85) que sigue hasta el corte; a los 18,75 s el foco pasa a la foto del porche |
| 20–24 s | Firma con el golpe final: icono, «Altillo», «Tu casa, en el notch.» («Home Assistant, in your notch.»), «Gratis · Código abierto · altillo.app» | — |

En el vertical, los mismos movimientos con encuadres adaptados al ancho de 1080 px (cuadrícula a 2,0; lámpara 2,6; persiana 2,55–2,62, sin cortar botones; interruptor 2,6 con todo el texto; tarjeta 2,05; porche 2,6).

## Música

`public/casa/audio/casa.wav` sale de `python3 scripts/casa-music.py`. Es la B del anuncio (`score-b.wav`, Apple Loops) sin los compases 8–9 ni 12–13: salida 1–7 = B 1–7, 8 = B 10, 9 = B 11 (break), 10 = B 14 (la vuelta, con la subida hacia el golpe) y 11–12 = B 15–16 (golpe final y cola). Los empalmes están en límites de compás, con un fundido de 6 ms que coge material de después del compás, así nada se adelanta: el break cae a los 16,000 s y el golpe final, a los 20,000 s, justo en el corte a la firma. La cola de la B se apaga sola y el último medio segundo se funde a cero. En el silencio del break suena un timbre sintetizado (dos campanas, Mi5 y Do5, a 16,5 y 17,0 s). Mide −14,0 LUFS y −1,9 dBTP (−2,0 en el AAC de los MP4). Solo se ha verificado con medidas; nadie lo ha escuchado.

## De dónde sale la interfaz

`scripts/HomeExportTests.swift` hace capturas a 3× de `NotchRootView` en una ventana fuera de pantalla, igual que `ScenarioExportTests`. Lo que cambia de un estado a otro se aplica a la casa de demostración (`HomeDemoService.update`, `HomeStore.activate`). Hay varios modos (`ALTILLO_HOME_EXPORT`), y cada uno corre en su propio proceso porque `-demoHome` solo se lee una vez:

| Modo | Exporta |
|---|---|
| `grid` | `unrevealed`, `grid`, `dim-00…27` (70 → 16 %), `movie-final`, `after-blind`, `after-lamp` |
| `blind` | `blind-00…28` (60 → 4 %), detalle de la persiana |
| `lamp` | `lamp-off`, `lamp-on`: el interruptor del pasillo (sin brillo, porque es una luz que solo se enciende y se apaga) |
| `peek` | `peekDoorbell` (el aviso del timbre) e `idle` |
| `ring` | `ring-grid`: Casa justo después de un timbrazo (Peli, persiana al 60 % y pasillo encendido, como deja la casa el vídeo), con la tarjeta de la cámara arriba |
| `settings` | `settings` (servidor encontrado) y `settings-connected`: la página Ajustes › Casa (sin barra lateral) con un descubrimiento falso. El vídeo ya no los usa (se quitó el final de Ajustes), pero se conservan |
| `settings-page` | `settings-page`, `settings-page-full` (alto, toda la página) y `settings-sections`: la ventana de Ajustes real en su página Casa con la casa de demostración conectada (`-homeSettingsDemo`). Para revisar el diseño, no para el vídeo |
| `demo` | cualquier `-demoHome` como imagen fija (`ALTILLO_HOME_DEMO=area`…), para revisar |

Pasos:

1. En el worktree, usa un `Config/Local.xcconfig` propio (`ALTILLO_BUNDLE_PREFIX = dev.altillo.promoexport`, `ALTILLO_MAC_SIGN_IDENTITY = -`). Así el test no cierra tu Altillo ni hereda tus ajustes. Copia `scripts/HomeExportTests.swift` en `Tests/AltilloMacTests/` y ejecuta `xcodegen generate`.
2. Por cada idioma y modo, con los datos derivados fuera de `~/Documents`:
   ```sh
   TEST_RUNNER_ALTILLO_EXPORT_DIR=/tmp/casa-ui/es TEST_RUNNER_ALTILLO_HOME_EXPORT=grid \
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Altillo.xcodeproj -scheme Altillo \
     -destination 'platform=macOS' -derivedDataPath /tmp/altillo-h2-dd-promo \
     -only-testing:AltilloMacTests/HomeExportTests -testLanguage es -testRegion ES
   ```
   Repite con `blind`, `lamp`, `peek`, `ring` y `settings`, y luego con `en` / `US`. A veces el primer arranque se cae: xcodebuild reintenta solo. Comprueba que estén todos los PNG.
3. `python3 scripts/casa-manifest.py [--from /tmp/casa-ui]` convierte los PNG a WebP en `public/casa/ui` (color con pérdida a q 92, alfa sin pérdida, `cwebp`), borra cualquier PNG que quede allí y mide la forma de cada estado y la miniatura de la cámara (`src/casa/manifest.ts`). Los PNG a 3× son los originales y no se versionan (`promo/.gitignore`); `public/casa/ui` ocupa unos 22 MB y todo `public/casa`, unos 30 MB. Si solo vuelves a exportar unos modos, pasa una carpeta con todos los PNG (los de antes más los nuevos), porque los WebP de los modos que no estén se conservan pero no se miden de nuevo.
4. Devuelve `Local.xcconfig` a su estado y quita el test de `Tests/`.

En español, los dispositivos y las estancias de demostración se renombran («Lámpara de pie», «Salón», «Peli»…) con `HomeDemoService.rename(entities:areas:)`. Es el único cambio en el código de la app: solo existe en DEBUG y solo lo usa este test. «Buenas noches» se quita de favoritos para que las etiquetas y los sensores quepan en una fila sin cortarse.

La foto de la cámara de la casa de demostración es un degradado de 320×180, así que en el vídeo se tapa (en la miniatura del aviso y en la tarjeta, `SNAPSHOT` en `Casa.tsx`, 136×76 pt) con `Porch.tsx`: un porche al atardecer dibujado a mano en SVG, con farol, puerta verde, maceta y una silueta con un paquete. No usa imágenes generadas.

## Suavidad

- `node scripts/casa-camera-check.mjs [wide|vertical]` es la comprobación analítica de la cámara y del cursor, fotograma a fotograma, hasta el corte a la firma. En la última versión, el paneo del centro del encuadre no pasa de 14,8 px por fotograma (13,5 en el vertical) y el zoom, de 1,7 %/f (2,3 en el vertical, en la entrada de la pantalla). Los puntos fijos a 300 pt del centro llegan a 15 px/f; el más alejado (abajo a la derecha, casi siempre fuera de cuadro) llega a 23–24 px/f durante el acercamiento a la lámpara, porque es un zoom rápido (con suavizado quíntico, sin saltos). La aceleración máxima de la cámara es de 2,5 px/f² y el *jerk*, de 1,5. El cursor no pasa de 40 px por fotograma (máximo 37).
- `python3 scripts/motion-check.py videos/altillo-casa.mp4 --expect-cuts 120,1200` analiza el vídeo renderizado fotograma a fotograma (necesita `numpy` y `cv2`; `/opt/homebrew/bin/python3` los tiene). Sigue puntos con Lucas–Kanade, ajusta una similitud con RANSAC y mide la diferencia media entre fotogramas. En el corte ancho, además de los dos cambios de escena previstos (120 y 1200), marca los cambios de forma del notch (apertura 185–186, detalle → cuadrícula 619–620, cierre 961 y aviso → tarjeta 1040); en el vertical, solo los dos previstos. Fuera de esos tramos, la cámara medida no pasa de 14,8 px/f (13,9 en el vertical) ni de 1,8 %/f de zoom (2,5), y el p99 de la aceleración es de 2,3–3,5 px/f².

## Render

```sh
cd promo
python3 scripts/casa-music.py       # solo si cambia la música
npm run render:casa                 # español
npm run render:casa:en              # inglés
npm run render:casa:vertical        # 1080×1920, español
npm run render:casa:vertical:en     # 1080×1920, inglés
npx remotion still src/index.ts AltilloCasa videos/altillo-casa.png --frame=250
```

## Textos de la app

En español, «Abierto %@» (persiana a medias) pasa a ser «Apertura %@» (`home.state.openPercent` en `Apps/macOS/Resources/Localizable.xcstrings`), para que no choque con «Persiana». Afecta a la baldosa y al detalle. «Abierto» y «Cerrado» se quedan para los estados completos. «Abriendo hasta %@», «Cerrando hasta %@», «Encendido · %@» y «Apagado» no llevan género que choque en el vídeo. El sensor de la puerta dice «Cerrado» (es «Puerta»), pero se deja así porque es el estado completo.
