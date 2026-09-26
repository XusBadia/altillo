# La puerta + demo de producto

## Entrega

`videos/altillo-trailer-demo.mp4` · 40 segundos · 1920×1080 / 30 fps / H.264 + AAC.

Se conservan los 8 segundos de apertura y los 12 segundos finales de `AltilloLaPuerta`. Se sustituye el desván interior por 20 segundos de interfaz reconstruida como componentes HTML/SVG independientes y animados por fotograma. No se utilizan capturas, screencasts ni vídeo generativo de la interfaz. Solo los planos cinematográficos conservados son Grok a 720p reescalado; la demo, el texto y el icono se renderizan a 1080p.

## Referencias observadas

- [Apple: macOS Big Sur, film de diseño](https://www.apple.com/in/macos/big-sur/index.html), tramo 50–66 s: controles aislados, construcción por capas, recorrido de cámara oblicua y aproximación a la interfaz. Tomamos el tratamiento de objetos independientes; no sus gráficos.
- [Apple: nuevo diseño de software, 2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/): enfoque sobre una interacción, navegación que cede espacio al contenido y mantiene sus anclajes. No trasladamos Liquid Glass al producto: Altillo conserva madera, papel y ámbar.
- [Designing Fluid Interfaces, WWDC18](https://developer.apple.com/videos/play/wwdc2018/803/): continuidad espacial, origen reconocible y causalidad del movimiento.
- [Remotion: skills oficiales](https://github.com/remotion-dev/skills/tree/main/skills/remotion-best-practices): componentes separados, animación determinista basada en frames y montaje reproducible.

Skills utilizadas: `find-skills`, `apple-design`, `marketing-os` y guía oficial `remotion-best-practices`. La revisión especializada se delegó en investigación de Apple, verificación del código real y construcción de componentes; integración y QA final en el agente principal.

## Guion central

| Tiempo dentro de la demo | Acción |
|---|---|
| 0–4,4 s | El notch se despliega, tres archivos se elevan hacia la zona de recepción. |
| 4,4–6,6 s | Los archivos reposan sobre la balda; aproximación de cámara y selección del PDF. |
| 6,6–9 s | La tecla espacio abre una vista rápida desde el documento y lo devuelve a su lugar. |
| 9–11 s | El PDF se copia hacia el proyecto; sigue en la balda, coherente con el comportamiento de copia real. |
| 11–15 s | Cambio a Sonando; pausa con silencio musical y segunda pulsación para reanudar. |
| 15–20 s | Cambio a Agenda; próxima reunión y enlace. El panel se recoge sin aplastar sus controles. |

## Fidelidad y límites

Fuente: `Apps/macOS/Views/Desvan/` y los stores de Shelf, NowPlaying y Calendar. Medidas base: ancho560, contenido x26/y36, notch185×32, esquinas14/24. Colores extraídos de `DesvanTheme.swift`. El contenido de archivos, canción y reuniones es ficticio y se identifica en el pie como contenido de demostración.

Shelf, Quick Look, Música/Spotify y Agenda están implementados. No se presentan Uso o Agentes como funciones en vivo: usan datos de ejemplo. Sus iconos aparecen únicamente como parte de la navegación existente.

La reconstrucción cinematográfica no es una captura exacta de píxeles: usa ilustraciones vectoriales propias para los documentos, títulos legibles y escala magnificada. No implica sincronización, almacenamiento remoto ni reproducción de música dentro de Altillo.

## Audio

Base procedente del audio generado de Grok ya existente, extendida mediante fundidos cruzados. Foley original breve creado con ruido filtrado para contactos y movimiento de papel. La música se atenúa al pulsar pausa y vuelve al pulsar reproducir. No se utiliza música de Apple ni de artistas externos.

## Evaluación editorial

Versión archivada, sustituida por `AltilloDirectorCut`. La revisión del usuario detectó discontinuidades importantes entre escenas y música ausente durante la firma. Las puntuaciones heurísticas anteriores no eran una validación útil y se han retirado. Véase `DIRECTOR-CUT.md` para los cambios y la evidencia de revisión de la nueva versión.

## Reproducir

Desde `promo`:

```sh
npx remotion render src/index.ts AltilloTrailerDemo videos/altillo-trailer-demo.mp4 --codec=h264 --crf=16 --audio-codec=aac --audio-bitrate=192k
```

Composición central independiente: `AltilloDemoOnly` (600frames). El vídeo anterior permanece intacto.

## Verificación

TypeScript y `git diff --check` sin errores. MP4 completo decodificado: 1200 fotogramas, H.264 1080p30, AAC estéreo48kHz. Medición del primer render: −22,32 LUFS integrados, pico−3,68dBTP. Revisión visual mediante renders completos, fotogramas de escenas y contact sheet; revisión independiente de continuidad espacial. Último ajuste: cuerpo de balda compartido al cambiar a Sonando para eliminar un salto de42px. La pista se verificó técnicamente, sin escucha crítica independiente.
