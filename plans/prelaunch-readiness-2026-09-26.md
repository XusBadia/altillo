# Preparación para lanzamiento público — Altillo

## Actualización para el lanzamiento (03-10-2026)

- Versión pública vigente: **0.10.0**, firmada y notarizada, con Sparkle.
  No hace falta crear otra release para anunciarla.
- QA aceptada por confirmación del usuario: «Qa hecho.» Los planes 002 y 009
  quedan DONE con ese origen de aceptación, sin inventar hardware ni resultados
  por caso: [registro](../docs/launch-qa-2026-10-03.md).
- 006–008 y 010 están DONE. Se refuerza 008 para que la publicación local
  también exija el último CI verde de `main` para el commit exacto, un árbol
  limpio y el smoke del DMG; el dispatch manual no evita las puertas ni el opt-in.
- Compatibilidad corregida: el Cajón **oculta en macOS 27**; en macOS 26
  agrupa/mueve/abre sin ocultar. La captura opcional de iconos necesita permiso
  de captura de pantalla y las imágenes se quedan en el Mac.
- Las credenciales de consumo se envían solo al proveedor al que pertenecen;
  Altillo no recibe ni conserva una copia. El README y el contexto de marca
  reflejan la distribución pública y este contrato.
- Semana objetivo del anuncio amplio: **19–25 de octubre de 2026**.
  Preparación multicanal y materiales: [paquete de lanzamiento](../promo/launch/README.md).

Lo que sigue conserva la auditoría original como evidencia histórica; sus
pendientes, versiones y claims no describen el estado vigente. El score 72/100
es una heurística fechada, no una medición actual ni se recalcula sin auditoría.

## Auditoría histórica (26-09-2026)

26-09-2026 · Estado auditado: `7f80680` · **72/100** (heurística de producto,
no una métrica observada)

## La conclusión

Altillo ya es una app distribuible, no un prototipo: la 0.7.5 es pública, el
DMG descargado de GitHub pasa Gatekeeper como `Notarized Developer ID`, Sparkle
tiene un appcast firmado, AltilloKit pasa y la suite macOS ejecuta 755 tests en
56 suites. Lo que impide recomendar un lanzamiento amplio no es otra feature:
son cinco cierres de confianza, QA físico, privacidad, release, diagnóstico y
soporte.

## Estado comprobado

- Release pública: v0.7.5, DMG de 11,2 MB y SHA-256 publicado
  `69fecf9c…cae15`; notarización aceptada.
- HEAD local: `swift test` pasa; `xcodebuild … test` pasa con 755 tests.
- CI de `7f80680` terminó verde en gitleaks, AltilloKit, macOS e iOS.
- Web local en curso: `npm run build` pasa. Un run completo muy paralelo de Playwright perdió
  su servidor tras los primeros fallos; una repetición dirigida en WebKit con
  un worker pasó 11/11. La web no está en CI, así que hoy no es una puerta.
- Planes anteriores: 001, 003 y 004 DONE; 005 REJECTED con criterio; 002 sigue
  BLOCKED por pruebas físicas. La auditoría UI/UX 14/14 está implementada.
- Distribución: GitHub Releases, Sparkle y cask preparado funcionan. iOS,
  widgets y Live Activities son scaffolds post-lanzamiento y no bloquean Mac.

## Bloqueos antes de anunciarlo

| Orden | Pendiente | Impacto | Esfuerzo | Confianza | Plan |
|---:|---|---|---:|---:|---|
| 1 | Quitar herramientas de spike de Release y no registrar rutas/apps como públicas | Alto, privacidad | M | Alta | [006](006-harden-release-diagnostics.md) |
| 2 | Explicar con precisión qué sale del Mac y a qué proveedor | Alto, confianza | S/M | Alta | [007](007-publish-accurate-privacy-contract.md) |
| 3 | Impedir una publicación sin suites verdes y probar el artefacto exacto | Alto, regresión | M | Alta | [008](008-gate-and-smoke-test-releases.md) |
| 4 | Cerrar la matriz real en notch, monitor externo, apps y TCC | Alto, promesa central | M | Alta | [009](009-close-physical-launch-matrix.md) |
| 5 | Dar soporte y una desinstalación que retire hooks externos | Medio/alto, recuperación | S/M | Alta | [010](010-add-support-and-safe-uninstall.md) |
| 6 | Buscar `Altillo` en EUIPO/OEPM/WIPO (clases 9/42) y registrar decisión | Alto si aparece conflicto | S | Alta sobre el pendiente | Manual |

No abriría el lanzamiento amplio hasta cerrar 006–009. El 010 y la búsqueda de
marca son baratos y conviene terminarlos antes del anuncio, aunque no impiden
seguir con una beta pública pequeña.

## Correcciones públicas inmediatas

- `README.md:203-208` todavía dice que Altillo es compatible con la API local
  de OpenUsage, mientras `PLAN.md:138` y la implementación dicen que esa fuente
  se retiró. La documentación pública debe decir que OpenUsage es solo una
  referencia con atribución.
- La auditoría original invirtió la compatibilidad de Drawer. Corrección:
  oculta en macOS 27, y cataloga/mueve/abre sin ocultar en macOS 26.
- La privacidad no puede decir que las credenciales o cifras “nunca salen del
  Mac”: los tokens se envían al proveedor correspondiente para leer consumo
  (`ClaudeCollector.swift:68-79`, `CodexCollector.swift:98-118`). La afirmación
  correcta es que no se envían a Altillo ni a terceros distintos del proveedor.
- La release 0.7.5 solo tiene “Full Changelog”. Antes del anuncio, publicar
  notas con novedades, limitaciones conocidas, permisos y procedimiento de
  rollback/hotfix.

## Qué ya funciona bien

- La firma, notarización y actualización automática están resueltas.
- La cobertura automatizada es amplia y toca los flujos de riesgo: hooks,
  comandos peligrosos, shelf, AirDrop, uso y recuperación de datos.
- Las decisiones de no copiar HUDs, CPU/RAM, clipboard de imágenes y soporte
  macOS 14/15 reducen superficie y mantienen la propuesta enfocada.
- El posicionamiento doméstico, nativo y calmado es reconocible y no depende de
  una lista genérica de widgets.

## Después del lanzamiento

- Mantener iOS/iPad/widgets, OCR/imágenes, HUDs y macOS 14/15 fuera de este
  corte.
- Añadir inbox de agentes ordenado por urgencia y salud/frescura de parsers si
  el uso real confirma que ahí está la retención.
- Refactorizar `MenuBarDrawerStore` y `NotchCoordinator` solo tras estabilizar;
  hoy tienen alto churn y un refactor previo al lanzamiento elevaría el riesgo.
- Publicar mediciones reproducibles de CPU, RAM y wakeups, sin prometer “0 %”.

## Lo que no se pudo determinar

- No se ejecutaron los recorridos que requieren MacBook con notch, trackpad,
  AirDrop, cámara, TCC y sesiones reales de agentes.
- No hay datos de activación, retención ni uso por módulo; las prioridades de
  producto son inferencias del código, la competencia y los riesgos.
- La búsqueda de marca no es asesoría legal y sigue pendiente.
