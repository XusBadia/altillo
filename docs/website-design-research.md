# Web de Altillo: dirección e investigación

Investigación: 20 de septiembre de 2026. Encargo: una web singular, con animación al hacer scroll y una demo que se pueda manipular, sin depender de pestañas para explicar el producto.

## Referencias consultadas

Se abrieron las fuentes oficiales con búsqueda web. Además, se capturaron los primeros 1050 píxeles de Raycast, Linear y Apple en Chromium, a 1440 píxeles de ancho. Las observaciones siguientes separan lo visto de las propuestas para Altillo; no se han medido curvas de animación de estas webs.

| Referencia | Observación y evidencia | Qué trasladar a Altillo |
| --- | --- | --- |
| [Raycast](https://www.raycast.com/) | Hero oscuro, composición roja diagonal que ocupa casi toda la pantalla, titular centrado y CTA muy separado debajo. Más abajo aparecen interfaces concretas, atajos y tareas. Captura inspeccionada. | Una sola composición reconocible debe llevar el peso visual. Para Altillo, el objeto es la abertura del notch y su luz, con archivos reales de ejemplo. No copiar los haces rojos ni el eslogan. |
| [Linear](https://linear.app/) | Titular grande a la izquierda, mucho espacio libre, navegación fina y una interfaz extensa debajo. El contenido muestra una tarea, actividad y revisión, en lugar de limitarse a iconos abstractos. Captura inspeccionada durante la entrada: el texto seguía parcialmente desenfocado. | Mostrar una tarea completa con nombres y consecuencias. Usar alineaciones editoriales, no centrar todos los bloques. No reproducir la entrada desenfocada: la información debe verse inmediatamente. |
| [MacBook Pro, Apple](https://www.apple.com/macbook-pro/) | Hero negro con el hardware enorme y recortado. Texto situado en el tercio inferior izquierdo. La página separa presentación, exploración del objeto y explicaciones específicas. Captura inspeccionada. | El notch puede superar el ancho del texto y salir del encuadre. Dar escala al objeto y revelar su utilidad después. No hace falta dibujar un portátil entero ni copiar precios, beneficios o degradados tipográficos. |
| [boring.notch](https://theboring.name/) y [repositorio oficial](https://github.com/TheBoredTeam/boring.notch) | La web devolvió título en búsqueda, pero la primera navegación visual agotó el tiempo de carga. El README oficial documenta expansión al acercar el cursor, controles de música y estante. | La demo debe explicar que el borde superior responde al acercarse y que el archivo sigue existiendo después de subirlo. Referencia de interacción, no atribuir a su web una composición no verificada. |
| [NotchNook](https://lo.cafe/notchnook) | El acceso web devolvió 502 y Chromium no resolvió el dominio durante esta revisión. | No basar decisiones en una supuesta inspección ni imitar capturas de terceros. Se registra como referencia intentada, no como evidencia visual. |

## Dirección propuesta: abrir el altillo

La página comienza dentro del mundo del producto: negro cálido, una abertura negra en el borde superior y una luz doméstica muy contenida. El titular de marca aparece grande, ligeramente descentrado: «Tu Mac ya tenía un altillo». La continuación, «Solo le faltaba una puerta», acompaña la apertura del notch. Debajo basta una frase concreta: «Deja archivos arriba. Recógelos donde los necesites».

El efecto distintivo sale de una relación física entendible: algo pequeño arriba puede albergar lo que dejas un momento. No añadir planetas, partículas, cuadrículas técnicas, marcos de navegador ni una colección de tarjetas de funcionalidades.

Tipografía de sistema con títulos de 88–112 px en escritorio y 44–52 px en móvil como punto de partida, ajustados por anchura real. Texto de lectura de 17–19 px. Titulares cortos, interlineado aproximado de 1.0–1.08 y tracking moderado. El ancho del párrafo no debe crecer con el del escenario.

Superficies: madera casi negra `#1E1914`, interior `#2A231C`, papel `#F6EFE3`, luz `#FFB547`. La luz se concentra en el interior; no colorea todos los botones. Texturas muy leves y sin interferir en la lectura. El icono canónico 11A conserva su aspecto.

## Recorrido y movimiento

| Momento | Composición | Movimiento propuesto |
| --- | --- | --- |
| 1. Descubrir | Un notch unido al borde superior; titular dominante y espacio vacío alrededor. | Al empezar a bajar, una fina rendija revela luz. La fuente de luz permanece fija: crece su opacidad, no viaja por la página. |
| 2. Subir | Dos o tres archivos asimétricos se acercan al estante; una sola explicación breve junto a ellos. | Un archivo sigue una trayectoria ascendente hasta la abertura y aterriza. El resto no flota en bucle. Un ligero asentamiento comunica peso. |
| 3. Probar | La escena se estabiliza como escritorio utilizable. Notch arriba, archivos abajo, destino lateral. | Acercar el archivo abre el receptáculo; soltar lo deja en el estante. Sacarlo a una ventana de destino completa la historia. |
| 4. Lo siguiente | Una demostración específica de uso y otra de agente, con el estado «En desarrollo» visible. | El contador cambia por una acción explícita. Una llamada breve señala que el agente pide atención. Sin sondeo ficticio ni aprobación automática. |
| 5. Apoyar | El fondo vuelve al papel cálido. Aurio aparece como otra app de los mismos creadores, con espacio y un enlace claro. | Una entrada breve al llegar. Sin ticker, confeti ni efecto que compita con la petición. |

La secuencia narrativa puede ocupar un tramo sticky de 180–220 vh en escritorio. El desplazamiento sigue siendo nativo, reversible y sin capturar la rueda. No forzar al visitante a consumir una película antes de llegar a los controles. El botón «Probar» lleva directamente al escenario listo para usar.

En móvil, reducir el tramo o presentar la escena directamente. La demo admite tocar un archivo y después el destino, además del arrastre. Los elementos manipulables tienen acciones equivalentes con teclado y etiquetas visibles. No requiere hover para descubrir lo esencial.

## Valores iniciales de interacción

Aplicación de las skills locales `apple-design` y `emil-design-eng`, contrastada con el objetivo de esta página:

- Respuesta al presionar: inmediata; escala de 0.98 durante unos 100 ms si ayuda a identificar el objeto.
- Durante el arrastre: posición 1:1 con el puntero, conservando el punto donde se agarró. Sin interpolación que provoque retraso bajo la mano.
- Apertura del notch: 240–320 ms, origen arriba y centro. Cierre más breve, aproximadamente 180–220 ms, sin rebote.
- Aterrizaje: un único asentamiento de 300–380 ms, equivalente a un muelle con amortiguación cercana a 0.8. El resto de la UI usa amortiguación cercana a 1.
- Párrafos al entrar: como máximo 12–20 px de recorrido y 240–360 ms. Nunca ocultar todo el contenido a la espera de JavaScript.
- Scroll narrativo: progreso conectado al desplazamiento; sin temporizadores que obliguen a esperar. Al comenzar una manipulación, el scroll deja de controlar ese objeto.
- Reducir movimiento: escenas estáticas completas o fundidos cortos; sin zoom, parallax, trayectorias ni rebotes. La funcionalidad permanece idéntica.
- Animar preferentemente transform y opacidad. Activar trabajo por frame solo mientras la escena se mueve y evitar recalcular la geometría completa en cada movimiento del puntero.

## Condiciones para considerar lograda la nueva versión

Una captura inicial debe reconocerse como Altillo incluso sin el logotipo. En diez segundos se entiende dónde se dejan los archivos y cómo se recuperan. Al interactuar, el objeto responde al gesto y el resultado persiste: no basta con reproducir una animación al pulsar un botón. La misma historia funciona con teclado, tacto y movimiento reducido.

La fidelidad funcional no implica inventar integraciones: Claude y Codex siguen siendo prototipos con datos de ejemplo. La web no anuncia descarga mientras no exista una release pública. La sección de Aurio mantiene el enlace oficial y no promete que probarla genere una donación.
