# Revisión visual competitiva de la web de Altillo

26 de septiembre de 2026. Contexto: `brand-context.md`, `docs/website-design-research.md`, `plans/competitive-notchview-2026-09-26.md` y las cinco capturas aportadas. Método: módulo competitive de marketing-os, fuentes oficiales, extracción del texto visible y capturas Chromium a 1440 × 1000. No se han instalado ni comprado apps.

## La decisión

Altillo ya tiene una idea propia: subir cosas a un altillo. Hay que darle la precisión visual de una app de Mac y una demostración que responda al visitante. Alcove aporta jerarquía y espacio; boring.notch demuestra que se puede entrar directamente en un escritorio; NotchBay trata cada función como una escena. La dirección propuesta combina esa claridad con el papel, la luz cálida y la voz doméstica de Altillo.

La categoría ya repite «Dynamic Island para Mac», privacidad local y agentes. Son expectativas o capacidades a demostrar, no exclusividades que podamos reclamar. El artículo oficial de [DynamicLake Market, del 4 de septiembre](https://www.dynamiclake.com/blog/dynamiclake-market-and-plugins) incluye plugins para agentes; la web de [NotchBay](https://notchbay.com/) muestra Claude y Codex. La oportunidad es hacer comprensible y agradable una tarea completa, con límites y acciones explícitos.

## Webs revisadas

### Alcove — referencia principal para jerarquía

Fuente: [tryalcove.com](https://tryalcove.com/). Página cargada y hero inspeccionado visualmente.

Fondo crema, texto casi negro, titular enorme de dos líneas. La descarga tiene un botón sólido con espacio lateral generoso; compra y precio aparecen en un control secundario. Debajo hay un escritorio violeta con pantalla bloqueada, hora y notch. La página invita expresamente a interactuar y enumera transiciones, notificaciones y gestos. El precio observado era 14,99 dólares; no se abrió checkout.

**Aplicación:** separar título, explicación y controles; botón dorado de Altillo con texto oscuro y un padding que sobreviva al castellano; dejar que el escenario sea el único gran bloque de color. El tamaño de un botón debe depender de su contenido, nunca de una anchura pensada para una palabra inglesa.

**No trasladar:** el subrayado rosa, la identidad de Apple ni la promesa genérica de isla dinámica. No se han medido sus muelles ni probado todos los gestos.

### boring.notch — un mundo manipulable

Fuente: [theboring.name](https://theboring.name/). Esta vez sí cargó: sustituye el bloqueo de la investigación del 20 de septiembre.

La primera pantalla reproduce un escritorio entero: barra superior, notch con música, carpetas, ventanas, widgets y dock. Descarga y GitHub quedan dentro de una tarjeta del escritorio. El resultado se reconoce antes de leer, aunque la mezcla de vídeo, otra web, relojes y cotizaciones dispersa la atención. La descarga se presenta como gratuita y de código abierto.

**Aplicación:** convertir los archivos en objetos creíbles, con borde de papel, escala común y respuesta inmediata. Dock y ventanas deben servir al trayecto del archivo. El objetivo no es reconstruir todo macOS.

**No trasladar:** el número de elementos simultáneos, cotizaciones, enlaces ajenos o ventanas que compiten con la demo. La identidad cálida de Altillo puede ser mucho más calmada.

### NotchView — una tarea por escena

Fuente: [notchview-site.vercel.app](https://notchview-site.vercel.app/). Hero y tramo inferior capturados.

Negro, titular blanco con segunda línea rosa/lila, descarga visible con precio y un MacBook de gran tamaño. Tras el hero, una escena a la izquierda y tres explicaciones a la derecha: música, archivos y controles del sistema. La sección de agentes ordena el relato en comenzar, apartarse, recibir aviso y volver al terminal. El precio de la página era 5 dólares una vez; no se comprobó el cobro.

**Aplicación:** guiar cada estado de la demo mediante una acción corta: «Deja un archivo arriba», «Recógelo en otra app», «Mira cuánto te queda». Mantener una sola acción principal por escena y asegurar la lectura de las acciones inactivas.

**No trasladar:** degradado del titular, tabla de ataques por precio, ni el marco del portátil si reduce la legibilidad. La comparación comercial de la página es una afirmación del vendedor, no evidencia independiente.

### DynamicLake — explica las variantes, pero tarda en enseñar

Fuentes: [home oficial](https://www.dynamiclake.com/) y [artículo de Market](https://www.dynamiclake.com/blog/dynamiclake-market-and-plugins).

El primer viewport capturado es gris claro: una pequeña isla, título enorme, compra y blog. El anuncio de plugins entra en ese mismo primer viewport; las demostraciones de variantes y funciones están más abajo. La página distingue Liquid Glass, miniLake y capacidades concretas, y publica una FAQ extensa.

**Aplicación:** explicar modos solo cuando resuelvan una duda del visitante. En Altillo, demo antes que lista de novedades. Reservar un área específica para requisitos y estado real de distribución.

**No trasladar:** titulares abstractos sobre ideas o plataformas. La home no nos permite afirmar calidad de rendimiento ni estabilidad del producto.

### NotchNook — referencia pendiente, sin inventar una inspección

Fuente intentada: [lo.cafe/notchnook](https://lo.cafe/notchnook). Chromium devolvió `ERR_NAME_NOT_RESOLVED`; la herramienta web también falló. No hay evidencia visual nueva y no se toma una captura de un distribuidor como si fuera la web oficial. Las observaciones históricas del repositorio se mantienen como antecedentes, no como revisión actual.

### Notchmeister — personalidad puntual

Fuentes oficiales: [anuncio de Iconfactory](https://blog.iconfactory.com/2021/12/notches-gone-wild/), [Fusion Dice](https://blog.iconfactory.com/2023/05/a-revolutionary-new-feature-for-notchmeister/) y [ficha App Store](https://apps.apple.com/id/app/notchmeister/id1599169747?mt=12).

La ruta `iconfactory.com/notchmeister/` cargó una página «File Not Found». Sus fuentes oficiales presentan una utilidad lúdica y efectos que responden al cursor. Sirve como referencia de personalidad, no como comparación de landing moderna ni de almacenamiento de archivos.

**Aplicación:** el guiño de Aurio debe ser un gesto breve al acercarse y al enfocar con teclado. El rostro vuelve a reposo al salir. Sin bucle automático, sin desplazar texto y respetando movimiento reducido.

### NotchBay — incorporación relevante

Fuente: [notchbay.com](https://notchbay.com/). Hero y escritorio capturados; texto visible del resto de la página revisado.

La propia navegación adopta forma de notch. Fondo blanco, titular con contraste entre sans y serif cursiva, CTA rojo y gran escritorio con paisaje. El segundo viewport conserva el producto a gran escala. Más abajo separa tray, dictado y reuniones, con interfaz y acción concreta por sección. La página publica controles de agentes y uso de Claude/Codex.

**Aplicación:** pocas señales visuales repetidas con intención; una gran escena por capítulo. El dock se reconoce por silueta e iconos coherentes, sin necesidad de añadir decoración a cada control.

**No trasladar:** marca, tipografía cursiva ni promociones temporales. Privacidad y precisión de sus muelles son declaraciones del vendedor; no se ha auditado su implementación.

## Otras referencias encontradas

[NotchDrop de Lakr233](https://github.com/Lakr233/NotchDrop) aporta un posicionamiento muy concreto alrededor de archivos temporales y AirDrop. No confundirlo con otros productos llamados NotchDrop.

[Atoll](https://github.com/Atoll-Labs/Atoll) documenta un conjunto amplio de medios, widgets, sistema y utilidades, con herencia explícita de boring.notch. Hay otros repositorios con ese nombre: no se mezclan autores ni capacidades. Su README se usó para ampliar el panorama; su app y landing no se inspeccionaron visualmente.

[MacNotch](https://macnotch.io/) también merece seguimiento por sus módulos configurables y su explicación de requisitos. Solo se revisó el texto oficial servido por búsqueda, sin atribuirle una calidad visual no comprobada.

## Prioridades concretas para Altillo

| Prioridad | Cambio propuesto | Evidencia / motivo | Esfuerzo | Confianza |
| --- | --- | --- | --- | --- |
| 1 | Botón Descargar con fondo ámbar, texto casi negro, ancho intrínseco y padding horizontal generoso. La navegación debe conservar altura estable. | En la captura el texto claro pierde contraste y el contorno abraza la palabra. Alcove muestra una jerarquía legible. | S | Alta |
| 2 | Unificar los archivos: área de miniatura común, badges pequeños con margen, nombre debajo y sin adornos encima del nombre. | Las flechas doradas dominan los documentos y la estrella invade «Escapada.jpg». | S | Alta |
| 3 | Limpiar consumo: superficie oscura lisa o textura casi imperceptible, anillos nítidos, proveedor como encabezado, reset secundario, barra semanal discreta. | Las líneas del material atraviesan todo el contenido y compiten con cifras y barras. | M | Alta |
| 4 | Rehacer proporciones del dock: iconos cuadrados coherentes, sombra común, separador tenue y Finder reconocible dentro de su icono. | La boca de Finder parece salir por encima. El dock visible de NotchBay conserva la lectura de los iconos a pequeña escala. | S | Alta |
| 5 | Aurio mantiene el guiño durante hover/focus y vuelve al salir, con la transición de su app. | Petición explícita del usuario; la personalidad de Notchmeister avala el valor de una sorpresa pequeña. | S | Alta |
| 6 | Dar a la demo una progresión visible: subir → guardar → recuperar. Un solo foco luminoso y el resto quieto. | Convergencia de Alcove, NotchView y NotchBay alrededor de demostraciones claras. | M | Alta |

La puntuación de prioridad es heurística, no una predicción de conversiones. Para comparar las referencias **en utilidad para este encargo**, se asigna 40% a claridad del producto, 35% a jerarquía visual y 25% a ideas trasladables sin perder la marca: Alcove 90/100 (9/9/9), NotchBay 86/100 (9/9/7,5), NotchView 83/100 (8,5/8,5/7,5), boring.notch 73/100 (7/6,5/9) y DynamicLake 61/100 (6/6,5/5,5). No se puntúan webs inaccesibles ni apps no ejecutadas. Son juicios de diseño basados en las capturas descritas, no calidad global de las apps.

## Qué conservar

La pareja «Tu Mac ya tenía un altillo / Solo le faltaba una puerta» sí distingue el proyecto. El material cálido, los archivos manipulables y Aurio ofrecen una identidad que no depende de degradados púrpura. La mejora debería hacer más nítido ese mundo: menos ruido en las superficies y más precisión en cada borde, espacio y respuesta.

## Límites de esta investigación

No se consultaron bibliotecas publicitarias, gasto, datos de conversión, ventas, entrevistas ni reseñas suficientes para inferir satisfacción; esta es una revisión de webs para dirección visual. No hay base para decir qué diseño vende más. Tampoco se midieron rendimiento, accesibilidad completa, móvil ni curvas de animación de terceros. Las capturas registran estados puntuales y no equivalen a probar todo el recorrido.

Las capturas de trabajo permanecen en `/tmp/altillo-competitors/`: `0.png` Alcove, `1.png` boring.notch, `3.png` NotchView, `4.png` DynamicLake, `6.png` NotchBay; `notchview-below.png` y `notchbay-below.png` documentan un segundo viewport. `alcove-below.png` regresó al hero, por lo que no se usa como prueba de una sección inferior. No se han añadido imágenes de terceros al producto ni publicado cambios.


## Cambios aplicados en esta revisión

- Navegación: corregida la especificidad que anulaba color y padding de Descargar. Texto oscuro sobre ámbar; controles ajustados a móvil y cabecera con fondo translúcido al desplazarse.
- Portada: acción de probar más visible y acceso directo a descarga, en español e inglés. Mejoradas escalas de lectura, contraste y espaciado de las secciones posteriores.
- Demo: badges de archivos y sus SVG proporcionados; cara de Finder contenida dentro del icono; consumo sin rayas, con cifras tabulares y separación semanal más clara.
- Aurio: crossfade de 180 ms entre los recursos originales, como en SettingsSupportCard de la app, con foco de teclado y movimiento reducido.
- El destello bajo Escapada.jpg no se reproduce en el DOM ni en las capturas de la versión local actual. No se ha añadido una corrección especulativa.

Verificación: build de producción correcto; pruebas de hero, navegación, página, guiño y geometría de demo en Chromium, WebKit y móvil. Capturas locales revisadas a 1440, 390 y 320 px; contraste y límites de navegación comprobados también a 768 px. No se ha desplegado.
