# Vídeo promocional de Altillo

Pieza horizontal de 33 segundos creada con Remotion. La dirección mezcla stop motion de recortes, fotografías impresas de la interfaz y el lenguaje cálido de «Desván».

## Idea

> **Tu Mac ya tenía un altillo.**<br>
> **Solo le faltaba una puerta.**

El vídeo convierte esa frase en una acción literal: el notch cae sobre un Mac de papel, aparece una puerta y la luz del altillo se enciende. A partir de ahí, los archivos suben, el uso de IA se convierte en un dial físico y los agentes llaman a la puerta.

La idea también está registrada en [`../brand-context.md`](../brand-context.md) como hero recomendado para futuras campañas y para la web.

## Dirección de movimiento

- Máster a 30 fps con posiciones cuantizadas a 12 fps.
- Variaciones deterministas de posición y rotación por fotograma.
- Bordes irregulares, cinta, sombras duras y textura de papel.
- Barridos de cartulina entre escenas.
- Fotografías del prototipo en lugar de una grabación de navegador.
- Ensamblaje final de las tres capas del icono adaptativo, que resuelve en el máster 11A actualizado.
- Banda sonora original sintetizada localmente; no usa música ni efectos de terceros.

## Guion

1. Un Mac de papel recibe su notch.
2. «Tu Mac ya tenía un altillo.»
3. La puerta se abre: «Solo le faltaba una puerta.»
4. Shelf: los archivos suben y aterrizan arriba.
5. Uso de IA: el dial avanza hasta el 85 %.
6. Agentes: una mano llama y aparecen Denegar / Permitir.
7. El icono nuevo se construye por capas.
8. «Un sitio arriba para lo importante.»

## Investigación aplicada

- [Remotion: fundamentos](https://www.remotion.dev/docs/the-fundamentals): la composición se define como React + duración + fps + tamaño.
- [Remotion: animación](https://www.remotion.dev/docs/animating-properties): todo el movimiento depende de `useCurrentFrame()`; no hay animaciones CSS durante el render.
- [Remotion: recursos estáticos](https://www.remotion.dev/docs/staticfile): iconos, capturas y audio se sirven desde `public/`.
- [Synima: paper cut-out stop motion](https://www.synima.com/case-study/fdi-be-proud-of-your-mouth/): contraste entre recortes planos y objetos con profundidad.
- [Creative Bloq: producción stop motion](https://www.creativebloq.com/art/animation/8-practical-lessons-for-making-stop-motion-animation): cámara cenital, luz direccional, sombras y coherencia entre micro-movimientos.

## Archivos

- `src/AltilloStopMotion.tsx`: composición completa y dirección de movimiento.
- `src/Root.tsx`: formato 1920×1080, 30 fps, 990 fotogramas.
- `public/icon/`: máster 11A y capas del icono adaptativo.
- `public/ui/`: capturas del prototipo usadas como fotografías impresas.
- `public/audio/score.m4a`: banda sonora original.
- `videos/altillo-promo.mp4`: máster final.
- `videos/altillo-promo.png`: imagen de portada.

## Trabajar con la pieza

```sh
cd promo
npm install
npm run studio
```

Render final:

```sh
npm run render
npm run still
```
