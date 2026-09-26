# La puerta — nueva película de marca

Estado: tres clips generados con las herramientas nativas de Grok Imagine mediante Grok Build CLI. Montaje: `videos/altillo-la-puerta.mp4`. La pieza anterior se conserva por separado.

## Dirección

Una puerta de roble diminuta en el notch de un Mac abre un desván cálido. La cámara entra; los papeles vuelan y encuentran su sitio. Volvemos al Mac y la puerta se cierra. Cierre con el icono canónico 11A, sin regenerar su geometría.

28 segundos: tres planos de 8 segundos y cierre de marca de 4 segundos. Imágenes creadas con imagegen integrado; animación y sonido generados por la herramienta nativa `image_to_video` de Grok Build. Fuentes de 10 segundos, 1264×720, H.264 a 24 fps; montaje a 1920×1080 y 30 fps. El vídeo fuente está reescalado, no es 1080p nativo. Textos e icono compuestos en Remotion a 1080p.

Texto aprobado: «Tu Mac ya tenía un altillo. Solo le faltaba una puerta.» Cierre: «Un sitio arriba para lo importante.» El concepto está también guardado en `../brand-context.md` para marketing y web.

## Arte y prompts

- `public/film/01-door.png`: macro cinematográfico horizontal de un portátil de aluminio grafito en un escenario oscuro cálido; puerta diminuta de roble integrada en el notch, luz ámbar bajo la puerta, carpetas kraft y papel marfil, materiales físicos y ninguna interfaz o letra generada.
- `public/film/02-attic.png`: interior de desván miniatura artesanal, vigas de nogal y suelo de roble, estantes con carpetas kraft, bombilla cálida, tres papeles levitando, lente macro y polvo iluminado; sin personas, texto ni logotipos.
- Prompts de animación exactos y referencias de medios: `film-production.json`.

## Producción

La ruta inicial de Higgsfield estaba bloqueada por su requisito de plan. Se resolvió usando el CLI Grok ya autenticado, sin contratar nada ni usar una API externa de pago. Sesión reproducible: `01a0be37-2fca-7420-a6bd-c5be228cbea3` (`grok export` muestra los prompts ejecutados).

Los archivos devueltos tenían nombres intercambiados; se identificaron por sus fotogramas y corrigieron antes del montaje. Originales sin modificar en `public/film/source/`. Apertura acelerada 1,10× y cortada a 8 s, desván y retorno a 1,25× y 8 s. Audio normalizado a objetivo −19 LUFS y pico −2 dBTP por plano, con fades anti-click en montaje. El cierre de marca queda en silencio.

Render desde `promo`:

```sh
npx remotion render src/index.ts AltilloLaPuerta videos/altillo-la-puerta.mp4 --codec=h264 --crf=16 --audio-codec=aac
```
