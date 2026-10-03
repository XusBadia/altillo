# Checklist de ejecución

## Preparado localmente

- [x] QA real confirmado por Xus el 03/10; no tratarlo como bloqueo pendiente.
- [x] Calendario 19–25 con Madrid/UTC y cambio de hora del 25.
- [x] Fichas, FAQ, notas de 100 palabras, anuncios ES/EN y pitches.
- [x] Perfiles personales de Aurio identificados; fichas Altillo independientes.
- [x] Límites honestos: macOS 26+, Drawer en 27, isla virtual, pre-1.0, credencial solo a su proveedor, modelo Ask local con web externa.
- [x] Canales condicionados: HN con texto humano, DEV sin anuncio IA, Reddit con karma y confianza, colas gratuitas y badges sujetos a aprobación.
- [x] Activos existentes reutilizados; teasers del usuario intactos.

## Antes de crear o programar fichas

- [ ] Leer reglas el 12/10 y registrar cuenta autenticada; verificar Peerlist Xus y su ventana real de programación.
- [x] Peerlist/PH/X revisados sin duplicados; consultar EXECUTION antes de continuar en otros canales.
- [x] PH confirma 20/10, 00:01 PDT, 09:01 Madrid, 07:01 UTC; descripción de 447 aceptada.
- [x] X y LinkedIn personales: tres posts ES con vídeo programados y verificados; Aurio intacto.
- [x] Textos, fechas y acciones del calendario aprobados por Xus el 03/10. Consultar [EXECUTION.md](EXECUTION.md) para conocer qué está realmente programado; no repetir esta aprobación.
- [ ] HN: autor redacta personalmente y comprueba elegibilidad. No usar texto generado por IA.
- [ ] Reddit: identidad, karma local, 30 días desde promoción anterior, reglas leídas, vía de confianza o App Pile; editar antes de enviar.
- [x] DMG 0.10.0, enlaces y firma verificados; binario universal Intel x86_64 + Apple Silicon arm64. Releer el 18/10.
- [x] Galería 07/08 corregida y guardada en PH: Drawer y privacidad exactos.
- [ ] Pitches: destinatario oficial y aprobación de envío; sin contactos inventados ni gastos.
- [ ] Colas y badges: usar gratis; aprobar cualquier backlink público; si no hay opción gratuita, omitir.

## Baseline y medición sin analítica

Guardar recuento inicial el 18/10 y final el 25/10:

```sh
gh api repos/XusBadia/altillo/releases/tags/v0.10.0 --jq '.assets[] | select(.name | endswith(".dmg")) | {name, download_count}'
```

Registrar fecha/hora UTC, versión y contador. La diferencia cuenta descargas del artefacto entre capturas, sin identificar instalaciones, usuarios únicos o canal. Si cambia el release, seguir ambos activos por separado. No añadir telemetría para el lanzamiento.

## Día de ejecución

- [ ] Comprobar URL real y estado público/cola tras cada acción; guardar evidencia y perfil usado.
- [ ] Peerlist: comprobar ficha y no solo listado rotatorio; evitar doble Launch; comentario corto insertado entero y releído.
- [ ] PH: galería ≥2, thumbnail <3 MB, URL completa de YouTube y vídeo no privado; comentario y maker comprobados.
- [ ] YouTube: público tras aprobación; verificar reproducción sin autenticación.
- [ ] Una versión lingüística por audiencia; evitar duplicado inmediato.
- [ ] Responder personalmente; sin comentarios IA en HN/DEV ni spam en otros proyectos.
- [ ] Registrar bugs y preguntas; no pedir credenciales o archivos privados.

## Respuestas de referencia a incidencias

Descarga rota: «El enlace de descarga está fallando. Estoy revisándolo. La versión pública y el código están en GitHub Releases: https://github.com/XusBadia/altillo/releases/latest». Usar solo después de comprobar que el enlace funciona.

Fallo de arrastre: «¿De qué app arrastras y a cuál? Con la versión de Altillo y macOS, y esos pasos, puedo reproducirlo. No hace falta enviar el archivo privado.»

Privacidad: «Las consultas opcionales de uso presentan la credencial únicamente a su proveedor. Altillo no recibe esos datos en un servidor. La política detalla también consultas web, letras y actualizaciones: https://altillo.app/privacy/».

Promoción retirada: leer motivo; editar o contactar moderación mediante el canal permitido tras aprobación; no repostear ni usar cuentas alternativas. En HN y DEV, redactar respuestas desde cero en palabras del autor; estas referencias no son comentarios para pegar.

## Cierre del 25/10

- [ ] Guardar contadores finales y enlaces de publicaciones reales.
- [ ] Publicar seguimiento sin cifras inventadas; resultados solo con evidencia.
- [ ] Priorizar bugs, preguntas y asuntos abiertos.
- [ ] Comprobar colas editoriales; envío no significa publicación.
