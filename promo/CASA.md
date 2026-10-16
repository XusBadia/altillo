# Casa / Home: Home Assistant en el notch (borrador)

Entrega: 28 s a 60 fps con la música B recortada.

- `videos/altillo-casa.mp4` (ES) y `videos/altillo-casa-en.mp4` (EN): 1920×1080.
- `videos/altillo-casa-vertical.mp4` y `videos/altillo-casa-vertical-en.mp4`: 1080×1920, para X y Reels.
- Pósters: `videos/altillo-casa.png` y `videos/altillo-casa-en.png` (fotograma 250, todas las luces encendidas).

Código: `src/casa/Casa.tsx` (composiciones `AltilloCasa`, `AltilloCasaEN`, `AltilloCasaVertical` y `AltilloCasaVerticalEN`), `src/casa/Porch.tsx` (la imagen de la cámara del timbre) y `src/casa/manifest.ts` (generado).

## Dirección

- **Enseña el producto:** todos los fotogramas del notch son la app real (`NotchRootView` con la casa de demostración), exportados por `scripts/HomeExportTests.swift`. Finder, Mail y el MacBook no salen; la pantalla es el fondo del anuncio con la barra de menús.
- **Suave:** no hay cortes de cámara. Los encuadres son fijos (pantalla, notch, notch empujado, aviso y Ajustes) y se unen con movimientos quínticos con el zoom en escala logarítmica. El cursor usa el mismo suavizado y ningún desplazamiento pasa de 40 px por fotograma. Solo cambian de escena el gancho (sobre negro) y la firma.
- **El notch se abre** (muelle de unos 150 ms) y cambia de estado dentro: la cuadrícula, el detalle de la persiana, la cuadrícula otra vez y el detalle del interruptor. Se cierra con el golpe del break para dejar paso al aviso del timbre. Un clic en el aviso lo vuelve a abrir con la tarjeta de la cámara.
- **Movimiento 1:1:** el arrastre de la lámpara y el de la persiana usan fotogramas reales cada 2 % (28 y 29) y se funden según la posición del cursor. El encendido escalonado es el de la app: cada baldosa se ilumina con su `easeOut` de 0,35 s, ahora una por semicorchea.
- **Rejilla:** 120 BPM; 1 compás = 2 s = 120 fotogramas.

| Tiempo | Plano |
|---|---|
| 0–2 s | Gancho sobre negro: «Tu casa, / ahora / en el notch.» («Your notch can now run your home.») |
| 2–3 s | Entra la pantalla con el *drop* y la cámara empuja hacia el notch mientras sube el cursor |
| 3–4,4 s | Al pasar el cursor, el notch se abre y las baldosas se encienden una a una con el color real de cada bombilla. «Tus luces. Con su color real.» |
| 4,4–5,6 s | Arrastre sobre «Lámpara de pie»: del 70 % al 16 %, 1:1. «Arrastra para atenuar.» |
| 6,0 s | Clic en la etiqueta «Peli»: la lámpara pasa a morado al 25 %, se apaga el resto y se baja la persiana. «Noche de peli. Un clic.» |
| 6,9–10,3 s | Mantener pulsada «Persiana» (anillo de 0,6 s), se abre su detalle y se sube el tirador de latón del 4 % al 60 % («Apertura 52 %»): la ventana se ilumina. Clic en «‹ Favoritos». «Sube la persiana.» |
| 11,2–13,6 s | Mantener pulsado «Pasillo», se abre el interruptor de baquelita y se acciona la palanca: el piloto se enciende. Vuelta a la cuadrícula. «Dale al interruptor.» |
| 13,8–16 s | Recorrido por Luces, Enchufes, Persianas y Escenas, una palabra por tiempo. «Todo lo que tengas en Home Assistant.» |
| 16 s | Break: el notch se cierra con el golpe y la música se para |
| 16,5–17,2 s | «Ding… dong»: el aviso del timbre, centrado y de cerca (la cámara sube hasta él con un movimiento quíntico). «Ding-dong.» |
| 17,25–18,7 s | Clic en el aviso: se abre Casa con la tarjeta de la cámara arriba (el estado real tras un timbrazo, que dura 2 min) y la cámara se acerca a la tarjeta: el porche se ve grande, «Han llamado · Timbre · ahora». «Ding-dong. Mira quién es.» («See who it is.») |
| 18,9–21 s | El notch se cierra y la cámara baja a Ajustes, con la tarjeta Casa real: servidor encontrado en la red (`homeassistant.local:8123`). «Encuentra tu Home Assistant. En tu red. Sin escribir direcciones.» |
| 21–24 s | Clic en «Iniciar sesión con Home Assistant» y la tarjeta pasa a Conectado. «Inicia sesión. Sin tokens.» |
| 24–28 s | Firma con el golpe final: icono, «Altillo», «Tu casa, en el notch.» («Home Assistant, in your notch.»), «Gratis · Código abierto · altillo.app» |

