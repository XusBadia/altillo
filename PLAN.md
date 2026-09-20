# Altillo: plan de desarrollo

> Altillo convierte el notch del Mac en **un sitio arriba donde dejar cosas y ver lo importante**:
> - archivos que dejas un momento y luego bajas donde quieras;
> - cuánto te queda de tus agentes de IA y qué están haciendo ahora mismo;
> - los iconos de la barra de menú que el notch esconde.
>
> En iPhone y iPad, Altillo es la misma app adaptada: uso de IA, agentes en vivo en la Dynamic Island y widgets.
>
> Soporte: [investigación](docs/investigacion.md) · [uso de IA](docs/uso-ia.md) · [agentes en vivo](docs/agentes-en-vivo.md) · [barra de menú](docs/barra-de-menu.md)

## 0. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Repo | **Monorepo `altillo`**: app de macOS, app de iOS/iPadOS, widgets, paquete compartido y CLI de hooks |
| App de iOS | **Altillo para iOS, desde cero.** Sustituye al companion del fork de openusage y a ai-limits; de ellos solo se aprovechan ideas y fragmentos, con atribución MIT |
| Hardware | MacBook con notch + Mac mini (monitor externo sin notch). La isla virtual es tan importante como el notch real |
| Distribución | Open source MIT. En Mac: Developer ID + notarización + Sparkle, **sin sandbox**, hardened runtime. En iOS: TestFlight / App Store. Team `9L2TD7KVV9` |
| Versiones | **macOS 26 mínimo, probado en 26 y 27** (macOS 27 salió el 14-09-2026). iOS/iPadOS 26 mínimo |
| Shelf | Referencia + mover al sacar (estilo Yoink). Lo temporal se copia |
| Módulos | Shelf · Uso de IA · **Agentes en vivo** · Iconos de la barra de menú · AirDrop/compartir · Now Playing · Calendario |
| UX | **Prioridad máxima.** Personalizable, con edición directa del notch y buenos defaults. Estética **«Desván»: cálida y skeuomórfica** (§3) |
| Fuera de alcance por ahora | Asistente o agente propio dentro de Altillo, portapapeles, HUDs, batería |

## 1. Principios

1. **Primero la UX.** Cada interacción se prototipa y se prueba antes de darla por buena (§4). Una feature que no se siente bien no se publica.
2. **Invisible hasta que hace falta.** En reposo ocupa exactamente el notch, o nada si no hay notch.
3. **Personalizable sin abrumar.** Los defaults son excelentes y la personalización es profunda pero ordenada: se edita el notch directamente y los ajustes avanzados van aparte. Es lo contrario de Notchy.
4. **El arrastre nunca falla.** Es la métrica de calidad número uno del shelf.
5. **Nativo, ligero y reactivo a eventos.** CPU en reposo ≈ 0 % y < 60 MB de RAM, sin timers de sondeo en la UI.
6. **Nunca decide por ti ni filtra tus datos.** Las credenciales no salen del Mac. Altillo nunca aprueba nada automáticamente y, si está cerrado, los agentes funcionan igual que sin él.

## 2. Estructura del monorepo

```
altillo/
├─ project.yml                 XcodeGen: todos los targets; el .xcodeproj no se versiona
├─ Config/                     xcconfigs, Local.xcconfig.example (team/bundle/container fuera de git)
├─ Packages/
│  └─ AltilloKit/              SwiftPM local, Swift 6
│     ├─ AltilloCore           modelos compartidos: UsageSnapshot, AgentSession, ShelfItemRef, Settings
│     ├─ AltilloSync           CloudKit (CKSyncEngine), iOS + macOS
│     ├─ AltilloUsage          collectors de proveedores (solo macOS): Claude, Codex, …
│     ├─ AltilloAgents         protocolo de eventos de agentes, parsers por agente y máquina de estados
│     └─ AltilloDesign         tokens de diseño, componentes compartidos (anillos, barras, chips)
├─ Apps/
│  ├─ macOS/                   Altillo.app (notch)
│  ├─ iOS/                     Altillo para iPhone y iPad (universal)
│  ├─ Widgets/                 WidgetKit + ActivityKit (Live Activities)
│  └─ Hook/                    altillo-hook: CLI incluida en Altillo.app que usan los hooks de los agentes
├─ Tests/                      tests por paquete y UI tests
├─ docs/                       investigación, decisiones y guías
└─ .github/workflows/          CI (build + tests en PR; release firmada en tag)
```

