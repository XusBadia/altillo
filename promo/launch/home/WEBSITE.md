# altillo.app · propuesta de sección Home / Casa

**Solo propuesta.** No se ha tocado `website/` ni desplegado nada. Revisado contra `~/Developer/altillo-h2/website` (rama `release/home-0.11.0`) el 17/10.

## Dónde va

Estructura actual de `index.html`: hero `#hero` → demo interactiva `#features` («See it in action», chips Shelf…Drawer) → bento «Everything up there.» → `#aurio` → cierre `#open-source`. La web no tiene ningún `<video>` hoy.

**Propuesta: una sección propia `#home` entre el bento y `#aurio`** (línea ~651 de `index.html`, mismo sitio en `es/index.html`).

- No se mete en la demo interactiva: esa demo simula módulos en HTML, y Casa necesitaría su propia maqueta. Para el día 27 basta el vídeo real; un chip «Home» en la demo puede llegar después.
- No va dentro del bento: Casa es opt-in y beta, así que conviene que tenga su propio titular y sus límites a la vista.
- Va antes de Aurio para que el producto quede antes de la promoción cruzada.

Opcional: un enlace «Home» / «Casa» en la navegación si existe una barra de anclas. No añadir una insignia «New» que luego haya que quitar a mano.

## Vídeo

```html
<video class="home__video" autoplay muted loop playsinline preload="none"
       poster="/media/altillo-casa-en.jpg" aria-describedby="home-video-desc">
  <source src="/media/altillo-casa-en.mp4" type="video/mp4">
</video>
<p id="home-video-desc" class="visually-hidden">…alt text de SOCIAL.md…</p>
```

- EN usa `altillo-casa-en.mp4` y su póster; ES usa `altillo-casa.mp4` y `altillo-casa.png`.
- **Peso:**
  - Los MP4 pesan 14 MB. Para la web, recodificar una copia de 1280×720 a 30 fps (orientativo, unos 3–4 MB; no medido) y convertir el póster a JPG/WebP.
  - `preload="none"` con póster evita descargar el vídeo antes de que se vea.
  - Arrancarlo con el `IntersectionObserver` que ya usan las animaciones de la página, si existe.
- **Reducir movimiento:** con `prefers-reduced-motion: reduce`, sin `autoplay`. Mostrar el póster con controles.
- **Sonido:** silenciado. El vídeo depende del texto en pantalla, no del audio.
- **Rótulo de 13–16 s:** ya corregido a «Straight from your Home Assistant.» / «Desde tu Home Assistant.» en los cuatro MP4 ([COPY-REVIEW.md](COPY-REVIEW.md#vídeo)).

## Copy EN

```text
Eyebrow:  Home · beta
Title:    Home Assistant, in your notch.
Lede:     Your lights, blinds and scenes as switch plates that glow in each bulb's real colour. Click to switch, drag to dim, and when the doorbell rings, the notch shows who's there.

Three points:
  Finds your server.   Altillo looks for Home Assistant on your network and signs in with its own login page. No token to copy.
  Stays at home.       Your Mac talks directly to your Home Assistant, on your network or at your https address. The token lives in your Keychain. No Altillo server.
  Make it yours.       Rooms from your areas, your own pages, names, icons and sizes. Altillo picks up to eight to start.

Small print: Beta. Lights, switches, fans, blinds, scenes, scripts and sensors. Climate, locks and a live camera aren't supported yet. Other ecosystems (Hue, Matter, Google Home, Alexa) work through Home Assistant. Altillo is not affiliated with Home Assistant.
CTA:      Download Altillo   ·   How Home handles your data → /privacy/#home
```

## Copy ES

```text
Antetítulo: Casa · beta
Título:     Tu casa, en el notch.
Entradilla: Tus luces, persianas y escenas como placas de interruptor que brillan con el color real de cada bombilla. Un clic para encender, un arrastre para atenuar y, cuando suena el timbre, el notch te enseña quién es.

Tres puntos:
  Encuentra tu servidor. Altillo busca Home Assistant en tu red e inicia sesión con su propia página de acceso. Sin copiar tokens.
  Se queda en casa.      Tu Mac habla directamente con tu Home Assistant, en tu red o en tu dirección https. El token vive en tu Llavero. Sin servidores de Altillo.
  A tu manera.           Estancias de tus áreas, páginas propias, nombres, iconos y tamaños. Altillo elige hasta ocho para empezar.

Letra pequeña: Beta. Luces, interruptores, ventiladores, persianas, escenas, scripts y sensores. Aún sin clima, cerraduras ni cámara en directo. Otros ecosistemas (Hue, Matter, Google Home, Alexa) funcionan a través de Home Assistant. Altillo no está afiliada a Home Assistant.
CTA:        Descargar Altillo   ·   Cómo trata Casa tus datos → /es/privacidad/#casa
```

**Imprescindible:**
- «Home Assistant» siempre completo.
- Sin logo de Home Assistant ni la frase «Works with Home Assistant».
- Mantener la línea de no afiliación.

«Quién es» y «who's there» describen una foto fija del timbre, no vídeo en directo; no cambiarlo por «mira en directo».

## Ajuste de privacidad (antes del día 27)

La sección «Home (optional)» de la rama todavía no está en producción: el 17/10, `https://altillo.app/privacy/` no la contiene. Desplegarla es una dependencia del lanzamiento.

Su texto dice «the Home Assistant address **you type**». Desde H2, Altillo también busca servidores en la red y abre el inicio de sesión de Home Assistant en el navegador. Propuesta de frases sustitutas, sin cambiar lo demás:

EN:
```text
Home is off until you turn it on and connect it. To find a server, Altillo looks for Home Assistant on your local network (Bonjour and homeassistant.local); macOS asks for Local Network access first. Altillo then talks only to the Home Assistant address you connect to, directly from your Mac over your network or your own https URL. Signing in opens your Home Assistant's own login page in your browser and creates an access token named after your Mac. The token is stored in the macOS Keychain and never leaves your Mac except to authenticate with your own server. […] Disconnecting deletes the token from your Mac; to revoke it, delete it in your Home Assistant profile.
```

ES:
```text
Casa está desactivada hasta que la activas y la conectas. Para encontrar un servidor, Altillo busca Home Assistant en tu red local (Bonjour y homeassistant.local); antes, macOS pide permiso de red local. Después, Altillo se comunica solo con la dirección de Home Assistant a la que te conectas, directamente desde tu Mac por tu red o por tu propia URL https. Al iniciar sesión se abre la página de acceso de tu Home Assistant en el navegador y se crea un token con el nombre de tu Mac. El token se guarda en el llavero de macOS y no sale de tu Mac salvo para autenticarse con tu propio servidor. […] Al desconectar se borra el token de tu Mac; para revocarlo, bórralo en tu perfil de Home Assistant.
```

`[…]` = conservar las frases actuales sobre entidades en memoria, favoritos, instantáneas del timbre y la ausencia de servidor. Añadir `id="home"` / `id="casa"` a esas secciones para los enlaces del CTA.