## Música

`public/casa/audio/casa.wav` sale de `python3 scripts/casa-music.py`. Es la B del anuncio (`score-b.wav`, Apple Loops) sin los compases 8 y 9, empalmada en un límite de compás. Así el break («toc, toc» en el anuncio) cae a los 16 s y el golpe final a los 24 s. En el silencio del break suena un timbre sintetizado (dos campanas, Mi5 y Do5, a 16,5 y 17,0 s). Mide −14 LUFS y −1,5 dBTP. Solo se ha verificado con medidas; nadie lo ha escuchado.

## De dónde sale la interfaz

`scripts/HomeExportTests.swift` hace capturas a 3× de `NotchRootView` en una ventana fuera de pantalla, igual que `ScenarioExportTests`. Lo que cambia de un estado a otro se aplica a la casa de demostración (`HomeDemoService.update`, `HomeStore.activate`). Hay varios modos (`ALTILLO_HOME_EXPORT`), y cada uno corre en su propio proceso porque `-demoHome` solo se lee una vez:

| Modo | Exporta |
|---|---|
| `grid` | `unrevealed`, `grid`, `dim-00…27` (70 → 16 %), `movie-final`, `after-blind`, `after-lamp` |
| `blind` | `blind-00…28` (60 → 4 %), detalle de la persiana |
| `lamp` | `lamp-off`, `lamp-on`: el interruptor del pasillo (sin brillo, porque es una luz que solo se enciende y se apaga) |
| `peek` | `peekDoorbell` (el aviso del timbre) e `idle` |
| `ring` | `ring-grid`: Casa justo después de un timbrazo (Peli, persiana al 60 % y pasillo encendido, como deja la casa el vídeo), con la tarjeta de la cámara arriba |
| `settings` | `settings` (servidor encontrado) y `settings-connected`: la tarjeta Casa con un descubrimiento falso |
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

- `node scripts/casa-camera-check.mjs [wide|vertical]` es la comprobación analítica de la cámara y del cursor, fotograma a fotograma. En la última versión, la cámara mueve como mucho 16 px por fotograma, con una aceleración máxima de 0,8 px/f² y un *jerk* de 0,11. El cursor no pasa de 40 px por fotograma.
- `python3 scripts/motion-check.py videos/altillo-casa.mp4 --expect-cuts 120,1440` analiza el vídeo renderizado fotograma a fotograma. Sigue puntos con Lucas–Kanade, ajusta una similitud con RANSAC y mide la diferencia media entre fotogramas. Solo detecta los dos cambios de escena previstos (120 y 1440), los cambios de forma del notch (apertura 184–186, cuadrícula ↔ detalle 452 y 620, cierre 961, aviso 995, aviso → tarjeta 1039–1042 y cierre 1123) y, en el corte ancho, el barrido hacia la tarjeta (1057–1067). Ese barrido es una inclinación continua de unos 13 px por fotograma, sin saltos: la diferencia media pasa del umbral solo porque se mueve mucho detalle. Fuera de esos tramos, el p99 de la aceleración medida es de 2–3,5 px/f².

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