**Identificadores** (en `Local.xcconfig`; sin ellos, los forks compilan con iCloud desactivado):
- `me.badia.altillo` (macOS), `me.badia.altillo.ios` (iOS)
- `.widgets`
- contenedor `iCloud.me.badia.altillo`
- App Group `group.me.badia.altillo`

## 3. Lenguaje visual: «Desván»

Elegido el 18-09-2026 entre tres prototipos (Matriz, Desván, Fluido). La especificación completa está en [docs/design/direcciones.md](docs/design/direcciones.md#dirección-b-desván) y las capturas en `docs/design/direcciones/`.

- **Concepto:** el altillo de casa, con una bombilla cálida, cajas de cartón y etiquetas de papel. Software **cálido y skeuomórfico**, hecho a mano, pero sobrio fuera de sus momentos firma.
- **Silueta:** negro puro opaco, que empasta con el notch físico. La personalidad va dentro: la luz de la bombilla, la madera, el papel y el kraft.
- **Paleta:**
  - madera `#1E1914` / `#2A231C`, balda `#3A3027`, texto papel `#F6EFE3`;
  - acento bombilla `#FFB547`, que se usa como luz y no como pintura;
  - kraft `#C9A77C`;
  - 7 colores de etiqueta, solo para identidad.
  - En iOS, los widgets y la pantalla de bloqueo van en papel claro.
- **Tipografía:** SF Pro Rounded, la del sistema, elegida el 18-09-2026 entre 10 candidatas (muestra en `docs/design/tipografia/candidatas.png`). Se usa en títulos, cifras grandes, pestañas y botones; SF Pro / SF Mono en nombres y comandos. No se incluye ninguna fuente en la app.
- **Materiales:** grano de papel, balda de madera en la que se apoyan las miniaturas (nombre en una línea debajo, **sin etiquetas kraft**: ocupaban demasiado), caja de cartón en la zona de soltar y el avión de papel de AirDrop. Más adelante se pueden generar texturas bitmap (madera, cartón) con IA si mejoran el resultado.
- **Compacto:** el notch abierto mide unos 150 pt de alto (franja del notch + unos 104 pt de contenido) y el peek, 60 pt. Hay que ocupar poco espacio vertical.
- **Movimiento:** con peso: las cosas caen, se aplastan un poco y se asientan. Al cerrar, nunca rebotan. Los momentos firma son el ítem que aterriza en la balda, la caja que abre las solapas bajo el cursor, el "toc, toc" del agente que espera y el sello "Hecho". Con Reducir movimiento, todo son fundidos.
- **Voz:** cálida y doméstica, de tú, con verbos del altillo: "Súbelo ↑", "Suéltalo, ya lo guardo arriba", "¿Lo bajamos?".
- **Límite para no caer en lo cursi:** el sello solo aparece al terminar y las solapas solo en la zona de soltar. Todo lo demás es sobrio.

## 4. UX y personalización

### Qué se puede personalizar

| Área | Opciones |
|---|---|
| Módulos | Activar o desactivar cada uno y ordenar las pestañas del notch abierto |
| Orejas | Qué va en la izquierda y en la derecha: uso de IA, agentes, música, próximo evento, nº de ítems del shelf o nada. También si se ven siempre o solo con actividad |
| Comportamiento | Abrir con hover o con clic; retardo del hover; distancia a la que se activa el arrastre; cierre automático; atajo global |
| Apariencia | Color de acento (presets más uno libre), superficie cálida o neutra, densidad compacta o cómoda, tamaño del notch abierto (S/M/L) |
| Pantallas | Dónde aparece (notch / principal / todas / la del cursor); isla visible siempre o solo al usarla; comportamiento a pantalla completa |
| Por módulo | Shelf: caducidad, cuadrícula o lista, tamaño de las miniaturas. IA: proveedores, métricas, umbrales de alerta. Agentes: qué agentes, qué eventos avisan, sonido. Barra de menú: qué iconos se muestran |

### Cómo se personaliza (la clave de la UX)
- **Modo edición del notch:** clic derecho en el notch → "Personalizar…". El notch se abre en modo edición:
  - arrastras módulos a las orejas y a las pestañas;
  - los activas o desactivas con un toque;
  - ves el resultado en vivo.
  Es el patrón de editar widgets de iOS, aplicado al notch.
- **Presets de inicio:** "Mínimo" (solo shelf), "Desarrollador" (shelf + IA + agentes) y "Todo". Se eligen en la bienvenida y luego se ajusta lo que quieras.
- **Ventana de Ajustes** con vista previa en vivo del notch. Lo avanzado va en su propia sección.
- **Exportar e importar la configuración** (JSON) y sincronizarla entre tus Macs por iCloud.

### Proceso de UX (en todas las fases)
- **Mock primero:** cada estado nuevo se diseña en SwiftUI Previews con datos falsos antes de conectar la lógica. Se valida la estética contigo antes de implementar.
- **Checklist por feature:**
  - Descubrible sin leer nada.
  - Responde en < 100 ms a la intención.
  - Tiene estados vacío, cargando, error y desactualizado.
  - Se puede deshacer (⌘Z al quitar del shelf).
  - Funciona con teclado.
  - VoiceOver.
  - Reducir movimiento y Reducir transparencia.
- **Presupuestos:**
  - El notch empieza a abrirse en menos de 1 frame desde que se decide abrirlo.
  - Animaciones a 120 Hz sin frames perdidos (se revisa con Instruments).
- **Dogfooding:** al final de cada fase, uso diario en los dos Macs y una lista de fricciones que se resuelve antes de avanzar.
- **Grabaciones:** un GIF o vídeo de cada interacción clave para revisar el detalle (y para el README).

## 5. Módulos: diseño técnico

### 5.1 Shelf
- Ventana: `NSPanel` fijo por pantalla, transparente, que deja pasar los clics en reposo.
- Detección de arrastres: se observa el pasteboard de drag de forma global.
- Recepción con AppKit, incluidas las promesas de archivo de Fotos, Mail y Safari. Drag out multi-ítem con `NSDraggingSource`.
- Guardado: bookmarks para archivos estables y `clonefile` para temporales.
- Detalle en [investigación](docs/investigacion.md).

### 5.2 Uso de IA ([detalle](docs/uso-ia.md))
- **Collectors propios en `AltilloUsage`:**
  - Claude: llavero `Claude Code-credentials` y el fichero como respaldo. **Nunca se refresca el token.**
  - Codex: `codex app-server` por JSON-RPC.
  - Después se portan de openusage, uno a uno y con atribución MIT: Cursor, Copilot, Gemini/Antigravity y OpenRouter.
- **Fuente opcional "compatible with OpenUsage":** su API local, para los proveedores que no tengamos nativos.
- **Refresco:** cada 5 min, stale-while-revalidate, y en pausa mientras el Mac duerme.
- **Publicación:** a CloudKit para iOS.
- **Transición opcional:** escribir también el formato antiguo `openusage.mobile.v1` para que la app de TestFlight actual siga funcionando hasta que llegue Altillo iOS. Así se retiran ya el bridge y su watchdog.

### 5.3 Agentes en vivo ([detalle](docs/agentes-en-vivo.md))
- **Captura de eventos** con hooks oficiales:
  - Claude Code: `~/.claude/settings.json`, eventos `SessionStart/End`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `Stop` y `StopFailure`.
  - Codex: `~/.codex/hooks.json`, con los mismos conceptos.
  - Más adelante: Gemini CLI y Copilot CLI (hooks) y OpenCode (SSE de `opencode serve`).
- **Transporte:** todos los hooks llaman a `altillo-hook <agente> <evento>`. Es una CLI mínima incluida en la app que reenvía el JSON de stdin por un **socket Unix** a Altillo.
  - Si Altillo no está abierto, sale al instante sin decidir nada. **El agente nunca se queda colgado.**
- **Aprobar o denegar desde el notch:**
  - En `PermissionRequest`, el hook espera la respuesta como mucho N segundos (configurable, 120 s por defecto). Si no llega, devuelve "sin decisión" y el agente pregunta en la terminal como siempre.
  - **Nunca se aprueba nada automáticamente.**
  - Los comandos marcados como peligrosos (`rm -rf`, `git push --force`…) piden confirmación extra.
- **Modelo:** `AgentSession {agente, session_id, proyecto (de cwd), estado, última actividad, petición pendiente}`.
  - Estados: `trabajando`, `esperando permiso`, `esperando tu respuesta`, `terminado`, `error`.
- **En el notch:**
  - Oreja con el nº de agentes trabajando (animación sutil).
  - **Peek automático** cuando uno espera permiso o respuesta, o cuando termina.
  - Pestaña con las sesiones y sus botones Permitir / Denegar / Ir a la terminal.
- **Instalador de hooks:** con consentimiento explícito, muestra el diff antes de escribir, hace copia de seguridad, es idempotente y **se puede desinstalar con un clic**. Los hooks existentes del usuario no se tocan.
- **Limitación conocida:** los hooks no se disparan de forma fiable en la app Claude Desktop. Funcionan en la CLI y en VS Code/JetBrains.

### 5.4 Iconos de la barra de menú ([detalle](docs/barra-de-menu.md))
- **Qué hace:** muestra dentro del notch abierto los iconos que el notch tapa y permite pulsarlos. Se enumeran con la API de Accesibilidad (`AXExtrasMenuBar`), se detecta cuáles caen detrás del notch y se pulsan con `AXPress` (clic derecho: `AXShowMenu`), recogiendo antes el panel.
- **Permisos:** **Accesibilidad** es obligatoria. **Grabación de Pantalla** es opcional, solo para mostrar el icono real en vez del de la app.
- **macOS 27:** Apple ya añade su propio chevrón de desbordamiento, así que ahí Altillo ofrece **lista y búsqueda** de todos los iconos por Accesibilidad.
- **Ocultar secciones:**
  - En 26, con el separador de 10.000 pt (API pública).
  - En 27, enlace a Ajustes › Barra de menús.
- **Reordenar: no.** Es frágil y exige mucho mantenimiento (Bartender e Ice viven rotos).

### 5.5 Sincronización Mac ⇄ iPhone/iPad
- **CloudKit, base privada, con `CKSyncEngine`**, en el contenedor `iCloud.me.badia.altillo`.
- **Registros:** `Device`, `UsageSnapshot` (por dispositivo y proveedor), `AgentSession` (solo los cambios de fase, no cada tick) y más adelante `ShelfItem` con `CKAsset`.
- **Actualización en iOS:** las suscripciones de CloudKit envían un push silencioso a iOS, que recarga los widgets.
- **Live Activities** (Dynamic Island):
  - iOS sube a CloudKit sus tokens de *push-to-start* y de actualización.
  - El Mac actúa como proveedor de APNs con **tu clave `.p8` guardada en el llavero**, configurada una vez y nunca incluida en el repo. Envía solo las transiciones relevantes (empieza, espera, termina).
  - Sin clave configurada, las Live Activities solo se actualizan cuando la app está activa.

### 5.6 AirDrop, Now Playing y calendario
- **AirDrop y compartir:** `NSSharingService`, con una zona AirDrop durante el arrastre.
- **Now Playing:** `mediaremote-adapter` detrás de `NowPlayingProvider`, con fallback AppleScript para Spotify y Música. Si se rompe, se desactiva solo.
- **Calendario:** EventKit, con el próximo evento, el botón "Unirse" y un aviso 5 min antes.

## 6. Altillo para iOS y iPadOS

**iPhone (v1):**
- **Uso de IA:** dashboard por proveedor, con ventanas de sesión y semana, cuenta atrás hasta el reset e indicador de ritmo.
- **Agentes:** lista de sesiones activas en todos tus Macs y **Live Activity en la Dynamic Island** cuando un agente trabaja, espera o termina.
- **Widgets:** pantalla de inicio (S/M/L), pantalla de bloqueo, StandBy y Centro de Control.
- **Notificaciones:** umbrales de uso y resets, "Claude espera tu permiso en *altillo*" y "Codex ha terminado".
- **Personalización:** los mismos criterios que en el Mac: módulos, proveedores, métricas y umbrales.

**Confirmadas (18-09-2026), después de la v1:**
- **Aprobar o denegar desde el iPhone** (fase 6): un botón en la notificación o en la Live Activity.
  - La decisión vuelve al Mac por CloudKit, y por APNs hacia el Mac si hace falta inmediatez.
  - Exige Face ID y caduca a los 2 minutos.
  - El Mac solo acepta decisiones firmadas por un dispositivo emparejado.
- **Altillo compartido** (fase 9): extensión de compartir en iPhone ("Enviar al Altillo") que hace aparecer el archivo en el shelf del notch del Mac, y al revés.
  - Los ítems se sincronizan como `CKAsset` con un límite de tamaño configurable.
- **iPad** (fase 9):
  - **Shelf propio** (ventana compacta o Slide Over) con drag & drop entre apps, sincronizado con el del Mac.
  - Dashboard ampliado en dos columnas.

## 7. Fases

Hay tres pistas: **M** (Mac), **K** (AltilloKit) e **I** (iOS). Pueden avanzar en paralelo cuando no dependen entre sí, y cada fase termina con criterios de aceptación.

| Fase | Contenido | Depende de | Estimación |
|---|---|---|---|
| **0. Cimientos** | Monorepo, `project.yml` con todos los targets, CI, AltilloDesign (tokens), mock visual de todos los estados del notch y spikes de drag & drop | — | 3-4 días |
| **1. Shelf MVP (M)** | Máquina de estados, animaciones, recepción, drag out, Quick Look, persistencia, menú de la barra y arranque al iniciar sesión | 0 | 1 semana |
| **2. Robustez + personalización (M)** | Multi-pantalla, pantalla completa, sleep/wake, macOS 27, **modo edición del notch**, presets, ajustes con vista previa, accesibilidad, primera release notarizada + Sparkle | 1 | 1,5 semanas |
| **3. Uso de IA (K+M)** | AltilloUsage (Claude arreglado, Codex), fuente OpenUsage opcional, oreja + pestaña + alertas en el notch y escritor del formato antiguo para retirar el bridge | 0 | 1 semana |
| **4. Agentes en vivo (K+M)** | `altillo-hook`, socket, instalador de hooks (Claude, Codex), sesiones, peek automático, permitir/denegar desde el notch | 2 | 1,5 semanas |
| **5. Altillo iOS v1 (K+I)** | AltilloSync (CKSyncEngine), app de iPhone: dashboard, agentes, widgets, notificaciones y personalización. Retirar el fork y ai-limits | 3 (puede ir en paralelo con 4) | 2 semanas |
| **6. Dynamic Island + aprobar desde el iPhone (I+M)** | Live Activities, el Mac como proveedor de APNs (spike primero), permitir/denegar desde el iPhone con Face ID | 4, 5 | 1,5 semanas |
| **7. Barra de menú (M)** | Iconos ocultos en el notch, lista y búsqueda en 27, ocultar secciones en 26 | 2 | 1 semana |
| **8. AirDrop, Now Playing, calendario (M)** | §5.6 | 2 | 1-1,5 semanas |
| **9. Altillo compartido + iPad** | `ShelfItem` en CloudKit, extensión de compartir en iPhone, shelf en iPad, dashboard de iPad | 5 | 2 semanas |
| **10. Publicación** | Icono, nombre, bienvenida, web/README, Homebrew Cask, App Store (iOS) | — | 1 semana |

### Estado

- **Fase 0 (18-09-2026):** el código está hecho.
  - Monorepo y CI.
  - Tokens de diseño y mock visual de los 11 estados (capturas en `docs/design/phase0/`).
  - Spikes de drag & drop con registro en la app.
  - 19 tests en el paquete y 33 en macOS.
  - Revisión independiente del código aplicada.
  - **Pendiente, que haces tú:** la matriz manual de `docs/pruebas-drag-drop.md` en el Mac mini y en el MacBook, y dar el visto bueno a la estética.
- **Fase 1 (20-09-2026):** implementación terminada y validación automática en verde.
  - Shelf funcional de extremo a extremo: máquina de estados, recepción de archivos y promesas, drag out seguro, selección, Quick Look, menú y arranque al iniciar sesión.
  - Persistencia robusta con bookmarks, copias propias recuperables, caducidad, restauración tras wake/cambio de reloj y cuarentena de snapshots corruptos o incompatibles.
  - Deshacer/rehacer al quitar o vaciar (⌘Z/⇧⌘Z), estados visibles de carga y error, y protección frente a promesas tardías y movimientos parciales.
  - 23 tests en `AltilloKit` y 98 tests de macOS; ambos conjuntos pasan con Xcode 26.
  - Rendimiento en reposo medido en Release en el Mac mini: CPU media estable 0,000 % (17 muestras de 1 s) y `phys_footprint` de 20 MB.
  - **Aceptación manual pendiente:** completar la matriz de `docs/pruebas-drag-drop.md` en el Mac mini y el MacBook y usar Altillo 2-3 días sin NotchNook. No se marca la fase como aceptada hasta completar ambas comprobaciones.

### Criterios de aceptación clave
- **0:** los spikes de drag & drop pasan la matriz §8 y el mock visual te convence.
- **1:** 2-3 días sin NotchNook, la matriz §8 en verde y CPU en reposo < 0,1 %.
- **2:** personalizas el notch entero desde el modo edición sin abrir Ajustes; una semana sin bugs en los dos Macs, con macOS 26 y 27.
- **3:** los datos de Claude y Codex coinciden con los de las apps oficiales, y el iPhone sigue recibiendo datos sin el bridge.
- **4:** apruebas un permiso de Claude Code desde el notch. Con Altillo cerrado, Claude Code se comporta exactamente igual que sin hooks.
- **5:** el iPhone muestra los usos y agentes de los dos Macs y los widgets se actualizan solos.
- **6:** la Dynamic Island avisa en < 5 s cuando un agente espera permiso.
- **7:** en el MacBook, un icono tapado por el notch se abre desde Altillo con un clic.

## 8. Matriz de pruebas de drag & drop

**Fuentes:** Finder (uno, varios, carpeta), Escritorio, Fotos, adjunto de Mail, imagen de Safari/Chrome, miniatura flotante de captura, texto seleccionado, URL de la barra de direcciones, Slack, VS Code / Xcode, Descargas del Dock.

**Destinos:** Finder (mismo disco → move; disco externo → copy), Escritorio, Mail, Mensajes, Slack, WhatsApp, `<input type=file>` en Chrome y Safari, Terminal, Papelera del Dock.

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Los endpoints de uso de Claude/Codex son internos y cambian | Mappers aislados con tests de fixtures; ante un fallo se muestra "desactualizado" sin romper nada; upstream openusage como canario |
| Los hooks de los agentes cambian de formato (Codex saca varias versiones al día) | Parsers tolerantes y versionados; tests con payloads reales; `altillo-hook` falla siempre en abierto |
| Un error en el instalador rompe el `settings.json` del usuario | Diff previo, copia de seguridad, escritura atómica, desinstalación con un clic y tests del instalador |
| Seguridad al aprobar desde fuera de la terminal | Nunca automático, timeout, confirmación extra para comandos peligrosos, y en iPhone Face ID + caducidad |
| Apple rompe la barra de menú o MediaRemote en cada versión | Módulos aislados que se desactivan solos; alcance limitado (sin reordenar) |
| El desarrollo principal es en un Mac sin notch | Release notarizada con Sparkle desde la fase 2 para probar de forma continua en el MacBook |
| macOS pide permiso (TCC) al acceder de nuevo a archivos de Documentos, Escritorio o Descargas tras reiniciar la app | Se verifica en la fase 1 con referencias persistidas. Si molesta, se copia (`clonefile`) en vez de referenciar en esas carpetas, o se explica el permiso en la bienvenida |
| Scope creep | Cada módulo está desactivado por defecto salvo en su preset, y cada feature pasa el checklist de UX |

## 10. Pendiente de validar contigo
- **Nombre definitivo** y disponibilidad (GitHub, Homebrew, App Store).
- **Clave APNs `.p8`** para las Live Activities (fase 6): crearla en tu cuenta de desarrollador.
