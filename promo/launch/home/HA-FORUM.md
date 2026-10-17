# Foro de la comunidad de Home Assistant · post de lanzamiento

Canal principal del lanzamiento de Casa. Publica **Xus con su cuenta personal**, a mano, el martes 27/10 a las 14:00 Madrid (13:00 UTC, 09:00 EDT). Borrador sin aprobar; nada publicado. Fuentes en [SOURCES.md](SOURCES.md) (acceso 17/10/2026).

## Dónde

- **Categoría: «Share your Projects!»** (id 9). Descripción oficial: *«Show off the cool projects, automations and configurations you made with Home Assistant!»*. Tres de las cuatro apps de Mac para Home Assistant publicadas en 2026 (Itsyhome, HomeOtter, Peek) usaron esta categoría; HomeBar/HomeGlance fue a *Dashboards & Frontend*.
- No usar sus subcategorías (*Custom Integrations*, *Dashboards & Frontend*, *Themes*, *Scripts*): Altillo no es nada de eso.
- Alternativa si un moderador lo mueve: **Mobile Apps** (id 40), cuya descripción admite apps de terceros (*«both official (Home Assistant Companion) and third party»*). Aceptar el cambio sin discutir.
- **No** «Social»: los moderadores la indican para servicios de pago y ventas; Altillo es gratis y MIT.
- **No** «Third party integrations»: es para integraciones dentro de Home Assistant.
- **Etiquetas:** opcionales. Usar solo etiquetas que el editor ofrezca ya (probables: `macos`, `apple`); no se pudo comprobar la lista ni si una cuenta nueva puede crear etiquetas. No inventarlas.

## Cuenta nueva: límites que condicionan el post

La configuración real de Discourse del foro no es pública. Lo verificable:

| Límite | Fuente | Aplicación |
|---|---|---|
| **2 enlaces por post** para usuarios nuevos | Usuario del foro: *«new users can only post 2 links in a post»*; coincide con el valor por defecto de Discourse | El post lleva solo YouTube + GitHub. Web y privacidad, en la primera respuesta |
| **1 medio incrustado** (imagen u onebox de vídeo) | Valor por defecto de Discourse `newuser max embedded media - default 1`; otro usuario del foro: *«limited to a few images and links»* | Un único medio: el vídeo de YouTube EN como onebox. Sin capturas adicionales |
| **0 adjuntos** no-imagen | Valor por defecto de Discourse `newuser max attachments - default 0` | No subir el MP4 al foro |
| Spam/retención de cuentas nuevas | No publicado | Si queda en revisión, esperar; no repostear |

Comprobado en hilos reales: los autores de Itsyhome y Peek siguen en nivel de confianza 0 y pudieron crear el tema en *Share your Projects!* (Peek con una imagen y un enlace a GitHub).

Xus puede crear la cuenta el jueves 22 y leer hilos de verdad. Pasar a nivel 1 levantaría estos límites, pero sus requisitos en este foro no son públicos: **escribir el post para nivel 0 de todas formas**. No cambiar de nivel artificialmente.

## Títulos

Recomendado:
```text
Altillo: control Home Assistant from your Mac's notch (free, open source, macOS 26+)
```

Alternativas:
```text
Home Assistant in the MacBook notch: lights, blinds, scenes and a doorbell peek (free, MIT)
```
```text
I added Home Assistant to my open-source Mac notch app and would like your feedback
```

Por qué: plataforma, precio y licencia en el título. En MIDI-HA Bridge un lector se quejó de que el carácter propietario no estaba «at the TOP». «Home Assistant» completo, nunca «HA» en título ni texto propio (guía de marca).

## Post (EN)

Pegar en el editor Markdown del foro. `<YOUTUBE_EN_URL>` = URL completa del vídeo EN, sola en su línea para que Discourse la convierta en onebox. Las líneas entre `[[ ]]` son para que Xus las escriba o confirme con sus palabras; borrar los corchetes.

