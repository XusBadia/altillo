# OmniNotch: análisis y qué aprendemos (22-09-2026)

Probado en el Mac mini (pantalla externa sin notch, macOS 26.6) con OmniNotch 1.1.2 (build 6), además de su web y su bundle. Fuentes: [omninotch.app](https://omninotch.app/), [Ask Omni](https://omninotch.app/features/ask-omni), [comparativa](https://omninotch.app/guides/mac-notch-apps-compared).

## Qué es

Una app de notch «todo en uno» de pago único (14,99 $, 5 $ de lanzamiento), con Sparkle, sin sandbox y sin telemetría. Tiene 18 herramientas que se activan en una rejilla de ajustes dentro del propio notch:

Inicio, Shelf, Portapapeles, Calendario, Uso de IA, **Ask Omni**, Tiempo, Recordatorios, Sistema (CPU/memoria/red), Tareas, Atajos, Bolsa, Emoji, Conversor, Espejo, Teleprompter, Herramientas y Temporizadores.

La web también anuncia Now Playing, AirDrop, «Keep Awake» y un HUD de volumen.

## Lo que hace bien

- **Movimiento.** Grabado a 60 fps, el notch abre en unos 270 ms. La silueta crece desde el notch con un rebote pequeño (5-7 % más grande durante un par de frames) y se asienta en unos 300 ms. El contenido entra desenfocado y se enfoca mientras la forma crece. Al cerrar tarda 150-200 ms, sin rebote, y el contenido se desenfoca. Usa la librería Pow y spring physics.
- **Asistente on-device.** Ask Omni usa Foundation Models (Apple Intelligence). Todo es local: la UI dice «Nothing you type leaves your Mac». Tiene chips de sugerencias, «Thinking…», botón de parar y «New chat».
- **Todo se abre con hover.** En Macs sin notch dibuja uno flotante.
- **Hápticos opcionales**, retardo del hover configurable y caducidad del shelf (1 h - siempre).
- **Uso de IA** de Claude Code, Codex y Copilot leyendo credenciales locales.

## Lo que hace mal (y es nuestra oportunidad)

- **Ask Omni no ve nada.** Le pregunté «What's on my calendar today and what did I copy last?» y respondió «I cannot see your calendar or your clipboard». Es un chat genérico con un prompt de sistema, sin tool calling. **Altillo puede usar su propio contexto** (shelf, calendario, música, portapapeles y, más adelante, uso de IA y agentes) con tools de Foundation Models, sin salir del Mac.
- **Sin personalidad.** Es negro y gris, con una barra de iconos genérica abajo. El Desván es justo lo contrario.
- **Sin avisos en vivo.** No hay peeks: el notch solo muestra algo si lo abres. En Altillo, lo que importa (una reunión en 5 min, un agente que espera) debe asomar solo y volver a su sitio.
- **Sin gestos.** No hay swipe entre secciones ni atajos de teclado para cambiar de sección. Tampoco hay atajo global para el asistente.
- **Uso de IA frágil.** Claude mostraba «Session expired — run `claude`» y Codex 100 % sin contexto. No tiene agentes en vivo.
- **Ajustes mínimos.** Solo hay idioma, abrir al iniciar sesión, hápticos, retardo del hover y caducidad del shelf. No hay orden libre de secciones ni vista previa.

## Qué adoptamos

| Idea de OmniNotch | Cómo la hace suya Altillo | Fase |
|---|---|---|
| Apertura «líquida» con enfoque del contenido | Resorte con un rebote sutil y enfoque del contenido; al cerrar se desenfoca sin rebote. Todo con peso de Desván y fundidos con Reducir movimiento | 11 |
| Asistente on-device | **«Pregunta»**, con tools sobre el contexto de Altillo: shelf (leer textos y PDFs que dejas arriba), calendario, música y portapapeles. Además, **«Súbelo»**: la respuesta se convierte en algo del shelf que puedes arrastrar. Atajo global ⌃⌥A | 11 |
| Hápticos | Un toque al cambiar de sección con swipe o cuando algo aterriza en el shelf, desactivable | 11 |
| — (no lo tiene) | **Avisos en vivo** como peek: reunión en 5 min y canción nueva (opcional). Luego los agentes y los umbrales de uso | 11 |
| — (no lo tiene) | **Swipe con dos dedos** entre secciones, ⌘1…⌘9 y ⌃Tab, con goma elástica en los extremos | 11 |
| Temporizadores, portapapeles, notas y atajos | Utilidades del altillo con estética Desván: un reloj de cocina como temporizador, portapapeles solo de texto opt-in, una nota rápida y lanzador de Atajos | 12 |
| Tiempo, bolsa, emoji, conversor y teleprompter | Fuera: no encajan con «invisible hasta que hace falta» | — |
