# Reddit · r/homeassistant (condicional)

Secundario frente al foro. Publica Xus a mano, martes 27/10 a las 15:00 Madrid (14:00 UTC, 10:00 EDT), **solo si** las reglas leídas con sesión iniciada el 26/10 lo permiten. Borrador sin aprobar.

## Estado de las reglas: sin verificar

El 17/10 no se pudo leer ninguna regla de r/homeassistant. Reddit bloquea las lecturas sin sesión: `rules.json` devuelve una página HTML, `old.reddit.com` da 403 y WebFetch está bloqueado. Los buscadores tampoco devolvieron copias. Este kit **no afirma nada** sobre autopromoción, flairs, vídeo, karma o IA en ese subreddit.

Comprobar el 26/10 con la sesión de u/flix_md (perfil Reddit documentado en el kit principal):

- [ ] Reglas completas del sidebar y wiki: autopromoción, proporción de contenido propio, posts de proyectos/apps de terceros, día o hilo semanal obligatorio, vídeo, contenido hecho con IA.
- [ ] Flairs disponibles al crear el post. Elegir el que describa un proyecto o software propio; si ninguno encaja, el más neutro. No inventar uno.
- [ ] Requisitos de cuenta (antigüedad, karma, email verificado). u/flix_md tenía 0 karma local en r/macapps el 13/10; su karma en r/homeassistant es desconocido.
- [ ] Si las reglas son ambiguas, escribir a modmail antes de publicar y esperar respuesta. No publicar «a ver si pasa».

Norma general de Reddit, citada por fuentes secundarias porque el centro de ayuda devolvió 403: el contenido debe ser auténtico y en comunidades en las que tienes interés personal, sin manipulación de votos. La guía «9:1» de autopromoción es una costumbre, no una regla oficial. Las reglas del subreddit mandan.

Si la cuenta solo ha publicado promoción, el riesgo de retirada es alto. **Si se retira: no repostear, no usar otra cuenta.** El foro de Home Assistant sigue siendo el canal principal.

## Post

Tipo: **post de vídeo nativo** con `altillo-casa-en.mp4` (16:9, 24 s) si las reglas admiten vídeo. Si no, post de texto con el enlace de YouTube. El texto va en el cuerpo, o como primer comentario del autor si el formato de vídeo no admite cuerpo.

Título:
```text
I made a free, open-source Mac app that puts Home Assistant in the MacBook notch
```

Alternativa:
```text
Home Assistant in my Mac's notch: lights, blinds, scenes and a doorbell peek (free, MIT, macOS 26+)
```

Cuerpo:
```text
I'm Xus, the developer. Altillo is a free, MIT-licensed macOS app that lives in the notch (or a virtual island on displays without one). Version 0.11.0 adds a Home section, in beta, that talks directly to Home Assistant on your network. No account, no Altillo server, no analytics. macOS 26+ only. It's an independent project, not affiliated with Home Assistant.

What works today: lights (click to toggle, drag to dim, tiles glow in the bulb's colour), switches, fans (on/off), covers with position, scenes and scripts, a sensor row, rooms from your areas, and a doorbell peek with a camera snapshot. It finds your instance on the network and signs in with Home Assistant's own login page (OAuth + PKCE); the resulting long-lived token stays in the macOS Keychain. Plain http only on the LAN; remote needs https.

Not yet: climate, locks, alarm, garage door control, media players, live camera, multiple servers, iPhone. Apple Home on the Mac only through Shortcuts, and that's still "coming soon".

The video uses the app's demo home; the doorbell picture is an illustration.

Download: https://altillo.app/
Code: https://github.com/XusBadia/altillo

I'd like to hear where discovery or sign-in fails (reverse proxies, custom ports, self-signed certs) and which entities look wrong.
```

Respuestas: usar la tabla de [HA-FORUM.md](HA-FORUM.md#respuestas-de-referencia), adaptada y escrita por Xus.

## Otros subreddits: no recomendados esta semana

| Subreddit | Motivo |
|---|---|
| r/macapps | Bloqueado según el kit principal: 10 de karma local mínimo (u/flix_md tenía 0) y una promoción cada 30 días, aunque se borre. Si Altillo se publicó allí el 22/10, la siguiente promoción no puede ser antes del 21/11. Para desarrolladores sin «trust signal» (repo GitHub de 1 año y 100+ estrellas), la vía es el megathread «The App Pile» en formato PCP. El repo es del 20/09/2026 y tiene 0 estrellas, así que no tiene esa señal |
| r/selfhosted | Según capturas de mirrors (no la web oficial), los proyectos de menos de 3 meses van al megathread semanal «New Project» o al viernes. Además, una app de Mac no es software autoalojado. No publicar el martes |
| r/smarthome, r/HomeKit | Reglas no verificadas. r/HomeKit es poco adecuado: Altillo no usa HomeKit en el Mac |
| r/homeautomation | Una captura indica que los anuncios de empresas necesitan permiso de los moderadores. Sin verificar; omitir |
| r/MacOS | Developer Saturday con requisito de repo establecido, no demostrado (ver kit principal). Omitir |
