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
- [x] Rellenar o borrar los `[[ ]]` de [HA-FORUM.md](HA-FORUM.md): motivo personal, versión y tamaño de su Home Assistant, orden de lo siguiente (¿clima?), universal binary de 0.11.0.
- [ ] Confirmar las frases personales de [SOCIAL.md](SOCIAL.md) («lo que más uso», «mi parte favorita»).
- [x] Sustituir `docs/releases/0.11.0.md` por [RELEASE-NOTES.md](RELEASE-NOTES.md).
- [x] Ajuste de privacidad aprobado y desplegado en EN/ES/CA. La sección comercial Home de [WEBSITE.md](WEBSITE.md) sigue siendo opcional y no se ha añadido.
- [ ] Idioma por perfil: X en EN y LinkedIn en ES (propuesta) u otra combinación.

## Dependencias (lunes 26, go/no-go a las 18:00)

- [x] `docs/releases/0.11.0.md` corregido y fusionado en `main`; CI verde en ese SHA.
- [x] Tag `v0.11.0` y `script/release.sh 0.11.0 --publish` desde un worktree limpio (el tag solo no publica). Release **Latest** con `Altillo-0.11.0.dmg`.
- [x] `https://altillo.app/appcast.xml` apunta a 0.11.0 (build 205); longitud y firma Ed25519 del DMG verificadas con la clave pública de la app.
- [ ] Actualización 0.10.8 → 0.11.0 por **Check for Updates…** en un Mac real; Home apagada por defecto y la bienvenida en orden.
- [ ] Prueba completa con Home Assistant real: descubrimiento, «Sign in with Home Assistant», token visible en Perfil → Seguridad, pegar token, timbre, desconectar.
- [x] `script/update-cask.sh 0.11.0`, commit y push.
- [x] Privacidad «Home (optional)» / «Casa (opcional)» **en producción** (el 17/10 aún no está).
- [x] Vídeos de YouTube EN y ES subidos como no listados; URL completa copiada.
- [x] Cuenta del foro de Home Assistant de Xus creada; anotar su nivel de confianza.
- [x] Baseline de descargas:
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

## Preparación ejecutada · 26/10/2026

- Autorización de Xus en este hilo para push, PR, merge, release, cask, privacidad y vídeos ocultos.
- [PR #10](https://github.com/XusBadia/altillo/pull/10) fusionada. Fuente de la release: `06c245f65e7c9f8fb6ced0aceb9c9f0890a7aff6`; build 205, universal `x86_64 arm64`. Conserva el arreglo de Finder de 0.10.8.
- [CI de main](https://github.com/XusBadia/altillo/actions/runs/40294922649) verde en ese SHA. Pruebas locales: 421 AltilloKit; 867 macOS correctas / 1 omitida; 252 web correctas / 36 omitidas por proyecto. Localización: 0 de 1488 cadenas sin español.
- [Release Latest 0.11.0](https://github.com/XusBadia/altillo/releases/tag/v0.11.0), DMG de 17.185.483 bytes. App y DMG notarizados y stapled; Gatekeeper y arranque desde el DMG correctos. SHA256 público/local: `2ac6822a43092af1599658c6aad3b47a35fc26c3d174cacfc36d5ef70f8be63a`.
- Privacidad desplegada y comprobada en `/privacy/`, `/es/privacidad/` y `/ca/privadesa/`, con descubrimiento de red, login, token y revocación. Deployment de producción: `dpl_D5NvBREy9D2RqEVvCu3HNvUWzRuC`. La portada no se ha ampliado con la sección Home opcional.
- YouTube EN: https://www.youtube.com/watch?v=IWd3CM_M17k · ES: https://www.youtube.com/watch?v=xz2JBf3yTy0. Ambos **no listados**, miniaturas correctas, checks sin incidencias, reproducen sin sesión.
- Foro: sesión `xusbadia`, nivel de confianza **2**, verificada en preview default de T3; no necesita Apple Events. Nada publicado ni borrador creado.
- Baseline anterior a publicar: `download-baseline-2026-10-26.jsonl`, capturado a las **08:45:04 UTC**. La nueva 0.11.0 todavía no existía; sus descargas empiezan en cero. Las comprobaciones de descarga y actualizaciones también incrementan el contador.
- Recordatorio de revisión final: **27/10, 13:20 Madrid / 12:20 UTC**. Se elimina tras ejecutarse. No hay publicaciones sociales ni cambios de visibilidad programados.
- **Pendiente manual antes del anuncio:** actualización 0.10.8 → 0.11.0 por Sparkle y recorrido completo con Home Assistant real, incluido login, token visible, timbre y desconexión. El servidor real responde, pero no se ha repetido ese recorrido completo en la release final.
- Appcast público verificado a las 09:07 UTC: 0.11.0 / build 205, firma Ed25519 correcta y versiones anteriores conservadas.
- Cask actualizado en este repositorio con el checksum de la descarga pública. No existe un tap propio publicado verificado; no se ha creado ninguno ni se afirma que `brew upgrade --cask altillo` esté comprobado.
