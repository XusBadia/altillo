# Checklist · lanzamiento de Casa / Home

## Preparado localmente (17/10)

- [x] Copy del foro, de Reddit, de X/LinkedIn (ES/EN), de YouTube, notas de release y web en `promo/launch/home/`.
- [x] Afirmaciones auditadas contra `release/home-0.11.0` ([COPY-REVIEW.md](COPY-REVIEW.md)); límites en [README.md](README.md#límites-de-lo-que-se-puede-decir).
- [x] Reglas del foro de Home Assistant, guía de marca, Works with Home Assistant, HACS, awesome-home-assistant y YouTube revisadas ([SOURCES.md](SOURCES.md)).
- [x] Vídeos comprobados con `ffprobe`: 4 MP4 de 24,04 s, 60 fps; pósters revisados.
- [ ] Reglas de r/homeassistant y del Discord: **no verificadas**. Leerlas con sesión el 26/10.

## Decisiones de Xus antes del 23/10

- [ ] Aprobar el calendario (martes 27, 14:00 Madrid) o elegir otra fecha.
- [x] Rótulo de 13–16 s: cambiado a «Straight from your Home Assistant.» / «Desde tu Home Assistant.» y vueltos a renderizar los cuatro MP4 ([COPY-REVIEW.md](COPY-REVIEW.md#vídeo)).
- [ ] Rellenar o borrar los `[[ ]]` de [HA-FORUM.md](HA-FORUM.md): motivo personal, versión y tamaño de su Home Assistant, orden de lo siguiente (¿clima?), universal binary de 0.11.0.
- [ ] Confirmar las frases personales de [SOCIAL.md](SOCIAL.md) («lo que más uso», «mi parte favorita»).
- [x] Sustituir `docs/releases/0.11.0.md` por [RELEASE-NOTES.md](RELEASE-NOTES.md).
- [ ] Aprobar el ajuste de privacidad y, si se quiere, la sección web ([WEBSITE.md](WEBSITE.md)).
- [ ] Idioma por perfil: X en EN y LinkedIn en ES (propuesta) u otra combinación.

## Dependencias (lunes 26, go/no-go a las 18:00)

- [ ] `docs/releases/0.11.0.md` corregido y fusionado en `main`; CI verde en ese SHA.
- [ ] Tag `v0.11.0` y `script/release.sh 0.11.0 --publish` desde un worktree limpio (el tag solo no publica). Release **Latest** con `Altillo-0.11.0.dmg`.
- [ ] `https://altillo.app/appcast.xml` apunta a 0.11.0 (puede tardar unos minutos tras gh-pages).
- [ ] Actualización 0.10.7 → 0.11.0 por **Check for Updates…** en un Mac real; Home apagada por defecto y la bienvenida en orden.
- [ ] Prueba completa con Home Assistant real: descubrimiento, «Sign in with Home Assistant», token visible en Perfil → Seguridad, pegar token, timbre, desconectar.
- [ ] `script/update-cask.sh 0.11.0`, commit y push.
- [ ] Privacidad «Home (optional)» / «Casa (opcional)» **en producción** (el 17/10 aún no está).
- [ ] Vídeos de YouTube EN y ES subidos como no listados; URL completa copiada.
- [ ] Cuenta del foro de Home Assistant de Xus creada; anotar su nivel de confianza.
- [ ] Baseline de descargas:
  ```sh
  gh api --paginate repos/XusBadia/altillo/releases --jq '.[] | .assets[] | select(.name | endswith(".dmg")) | {id, name, download_count}'
  ```
  Registrar la fecha y hora UTC. Sparkle descarga el mismo DMG, así que el contador mezcla actualizaciones e instalaciones nuevas.

## Día 27

- [ ] 09:00 Release Latest, DMG, web y privacidad OK.
- [ ] 13:30 YouTube EN y ES públicos; reproducción sin sesión.
- [ ] 14:00 Foro: categoría *Share your Projects!*, título, ≤ 2 enlaces, 1 medio, vista previa revisada, sin `[[ ]]` sobrantes. Guardar la URL del tema.
- [ ] 14:10 Primera respuesta con descarga y privacidad (si hizo falta).
- [ ] 15:00 r/homeassistant solo si las reglas lo permiten; flair existente; guardar la URL.
- [ ] 15:30 X (vertical) y LinkedIn (16:9) con vídeo nativo y texto alternativo; una lengua por perfil.
- [ ] 14:00–18:00 y 21:00 Responder personalmente. Bugs a GitHub Issues con versión, macOS y pasos.
- [ ] No pedir likes ni votos, no reflotar, no usar cuentas alternativas, no repostear contenido retirado.

## Respuestas de referencia a incidencias

- **El inicio de sesión no vuelve a Altillo:** «¿Qué navegador y qué dirección usas (local o https remota, con proxy inverso o no)? Mientras tanto, puedes pegar un token de Perfil → Seguridad → Tokens de larga duración.»
- **No encuentra el servidor:** «¿Aceptaste el permiso de Red local de macOS? Si lo denegaste, está en Ajustes del Sistema → Privacidad y seguridad → Red local. También puedes escribir la dirección a mano.»
- **http remoto bloqueado:** «Fuera de tu red local, macOS y Altillo solo usan https. Escribe tu dirección https externa.»
- **Entidad que no aparece:** «En 0.11.0 hay luces, interruptores, ventiladores, persianas, escenas, scripts y sensores. ¿Qué dominio es? Si es uno de esos, abre un issue con el dominio y los atributos (sin tokens).»
- **Descarga rota:** comprobar primero el enlace y luego: «El enlace está fallando; la release y el código están en https://github.com/XusBadia/altillo/releases/latest».
- **Post retirado o retenido:** leer el motivo, contestar por el canal de moderación y no repostear.

## Cierre (domingo 1/11)

- [ ] Contadores finales del DMG frente al baseline, con su limitación explicada.
- [ ] Enlaces reales del foro, Reddit, X, LinkedIn y YouTube.
- [ ] Issues abiertos y peticiones repetidas (clima, cerraduras, cámara…) priorizados.
- [ ] Si la ficha de TinyLaunch del 2/11 se puede editar, añadir Home beta; no crear otra.
- [ ] awesome-home-assistant: **no** antes del 20/03/2027. Exige que el repo tenga al menos 6 meses (se creó el 20/09/2026) y penaliza la autopromoción.
