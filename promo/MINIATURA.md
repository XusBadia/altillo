# Miniatura — película stop motion

Entrega: `videos/altillo-miniatura.mp4` (ES) y `videos/altillo-miniatura-en.mp4` (EN). 32 s, 1920×1080, 24 fps.

## Idea

Un set en miniatura hecho a mano vive dentro del notch: una puerta de roble, una escalera de cerillas, un desván con estantes y un robot de cuerda que llama antes de entrar. Cada plano cuenta una sola función de Altillo con objetos físicos, sin interfaz.

| Plano | Qué pasa | Texto |
|---|---|---|
| 1 | Portátil de noche; luz ámbar bajo la puerta del notch | Tu Mac ya tenía un altillo. |
| 2 | Un paquete, un sobre y una foto suben la escalera y entran | Solo le faltaba una puerta. |
| 3 | Macro: la puerta se abre y la cámara entra | — |
| 4 | Desván: los paquetes aterrizan en su sitio | Deja arriba lo que quieras a mano. |
| 5 | Un robot de cuerda llama tres veces; la puerta se abre | Tus agentes llaman antes de entrar. |
| 6 | Alejamiento; la puerta vuelve a quedar en calma | — |
| Firma | Icono 11A, «Altillo», «Un sitio arriba para lo importante.», altillo.app | |

## Marco aplicado

Referencia: [«Make your product videos look expensive (Apple Framework)»](https://x.com/leomeethewoo/status/2103529310208606701) de leo (@leomeethewoo).

- **Intención y reglas:** tres colores (negro grafito, ámbar, kraft/marfil), una tipografía y un solo mundo físico.
- **Un plano = una idea**, sujeto centrado y aire alrededor.
- **Movimiento suavizado** en cámara y texto; fundidos cortos en lugar de cortes secos, con destello cálido al cruzar la puerta.
- **Ritmo adaptativo:** entrada lenta, parte central más viva y resolución calmada.
- **Música de 96–100 BPM** (rango «suave, sin esfuerzo») y efectos de sonido mínimos, solo donde hay una acción física.

## Producción

1. **Fotogramas clave** (`public/stopmotion/keys/`): generados con `chatgpt-imagegen` (backend codex). Se encadenan como referencias para mantener la continuidad del set. Hay recortes 16:9 en `keys169/`.
2. **Animación** (`public/stopmotion/grok720/`): herramienta nativa `image_to_video` de Grok Build con `resolution_name="720p"`, 6 s por plano, 1280×720. El script es `public/stopmotion/grok-shots-720.sh`. Las tomas de prueba a 480p están en `grok/`. En esa tanda, la toma de cierre generada inventó una puerta gigante y se descartó: el cierre es el plano 1 invertido.
3. **Tratamiento stop motion** (`public/stopmotion/process.sh`): 12 fps a doses, vibración del set por fotograma (±5 px), parpadeo de exposición, grano fijo por fotograma y viñeta. Reescalado Lanczos a 1080p: el metraje de origen es 720p, no 1080p nativo.
4. **Montaje** (`src/AltilloMiniatura.tsx`): Remotion a 24 fps. Los textos también se mueven a doses, con una ligera vibración. El icono es el máster 11A original con la máscara de macOS aplicada.
5. **Audio** (`public/stopmotion/audio/`, detalle en su `README.md`): la banda sonora sale de dos frases instrumentales de 10 s generadas con Grok, montadas a 32 s con fundidos. Está a −18 LUFS y −2,1 dBTP. Tiene una pausa a los 19 s, justo antes de que el robot llame. Los efectos se sintetizaron en local con sox/ffmpeg porque el saldo de Grok Build se agotó. Solo se usan golpes, papel, tic y pestillo, a volumen bajo; el crujido de puerta y la cuerda se descartaron por sonar sintéticos. Nadie ha escuchado el audio: está verificado con medidas, no de oído.

Higgsfield y ElevenLabs no se pudieron usar: el plan gratuito de Higgsfield bloquea el vídeo y el conector de ElevenLabs no tiene permisos.

## Render

```sh
cd promo
npm run render:miniatura
npm run render:miniatura:en
```
