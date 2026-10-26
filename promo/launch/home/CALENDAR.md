# Calendario operativo · Casa / Home · 22 oct – 2 nov de 2026

Zona del usuario: **Europe/Madrid**. Desde el domingo 25/10 rige **CET, UTC+1**. EE. UU. sigue en horario de verano hasta el domingo 1/11: el martes 27 Nueva York es **EDT, UTC−4** y Los Ángeles **PDT, UTC−7**. Esa semana Madrid y Nueva York están a 5 h, no a 6. Comprobado con `date` del sistema el 17/10.

Preparación del 26/10 **autorizada por Xus**: 0.11.0 publicada, privacidad desplegada y vídeos no listados subidos. El anuncio del 27/10 queda pendiente de comprobaciones manuales y visto bueno final; hay un recordatorio en este hilo el 27/10 a las 13:20 Madrid (12:20 UTC), que se elimina tras ejecutarse. Las publicaciones no están programadas; el [ICS](home-launch.ics) es una agenda local que no publica, no reserva nada ni crea borradores en ninguna plataforma. Las horas son ventanas de trabajo elegidas para poder responder en directo, no horarios óptimos demostrados.

## Por qué el martes 27

- La semana principal (Peerlist 19, PH 20, HN/Reddit/directorios hasta el 25) queda cerrada. Casa no compite con su propio lanzamiento ni diluye el seguimiento del 25.
- El lunes 26 Aurio tiene su plaza de TinyLaunch ([CHANNELS](https://github.com/XusBadia/altillo/blob/main/promo/launch/CHANNELS.md)); el martes deja ese día limpio y da un día de margen para publicar 0.11.0 y comprobar el cask.
- El lunes 2/11 entra TinyLaunch de Altillo: Casa tiene cinco días para recoger feedback antes, y esa ficha puede mencionar Home ya publicada.
- Hora del post principal, **14:00 Madrid / 13:00 UTC / 09:00 EDT**: tarde europea y mañana de la costa este a la vez, y Xus disponible cuatro horas seguidas para responder. Las guías de «mejor hora» de Reddit que se encontraron son blogs de proveedores sin método publicado ([SOURCES](SOURCES.md)); no se usan como prueba.

## Dependencias (bloqueantes)

Nada del día 27 sale si falla alguna. Si el 26 a las 18:00 no está todo, se mueve el bloque entero al **miércoles 28** a la misma hora, sin anunciar fecha.

1. **0.11.0 publicada de verdad**: `script/release.sh 0.11.0 --publish` desde un worktree limpio (el tag solo no publica), release **Latest** con DMG, appcast actualizado.
2. **Cask actualizado**: `script/update-cask.sh 0.11.0`, commit y push; `brew upgrade --cask altillo` instala 0.11.0.
3. **Privacidad en la web pública** con la sección «Home (optional)» EN y ES (existe en la rama `release/home-0.11.0`; tiene que estar desplegada en altillo.app). Ver la corrección propuesta en [WEBSITE.md](WEBSITE.md).
4. **Vídeos de YouTube subidos** (no listados) EN y ES, con el rótulo de 13–16 s ya corregido a «Straight from your Home Assistant.» / «Desde tu Home Assistant.» ([COPY-REVIEW.md](COPY-REVIEW.md#vídeo)).
5. **Cuenta del foro de Home Assistant** creada por Xus con su identidad real y leída la categoría. Ver [HA-FORUM.md](HA-FORUM.md).

## Preparación

| Fecha | Madrid | UTC | Tarea y salida comprobable |
|---|---|---|---|
| Jue 22 | 19:00 | 17:00 | Xus crea (o recupera) su cuenta en community.home-assistant.io y lee de verdad algunos hilos de *Share your Projects!*; sin publicar nada. Anotar nivel de confianza |
| Vie 23 | 10:00 | 08:00 | Decidir rótulo del vídeo (re-render o no) y copy de este kit; aprobación de Xus |
| Lun 26 | 10:00 | 09:00 | Publicar 0.11.0 + cask + appcast (dependencias 1–2). Comprobar actualización 0.10.7 → 0.11.0 por Sparkle en un Mac real |
| Lun 26 | 12:00 | 11:00 | Desplegar privacidad (y sección Home de la web, si se aprueba). Releer EN y ES en producción |
| Lun 26 | 13:00 | 12:00 | Subir los dos vídeos de YouTube como **no listados** ([YOUTUBE.md](YOUTUBE.md)); copiar URL completa |
| Lun 26 | 17:00 | 16:00 | Releer reglas: r/homeassistant con sesión iniciada (no verificadas en este kit), foro HA, X/LinkedIn. Guardar baseline de descargas DMG |
| Lun 26 | 18:00 | 17:00 | **Go/no-go.** Si falta una dependencia, todo pasa al miércoles 28 |

## Día de lanzamiento · martes 27/10

| Madrid | UTC | EDT | Plataforma / acción | Qué publicar o revisar |
|---|---|---|---|---|
| 09:00 | 08:00 | 04:00 | GitHub / web | Release v0.11.0 sigue Latest; DMG descarga; altillo.app y privacidad sirven bien; cask OK |
| 13:30 | 12:30 | 08:30 | YouTube | Pasar EN y ES a **públicos**; comprobar reproducción sin sesión |
| **14:00** | **13:00** | **09:00** | **Foro de Home Assistant** · *Share your Projects!* | [HA-FORUM.md](HA-FORUM.md): post principal, ≤ 1 vídeo y ≤ 2 enlaces si la cuenta es nueva |
| 14:10 | 13:10 | 09:10 | Foro HA | Primera respuesta propia con web, release y privacidad (si el límite de enlaces lo impidió en el post) |
| 15:00 | 14:00 | 10:00 | r/homeassistant, **condicional** | [REDDIT.md](REDDIT.md); solo si las reglas leídas el 26 lo permiten. Si no, se omite |
| 15:30 | 14:30 | 10:30 | X y LinkedIn | [SOCIAL.md](SOCIAL.md): X en EN, LinkedIn en ES (una lengua por perfil) |
| 14:00–18:00 | 13:00–17:00 | 09:00–13:00 | Foro, Reddit, X, LinkedIn | Respuestas humanas con la FAQ como referencia; registrar bugs en GitHub Issues |
| 21:00 | 20:00 | 16:00 | Foro HA | Segunda ronda de respuestas (tarde de EE. UU.). No reflotar el hilo |

## Seguimiento

| Fecha | Madrid | UTC | Tarea |
|---|---|---|---|
| Mié 28 | 10:00 | 09:00 | Discord oficial de Home Assistant, **condicional**: el canal de autopromoción existe según un anuncio de moderación, pero sus reglas no son públicas. Leer reglas dentro del servidor; si permiten apps de terceros, mensaje corto de [SOCIAL.md](SOCIAL.md#discord). Si no, omitir |
| Mié 28 | 10:00–12:00 | 09:00–11:00 | Foro HA | Responder lo pendiente; si sale un parche (0.11.1), anunciarlo como respuesta en el hilo, no como tema nuevo |
| Jue 29 | 18:00 | 17:00 | X y LinkedIn | Follow-up (timbre / feedback concreto) de [SOCIAL.md](SOCIAL.md) |
| Dom 1/11 | 18:00 | 17:00 | Cierre | Descargas DMG frente al baseline, enlaces reales, bugs abiertos. Sin cifras inventadas |
| Lun 2/11 | 09:00 | 08:00 | TinyLaunch (ya reservado para Altillo, medianoche PT = 08:00 UTC tras el cambio de hora de EE. UU. del 1/11) | Si la ficha se puede editar antes de su aprobación, añadir una línea sobre Home beta. No crear otra ficha |

## Plan si un canal falla

- **0.11.0 no publicada o cask roto:** no se publica nada; todo al miércoles 28.
- **Foro: post retenido para revisión** (los sistemas antispam de Discourse retienen a cuentas nuevas): esperar a moderación, no repostear ni abrir otro tema. Si un moderador lo mueve de categoría, aceptarlo.
- **r/homeassistant no permite el post o lo retira:** no repostear ni usar otra cuenta; el foro es el canal principal.
- **Pregunta frecuente que el kit no cubre:** responder con hechos del código; si es un bug, issue en GitHub y enlazarlo.