```markdown
Hi everyone. I'm Xus, a developer in Spain. I make Altillo, a free, open-source (MIT) macOS app that lives in the MacBook notch, or in a small virtual island on displays without one. Version 0.11.0 adds a **Home** section, in beta, that talks directly to Home Assistant on your network.

The essentials first: **macOS 26 or later only**. Free, MIT, no account, no Altillo server and no analytics. Signed and notarized. Altillo is pre-1.0, and Home is a beta. It's an independent project, not affiliated with or endorsed by Home Assistant or the Open Home Foundation.

<YOUTUBE_EN_URL>

The video uses Altillo's built-in demo home, not my house, and the doorbell picture is an illustration.

**What it does**

- **Lights:** click to toggle, drag across a tile to dim. Tiles glow in the bulb's actual colour. Hold a light (or right-click → Show Controls) for brightness, white temperature and eight colour presets.
- **Switches, input_booleans and fans** (on/off), and **covers** (drag to set the position; the detail view has Stop when the cover supports it).
- **Scenes and scripts** run with one click.
- **Sensors and binary sensors** in a compact row under the tiles.
- **Rooms:** chips from your areas, plus your own pages. Rename a tile, change its icon or size, hide it, reorder. It suggests up to eight favourites to start, and right-click → Open in Home Assistant takes you to the entity.
- **Doorbell:** pick an `event.*` or `binary_sensor` and, optionally, a camera. When it fires, the notch peeks out with a still snapshot from `camera_proxy`.
- **With the notch closed**, it can tell you that a door, window or garage sensor has been open for 10 minutes or more, or that lights are on while `zone.home` is 0.

**How it connects**

- It finds instances with zeroconf (`_home-assistant._tcp`) and by trying `homeassistant.local:8123`. macOS asks once for Local Network access.
- "Sign in with Home Assistant" opens your instance's own login page in your browser: OAuth 2 with PKCE and a loopback redirect on 127.0.0.1, so no external website is involved. Altillo then creates a long-lived token named "Altillo (your Mac's name)", which you'll see under Profile → Security, and keeps it in the macOS Keychain. You can paste your own long-lived token instead.
- WebSocket API with `subscribe_entities` limited to the entities on screen and in your peeks. No polling; one ping a minute while connected.
- Plain http only on the local network. Away from home it needs an https address that you enter. With a self-signed certificate, you trust it once and Altillo pins the fingerprint.

**Not there yet**, so nobody installs it expecting these:

- Climate, locks, alarm panels, garage door control and media players. Locks, alarms and garage covers are deliberately left out until there's a hold-to-confirm.
- A live camera stream (snapshot only).
- More than one Home Assistant server.
- Apple Home. HomeKit isn't available to Mac apps distributed outside the Mac App Store, so the plan there is scenes through Shortcuts; it's marked "coming soon" in the app. Devices you already bring into Home Assistant (HomeKit Controller, Matter, Hue…) show up like any other entity.
- An iPhone version.

[[One or two sentences in your own words: why the notch, and what you use it for. E.g. what you do ten times a day without wanting to open a dashboard.]]

[[Confirm or delete: I've been using it every day with my own Home Assistant (2026.9, around 250 entities).]]

The most useful feedback for me: entities that look wrong or are missing from a room, setups where discovery or sign-in fails (reverse proxies, custom ports, self-signed certificates), and things that shouldn't be a tile. Source code and issues: https://github.com/XusBadia/altillo

The download link and the privacy policy are in the first reply, because new accounts can only include two links per post.
```

Recuento: 2 enlaces (YouTube, GitHub) y 1 medio (onebox de YouTube). Las menciones `homeassistant.local:8123` y `camera_proxy` van en código para que no se conviertan en enlaces. Releer en la vista previa del editor: si muestra aviso de límite, quitar el enlace de GitHub y pasarlo a la respuesta.

## Primera respuesta propia (inmediatamente después)

```markdown
Links that didn't fit in the first post:

- Download (signed and notarized DMG, macOS 26+): https://altillo.app/
- Privacy policy, with a section on Home: https://altillo.app/privacy/

Once installed: Settings → Home, or the welcome screen. Home stays off until you turn it on.
```

Si la cuenta ya permite más enlaces, integrar estas dos líneas en el post y no publicar la respuesta.

## Si no se puede usar el vídeo

Sustituir la línea de YouTube por la imagen `altillo-casa-en.png` (subida, 1 medio) con este texto alternativo:
```text
Altillo's Home section open in the MacBook notch: eight switch-plate tiles for lights, a plug and a blind, two scene buttons and a sensor row.
```

## Respuestas de referencia

Una persona las adapta a la pregunta real. Sin respuestas automáticas.

