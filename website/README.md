# Web de Altillo

Web en español (`/`) e inglés (`/en/`) para presentar Altillo y probar un escritorio Mac simulado. Usa HTML, CSS y JavaScript con Vite. No necesita servidor de aplicación ni base de datos.

La página abre con una secuencia cinematográfica del Mac y su puerta. El scroll controla el avance y el retroceso del vídeo, hasta entrar en el altillo y mostrar allí la explicación del estante. Después siguen tres capítulos interactivos, una escena del altillo y una sección compacta para conocer Aurio con su mascota oficial.

El selector ES/EN de la cabecera navega entre páginas estáticas y conserva el fragmento de la URL cuando lo hay. Cada página incluye su idioma, título, descripción y enlaces `hreflang`. La demo también cambia de idioma: controles, instrucciones, documentos de ejemplo, solicitudes y anuncios accesibles.

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

La compilación genera `dist/index.html` y `dist/en/index.html`, junto con los recursos compartidos. La vista previa sirve ese resultado para revisarlo antes de publicar.

## Pruebas de navegador

Instala Chromium y WebKit para Playwright la primera vez:

```sh
npx playwright install chromium webkit
npm test
```

La configuración arranca Vite en el puerto 4174 y contempla Safari de escritorio, Chrome de escritorio y móvil con Chromium. Las capturas de revisión visual también pueden hacerse con Chrome instalado mediante `channel: 'chrome'` si el Chromium incluido presenta problemas en el entorno local.

## Estructura

- `index.html` y `en/index.html`: contenido, navegación y secciones en español e inglés.
- `vite.config.js`: entradas de compilación para ambas páginas.
- `src/style.css`: composición responsive de la página.
- `src/demo.js` y `src/demo.css`: escritorio, notch, archivos y solicitudes simuladas.
- `src/demo-copy.js`: textos de la demo por idioma.
- `src/hero-film.js` y `src/hero-film.css`: escena fija durante el scroll y transición hacia la explicación del estante.
- `src/hero-sequence.js`: reproducción reversible de fotogramas WebP, con caché limitada y descarga por proximidad.
- `src/motion.js` y `src/motion.css`: entradas y coordinación de los capítulos con el scroll.
- `src/main.js`: montaje de la demo según el idioma del documento, movimiento y navegación entre idiomas.
- `public/`: imágenes, iconos y símbolo de Aurio servidos localmente.

## Interacción y límites

Hay un único escritorio, sin pestañas de demostración. Los capítulos recorren el estante, el consumo de IA y los agentes; el escritorio conserva sus archivos y resultados mientras se explora.

En escritorio, una pista invita a acercar el cursor al notch para abrirlo. En móvil, la pista permite tocar para abrir. El notch también dispone de botones para acceder al estante y al consumo.

Arrastra un documento desde Finder al notch y después desde el estante a Entregas. La implementación usa Pointer Events y captura del puntero. También puedes seleccionar un archivo y pulsar **Subir al estante** o **Llevar a Entregas**. Los botones funcionan con Tab y Enter/Espacio; Escape cancela el arrastre o cierra el panel. Los resultados se anuncian mediante una región de estado accesible.

El indicador del notch abre el consumo ficticio de Claude y Codex. La terminal permite pedir un permiso y probar Permitir o Denegar; no se ejecuta ningún comando. Reiniciar devuelve la demo al estado inicial.

Todo sucede con archivos y datos ficticios en memoria. La demo no abre ni sube archivos personales, no conecta cuentas y no envía solicitudes a servicios para realizar las acciones simuladas. La carga de la página solo necesita sus recursos estáticos. Los enlaces externos conducen a GitHub y Aurio.

El scroll es nativo. La película conserva los 24 fps de Grok, con 240 fotogramas en canvas y una suavización breve del avance visual, sin alterar el desplazamiento de la página. Se precargan imágenes comprimidas y se conservan solo 24 fotogramas decodificados, con hasta cuatro cargas simultáneas. Las descargas en curso no se cancelan al mover el scroll y las imágenes se reutilizan al retroceder. Con `prefers-reduced-motion: reduce` o ahorro de datos, se mantiene la imagen estática y no se descargan los fotogramas. Si falla la carga inicial, la explicación conserva su posición normal. El contenido permanece visible sin JavaScript, aunque la demo requiere activarlo.

Los iconos utilizan Lucide. `scripts/build-icons.mjs` genera un sprite SVG con los símbolos usados, durante `predev` y `prebuild`. Los iconos de la página funcionan también sin JavaScript. La licencia se sirve en `public/lucide-LICENSE.txt`.

El consumo de IA y los agentes son prototipos en desarrollo, no integraciones disponibles. La app requiere macOS 26 o posterior; la web no requiere macOS. GitHub permite consultar el proyecto mientras no haya una descarga publicada.

## Procedencia de los recursos

Se reutilizaron imágenes de marca de Altillo y se creó una ilustración de la mascota oficial de Aurio para la sección de apoyo.

| Recurso servido | Origen |
| --- | --- |
| `public/media/mac-door.webp` | `../promo/public/film/01-door.png`, convertido a WebP |
| `public/media/hero-sequence/` | 240 fotogramas a 24 fps de un vídeo de Grok; original y prompts documentados en `../docs/hero-film-production.md` |
| `public/media/attic.webp` | `../promo/public/film/02-attic.png`, convertido a WebP |
| `public/altillo-icon.png` | Versión de 128 px del máster canónico: `../Apps/Shared/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png` |
| `public/aurio-symbol.svg` | Símbolo oficial del repositorio vecino `aurio/apps/web/public/logo.svg` |
| `public/media/aurio-mascot.webp` | Nueva ilustración de la mascota oficial de Aurio: un dragón naranja sobre un baúl, con fondo transparente |

Las imágenes del Mac y del altillo ilustran el concepto de marca; no son capturas de la app. El símbolo y la ilustración de Aurio se incluyen localmente, sin depender de imágenes remotas.

## Publicación

Aloja el contenido de `dist/` en un hosting estático. Configura `website/` como directorio del proyecto, `npm run build` como comando y `dist/` como salida. Si sirves desde un subdirectorio, ajusta `base` en Vite y verifica las rutas de recursos antes de publicar.

Estos comandos preparan los archivos; no publican la web. La sección final enlaza a [Aurio](https://www.aurioapp.com) para quienes quieran apoyar el desarrollo probando la otra app del equipo.
