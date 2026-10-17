# Lanzamiento de Casa / Home · martes 27 de octubre de 2026

Preparado el 17/10/2026. **Borradores sin aprobar.** Nada se ha publicado, programado ni enviado. Formato y reglas iguales a los del kit principal (`promo/launch/` en `main`): afirmaciones comprobadas contra el código, reglas de cada canal desde fuentes primarias ([SOURCES.md](SOURCES.md)), sin cifras inventadas ni petición de votos.

**Orden recomendado: 0.11.0 publicada y cask actualizado el lunes 26 → martes 27: YouTube público 13:30 → foro de Home Assistant 14:00 → r/homeassistant 15:00 (condicional) → X y LinkedIn 15:30 → follow-up jueves 29 → cierre domingo 1/11.** Horas de Madrid (CET, UTC+1 desde el 25/10). Detalle, UTC/EDT y motivos en [CALENDAR.md](CALENDAR.md).

El canal principal es el **foro de la comunidad de Home Assistant** (lo pidió Xus y es donde estuvieron las apps de Mac comparables en 2026). Reddit es secundario y depende de reglas que este kit no pudo leer.

## Lo que se lanza

Altillo **0.11.0** con **Home (beta)**: Home Assistant en el notch del Mac. Gratis, MIT, nativa para macOS 26+, firmada y notarizada, pre-1.0. Sección opt-in (apagada hasta activarla).

Frase de marca: ES **«Tu casa, en el notch.»** · EN **«Home Assistant, in your notch.»**
Una línea para fichas y títulos (mecanismo primero): **«Control your Home Assistant lights, blinds and scenes from your Mac's notch.»** · ES: **«Controla las luces, persianas y escenas de tu Home Assistant desde el notch del Mac.»**

Qué hace, verificado en el código de `release/home-0.11.0` el 17/10:

- **Luces**: clic para encender/apagar, arrastrar en horizontal para atenuar; la baldosa brilla con el color real de la bombilla. Detalle: brillo, temperatura de blanco y 8 colores predefinidos (si la luz los admite).
- **Interruptores y enchufes** (`switch`, `input_boolean`) y **ventiladores** (solo encender/apagar).
- **Persianas** (`cover`): arrastrar para fijar la posición; detalle con posición y Parar si la persiana lo admite.
- **Escenas y scripts**: un clic.
- **Sensores** (`sensor`, `binary_sensor`): fila compacta de lecturas.
- **Estancias**: chips con las áreas de Home Assistant; una estancia muestra sus luces, persianas, interruptores, ventiladores, escenas y scripts.
- **Personalización**: Altillo propone hasta 8 favoritos; renombrar, icono, tamaño, ocultar, reordenar, páginas propias, clic derecho con «Abrir en Home Assistant».
- **Timbre**: una entidad `event.*` o `binary_sensor` hace asomar el notch con una **instantánea** de la cámara elegida (no vídeo en directo).
- **Notch cerrado**: aviso de puerta/ventana/garaje abierta 10 min o más, y de luces encendidas sin nadie en casa (`zone.home`).
- **Conexión**: busca Home Assistant en la red (mDNS `_home-assistant._tcp` y `homeassistant.local:8123`); inicio de sesión con la página de login del propio Home Assistant en el navegador (OAuth 2 + PKCE con redirección local) que crea un token de larga duración «Altillo (nombre del Mac)»; o pegar un token. El token va al Llavero.
- **Red**: directo entre el Mac y el Home Assistant del usuario; sin servidor de Altillo. `http` solo en la red local; fuera, una dirección `https` que pone el usuario. Certificados propios: confiar una vez y fijar la huella. Suscripción por eventos solo a las entidades vigiladas; un ping cada 60 s.

## Límites de lo que se puede decir

No decir, y corregir si aparece:

| No decir | Realidad en 0.11.0 |
|---|---|
| «Works with Home Assistant», «official», «for HA», logo de Home Assistant | El programa *Works with Home Assistant* certifica dispositivos de fabricantes; Altillo es un proyecto independiente. Escribir siempre «Home Assistant» completo, sin logo. Añadir «independent, not affiliated with Home Assistant or the Open Home Foundation» en foro, Reddit y YouTube |
| «Everything / anything in Home Assistant», «Todo lo que tengas en Home Assistant» | Solo luces, interruptores, enchufes, ventiladores (on/off), persianas, escenas, scripts y sensores. **Sin clima, cerraduras, alarma, garaje (control), media players** |
| Cámara «en directo», «stream» | Instantánea por `camera_proxy` al sonar el timbre, solo en memoria |
| Apple Home funciona | En la app pone «Muy pronto / Coming soon». Hoy un atajo de Casa puede ejecutarse desde la sección Atajos de Altillo, no como baldosa de Home. HomeKit no se puede usar en una app Mac con Developer ID fuera del Mac App Store |
| Hue/Google/Alexa/Matter «compatibles» | Solo **a través de Home Assistant** (lo que Home Assistant exponga como luz, interruptor, etc.) |
| Pregunta controla la casa, atajos de teclado por escena | No implementado |
| Varias casas / servidores | Un solo servidor |
| Nabu Casa / acceso remoto «sin configurar» | Fuera de casa hace falta una dirección `https` que el usuario escribe; no hay código específico de Nabu Casa ni se ha probado |
| «Desconectar revoca el token» | Desconectar borra el token del Llavero y los favoritos; el token sigue en el perfil de Home Assistant (Seguridad → Tokens de larga duración) hasta que el usuario lo borre |
| iPhone / iOS | No hay Home en iOS |
| Versión mínima de Home Assistant | No hay ninguna declarada ni comprobada |
| Más rápido, más ligero, mejor que X | Sin medición publicada; no comparar con Itsyhome, HomeOtter, HomeGlance, ha-menu ni House Control |
| «Beta» como etiqueta en la app | La app no lo dice; «beta» solo en notas de versión, README y posts |

