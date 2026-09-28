# Bandas sonoras alternativas del anuncio (A, B, C)

Generadas con `promo/scripts/anuncio-music-variants.py` (`python3 scripts/anuncio-music-variants.py [a] [b] [c]`).
Todo sale de Apple Loops (la licencia permite usarlos en composiciones propias), salvo el bajo de C, que se sintetiza con numpy.
`score.wav` (la versión anterior) no se ha tocado.

Formato común: WAV 48 kHz, estéreo, 24 bits, **1 536 000 muestras = 32,000 s exactos**, 120 BPM, 4/4, 16 compases (compás *n* empieza en (*n*−1)·2 s).

| Compás | Tiempo | Qué pasa (las tres variantes) |
|---|---|---|
| 1 | 0–2 s | Intro: el gancho suena filtrado y se va abriendo, sin batería completa. En la 2.ª mitad hay una aspiración inversa o un *riser* |
| 2 | 2,000 s | **DROP** en el primer tiempo: entra todo, con un sub-golpe grave |
| 2–5 | 2–10 s | Sección 1 con el gancho. Redoble en los tiempos 3–4 del compás 3 (5–6 s) |
| 6–9 | 10–18 s | Sección 2: cambian capas. Redoble en los tiempos 3–4 del compás 7 (13–14 s) |
| 10 | 18–20 s | Variación antes del break |
| 11 | 20–22 s | **BREAK**: golpe en el tiempo 1 y silencio desde el tiempo 2 («toc, toc»). Solo queda una cola de reverb. En el tiempo 4 entran un redoble y una aspiración |
| 12–14 | 22–28 s | Vuelve todo. Es la sección más grande (+1,5 dB y capas extra). En el 14 hay subida (ruido que se abre y redoble) |
| 15 | 28,000 s | **GOLPE FINAL**: todos los instrumentos en el 1, más sub-golpe, reverb larga (RT60 3,4 s) y acorde que se apaga |
| 16 | 30–32 s | La cola se apaga sola (termina en cero con coseno) y el último segundo tiene un fundido. No hay corte |

«Sidechain» simulado: en 2–10 y 12–14, el bus de bajo y armonía cae en cada negra y se recupera en unos 110 ms (A 25 %, B 30 %, C 45 %).
Master: filtro de graves a 30 Hz, EQ por variante, compresor suave y limitador, con el techo ajustado en bucle. Después, loudnorm lineal en dos pasadas (no hace bombeo).

---

## A: disco-funk pop (brillante, con metales)

**Tonalidad:** Si mixolidio. Todo el material armónico es del kit «Disco Delight» (mismo prefijo y misma tonalidad, B). Sus acordes medidos (cromagrama) son Si–La–Mi (I–♭VII–IV) y todos caben en Si mixolidio. El golpe de metales se transporta +2 semitonos: La7 pasa a **Si7**, el dominante propio del modo, así que no choca. Los cierres son sobre Si7, el acorde final típico del funk.

| Loop | Pack | Tonalidad (metadatos) | BPM | Tiempos | Tratamiento |
|---|---|---|---|---|---|
| Glitter Nights Beat | 09 Disco Funk | — | 120 | 16 | batería disco 4×4 |
| Glitter Nights Hi-Hat Topper | 09 Disco Funk | — | 120 | 16 | charles (intro y capa) |
| Throwback Funk Beat 04 | 09 Disco Funk | — | 120 | 8 | capa funk en el compás 10 |
| Disco Delight Bass | 09 Disco Funk | B | 120 | 8 | bajo 2–10 |
| Disco Delight Slap Bass | 09 Disco Funk | B | 120 | 8 | bajo *slap* 12–14 |
| Disco Delight Rhythm Guitar | 09 Disco Funk | B mayor | 120 | 16 | guitarra rítmica |
| **Disco Delight Lead Guitar** | 09 Disco Funk | B | 120 | 8 | **gancho** |
| Disco Delight Clav | 09 Disco Funk | B | 120 | 8 | clavinet 6–9 |
| Disco Delight Piano | 09 Disco Funk | B mayor | 120 | 16 | piano 6–9 y 12–14, cola final |
| Throwback Funk Brass 01 | 09 Disco Funk | A (acorde La7) | 120 | 8 | solo el golpe del tiempo 1, **+2 st → Si7** |
| 80s Synth FX Riser 01 | 09 Disco Funk | — | 120 | 8 | subidas (intro, 13–14) |
| Snare Drum Fill 01 / 03 | 10 Vintage Breaks | — | 105 / 110 → 120 | 4 | redobles (atempo) |