| Pregunta | Respuesta (EN) |
|---|---|
| **Privacy / does anything leave my network?** | Altillo talks only to the Home Assistant address you connect to: on your LAN, or the https address you entered. There's no Altillo server, account or analytics. Entity names and states stay in memory; favourites (entity ids) are saved in Altillo's preferences on your Mac; doorbell snapshots are fetched only for the peek and never saved. Privacy policy: https://altillo.app/privacy/ |
| **Token vs sign-in?** | Both end the same way: one long-lived token in the macOS Keychain. "Sign in with Home Assistant" uses your instance's login page (OAuth 2 + PKCE, loopback redirect on 127.0.0.1) and then creates the token for you, named "Altillo (your Mac's name)". If you prefer, create a token yourself under Profile → Security → Long-lived access tokens and paste it. |
| **How do I revoke it?** | Disconnect in Settings → Home deletes the token from the Keychain and forgets favourites and the doorbell, but it doesn't delete the token in Home Assistant. Delete "Altillo (…)" under Profile → Security → Long-lived access tokens to revoke it. |
| **Remote access / Nabu Casa?** | Away from your network, Altillo needs an https URL for your instance; macOS blocks plain http outside the local network. Enter your remote https address in Settings → Home. I haven't tested Nabu Casa specifically yet, so a report would help. |
| **Self-signed certificate / reverse proxy?** | Self-signed: Altillo asks you to trust it once and pins the fingerprint. If a reverse proxy or a custom port breaks discovery or sign-in, please open an issue with the setup (no tokens or URLs you'd rather keep private). |
| **Which entities?** | Lights, switches, input_booleans, fans (on/off), covers, scenes, scripts, and sensors/binary sensors as readings. Not yet: climate, locks, alarm panels, garage door control, media players. |
| **Climate / locks when?** | Climate is next on my list. [[confirm order]] Locks, alarms and garage doors need a hold-to-confirm first; I'd rather not put them one stray click away. No dates yet. |
| **Live camera?** | Not yet. The doorbell peek shows a still snapshot taken when it rings. |
| **Apple Home / HomeKit?** | HomeKit isn't available to Mac apps outside the Mac App Store, so Altillo can't read Apple Home on the Mac. The plan is to run Home scenes through Shortcuts; it's marked "coming soon". Today, Altillo's Shortcuts section can already run any shortcut, including one that controls Home. If your accessories are in Home Assistant (HomeKit Controller or Matter), they work like any other entity. |
| **iPhone / iPad?** | No. Altillo is macOS only for now. |
| **Intel / older macOS?** | macOS 26 or later. [[Confirm for 0.11.0: the 0.10.6 DMG was universal, Apple Silicon + Intel.]] |
| **Price / licence / catch?** | Free, MIT, no account, no paid tier. The code is on GitHub. |
| **Why not open source as an integration / HACS?** | It isn't something that runs inside Home Assistant. It's a Mac app that uses Home Assistant's WebSocket API, so HACS doesn't apply. |
| **How is it different from Itsyhome / HomeOtter / HomeGlance / ha-menu?** | Those are menu bar apps, and good ones if that's what you want. Altillo lives in the notch and has other optional sections (file shelf, calendar, music, AI usage…). Home is one section you can turn on. |
| **Multiple instances?** | One server for now. |
| **Minimum Home Assistant version?** | I haven't set one. [[Confirm: tested with 2026.9 and 2026.10.]] If an older version fails, please tell me which. |
| **Is it AI-written?** | Answer honestly in your own words (the code was written with AI assistance; you designed, reviewed and tested it). Peek's author disclosed AI assistance in the same category without backlash. |
| **Bug report** | Please open an issue at https://github.com/XusBadia/altillo/issues with the Altillo version, macOS version and steps. Settings → About → Report a Problem also helps. No tokens, URLs or camera images needed. |

## Después del día 27

- Responder en el hilo. Si sale 0.11.1, anunciarlo como **respuesta en el mismo hilo** (Peek e Itsyhome lo hicieron así), no como tema nuevo.
- No reflotar el hilo sin novedad. La guía del foro: *«Doing that too much, or too quickly, can make you look entitled, and that will drive people away.»*
- Pedidos de función: agradecer y llevar a GitHub Issues, como hizo Itsyhome.

## Reglas comprobadas

- [x] Categoría adecuada (*«Use a relevant category»*, guía «How to help us help you»): *Share your Projects!*.
- [x] Sin regla publicada contra la autopromoción. La moderación envía lo comercial a *Social* y el Discord a su canal de autopromoción. Altillo es gratis y MIT, así que es un proyecto compartido, no una venta.
- [x] Código de conducta: sin requisitos específicos de promoción; se aplica *«Other conduct which could reasonably be considered inappropriate in a professional setting»*.
- [x] Límites de cuenta nueva: 2 enlaces y 1 medio, respetados.
- [x] Licencia, precio y plataforma en las primeras líneas.
- [x] Marca: «Home Assistant» completo. Sin «Works with Home Assistant», reservado a socios certificados. Sin logo: no está disponible para uso comercial sin permiso escrito de la Open Home Foundation. Aviso de independencia incluido.
- [x] No se piden likes ni votos; no hay cuentas alternativas.
- [ ] Releer el 26/10 la categoría y cualquier aviso fijado nuevo.
