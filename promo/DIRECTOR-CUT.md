# Altillo · La puerta · Director cut

Entrega: `videos/altillo-director-cut.mp4`. 40 segundos, 1920×1080, 30 fps.
Las versiones anteriores se conservan como referencia, no como entregas aprobadas.

## Decisiones de montaje

La revisión anterior era demasiado estrecha: comprobaba componentes y no la continuidad de la película. Se retiraron las puntuaciones autoasignadas.

- Apertura: encuadre estable con avance editorial de cámara y la frase aprobada, presentada de forma secuencial. Se elimina el crecimiento/deformación generativo de la puerta y la mayor parte de los papeles voladores.
- Entrada: un breve macro de puerta precede una oclusión oscura de 16 fotogramas. La jamba conecta con el negro cálido del producto. No hay salto a una cartela crema ni fundido gris.
- Demo: interfaz reconstruida y animada por fotogramas, no capturas, screencast ni vídeo generativo de controles. Dejar archivos, seleccionar, Espacio/Quick Look, recuperar una copia, siguiente canción, agenda y recogida hacia el notch.
- Cámara: plano funcional para archivos; aproximación al documento; avance y desplazamiento hacia los controles musicales; reencuadre para agenda. La navegación causa los cambios de módulo.
- Material: textura de madera exportada del algoritmo determinista de la app (`DesvanTextures.swift`), aplicada a escala nativa y al 17%; no una textura inventada por un generador.
- Tipografía: una sola frase de campaña visible cada vez. Cambios de contenido mediante máscaras complementarias, no textos fundidos unos sobre otros. Quick Look opaco; el mensaje de arrastre desaparece antes de que pasen los archivos.
- Regreso: solo el fragmento limpio final del portátil, sin repetir la coreografía de hojas. El notch se contrae hacia la posición del punto ámbar y este conecta con el icono oficial.
- Firma: `AltilloIconMaster-11A.png` original, sin regeneración.
- Audio: una única banda musical de 40 segundos, independiente de los clips y de los controles ilustrados. Los audios de todos los clips están silenciados. Solo funde al final, desde 39,3 s. Procedencia y mediciones en `DIRECTOR-AUDIO-QA.md`.

## Referencias y skills

Referencias originales de Apple, sin reutilizar sus imágenes ni música:

- [Película de diseño de macOS Big Sur](https://www.apple.com/in/macos/big-sur/index.html): cambios de escala y profundidad sobre objetos de interfaz.
- [Diseño de software de Apple, 2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/): foco en contenido y continuidad del contenedor al transformarse.
- [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/): origen espacial y causalidad.

Skills aplicadas en esta revisión: `apple-design`, `review-animations` y `react-best-practices`. Sus reglas de interfaces interactivas se adaptan a un film pre-renderizado; no se imponen límites de duración de microinteracciones a movimientos editoriales de cámara.

Se delegaron independientemente música, crítica visual y comprobación de texto/producto. Integración y decisiones finales de montaje a cargo del agente principal.

## Fidelidad y límites

La UI usa medidas y materiales de `Apps/macOS/Views/Desvan/`, con contenido ficticio. Las etiquetas españolas son una recreación localizada; el código actual de la app está siendo traducido al inglés. El pie lo identifica como «Interfaz recreada · Contenido de demostración».

Las funciones mostradas existen en el código; Uso y Agentes no se presentan como funciones activas. Recuperar el PDF conserva el original porque es una copia, no un movimiento de Finder. Siguiente canción cambia el título y reinicia el progreso, manteniendo el mismo álbum ficticio.

Los dos fragmentos de puerta/portátil y el fotograma inicial proceden de Grok a 720p. Se han seleccionado y recortado para reducir defectos, no se afirma que sean fotografía real. UI, tipografía y marca se componen a 1080p.

## Verificación reproducible

```sh
cd promo
npx tsc --noEmit
node qa/text-layout-audit.mjs
node qa/director-text-audit.mjs
npm run render:director
```

La auditoría de texto mide los 1.200 fotogramas mediante DOM/Chromium y máscaras de visibilidad. Se complementa con inspección de los MP4 y fotogramas exportados: las métricas de fuente no demuestran por sí solas legibilidad ni calidad de montaje.

Resultado de la última auditoría del código final: 1.200 fotogramas, 6.389 rangos de texto visibles, **cero grupos de solapamiento**. También se aumentó el interlineado del documento de Quick Look para eliminar incluso la intersección de métricas de fuente que no se veía como colisión de tinta.

### Revisión de movimiento

| Antes | Después | Motivo |
|---|---|---|
| Puerta ámbar → fondo crema con fade gris | Oclusión de 16 frames → mismo negro cálido | Conserva material y movimiento sin mantener dos escenas visibles demasiado tiempo. |
| UI frontal casi fija | Cámara de detalle en documento, música y agenda | El encuadre sigue la interacción y varía la escala de forma motivada. |
| Cursor fuera de Siguiente | Centro nativo (512,5; 88), compensado por el punto del cursor | La acción ocurre sobre el control y cambia el título. |
| Notch diminuto inmóvil antes del portátil | Contracción retrasada y retorno solapado por posición | Evita un vacío que parecía accidental. |
| Dos contenidos fundidos | Máscaras complementarias | Ninguna pareja de textos se mezcla durante el cambio de módulo. |

Veredicto visual independiente: aprobado dentro de los tramos inspeccionados; no constituye una reproducción humana completa ni una certificación de calidad «Apple». Revisión React/TypeScript: sin errores; render determinista basado en frames, sin temporizadores, efectos aleatorios ni transiciones CSS dependientes del tiempo real.

Las uniones se inspeccionan con muestreo denso, además de la hoja de la película completa. Se comprueban duración, decodificación completa, audio final y ausencia de silencios internos sobre el archivo exportado, no solo sobre la pista de origen.

MP4 final: H.264, 1920×1080, 30 fps, 1.200 frames, vídeo de 40,000 s; AAC estéreo 48 kHz con duración de contenedor de 40,064 s por padding. Tamaño: 12.183.769 bytes. Decodificación completa sin errores. Fotogramas finales de música, agenda, entrada, regreso y firma inspeccionados tras exportar.

Límite de la revisión de audio: se verificaron espectro, continuidad, niveles, duración y cola; no se dispone de escucha crítica real mediante las herramientas usadas. No se afirma una audición humana ni una validación comercial con espectadores.