**Arreglo:** 1 gancho filtrado, charles y *riser*. En 2–5 entran batería, bajo, guitarra rítmica, gancho y metales en el 1. En 6–9 cambian a clavinet y piano (sale la guitarra rítmica) y entra más charles. En 10 vuelve la guitarra rítmica y entra la capa de batería funk. 11 es el break (golpe Si7, luego nada). En 12–14 suenan *slap* bass, guitarra, piano, gancho y metales en el 12 y en el 13, más la subida. En 15 llega el golpe Si7 con cola de piano y reverb.

**Medidas:** −13,9 LUFS integrados · pico real −1,7 dBTP · pico de muestra −2,41 dBFS · LRA 3,7 LU · 0 muestras recortadas · loudnorm en modo lineal.

## B: indie-pop de banda

**Tonalidad:** todo el material armónico es del kit «Disco Pop» (metadatos C#). La progresión medida es Re♭–Fa m–Mi♭–Mi♭. En La♭ mayor eso es IV–vi–V–V, una progresión pop ascendente, y la energía fuera de La♭ mayor es solo del 2–16 % por compás. La batería (Drummer «Duncan», Indie, 120 BPM) y la pandereta no tienen tonalidad. El final cae sobre Re♭ mayor (IV), un cierre abierto y luminoso.

| Loop | Pack | Tonalidad | BPM | Tiempos | Tratamiento |
|---|---|---|---|---|---|
| Duncan - Hit Factory | 13 Drummer | — | 120 | 32 | batería principal (4×4, corcheas). Su compás 8 da los redobles |
| Duncan - Chorus | 13 Drummer | — | 120 | 32 | batería más llena, 12–14 |
| Duncan - Intro | 13 Drummer | — | 120 | 32 | compás 1: caja y charles sin bombo |
| Tambourine 03 | Apple Loops for GarageBand | — | 120 | 8 | pandereta 6–9 y 12–14 |
| Disco Pop Bass | 08 Indie Disco | C# | 120 | 16 | bajo |
| Disco Pop Rhythm Guitar | 08 Indie Disco | C# mayor | 120 | 16 | guitarra rítmica |
| **Disco Pop Lead Guitar** | 08 Indie Disco | C# mayor | 120 | 16 | **gancho** |
| Disco Pop Synth Pad | 08 Indie Disco | C# mayor | 120 | 16 | pad 6–9 y 12–14, cola final |
| Disco Pop Synth Stabs | 08 Indie Disco | C# mayor | 120 | 16 | stabs 6–9 y golpe del break |

**Arreglo:** 1 gancho filtrado, caja y charles de intro, *riser*. En 2–5 entran batería, bajo, guitarra rítmica y gancho. En 6–9 suenan pad, stabs y pandereta, y sale la guitarra rítmica. En 10 vuelve la guitarra. 11 es el break (acorde Fa m y silencio). En 12–14 entran la batería «Chorus», pandereta, bajo, guitarra, pad y gancho, más la subida. En 15 llega el golpe en Re♭ con el pad apagándose.

**Medidas:** −14,0 LUFS · −2,0 dBTP · pico de muestra −2,31 dBFS · LRA 3,4 LU · 0 muestras recortadas · lineal. EQ de master: agudos +3 dB a 7 kHz, porque sin ella el reparto espectral salía apagado.

## C: electro-pop con pegada

**Tonalidad:** Do menor / Mi♭ mayor. Los tres loops armónicos son de Electro House y todos llevan la etiqueta C minor a 128 BPM. «Bedlam Synth Layers» marca la progresión La♭ | La♭–Si♭ | Do m | Do m–Si♭ (VI–VII–i, el «himno» de Mi♭ mayor). «Night Vision» (gancho) y «Airy Vox» se mueven en Do menor natural, la misma escala. Los bajos de Electro House están todos etiquetados como *Distorted/Dark/Intense* y no encajaban con «nada agresivo». Por eso el bajo es **sintetizado**: sierra filtrada a 900 Hz más un seno, en corcheas a contratiempo, siguiendo las fundamentales de Bedlam. La batería es Drummer «Julian» (Electro House, **120 BPM nativo**, sin estirar). El final cae sobre La♭ mayor.

| Loop | Pack | Tonalidad | BPM | Tiempos | Tratamiento |
|---|---|---|---|---|---|
| Julian - Star Burst | 13 Drummer | — | 120 | 32 | batería 4×4 limpia, 2–10 |
| Julian - Chorus | 13 Drummer | — | 120 | 32 | batería 12–14. Su compás 8 (redoble creciente) da los redobles |
| Bedlam Synth Layers | 02 Electro House | C menor | 128 → 120 | 16 | acordes (atempo 0,9375) |
| **Night Vision Synth Layers** | 02 Electro House | C menor | 128 → 120 | 16 | **gancho** |
| Airy Vox Synth | 02 Electro House | C menor | 128 → 120 | 16 | voz sintética 6–9 y 12–14 |
| House Clap Topper | 02 Electro House | — | 128 → 120 | 8 | palmas |
| Almost Reverse Topper | 02 Electro House | — | 128 → 120 | 8 | inversos (intro, break) |
| bajo sintetizado | numpy | La♭/Si♭/Do | 120 | 16 | bajo de contratiempo |

**Arreglo:** 1 acordes y gancho filtrados, inverso y *riser*. En 2–5 entran batería 4×4, bajo, acordes y gancho. En 6–9 se suman voz synth y palmas. 10 repite la formación de 2–5. 11 es el break (acorde y silencio). En 12–14 suenan la batería «Chorus», palmas, bajo, acordes, gancho y voz, más la subida. En 15 llega el golpe en La♭ con los acordes apagándose.

**Medidas:** −14,0 LUFS · −2,0 dBTP · pico de muestra −2,51 dBFS · LRA 3,6 LU · 0 muestras recortadas · lineal. EQ de master: graves −4 dB por debajo de 60 Hz y agudos +2 dB a 7 kHz, porque el bombo y el sub dominaban.

---

## Energía por compás (RMS mono, dBFS)

| Compás | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | −25,6 | −17,4 | −15,5 | −17,7 | −15,6 | −17,6 | −15,3 | −17,8 | −15,4 | −17,6 | **−21,2** | −15,9 | −15,6 | −15,1 | −19,2 | −57,8 |
| B | −21,5 | −16,8 | −16,5 | −16,8 | −16,9 | −16,8 | −16,3 | −16,6 | −16,6 | −16,9 | **−22,5** | −16,0 | −16,0 | −15,7 | −20,4 | −59,5 |
| C | −21,3 | −16,6 | −15,5 | −17,5 | −17,3 | −16,6 | −15,1 | −16,9 | −16,6 | −16,8 | **−20,6** | −15,3 | −15,5 | −14,1 | −20,9 | −51,1 |

Break, compás 11, por tiempos (1 / 2 / 3 / 4). El «toc, toc» cae en los tiempos 2–3:

| | Tiempo 1 | Tiempo 2 | Tiempo 3 | Tiempo 4 |
|---|---|---|---|---|
| A | −17 | −44 | −56 | −20 |
| B | −19 | −29 | −41 | −21 |
| C | −20 | −32 | −45 | −16 |

Golpe final, compás 15, tiempo 1: A −14,3, B −15,7, C −15,3. Desde ahí la cola cae unos 7–12 dB por tiempo, sin escalones.

**Comprobaciones:**

- Duración exacta en las tres.
- Ningún tramo de 100 ms por debajo de −50 dBFS fuera del break y de la cola.
- Ataques del drop, de la vuelta del 12 y del golpe final medidos en 2,000, 22,000 y 28,005 s (resolución de 5 ms).
- Energía fuera de escala por compás: A 18–30 %, B 2–16 %, C 13–31 %. Es parecida a la de cada loop aislado (fuga espectral de sintes desafinados y batería), así que no indica choques.

Formas de onda: `/tmp/score-a.png`, `/tmp/score-b.png`, `/tmp/score-c.png`. Las líneas rojas marcan los compases 2, 11, 12 y 15.

## Limitaciones honestas

- **No lo he escuchado.** Los loops se eligieron por metadatos, cromagramas, contornos melódicos y patrones de bombo, caja y charles medidos. Que el gancho *enganche* es un juicio que falta hacer de oído.
- **A:** el kit Disco Delight tiene «stops» de funk: bajo, guitarras y gancho callan juntos al final de cada 2 compases, y en la forma de onda se ven muescas. Es fraseo del loop y no un fallo, pero hace la mezcla más entrecortada que B y C. Los metales transpuestos +2 st con asetrate/atempo pueden sonar algo procesados; solo se usan como golpe corto.
- **B:** la batería Drummer y el kit Disco Pop vienen de packs distintos, y el empaste de sala no está garantizado. El gancho (Lead Guitar) es más rítmico que melódico en sus dos primeros compases. El final en IV (Re♭) queda abierto, no conclusivo.
- **C:** el estiramiento 128 → 120 se hace con `atempo`, porque este ffmpeg no trae `rubberband`. Los ataques de los sintes pueden quedar algo emborronados y con unos ±8 ms de desviación temporal; la batería no se estira. El bajo sintetizado es sencillo (no es un sinte de estudio).
- La reverb, los *risers* de ruido y el sub-golpe son síntesis propia simple.
- **Fallo encontrado en el compositor anterior (no corregido aquí, por el alcance):** los Apple Loops son AAC en CAF con 2112 muestras de *priming*, y ffmpeg no las recorta (`initial_padding=0`). `anuncio-music.py` (y por tanto `score.wav`) mete cada loop unos 48 ms tarde y deja un hueco de unos 48 ms en cada repetición. Este script lo corrige leyendo el chunk `pakt` del CAF.
