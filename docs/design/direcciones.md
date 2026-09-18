# Altillo: tres direcciones visuales

> Punto de partida: la fase 0 ([capturas](phase0/)) está bien resuelta pero es "negro cálido + SF Pro + ámbar", que es exactamente lo que hacen Seam, NotchNook y Alcove. Funciona, pero no se reconoce. Este documento propone **tres direcciones con personalidad propia**, cada una especificada para prototiparla en SwiftUI en un día, una tabla comparativa y una recomendación.
>
> Restricciones que no se tocan (PLAN §3): la **silueta sigue siendo negro puro opaco** para empastar con el notch físico; la personalidad va **dentro** y en los detalles. Acento personalizable (§4). Reducir movimiento / transparencia y VoiceOver en todo.

---

## 0. Qué da personalidad a las apps que nos gustan

| Referencia | Qué la hace reconocible | Qué nos llevamos |
|---|---|---|
| [Seam](https://getseam.app/) | Negro cálido, ámbar `oklch(73% .23 74)`, grano sutil, cristal solo en controles. Discreto y basado en eventos ([comparativa con NotchNook](https://getseam.app/blog/seam-vs-notchnook)). | La base actual. Es elegante pero *neutra*: no tiene una firma propia. |
| [NotchNook](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) | El movimiento: al pasar el ratón el notch "late" hacia fuera con sombra, al abrirse se pasa un poco y vuelve; el tray se desliza. | La silueta como algo físico que reacciona. |
| [Alcove](https://medium.com/@teslathewest/the-story-behind-alcove-macos-dynamic-island-app-dadb5d97e8b0) | Pasividad: aparece y se desvanece, nunca estorba. | Invisible hasta que hace falta. |
| [Nothing OS / Glyph Matrix](https://www.engadget.com/mobile/smartphones/nothing-phone-3-hands-on-dot-matrix-glyph-flagship-phone-173019742.html) | Tipografía de puntos (Ndot), monocromo estricto y un único rojo de "grabando" ([sistema](https://www.shadcn.io/design/nothing)). | El negro como pantalla LED apagada; un solo color que significa "te necesito". |
| [Teenage Engineering OP-1 field](https://teenage.engineering/products/op-1) | Tipografía monoespaciada, negro/blanco + tres grises + naranja industrial `#FF6600`; visualizaciones vivas de datos reales (cintas que giran, niveles que rebotan) ([análisis](https://blakecrosley.com/guides/design/teenage-engineering)). | Los datos *son* la decoración. |
| [Braun ET66](https://collections.vam.ac.uk/item/O1360553/et66-calculator-et66-calculator-dieter-rams/) (Rams/Lubs) | Grises y una sola tecla amarilla (la de "=", la más usada): el color señala la acción principal. | Un acento = una función. |
| [Playdate](https://help.play.date/developer/designing-for-playdate/) (Panic + TE) | 1 bit con tramado, Roobert a tamaños generosos, la manivela como gesto "juguetón". | Tramado (dither) como textura; legibilidad por encima de estilo. |
| [Things 3](https://culturedcode.com/things/features/) | Animaciones con propósito hechas a mano (la tarea que se abre como un papel en blanco, el Magic Plus que *arrastras* a su sitio). | Metáforas físicas precisas y contenidas. |
| [Tot](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/) (Iconfactory) | Siete puntos de colores = siete notas; el punto relleno/contorno comunica estado. Paleta muy cuidada en claro y oscuro ([Macworld](https://www.macworld.com/article/233920/tot-pocket-review.html)). | Un sistema de color pequeño y memorable. |
| [Halide Mark III](https://www.lux.camera/halide-mark-iii/) | Tipografía propia inspirada en el grabado de cámaras y objetivos, gestos como diales, fotómetro analógico. | Instrumento > app. |
| [Raycast](https://www.raycast.com/blog/a-fresh-look-and-feel) | Rojo `#FF6363` usado casi solo en la marca; icono = tecla (su valor: el teclado). | La marca cuenta *qué haces* con la app. |
| [Family](https://60fps.design/apps/family) (Benji Taylor) | Bandejas que se transforman unas en otras, botones que se convierten en paneles, "Continue" que muta letra a letra en "Confirm". | Continuidad: nada aparece de golpe. |
| [Dia](https://browsercompany.substack.com/p/the-strategy-behind-dias-design) / Arc | "Presupuesto de novedad": UI base sobria y la marca solo en momentos concretos (el panel que "se hincha" al abrir el chat). | Gastar la personalidad donde importa. |
| [Linear](https://linear.app/now/behind-the-latest-design-refresh) | "La estructura se siente, no se ve"; temas generados en LCH desde 3 variables (base, acento, contraste). | Tokens derivados, alto contraste automático. |
| [Rauno Freiberg](https://rauno.me/craft/interaction-design) / [Emil Kowalski](https://emilkowal.ski/ui/7-practical-animation-tips) | Consistencia espacial (la Dynamic Island), momentum, lo muy frecuente no se anima; ease-out, escalas 0,95–0,98, pulsar a 0,97. | Reglas de oficio comunes a las tres direcciones. |
| Apple [Liquid Glass](https://developer.apple.com/documentation/swiftui/glasseffectcontainer/) (26) y [macOS/iOS 27](https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/) | 27: deslizador global de opacidad del cristal, borde oscurecido y brillos especulares más intensos, más difusión del fondo. `glassEffectID` para fundir formas. En iOS 27 las Live Activities se ven en la isla también en horizontal ([WWDC26](https://developer.apple.com/videos/play/wwdc2026/223/)). | El cristal lo controla ahora el usuario: no podemos fiar la personalidad al cristal. |

**Conclusión de la investigación:** las apps con personalidad eligen *una* idea material (LED, papel, luz, tecla…) y la aplican con disciplina a tipografía, color, movimiento, sonido y voz. Ninguna se reconoce por el cristal. Por eso las tres direcciones se apoyan en una idea material distinta.

---

## Dirección A: «Matriz»

**Concepto:** el notch es una pantalla de hardware apagada; Altillo la enciende punto a punto.

**Referencias:** [Nothing Glyph Matrix](https://www.engadget.com/mobile/smartphones/nothing-phone-3-hands-on-dot-matrix-glyph-flagship-phone-173019742.html) · [Nothing design system](https://www.shadcn.io/design/nothing) · [OP-1 field](https://teenage.engineering/products/op-1) · [TE, restricciones como estética](https://blakecrosley.com/guides/design/teenage-engineering) · [Braun ET66](https://www.port-magazine.com/design/counter-culture/) · paneles de salidas de estación · [Playdate](https://help.play.date/developer/designing-for-playdate/).

### Paleta (oscuro; en iOS hay variante clara)

| Token | Hex | Uso |
|---|---|---|
| `notch` | `#000000` | Silueta. También el fondo del notch abierto: **no hay tarjetas rellenas**, la estructura la dan rejillas de puntos y filetes. |
| `panel` | `#0D0D0C` | Pozos (comando de un agente, zona de drop). |
| `panelRaised` | `#161614` | Botón secundario, fila seleccionada. |
| `dotOff` | `#262522` | LED apagado (rejillas, segmentos vacíos de anillos y barras). |
| `phosphor` | `#F4F1EA` | Texto y LEDs encendidos (blanco fósforo, algo cálido: hereda a Seam). |
| `phosphor2` | `#F4F1EA` al 58 % | Texto secundario (≈ 6:1 sobre negro). |
| `phosphor3` | `#F4F1EA` al 34 % | Solo decoración y deshabilitado (no pasa AA para texto). |
| `signal` (acento por defecto) | `#FF4D1F` | "Te necesito": agente esperando, zona de drop armada, marca. 6,3:1 sobre negro; texto negro encima también 6,3:1. |
| `amber` | `#FFB000` | Aviso (≥ 80 %, por encima del ritmo). |
| `critical` | `#FF3B2F` | ≥ 95 %, errores. Fijo aunque el usuario cambie el acento. |
| `airdrop` | `#3FA9FF` | Solo mientras el cursor está sobre la zona AirDrop. |
| Claro iOS: `thermal` / `ink` | `#EDEBE6` / `#1A1A1A` | Widgets y Live Activity en pantalla de bloqueo con fondo claro ("papel térmico"). |

**Reglas del acento:** monocromo por defecto; **un solo color vivo en pantalla a la vez**. El acento solo aparece en (1) lo que requiere acción, (2) la zona de drop bajo el cursor, (3) el punto de la marca. "Terminado" no es verde: es un LED blanco fijo. Si el usuario elige otro acento (presets actuales), sustituye a `signal`; `critical` y `amber` no cambian.

### Tipografía

| Fuente | Licencia | Dónde | Para qué |
|---|---|---|---|
| **Doto** (Óliver Lalan) | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Doto) · [GitHub](https://github.com/oliverlalan/Doto) | Números grandes y de las orejas. Matriz 6×10, monoespaciada, variable (peso, tamaño y redondez del punto; leer los tags con `CTFontCopyVariationAxes`). Cubre GF Latin Core (á, ñ, ¿…). |
| **Departure Mono** (Helena Zhang) | OFL | [departuremono.com](https://www.departuremono.com/) · [GitHub](https://github.com/rektdeckard/departure-mono) | Etiquetas en mayúsculas, estados, contadores. Pensada para múltiplos de 11 px: usar 11 pt (22 px en Retina). |
| SF Pro / SF Mono | Sistema | — | Todo lo que se *lee*: nombres de archivo, frases del peek, comandos. |

| Elemento | Especificación |
|---|---|
| Etiquetas de pestaña | Departure Mono 11 pt, MAYÚSCULAS, tracking +0,06 em. Activa: `phosphor` con un LED `signal` de 4 pt a la izquierda; inactiva: `phosphor3`. |
| Nombre de ítem | SF Pro Text 11 pt medium, 2 líneas máx., truncado central. Metadatos: Departure Mono 11 pt `phosphor2` ("PDF · 13 KB"). |
| Números (uso %) | Doto 26 pt peso 800 en el centro del dial; Doto 13 pt peso 700 en las orejas. `%` en Departure Mono 11. |
| Cuentas atrás | Departure Mono 11–13 pt: "1 H 11 MIN", "EN 12 MIN". |
| Peek | Etiqueta Departure Mono 11 ("CLAUDE") + frase SF Pro 12,5 medium + cifra clave en Doto 14. |
| Código | SF Mono 11. |

### Materiales, formas, iconos, marca

- **Textura: rejilla de puntos.** Paso 6 pt, punto 1,5 pt, `dotOff`. Se dibuja una vez como tile (`Image(...).resizable(resizingMode: .tile)`), igual que el `GrainOverlay` actual. Sin grano, sin cristal dentro del notch.
- **Brillo LED:** los elementos encendidos llevan una copia desenfocada (`blur 3`, opacidad 0,5, `.blendMode(.plusLighter)`). Es la única "luz" del sistema.
- **Formas:** radios pequeños (miniaturas 6 pt, pozos 8 pt, botones cápsula). Selección con **esquinas de visor** (cuatro "⌜ ⌝ ⌞ ⌟" de 6 pt en `signal`), no con relleno.
- **Anillos y barras segmentados:** el anillo de uso es un **dial de 48 LEDs**; la barra semanal, **40 celdas** de 5×8 pt con 2 pt de hueco. El marcador de ritmo es una celda hueca.
- **Iconos:** glifos propios de 7×7 puntos para pestañas y orejas (caja, dial, agente, nota, calendario), definidos como cadenas de bits y dibujados con `Canvas`. SF Symbols en el resto: peso `.medium`, `.monochrome`.
- **Marca:** un tejado de puntos con un LED rojo dentro, "lo que dejaste arriba":
  ```
  · · · ● · · ·
  · · ● · ● · ·
  · ● · ◉ · ● ·      ◉ = signal
  ● · · · · · ●
  ```
  Logotipo "altillo" en Doto minúscula. Icono de app: squircle negro con el tejado en fósforo y el punto rojo.

### Movimiento

Carácter mecánico y preciso: springs sin rebote, y la vida la ponen los LEDs, no los desplazamientos.

| Token | Valor SwiftUI |
|---|---|
| Abrir | `.spring(duration: 0.36, bounce: 0.08)` |
| Cerrar | `.spring(duration: 0.28, bounce: 0)` |
| Cambio de contenido | máscara "scanline" de arriba abajo en 120 ms `easeOut` (la pestaña nueva se "escribe") |
| Encendido escalonado | 6 ms por punto, cada punto sube de `dotOff` a su color en 90 ms `easeOut` |
| Pulsar | escala 0,97, 100 ms |

**Microinteracción firma por módulo:**
- **Shelf, al aterrizar:** el ítem cae 8 pt con `.spring(duration: 0.3, bounce: 0.2)` (el único rebote de la dirección, porque hay momentum real), sus esquinas de visor destellan una vez (0 → 1 → 0 en 260 ms) y el contador de la oreja **salta como un marcador**: el dígito viejo se apaga punto a punto y el nuevo se enciende (`contentTransition(.numericText())` no basta; se hace con dos capas y máscara de barrido).
- **Zona de drop bajo el cursor:** la rejilla se enciende en un radio de 80 pt alrededor del cursor con caída suave ("linterna sobre la matriz") y el borde pasa a **puntos que marchan** (un paso cada 80 ms). Solo la zona bajo el cursor.
- **Anillo de uso:** los LEDs del dial se encienden en orden hasta el valor; el último brilla más. Al cruzar 80 % los LEDs posteriores se encienden en `amber`; ≥ 95 % en `critical` y solo el último LED parpadea (1 Hz).
- **Agente esperando:** un único LED `signal` que "respira" (opacidad 0,35 ↔ 1, ciclo 1,6 s, `easeInOut`), como el piloto de grabación. En la oreja: LED + "1" en Doto.
- **Agente trabajando:** tres puntos que rotan (spinner de 3 LEDs, 120 ms por paso). Terminado: LED blanco fijo + "HECHO".
- **Now Playing:** la carátula se muestra **tramada en 1 bit** (`CIDither` + `CIColorMonochrome`, una vez por canción; opción "color real") y un ecualizador de 5×7 LEDs.
- **Calendario:** cuenta atrás en Doto; a menos de 5 min, los dos puntos del reloj parpadean.

**Sonido (desactivado por defecto, −24 dB, `NSSound` precargado):** "tic" de relé de 12 ms al guardar; bip de dos tonos (880 → 660 Hz, 60 ms cada uno) cuando un agente espera; "clac" corto al permitir. **Háptica** en trackpad (`NSHapticFeedbackManager`, `.alignment`) al entrar en una zona de drop y `.levelChange` al soltar.

### Voz

Telegráfica, precisa, de panel de instrumentos. Etiquetas en MAYÚSCULAS; frases cortas en minúscula normal.

- Vacío: **ALTILLO VACÍO** · "Arrastra algo hasta aquí. Lo guardo hasta que lo bajes."
- dragArmed: **SUELTA AQUÍ ↓**
- Drop: **GUARDAR · 6 → 7** / **AIRDROP**
- Peek uso: **CLAUDE** 85 % · reinicia en 1 h 11 min
- Peek agente: **ESPERA** · Claude quiere ejecutar `git push` en altillo
- Alerta: **95 %** · al ritmo actual te quedas sin sesión a las 17:40
- Botones: **DENEGAR** · **PERMITIR ⌘↩**
- Estados: ESPERA · EN MARCHA · HECHO · SIN DATOS · DESACTUALIZADO

### Estados del notch

| Estado | Cómo se ve |
|---|---|
| Reposo / orejas | Izquierda: glifo dial 7×7 + "85" en Doto 13. Derecha: glifo caja + "6". Sin actividad, orejas recogidas: solo el notch. Agente esperando: la oreja izquierda pasa a LED rojo que respira + "1". |
| Peek | Píldora negra; el texto entra con la máscara scanline de izquierda a derecha (180 ms), como un letrero. A la derecha, "HACE 8 S" en Departure Mono `phosphor3`. |
| dragArmed | En el borde inferior del notch, un chevron de 3 puntos que cae en cascada (90 ms por paso) + "SUELTA AQUÍ" en `signal`. |
| dropTarget | Dos campos de rejilla: shelf (≈ 75 %) y AirDrop (≈ 25 %). Sin cursor encima: rejilla apagada y etiqueta en `phosphor3`. **Solo el campo bajo el cursor** se enciende (linterna + borde de puntos que marchan, `signal` en shelf, `airdrop` en AirDrop); el shelf muestra "6 → 7" en Doto 28; AirDrop muestra anillos concéntricos de puntos que se expanden. |
| Shelf abierto | Sin tarjetas: miniaturas de 56 pt sobre negro con filete de 1 px. Cabecera: pestañas en Departure Mono; a la derecha "6 COSAS · VACIAR". Selección con esquinas de visor. Pie con atajos en Departure Mono `phosphor3`. |
| Uso | Por proveedor, bloque sin relleno separado por un filete de puntos: dial de 48 LEDs con Doto 26 dentro; "SESIÓN · 5 H" y "1 H 11 MIN"; barra semanal de 40 celdas; línea de ritmo "↗ +9 PTS SOBRE EL RITMO" en `amber`. |
| Agentes | Un **tablero de salidas**: columnas PROYECTO · AGENTE · ESTADO · HACE, en Departure Mono. La fila que espera se expande: comando en SF Mono sobre `panel`, "DENEGAR" (cápsula `panelRaised`) y "PERMITIR" (cápsula `signal`, texto negro). |
| iOS | **Dynamic Island** compacta: LED + "85" en Doto (izquierda), glifo 7×7 (derecha); mínima: el LED. Expandida: dial de LEDs. `keylineTint(signal)` solo si hay un agente esperando. **Pantalla de bloqueo:** variante "papel térmico" clara. **Widgets:** diales LED; en **StandBy nocturno** (que ya tiñe de rojo) queda de forma natural. |

### Riesgos

- **Legibilidad:** Doto por debajo de 12 pt se deshace. Doto solo para cifras ≥ 13 pt; nunca para frases. **En pantallas 1× (el monitor externo del Mac mini)** la rejilla puede dar moiré y Doto se emborrona: con `displayScale < 2`, pasar a SF Pro Compressed para cifras y a un paso de rejilla entero en píxeles.
- **"Clon de Nothing":** la diferencia está en el calor del fósforo, el tejado como marca, el acento elegible y la voz en español. Hay que cuidarlo.
- **Accesibilidad:** Reducir movimiento → encendido instantáneo, sin marcha ni scanline (fundido de 150 ms). Parpadeos ≤ 1 Hz y nunca en áreas grandes. Aumentar contraste → anillos y barras continuos en vez de segmentados. VoiceOver lee valores ("Claude, 85 por ciento de la sesión"), no puntos. Esperando = color + LED + palabra ESPERA (no depende del color).
- **Rendimiento:** bajo. Todo son tiles y `Canvas`; nada de una vista por punto. Las animaciones de LEDs se detienen fuera de pantalla.

### Prototipo en un día

`Tokens.Palette` nueva · registrar las dos fuentes (`ATSApplicationFontsPath` en macOS, `UIAppFonts` en iOS **y en la extensión de widgets**) · `DotGrid` (tile) · `DotRing(value:segments:)` y `SegmentBar` con `Canvas` · `DotGlyph(bits:)` · `ViewfinderCorners` · rehacer las orejas, dropTarget y la pestaña Uso con esas piezas.

---

## Dirección B: «Desván»

**Concepto:** el altillo de casa: una bombilla cálida, cajas de cartón, etiquetas de papel. Software acogedor, hecho a mano.

**Referencias:** [Things 3](https://culturedcode.com/things/features/) · [Tot](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/) y el catálogo de [Iconfactory](https://iconfactory.com/) · [Panic / Playdate](https://clipcontent.substack.com/p/the-playful-design-details-of-the) · [Halide Mark III](https://www.lux.camera/the-road-to-halide-mark-3/) (tipografía de grabado) · [Fraunces](https://design.google/library/a-new-take-on-old-style-typeface) · etiquetas kraft de mudanza · cinta de carrocero.

### Paleta

| Token | Oscuro | Claro (iOS/widgets) | Uso |
|---|---|---|---|
| `notch` | `#000000` | — | Silueta. |
| `wood` | `#1E1914` | `#F7F1E6` (papel) | Tarjetas. |
| `woodRaised` | `#2A231C` | `#EDE4D3` | Elevado, pozos. |
| `plank` | `#3A3027` | `#DCCFB8` | La balda del shelf, pistas. |
| `paper` (texto) | `#F6EFE3` | `#2B241D` (tinta) | Texto principal. Secundario al 62 %, terciario al 38 %. |
| `bulb` (acento por defecto) | `#FFB547` | `#C77A0A` | La bombilla: foco, drop, "te necesito". |
| `kraft` | `#C9A77C` | `#B8925F` | Etiquetas. |
| Colores de etiqueta (7, a lo Tot) | tomate `#F2674A` · mostaza `#E8B33A` · salvia `#9DB88A` · cielo `#86B6D9` · lavanda `#B7A3E0` · rosa `#EE9FB5` · arena `#D8C3A0` | versiones −12 % luminosidad | Identidad (tipo de archivo, proveedor, proyecto). |
| Estado | aviso = mostaza · crítico = tomate · hecho = salvia | igual | |

**Reglas del acento:** `bulb` es luz, no pintura: se usa como **resplandor** (degradados radiales, bordes que brillan) y en el botón principal. Los 7 colores de etiqueta son **solo identidad, nunca estado**. Rojo/verde nunca van solos: siempre con icono o palabra.

### Tipografía

| Fuente | Licencia | Dónde | Para qué |
|---|---|---|---|
| **Fraunces** (Undercase Type) | OFL | [Google Fonts](https://fonts.google.com/specimen/Fraunces) · [GitHub](https://github.com/undercasetype/Fraunces) | Logotipo, títulos de estados vacíos y el sello "Hecho". Ejes `opsz`, `wght`, `SOFT`, `WONK`: usar `SOFT 100`, `WONK 1` (blanda y un poco torcida). |
| **New York** | Sistema (`.serif`) | — | Cifras: porcentajes y cuentas grandes, con `monospacedDigit()`. Serif con dígitos tabulares y tamaños ópticos gratis. |
| **SF Pro Rounded** | Sistema (`.rounded`) | — | Pestañas, botones, chips. |
| SF Pro / SF Mono | Sistema | — | Nombres de archivo, frases, comandos. |

| Elemento | Especificación |
|---|---|
| Pestañas | SF Pro Rounded 12 pt semibold, sin mayúsculas. Activa sobre cápsula `woodRaised` con reflejo superior. |
| Nombre de ítem | SF Pro Text 11 pt medium, **escrito sobre una etiqueta kraft** (ver materiales). Metadatos SF Pro Rounded 10 pt `paper` 62 %. |
| Números (uso %) | New York 26 pt semibold en el anillo; 13 pt medium en las orejas. |
| Cuentas atrás | SF Pro Rounded 11 pt medium, `monospacedDigit()`. |
| Peek | SF Pro 12,5 regular; el dato clave en New York *itálica* 13 pt ("va por el *85 %*"). |
| Vacíos | Fraunces 16 pt `SOFT 100` + SF Pro 12 secundaria. |

### Materiales, formas, iconos, marca

- **Luz de bombilla:** degradado radial `bulb` al 6 % desde el centro del notch hacia abajo (radio 180 pt) sobre el interior. **Sube al 14 % cuanto más se acerca el cursor arrastrando** y parpadea una vez (+4 %, 120 ms) al guardar algo.
- **Papel:** el `GrainOverlay` actual al 4 % sobre `wood`, en `overlay`. Nunca sobre la silueta.
- **La balda:** los ítems del shelf *se apoyan* en un listón (`plank`, 3 pt, reflejo superior de 1 px `paper` al 10 % y sombra de 6 pt debajo). Cada miniatura tiene una rotación fija y pseudoaleatoria de ±1,5° derivada de su id (estable entre sesiones): cosas dejadas en una estantería, no una cuadrícula.
- **Etiquetas:** cada ítem cuelga una etiqueta kraft con agujero (forma de 5 lados, radio 3 pt, cordel de 0,5 pt) con el nombre; el color del borde de la etiqueta es el color de su tipo.
- **Formas:** tarjetas radio 14 pt, miniaturas squircle, botones cápsula, sombra interior suave y reflejo superior (lo que ya existe, más marcado).
- **Iconos:** SF Symbols `.hierarchical`, peso `.medium`, variantes redondeadas (`shippingbox`, `archivebox`, `gauge.with.needle`, `hand.raised`, `paperplane`). Algunos glifos propios dibujados a mano: la caja con solapas, la bombilla.
- **Marca:** perfil de casa (pentágono) con una ventanita encendida en `bulb`: "hay luz en el altillo". Logotipo "altillo" en Fraunces `SOFT 100`, `WONK 1`, peso 600. Icono de app: squircle negro, tejado en `paper`, ventana con resplandor.

### Movimiento

Carácter blando, con peso: las cosas caen, rebotan un poco y se asientan. Cierre siempre sin rebote.

| Token | Valor SwiftUI |
|---|---|
| Abrir | `.spring(duration: 0.44, bounce: 0.2)` |
| Cerrar | `.spring(duration: 0.32, bounce: 0)` |
| Contenido | fundido + 2 % (lo actual) |
| Asentarse | `.spring(duration: 0.5, bounce: 0.35)` |
| Péndulo | `.interpolatingSpring(stiffness: 120, damping: 6)` |

**Microinteracción firma por módulo:**
- **Shelf, al aterrizar:** el ítem cae desde el notch con −4° de giro, al tocar la balda se **aplasta** 60 ms (escala 1,04 × 0,94) y se asienta con el spring de 0,5 s; su **etiqueta se balancea** como un péndulo (8° → 0, anclado en el agujero). La bombilla parpadea.
- **Zona de drop bajo el cursor:** la zona del shelf es una **caja de cartón cuyas solapas se abren** (dos trapecios con `rotation3DEffect` 0 → −60° sobre X, 220 ms) y el interior se calienta; al salir el cursor, se cierran. La de AirDrop: el avión de papel se eleva 3 pt y se inclina hacia el cursor.
- **Anillo de uso:** se llena con spring desde el valor anterior y la cifra rueda (`.numericText()`); al cruzar 80 % el trazo cambia a mostaza con un fundido de 400 ms.
- **Agente esperando:** "toc, toc": el icono de mano da dos golpecitos (rotación ±12°, dos veces cada 3 s) y el borde de la tarjeta brilla en `bulb`.
- **Agente terminado:** un **sello de goma** "Hecho" (Fraunces itálica, salvia, −8°) cae de escala 1,3 a 1 en 180 ms con un pequeño temblor y, pasados 4 s, se reduce a una etiqueta normal.
- **Now Playing:** la carátula como funda de disco con canto de papel; **Calendario:** una hoja de taco que se arranca (desliza y gira 6°) cuando pasa el evento.

**Sonido (desactivado por defecto):** "toc" de madera al guardar, roce de papel al quitar, **dos golpecitos en la puerta** cuando un agente espera, una campanita suave al terminar. **Háptica** igual que en A.

### Voz

Cálida, doméstica, con humor suave; tuteo y verbos del altillo (subir, bajar, guardar, dejar arriba).

- Vacío: **El altillo está vacío.** "Sube aquí lo que quieras tener a mano un rato."
- dragArmed: "Súbelo ↑"
- Drop: "Suéltalo, ya lo guardo arriba" · "Ya hay 6 cosas esperando" / "AirDrop: mandarlo a otro dispositivo"
- Peek uso: "Claude va por el *85 %* de la sesión · se repone en 1 h 11 min"
- Peek agente: "Toc, toc: Claude quiere hacer `git push` en *altillo*"
- Terminado: "Listo. badia.me terminó en 6 min."
- Alerta: "Vas rápido: a este ritmo te quedas sin sesión a las 17:40."
- Caducidad: "Esto lleva 3 días aquí arriba. ¿Lo bajamos?"
- Error: "No he podido leer tu uso de Codex. Lo intento en un momento."

### Estados del notch

| Estado | Cómo se ve |
|---|---|
| Reposo / orejas | Izquierda: mini anillo + "85" en New York. Derecha: etiqueta kraft diminuta con "6". Esperando: mano que da golpecitos en `bulb`. |
| Peek | Píldora negra con la luz de bombilla muy tenue arriba; frase en SF con el dato en New York itálica. |
| dragArmed | La bombilla se enciende según la distancia del cursor; "Súbelo ↑" en SF Rounded `bulb`. |
| dropTarget | Izquierda, la caja (≈ 75 %); derecha, AirDrop (≈ 25 %). Sin cursor: planas, texto al 40 %. **Solo la zona bajo el cursor** reacciona: solapas abiertas y calor (`bulb`) o avión elevado y tono cielo. |
| Shelf abierto | Tarjeta `wood` con grano; ítems apoyados en la balda con sus etiquetas. Selección: la etiqueta pasa a `bulb` y el ítem se eleva 2 pt con más sombra. |
| Uso | Dos tarjetas `wood`; anillo con extremos redondeados, cifra en New York, ritmo en itálica ("vas 9 puntos por delante del ritmo"); barra semanal con muesca de ritmo. |
| Agentes | Tarjetas; la que espera brilla en `bulb`, comando en SF Mono sobre `woodRaised`, "Denegar" fantasma y "Permitir" relleno `bulb` con texto `#2B1A05`. Las terminadas llevan su sello. |
| iOS | **Dynamic Island:** compacta, la ventanita encendida (izq.) y "85" en New York (der.); mínima, la ventanita; expandida, anillo + frase. **Pantalla de bloqueo y widgets en papel claro** `#F7F1E6` con etiquetas: destacan sobre el resto de Live Activities. Variante oscura en `wood`. |

### Riesgos

- **Cursi o recargado:** si todo es metáfora, cansa. Límite duro: etiquetas solo en el shelf, sello solo al terminar, solapas solo en dropTarget. El resto, sobrio.
- **Escala:** a 56 pt la etiqueta y el cordel son pequeños; si el nombre no cabe, se sacrifica la etiqueta antes que la legibilidad (modo lista sin etiquetas).
- **Rotaciones ±1,5°** desalinean texto: el texto de la etiqueta no gira, solo la miniatura.
- **Accesibilidad:** Reducir movimiento → sin caída, péndulo, solapas ni sello animado (fundido). Reducir transparencia no afecta (casi no hay cristal). Mostaza sobre `wood` es 7:1; tomate 5:1: no usar tomate en texto pequeño < 11 pt.
- **Rendimiento:** bajo-medio; el grano ya es un tile. El péndulo y el aplastamiento son springs cortos.

### Prototipo en un día

Paleta + variantes claras · bundle de Fraunces · `Shelf` con `Plank` + `LuggageTag` + rotación por id · `CardboardBox` (dos solapas con `rotation3DEffect`) · `BulbGlow(intensity:)` · `RubberStamp` · orejas y peeks con New York.

---

## Dirección C: «Fluido»

**Concepto:** el notch es tinta negra viva: todo se transforma, nada aparece de golpe, y la luz se escapa por los bordes.

**Referencias:** [Family](https://60fps.design/apps/family) y su [botón fluido](https://www.michael.fm/kanon/posts/fluid-transaction-button) · [Dia, "se hincha al abrir"](https://browsercompany.substack.com/p/the-strategy-behind-dias-design) · [NotchNook](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) · [Rauno, consistencia espacial](https://rauno.me/craft/interaction-design) · [GlassEffectContainer / glassEffectID](https://www.createwithswift.com/morphing-glass-effect-elements-into-one-another-with-glasseffectid/) · el brillo de borde de Siri en iOS 18+.

### Paleta

| Token | Hex | Uso |
|---|---|---|
| `notch` | `#000000` | Silueta y fondo (sin tarjetas cálidas). |
| `ink1` | `#111113` | Pozos. |
| `ink2` | `#1C1C1F` | Elevado, pistas. |
| `text` | `#FFFFFF` (64 % / 40 %) | Texto. |
| Luz del Shelf | `#FFB224 → #FF6A3D` | |
| Luz de IA | `#8B7CFF → #4CC9F0` | |
| Luz de Agentes | `#C6F432 → #2EE6A6` | |
| Luz de Calendario | `#FF5E7E → #FFA24C` | |
| Luz de Now Playing | 2 colores dominantes de la carátula (`CIAreaAverage` en dos mitades) | |
| AirDrop | `#3FA9FF → #7AE1FF` | |
| Aviso / crítico | `#FFB224` / `#FF453A` | |

**Reglas del acento:** cada módulo tiene su **luz**, que solo aparece como (1) **luz de borde** del notch cuando ese módulo habla, (2) el trazo de su anillo o su chip activo. La luz nunca rellena superficies grandes. Si el usuario elige un acento, todas las luces pasan a un degradado de ese tono (±20° de matiz en LCH, como hace Linear).

### Tipografía

Solo fuentes del sistema, pero con **anchos** de SF Pro, que casi nadie usa y dan mucho carácter (como en Fitness o Tiempo):

| Elemento | Especificación |
|---|---|
| Pestañas | SF Pro 12 pt semibold `.fontWidth(.expanded)`. |
| Nombre de ítem | SF Pro Text 11 pt medium (ancho normal). |
| Números (uso %) | SF Pro 28 pt bold `.fontWidth(.expanded)` en el anillo; **SF Pro Compressed** 14 pt semibold en las orejas (caben más cifras junto al notch). `monospacedDigit()`. |
| Cuentas atrás | SF Pro 11 pt medium `.fontWidth(.condensed)`, `monospacedDigit()`. |
| Peek | SF Pro 12,5 medium; el dato clave en Expanded semibold. |

Licencia: fuentes del sistema, sin empaquetar nada. Opcional: [Geist / Geist Mono](https://vercel.com/font) (OFL) para comandos si SF Mono se queda corta.

### Materiales, formas, iconos, marca

- **Luz de borde (la firma):** un trazo de 1,5 pt con `AngularGradient` de la luz del módulo, recortado a la `NotchShape` por dentro, más una copia desenfocada 6 pt con `.plusLighter`. Se anima el ángulo del degradado (una vuelta cada 3 s) solo mientras hay un evento.
- **Cristal en controles:** `glassEffect(.regular.tint(luz.opacity(0.25)).interactive())` dentro de un `GlassEffectContainer`, con `glassEffectID` para que chips y botones **se fundan y separen**. Sobre negro el cristal no tiene nada que refractar: siempre con tinte o base del 7 % (como ya hace `GlassCapsuleBackground`).
- **Aurora:** detrás de cada anillo de uso, un `MeshGradient` 3×3 de la luz del módulo al 16 %, que se desplaza lentamente al cambiar el valor (no en bucle).
- **Formas:** radios grandes y concéntricos (panel 22, tarjetas 18, miniaturas squircle 14, botones cápsula).
- **Iconos:** SF Symbols `.palette` con los dos colores de la luz y efectos de símbolo: `.breathe`, `.bounce`, `.wiggle`, `.drawOn` (SF Symbols 7), `.variableColor` para "trabajando".
- **Marca:** la silueta del notch con una línea de luz en degradado a lo largo del borde inferior: "la luz que se escapa del altillo". Icono de app hecho con Icon Composer en capas de Liquid Glass (en 27 admite anotaciones de refracción).

### Movimiento

Carácter elástico y continuo; todo se transforma desde donde estaba.

| Token | Valor SwiftUI |
|---|---|
| Abrir | `.spring(duration: 0.45, bounce: 0.28)` (el latido de NotchNook) |
| Cerrar | `.spring(duration: 0.3, bounce: 0)` |
| Contenido | "materializar": `blur 6 → 0` + opacidad + escala 0,98 → 1, 260 ms |
| Morph | `matchedGeometryEffect` peek → abierto; `glassEffectID` en controles |
| Pulsar | escala 0,97 + `.interactive()` del cristal |

**Microinteracción firma por módulo:**
- **Shelf, al aterrizar: "el trago".** La miniatura fantasma se encoge hacia el punto de contacto y la silueta hace un **abombamiento** de 6 pt hacia abajo en esa x (un `NotchShape` con un parámetro `bulge(x:depth:)`), que vuelve con `.spring(duration: 0.4, bounce: 0.4)`. Luego el contador rueda.
- **Zona de drop bajo el cursor:** la silueta se estira hasta 10 pt **hacia el cursor** (magnetismo) y la zona tiene un foco radial de 120 pt que sigue al cursor. Solo la zona bajo el cursor se tiñe; al pasar de una a otra, la luz "fluye" (un resaltado con `glassEffectID` que cambia de contenedor).
- **Anillo de uso:** trazo con degradado y una **cabeza de cometa** (punto brillante desenfocado) en el extremo; la aurora cambia de matiz al subir.
- **Agente esperando:** la luz de borde lima **respira** (opacidad 0,35 ↔ 0,9, 2,4 s) y la píldora late (escala 1 → 1,015). Al pulsar Permitir, el botón se funde con el chip de estado y ambos se convierten en "Hecho" (morph de cristal).
- **Terminado:** `checkmark` con `.drawOn` y una sola vuelta de la luz de borde.
- **Now Playing:** la luz de borde toma los colores de la carátula; **Calendario:** la luz se vuelve rosa y se acorta como una mecha a medida que llega la hora.

**Sonido (desactivado por defecto):** "blips" de cristal de 40 ms afinados en pentatónica (Shelf do, IA mi, Agentes sol) y un "glup" grave y suave al tragar. **Háptica** igual que en A.

### Voz

Mínima y amable; casi no habla, deja que hable el movimiento.

- Vacío: **Nada por aquí.** "Suelta algo en el notch."
- dragArmed: "Suelta"
- Drop: "Guardar" / "AirDrop"
- Peek uso: "Claude · 85 % · 1 h 11 min"
- Peek agente: "Claude te necesita · `git push`"
- Alerta: "Claude al 95 %. Sin sesión a las 17:40."
- Terminado: "badia.me, hecho en 6 min."

### Estados del notch

| Estado | Cómo se ve |
|---|---|
| Reposo / orejas | Cifras en SF Compressed con un mini anillo de degradado. Esperando: luz de borde lima respirando. |
| Peek | La píldora crece desde el notch con rebote; el texto se materializa; la luz de borde es la del módulo que habla. |
| dragArmed | La silueta se estira hacia el cursor y la luz ámbar crece con la cercanía. |
| dropTarget | Dos zonas de cristal (shelf y AirDrop) en un `GlassEffectContainer`. **Solo la zona bajo el cursor** se tiñe (ámbar o azul) con foco que sigue al cursor; la otra, cristal apagado. |
| Shelf abierto | Miniaturas squircle de 60 pt sobre negro; al pasar el ratón, escala 1,04 y sombra de color de la carátula. |
| Uso | Anillos con degradado y cometa, aurora detrás, cifras Expanded. |
| Agentes | Tarjeta que espera con borde de luz lima; botones de cristal que salen del chip de estado por morph. |
| iOS | **Dynamic Island** con `keylineTint` de la luz del módulo (la isla es literalmente la luz de borde); compacta con cifras Compressed. Widgets con modo de renderizado `accented` para el cristal y los tintes de iOS 26/27. |

### Riesgos

- **Poco distintivo en captura:** la personalidad vive en el movimiento. En una imagen estática se parece a NotchNook, Alcove o Siri. Es la dirección más "Apple" y la menos "Altillo".
- **Estética genérica de "app de IA"** (degradados violeta-azul). Hay que controlar mucho los colores.
- **Choca con el PLAN y con macOS 27:** el abombamiento deforma la silueta (debe volver siempre a la forma exacta del notch), y el deslizador global de opacidad del cristal de 27 cambia nuestro aspecto sin que lo controlemos.
- **Accesibilidad:** Reducir movimiento → sin estiramiento, trago, latido ni rotación de luz (luz fija). Reducir transparencia / Aumentar contraste → controles opacos y luz de borde sólida. El lima sobre negro es muy contrastado, pero nunca como texto pequeño sobre cristal.
- **Rendimiento:** el más caro: cristal, desenfoques, `MeshGradient` y una forma de silueta animada. Hay que medir en Instruments para cumplir "CPU ≈ 0 % en reposo": todo parado sin eventos.

### Prototipo en un día

`NotchShape` con `bulge` · `RimLight(colors:)` · luces por módulo en tokens · `GlassEffectContainer` en dropTarget y agentes · anillos con cometa · `MeshGradient` detrás de Uso.

---

## Común a las tres (independiente de la dirección)

- **Oficio:** pulsar a 0,97 al *pulsar*, no al soltar; lo muy frecuente (cambiar de pestaña con teclado) no se anima; escalas de entrada ≥ 0,95; abrir desde el notch y cerrar hacia el notch (consistencia espacial).
- **Háptica en trackpad** al entrar en una zona de drop y al soltar.
- **Accesibilidad:** los tres sistemas tienen su versión con Reducir movimiento (fundidos de 150–200 ms), con Reducir transparencia y con Aumentar contraste. Los estados nunca dependen solo del color.
- **Fuentes en extensiones:** las fuentes empaquetadas tienen que estar también en el target de widgets / Live Activities.

## Comparativa

| | A · Matriz | B · Desván | C · Fluido |
|---|---|---|---|
| Idea material | LED / panel de instrumentos | Papel, cartón, bombilla | Tinta y luz |
| Se reconoce en una captura | ★★★ | ★★☆ | ★☆☆ |
| Diferencia frente a Seam / NotchNook / Alcove | ★★★ | ★★★ | ★☆☆ |
| Encaja con el nombre "Altillo" | ★★☆ (el tejado de puntos) | ★★★ | ★☆☆ |
| Encaja con módulos de datos (uso, agentes, cuentas atrás) | ★★★ | ★★☆ | ★★☆ |
| Aprovecha el negro puro obligatorio | ★★★ (es la pantalla) | ★☆☆ (lucha contra él) | ★★☆ |
| Paso a iOS (isla, widgets, StandBy) | ★★★ | ★★★ (bloqueo claro) | ★★☆ |
| Legibilidad | ★★☆ (Doto solo cifras) | ★★★ | ★★★ |
| Coste de rendimiento | Bajo | Bajo-medio | Alto |
| Riesgo principal | Parecerse a Nothing, pantallas 1× | Resultar cursi | Genérico, caro |
| Prototipo en un día | Sí | Sí | Justo |

## Recomendación

**A · Matriz como sistema visual, con la voz de B · Desván.**

1. **Convierte la restricción en identidad.** El negro puro obligatorio deja de ser un fondo neutro y pasa a ser una pantalla LED apagada que Altillo enciende. Ninguna app de notch hace esto, y las orejas (la superficie que más se ve) se reconocen de un vistazo.
2. **Encaja con lo que Altillo muestra:** porcentajes, cuentas atrás y estados de agentes son datos de instrumento. Un tablero de salidas para los agentes y diales de LED para el uso se entienden sin explicación.
3. **Es la opción más barata de renderizar** (tiles y `Canvas`, sin cristal ni desenfoques animados), así que cumple el presupuesto de CPU ≈ 0 % y 120 Hz.
4. **Pasa muy bien a iOS:** Dynamic Island, widgets y StandBy nocturno.
5. **La voz cálida de Desván** (tuteo, "toc, toc", "¿lo bajamos?") compensa la frialdad del instrumento y lo aleja de Nothing. El fósforo cálido `#F4F1EA` conserva la herencia de Seam.

**Siguiente paso:** prototipar en SwiftUI Previews tres momentos de Matriz: las orejas, el dropTarget con las dos zonas y la pestaña de Uso. Hacer también **la caja de Desván** como alternativa del dropTarget y revisarlo contigo en el Mac con notch y en el monitor 1× del Mac mini antes de tocar tokens.

---

### Fuentes

- Seam: [getseam.app](https://getseam.app/) · [Seam vs NotchNook](https://getseam.app/blog/seam-vs-notchnook) · [Seam vs Alcove](https://getseam.app/blog/seam-vs-alcove)
- NotchNook: [MacStories](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) · [Macworld](https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html)
- Alcove: [La historia de Alcove](https://medium.com/@teslathewest/the-story-behind-alcove-macos-dynamic-island-app-dadb5d97e8b0)
- Nothing: [Sistema de diseño (shadcn)](https://www.shadcn.io/design/nothing) · [Phone (3), Engadget](https://www.engadget.com/mobile/smartphones/nothing-phone-3-hands-on-dot-matrix-glyph-flagship-phone-173019742.html) · [Glyph Interface](https://nothing.wiki/software/glyph_interface)
- Teenage Engineering: [OP-1 field](https://teenage.engineering/products/op-1) · [Constraints as Aesthetic](https://blakecrosley.com/guides/design/teenage-engineering) · [Playdate](https://teenage.engineering/designs/playdate)
- Braun ET66: [V&A](https://collections.vam.ac.uk/item/O1360553/et66-calculator-et66-calculator-dieter-rams/) · [PORT](https://www.port-magazine.com/design/counter-culture/)
- Panic / Playdate: [Designing for Playdate](https://help.play.date/developer/designing-for-playdate/) · [Clip Content](https://clipcontent.substack.com/p/the-playful-design-details-of-the)
- Things 3: [Cultured Code](https://culturedcode.com/things/features/) · [9to5Mac](https://9to5mac.com/2017/05/19/friday-5-things-3-video-top-features/)
- Tot: [Iconfactory](https://blog.iconfactory.com/2020/02/meet-tot-your-tiny-text-companion/) · [Macworld](https://www.macworld.com/article/233920/tot-pocket-review.html)
- Halide: [Mark III](https://www.lux.camera/halide-mark-iii/) · [The Road to Mark III](https://www.lux.camera/the-road-to-halide-mark-3/)
- Raycast: [A fresh look and feel](https://www.raycast.com/blog/a-fresh-look-and-feel)
- Family: [60fps.design](https://60fps.design/apps/family) · [Fluid transaction button](https://www.michael.fm/kanon/posts/fluid-transaction-button)
- Dia: [The strategy behind Dia's design](https://browsercompany.substack.com/p/the-strategy-behind-dias-design)
- Linear: [A calmer interface](https://linear.app/now/behind-the-latest-design-refresh) · [How we redesigned the Linear UI](https://linear.app/now/how-we-redesigned-the-linear-ui)
- Oficio: [Rauno, Invisible Details](https://rauno.me/craft/interaction-design) · [Emil Kowalski, 7 practical animation tips](https://emilkowal.ski/ui/7-practical-animation-tips)
- Apple: [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer/) · [Liquid Glass en iOS 27 (MacRumors)](https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/) · [macOS 27 Golden Gate (Wccftech)](https://wccftech.com/macos-27-golden-gate-preview-announced-at-wwdc-2026/amp/) · [Live Activities essentials, WWDC26](https://developer.apple.com/videos/play/wwdc2026/223/)
- Fuentes: [Doto](https://fonts.google.com/specimen/Doto) · [Departure Mono](https://github.com/rektdeckard/departure-mono) · [Fraunces](https://github.com/undercasetype/Fraunces)