Revisión completa y correcciones necesarias en otros textos (notas de 0.11.0, rótulo del vídeo, privacidad) en [COPY-REVIEW.md](COPY-REVIEW.md).

## Archivos

| Artefacto | Contenido |
|---|---|
| [CALENDAR.md](CALENDAR.md) | Preparación, día 27 y seguimiento; Madrid/UTC/EDT; plan B |
| [home-launch.ics](home-launch.ics) | Agenda importable con alarmas; importar es manual y no publica |
| [CHECKLIST.md](CHECKLIST.md) | Dependencias, día de lanzamiento, respuestas a incidencias, cierre |
| [HA-FORUM.md](HA-FORUM.md) | Post del foro de Home Assistant (EN), categoría, etiquetas, medios con límites de cuenta nueva, FAQ de respuestas, reglas comprobadas |
| [REDDIT.md](REDDIT.md) | r/homeassistant (condicional) y por qué no r/macapps, r/selfhosted, r/smarthome, r/HomeKit |
| [SOCIAL.md](SOCIAL.md) | X y LinkedIn ES/EN, lanzamiento y follow-up; vídeo por red; alt text; Discord condicional |
| [YOUTUBE.md](YOUTUBE.md) | Títulos, descripciones, capítulos y etiquetas EN/ES; declaración de contenido alterado |
| [RELEASE-NOTES.md](RELEASE-NOTES.md) | Cuerpo de la release 0.11.0 corregido frente al código |
| [WEBSITE.md](WEBSITE.md) | Propuesta de sección Home en altillo.app ES/EN, vídeo y ajuste de privacidad |
| [COPY-REVIEW.md](COPY-REVIEW.md) | Variantes puntuadas y comprobación de afirmaciones contra el código |
| [SOURCES.md](SOURCES.md) | Fuentes primarias y código, con fecha de acceso 17/10/2026 |

## Activos

En `~/Developer/altillo-h2/promo/videos/` (rama `release/home-0.11.0`, sin publicar). Comprobados con `ffprobe` el 17/10: 24,04 s, 60 fps, H.264 + AAC.

| Archivo | Formato | Uso |
|---|---|---|
| `altillo-casa-en.mp4` | 1920×1080, 14 MB | YouTube EN, foro HA (vía YouTube), Reddit, LinkedIn EN, web EN |
| `altillo-casa.mp4` | 1920×1080, 14 MB | YouTube ES, LinkedIn ES, web ES |
| `altillo-casa-vertical-en.mp4` | 1080×1920, 11 MB | X EN, Reels/Shorts si se usan |
| `altillo-casa-vertical.mp4` | 1080×1920, 11 MB | X ES |
| `altillo-casa-en.png` / `altillo-casa.png` | 1920×1080, fotograma 250 | Miniatura YouTube, póster web, imagen única del foro si no se usa el vídeo |

El vídeo usa la casa de demostración de la app (fotogramas reales de `NotchRootView`), no una casa real. La foto del porche es una ilustración SVG hecha a mano que tapa el degradado de la cámara de demostración; no hay imágenes generadas por IA. Decirlo si alguien pregunta. El rótulo de 13–16 s, que antes decía «Anything in Home Assistant / Todo lo que tengas en Home Assistant», ahora dice «Straight from your Home Assistant. / Desde tu Home Assistant.» ([COPY-REVIEW.md](COPY-REVIEW.md#vídeo)).

## Métrica

Igual que el lanzamiento principal: descargas del DMG de 0.11.0 en GitHub Releases entre el baseline del 26/10 y el 1/11. Es un indicador de descargas, no de usuarios. Las actualizaciones por Sparkle descargan el mismo activo, así que el contador mezcla instalaciones nuevas y actualizaciones de 0.10.x: no atribuirlo a Casa ni a un canal. Sin telemetría.

## Dependencias antes del 27

1. `script/release.sh 0.11.0 --publish` desde un worktree limpio (el tag solo no publica) y release **Latest**.
2. `script/update-cask.sh 0.11.0`, commit y push. No hay `brew install` público anunciado en README ni web: no mencionar Homebrew en los posts.
3. Privacidad «Home (optional)» desplegada en altillo.app EN y ES.
4. Vídeos subidos a YouTube como no listados, con el rótulo decidido.
5. Corregir `docs/releases/0.11.0.md` con [RELEASE-NOTES.md](RELEASE-NOTES.md) **antes** de publicar la release (el texto actual promete Apple Home por Atajos y «todo» en las estancias).
