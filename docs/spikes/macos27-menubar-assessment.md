# Spike: ocultar iconos de la barra en macOS 27 con el allow-list del sistema

Fecha: 28-09-2026. macOS 27.0 (26A428), MacBook con notch (1728 pt) + pantalla externa 1920×1080.

## Qué hace Bartender 7 (7.0.4) en macOS 27

Leído de su bundle (`Info.plist`, entitlements, `Resources/*.md`, cadenas localizadas y símbolos). Solo
como referencia de enfoque; no se copia código.

- **Ocultar («Standard», por defecto):** no usa divisor ni arrastres. Adquiere una aserción del sistema,
  `MBAssessmentModeAssertion` (framework privado `MenuBarClientCore`, cargado con `dlopen`), con una
  configuración `MBAssessmentModeConfiguration(allowedSystemItems:allowedBundleIdentifiers:)`: la barra
  muestra **solo** lo permitido y oculta el resto. Granularidad por app (bundle id), no por icono.
- **Reordenar («mouse-free»):** escribe `TrailingItemPreferredPositions` en
  `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`. Pide acceso
  a ese único fichero con un `NSOpenPanel` que lo preselecciona («Grant Menu Bar Access»), y guarda un
  bookmark. Sin ese permiso no reordena (no cae a arrastres de ratón).
- **«Compatibility» (opcional):** edita `trackedApplications` del plist de Control Center (los interruptores
  de Ajustes → Barra de menús), con otro permiso de fichero y copias de seguridad.
- **Permisos:** Accesibilidad (obligatorio: leer y pulsar elementos), fichero de la barra (opcional,
  reordenar), Grabación de Pantalla **opcional** (solo imágenes de iconos; sin ella usa iconos de app).
  La aserción no necesita permiso ni entitlement.
- **Onboarding:** tarjetas por permiso con «Grant Access…»; icono arrastrable a la lista de Accesibilidad
  de Ajustes del Sistema; texto «Grant Access opens the native file picker, and you just need to select
  "Grant Access". This does not give Bartender access to any other files.»; «Screen recording now optional».
- **Competencia directa:** Bartender 7 incluye **Top Shelf** / Notch Bar: «turns the notch into a live space
  for music, weather, calendar, files, clipboard, agents, and quick context».

## Comprobado con sondas propias (`/tmp/mbprobe`)

- Un binario ad-hoc, sin entitlements, activa la aserción (`activateWithConfiguration:completionHandler:`
  → error nil). Con listas vacías desaparecen **todos** los elementos de estado, reloj y Centro de Control
  incluidos. `invalidate` (o terminar el proceso) los devuelve al instante.
- `allowedBundleIdentifiers` funciona: los bundles permitidos siguen visibles, el resto se oculta.
- `allowedSystemItems` es un array de **NSNumber** (enum `MenuBarSystemItemIdentifier` de MenuBarAgent).
  Cadenas (`clock`, `module:Clock`, `com.apple.menuextra.clock`) no funcionan. Medido uno a uno:
  `2` = reloj, `6` = red (Wi‑Fi/Ethernet), `8` = Centro de Control. 0–12 juntos muestran todos los del
  sistema presentes. Orden probable del enum en el binario: battery, bluetooth, clock, displays, keyboard,
  volume, wifi, addNewBentoBoxButton?, primaryBentoBox, bentoBox, screenMirroring.
- Con la aserción activa, **AX sigue exponiendo** los elementos ocultos (`AXExtrasMenuBar`) con su posición
  anterior y la acción `AXPress`: el catálogo y la apertura de menús desde el notch siguen funcionando.
- Un bundle que se lanza después de activar la aserción queda oculto hasta que se reactiva con la lista
  actualizada (hay que reconciliar al lanzar apps).
- El plist de la barra está sin sandbox de lectura para Terminal, pero es un Group Container protegido;
  Bartender pide el fichero con `NSOpenPanel`.

## Consecuencias para Altillo

El Cajón en macOS 27 puede ser lógico: la pertenencia es una lista de apps; ocultar = aserción con
allow-list = (apps en ejecución − apps del Cajón) + todos los elementos del sistema (salvo los que el
usuario meta en el Cajón). No hay divisor, flecha, espaciadores, arrastres ⌘ ni hueco en la barra.

## Fase 0: reconfigurar la aserción (28-09-2026)

- `activateWithConfiguration:` puede llamarse otra vez sobre el mismo objeto (error nil, 1–4 ms).
  **Ampliar** la lista así muestra el nuevo bundle sin parpadeo.
- **Reducir** la lista sobre el mismo objeto, o con un segundo objeto antes de invalidar el primero,
  **no vuelve a ocultar** lo que ya se mostró (probado 3 s).
- Para reducir hay que `invalidate` y activar una aserción nueva. Aunque se encadene sin espera, la barra
  muestra todo ~1 s y vuelve a ocultar (parpadeo). Bartender lo tapa con una ventana de cobertura
  («Hidden items are briefly revealed beneath a cover»).
- `allowedSystemItems` acepta 0…31 sin error. En este Mac solo hay tres elementos del sistema visibles:
  2 = reloj, 6 = red, 8 = Centro de Control. El resto de números no mostró nada aquí.
- Consecuencia: la lista permitida solo crece durante la sesión (apps que se lanzan; una app que se cierra
  se queda en la lista, es inocuo). Solo se reduce por un gesto explícito (meter una app en el Cajón,
  volver a ocultar tras «Peek»), y ahí el parpadeo es aceptable.
