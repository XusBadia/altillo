# Lanzamiento de Altillo · 19–25 octubre de 2026

Preparado el 03/10/2026. **Kit local para revisión y ejecución; ninguna ficha creada, publicación enviada ni fecha programada en una plataforma.** QA de la versión pública confirmado por Xus el 03/10. Propietario de todos los pasos externos: Xus.

**Orden recomendado: Peerlist lunes 19 → Product Hunt martes 20 → Show HN miércoles 21 → comunidad Mac y directorios → retrospectiva domingo 25.** Product Hunt es una propuesta de fecha, pendiente de disponibilidad en su formulario. Peerlist abre exclusivamente el lunes UTC. Las horas de los demás canales son ventanas de trabajo elegidas para poder responder, no horarios óptimos demostrados.

El viernes 16 empieza la comunicación previa de Altillo; las publicaciones de Aurio del 13–15 quedan separadas.

El objetivo es que personas con Mac prueben Altillo. Métrica principal disponible sin instrumentar la app: **incremento de descargas del DMG en GitHub Releases** durante la semana. Es un indicador de descargas, no de instalaciones ni usuarios únicos. No hay telemetría de la app. No conocemos tamaño de audiencia, lista de correo ni contactos confirmados; no se proyectan cifras ni puestos en rankings.

## Lo que se lanza

Altillo 0.10.0, nativa para macOS 26+, gratuita y MIT: archivos arriba para arrastrarlos después, límites de Claude/Codex y peticiones de agentes al alcance. Una isla virtual permite usarla sin notch y en pantallas externas. El binario público está firmado y notarizado. Sigue siendo pre-1.0.

La frase de marca es **«Tu Mac ya tenía un altillo. Solo le faltaba una puerta.»** En fichas sin vídeo, explicar primero el mecanismo: **«A shelf, AI usage and live agents in your Mac's notch.»** No afirmar que todas las funciones trabajan sin conexión ni que ninguna credencial sale del Mac: las consultas opcionales de límites presentan la credencial únicamente a su proveedor. Ask ejecuta su modelo en el dispositivo y puede consultar servicios web cuando se usa esa función. Drawer oculta iconos en macOS 27; en 26 los lista y abre, sin ocultarlos.

## Archivos listos

| Artefacto | Contenido |
|---|---|
| [CALENDAR.md](CALENDAR.md) | Preparación, ejecución y seguimiento; Madrid/UTC/plataforma |
| [launch-week.ics](launch-week.ics) | Agenda importable con alarmas; importar es un paso manual, no programa publicaciones |
| [PROFILES.md](PROFILES.md) | Identidades de Aurio reutilizables, evidencia y límites |
| [CHANNELS.md](CHANNELS.md) | Prioridad, coste, permisos, acceso, reglas, fuentes y estado por canal |
| [LISTINGS.md](LISTINGS.md) | Peerlist, HN, Reddit, IH, AlternativeTo, MacUpdate, directorio notch y propuesta de lista awesome |
| [SOCIAL.md](SOCIAL.md) | X y LinkedIn; ES/EN; prelaunch, lanzamiento y seguimiento |
| [FAQ-PRESS.md](FAQ-PRESS.md) | 10 respuestas frecuentes EN/ES y dos notas de prensa de 100 palabras |
| [OUTREACH.md](OUTREACH.md) | Pitches editoriales de MacStories/ 9to5Mac y newsletter técnica; no enviados |
| [DEV.md](DEV.md) | Artículo educativo y límites de la política DEV sobre promoción asistida por IA |
| [CHECKLIST.md](CHECKLIST.md) | Cierre de acceso, revisión, ejecución y respuesta a incidencias |
| [COPY-REVIEW.md](COPY-REVIEW.md) | Variantes, panel de puntuación y comprobación de afirmaciones |
| [SOURCES.md](SOURCES.md) | Fuentes primarias verificadas el 03/10/2026 |
| [Product Hunt](../producthunt/README.md) | Ficha, primer comentario, vídeo y orden de galería |
| [YouTube](../youtube/README.md) | Descripción corregida y publicación del vídeo el día del lanzamiento |

## Activos que ya existen

- Vídeo principal EN: [altillo-anuncio-en.mp4](../videos/altillo-anuncio-en.mp4); ES: [altillo-anuncio.mp4](../videos/altillo-anuncio.mp4).
- Galería de ocho capturas, 1270×760: [producthunt/gallery](../producthunt/gallery). Usar 01 como cubierta y 02/03 para explicar el arrastre; 04/06 para audiencia de agentes.
- Logo cuadrado: [thumbnail.png](../producthunt/thumbnail.png); GIF: [thumbnail.gif](../producthunt/thumbnail.gif).
- Demo YouTube existente, registrada como no listada: https://www.youtube.com/watch?v=L33ophXDYUM. El estado autenticado actual no se ha comprobado en este trabajo.
- Enlace de descarga para fichas generales: https://altillo.app/. Fuente: https://github.com/XusBadia/altillo. DMG verificado al preparar el kit: https://github.com/XusBadia/altillo/releases/download/v0.10.0/Altillo-0.10.0.dmg.
- Los teasers y sus cambios locales pertenecen al trabajo previo del usuario. Este kit no los modifica ni exige regenerarlos.

## Pendientes concretos

Los textos y activos están preparados. Se reutilizan los perfiles personales de Xus usados con Aurio, documentados en [PROFILES.md](PROFILES.md). Peerlist consta verificado el 27/09; el navegador compartido muestra «Log in» en Peerlist y «Sign in» en PH el 03/10. Hace falta iniciar sesión con esas cuentas existentes para guardar borradores. Hay que comprobar su estado actual, la elegibilidad de Show HN y las reglas de Reddit. Este kit no ha creado ni comprobado una URL de ficha Altillo en esos sitios. Revisar los textos, crear borradores y aprobar fecha/acciones externas antes de programar, enviar pitches o publicar. Las políticas se vuelven a comprobar el 12 y el 18 de octubre.

DEV necesita una pieza humana que cumpla su política: el borrador educativo adjunto no es un anuncio listo para publicar. Un canal que no supere su requisito de acceso se sustituye por el siguiente del calendario, sin inventar cuentas ni saltarse moderación.

## Verificación y entrega

Desde la raíz del repo, `python3 script/package-launch.py --check` verifica la integridad del paquete. `python3 script/package-launch.py` genera `dist/Altillo-launch-2026-10-19.zip` con copy, agenda y activos. Es un archivo local para revisión; no publica contenido. Las correcciones de producto/web se revisan en [PR #1](https://github.com/XusBadia/altillo/pull/1); el kit no las declara desplegadas.
