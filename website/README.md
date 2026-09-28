# Web de Altillo

La web de producción vive en **[altillo.app](https://altillo.app/)**.

Web en inglés (`/`) y español (`/es/`): una sola página con el notch del héroe que se abre en el Estante, una demo interactiva fija que avanza con el scroll (pausable al tocarla, con «Reanudar»), un bento de módulos, principios, la tarjeta de Aurio y un cierre que apaga la luz. Incluye huevos de pascua, modo noche, estilos de impresión y alternativas sin JavaScript o sin demo. Es el prototipo `lab/b2/` pasado a producción; `lab/` se conserva como registro y no se publica.

## Desarrollo

Desde la raíz del repositorio:

```sh
cd website
npm ci
npm run dev
```

Abre la dirección local que indique Vite.

## Compilación y vista previa

```sh
npm run build
npm run preview
```

La compilación genera `dist/index.html`, `dist/es/index.html` y las dos páginas de privacidad, con CSS, JS y la textura de madera con hash en `dist/assets/`. La vista previa sirve ese resultado para revisarlo antes de publicar.

## Pruebas de navegador

Instala Chromium y WebKit para Playwright la primera vez:

```sh
npx playwright install chromium webkit
npm test
```

La configuración compila la web y la sirve con `vite preview` en el puerto 4174. Hay cuatro proyectos: Chrome y Safari de escritorio a 1440 px, y iPhone 13 (390 px) con Chromium y con WebKit. En CI: `npm test -- --workers=1`.

## Estructura

- `index.html` y `es/index.html`: la misma página en inglés y español. El script lee `<html lang>` para localizar la demo y los huevos.
- `privacy/index.html` y `es/privacidad/index.html`: política de privacidad (`src/privacy.css`).
- `src/kit/notch.css` y `src/kit/wood.webp`: el kit del notch (`.an-*`).
- `src/demo/`: la demo (`demo.js`, `demo.css`). Si la página no enlaza sus hojas (marcadores `--an-kit`/`--dm-kit`), las inyecta desde las URL que genera Vite.
- `src/eggs/`: el motor de huevos de pascua (`eggs.js`, `eggs.css`).
- `src/site.css` y `src/site.js`: composición, movimiento ligado al scroll, demo guiada y dos huevos propios (polilla y visita completa).
- `public/`: iconos, `og.png`, música de la demo y mascota de Aurio.
- `tests/`: Playwright contra la compilación (`vite build` + `vite preview`), en Chromium y WebKit, escritorio (1440 px) y móvil (390 px).

La demo y los huevos usan solo datos de ejemplo; nada sale de la página salvo los enlaces a GitHub y Aurio.

## Procedencia de los recursos

Se creó una ilustración de la mascota oficial de Aurio para la sección de apoyo.

| Recurso servido | Origen |
| --- | --- |
| `public/altillo-icon.png` | Versión de 128 px del máster canónico: `../Apps/Shared/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png` |
| `public/media/aurio-mascot.webp` | Nueva ilustración de la mascota oficial de Aurio: un dragón naranja sobre un baúl, con fondo transparente |

La ilustración de Aurio se incluye localmente, sin depender de imágenes remotas. Los iconos del kit son de Phosphor Icons (licencia en `public/phosphor-LICENSE.txt`).

## Publicación

Aloja el contenido de `dist/` en un hosting estático. Configura `website/` como directorio del proyecto, `npm run build` como comando y `dist/` como salida. Si sirves desde un subdirectorio, ajusta `base` en Vite y verifica las rutas de recursos antes de publicar.

Estos comandos preparan los archivos; no publican la web. La sección final enlaza a [Aurio](https://www.aurioapp.com) para quienes quieran apoyar el desarrollo probando la otra app del equipo.

`vercel.json` mantiene `https://altillo.app/appcast.xml` como URL pública estable
del feed de Sparkle y lo sirve desde el origen publicado en GitHub Pages.
