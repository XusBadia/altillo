# Altillo: plan de desarrollo

> Altillo convierte el notch del Mac en **un sitio arriba donde dejar cosas y ver lo importante**:
> - archivos que dejas un momento y luego bajas donde quieras;
> - cuánto te queda de tus agentes de IA y qué están haciendo ahora mismo;
> - los iconos de la barra de menú que el notch esconde.
>
> En iPhone y iPad, Altillo es la misma app adaptada: uso de IA, agentes en vivo en la Dynamic Island y widgets.
>
> Soporte: [investigación](docs/investigacion.md) · [uso de IA](docs/uso-ia.md) · [agentes en vivo](docs/agentes-en-vivo.md) · [barra de menú](docs/barra-de-menu.md) · [OmniNotch](docs/omninotch.md)

## 0. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Repo | **Monorepo `altillo`**: app de macOS, app de iOS/iPadOS, widgets, paquete compartido y CLI de hooks |
| App de iOS | **Altillo para iOS, desde cero.** Sustituye al companion del fork de openusage y a ai-limits; de ellos solo se aprovechan ideas y fragmentos, con atribución MIT |
| Hardware | MacBook con notch + Mac mini (monitor externo sin notch). La isla virtual es tan importante como el notch real |
| Distribución | Open source MIT. En Mac: Developer ID + notarización + Sparkle, **sin sandbox**, hardened runtime. En iOS: TestFlight / App Store. Team `9L2TD7KVV9` |
| Versiones | **macOS 26 mínimo, probado en 26 y 27** (macOS 27 salió el 14-09-2026). iOS/iPadOS 26 mínimo |
| Shelf | Referencia + mover al sacar (estilo Yoink). Lo temporal se copia |
| Módulos | Shelf · **Pregunta** (asistente on-device) · Uso de IA · **Agentes en vivo** · Iconos de la barra de menú · AirDrop/compartir · Now Playing · Calendario · Espejo |
| UX | **Prioridad máxima.** Personalizable, con edición directa del notch y buenos defaults. Estética **«Desván»: cálida y skeuomórfica** (§3) |
| Asistente | **Sí, desde el 22-09-2026**: «Pregunta», con Apple Intelligence (Foundation Models) en el propio Mac y tools sobre el contexto de Altillo. Nunca sale nada del Mac y nunca actúa por su cuenta: lee y responde (§5.7) |
| Fuera de alcance por ahora | Agente que actúa por ti, HUDs de volumen/brillo, batería, tiempo, bolsa. El portapapeles pasa a la fase 12 como opción |

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
- **Que respire:** el notch abierto mide entre unos 190 y 260 pt de alto (franja del notch + 8 pt + entre 130 y 200 pt de contenido + 16 pt de margen); con el Cajón, hasta unos 360 pt. Decidido con Xus el 24-09-2026, a la manera de OmniNotch: antes medía unos 150 pt y todo quedaba apretado. El peek sigue en 60 pt. Cada sección usa solo la altura que necesita, pero con aire: miniaturas, cifras y textos más grandes, no huecos vacíos. Objetivos de puntero de 28 pt como mínimo, textos de 11 pt como mínimo (12,5 pt si son frases) y símbolos de navegación de 13 pt.
- **Movimiento:** con peso: las cosas caen, se aplastan un poco y se asientan. Al cerrar, nunca rebotan. Los momentos firma son el ítem que aterriza en la balda, la caja que abre las solapas bajo el cursor, el "toc, toc" del agente que espera y el sello "Hecho". Con Reducir movimiento, todo son fundidos.
- **Voz:** cálida y doméstica, de tú, con verbos del altillo: "Súbelo ↑", "Suéltalo, ya lo guardo arriba", "¿Lo bajamos?".
- **Límite para no caer en lo cursi:** el sello solo aparece al terminar y las solapas solo en la zona de soltar. Todo lo demás es sobrio.

## 4. UX y personalización

### Qué se puede personalizar

| Área | Opciones |
|---|---|
| Módulos | Activar o desactivar cada uno y ordenar las pestañas del notch abierto |
| Orejas | Qué va en la izquierda y en la derecha: uso de IA, agentes, música, próximo evento, nº de ítems del shelf o nada. También si se ven siempre o solo con actividad |
| Comportamiento | Abrir con hover o con clic; retardo del hover; distancia a la que se activa el arrastre; cierre automático; atajo global de Pregunta; hápticos; qué avisos asoman (reunión en 5 min, canción nueva) |
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
  - Después, un collector nativo por proveedor (Cursor, Copilot, OpenRouter, Z.ai, Grok, Gemini/Antigravity, Devin, OpenCode…), cada uno con su `setupHint`. openusage (MIT) solo sirve de referencia de cómo funciona cada proveedor; si se adapta código, con atribución.
- ~~**Fuente opcional "compatible with OpenUsage"**~~: **retirada el 24-09-2026 por decisión tuya.** Altillo es independiente y lee cada proveedor de forma nativa: no lee datos de otras apps (no hay acuerdos) ni obliga a instalar ninguna ([detalle](docs/uso-ia.md#independencia-24-09-2026)).
- **Ajustes:** por defecto, todo proveedor encontrado en este Mac está activado y se puede apagar; los que no están configurados se pliegan en «Not set up on this Mac» con una línea de cómo configurarlos.
- **Refresco:** cada 5 min, stale-while-revalidate, y en pausa mientras el Mac duerme.
- **Publicación:** a CloudKit para iOS.

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
- **Mejoras sobre el plan inicial (24-09-2026):**
  - **Funciona sin instalar nada.** Altillo lee los ficheros de sesión que los propios agentes escriben (`~/.claude/projects/…/*.jsonl` y `~/.codex/sessions/…/rollout-*.jsonl`), solo el final y solo cuando cambian. Así muestra qué sesiones hay y si trabajan o esperan. Los hooks pasan a ser un extra: estados precisos y aprobar desde el notch.
  - **«Ir a la terminal» de verdad.** El hook guarda desde qué app y pestaña corre el agente: Terminal, iTerm2, Ghostty, Warp, VS Code o Cursor, gracias a `TERM_PROGRAM`, el id de sesión, el tty y la cadena de procesos. Altillo trae al frente esa ventana y, cuando se puede, la pestaña exacta.
  - **Resumen al terminar:** el aviso incluye el principio del último mensaje del agente.
  - **«Permitir en esta sesión»** cuando el agente lo ofrece, con los permission suggestions de Claude.
  - **Pregunta** sabe de agentes («¿qué está haciendo Codex?»).
  - **Ruta estable del hook** (`~/Library/Application Support/Altillo/bin/altillo-hook`), para que los hooks sigan funcionando al mover o actualizar la app.
  - **Siguiente tanda:** Gemini CLI y Copilot CLI (hooks) y OpenCode (SSE). Más adelante, **responder al agente desde el notch** cuando espera tu respuesta: el hook `Stop` de Claude puede devolverle una instrucción para que siga.

### 5.4 Cajón / Drawer ([implementación y pruebas](docs/cajon.md))
- **Qué hace:** cuando está activo, una estantería compacta permanece encima de los modos y las opciones de Altillo. En Ajustes, el usuario mueve los iconos entre las zonas **Altillo** y **Menu Bar**; Drawer los oculta y ofrece búsqueda y apertura desde la estantería, con `AXExtrasMenuBar`, `AXPress` y `AXShowMenu`. El panel se recoge antes de abrir un menú.
- **Permisos:** Accesibilidad. Se muestran iconos de aplicación; no se solicita Grabación de Pantalla ni Monitorización de Entrada.
- **Ocultación en macOS 26:** separador de longitud adaptable y control visible para recuperar el grupo. Opt-in; posiciones conservadas por macOS. Cambios de pantalla, apps nuevas y fallos de acceso muestran el grupo.
- **Otras versiones:** ocultación deshabilitada; catálogo AX disponible según las apps. Sin APIs privadas ni garantía de compatibilidad no comprobada.
- **Colocación:** el gesto ⌘-arrastre usa eventos públicos de `CGEvent` y se verifica mediante Accesibilidad. Los elementos que no aceptan el gesto se marcan como inamovibles. La aceptación en MacBook con notch y monitores externos sigue la matriz manual del documento enlazado.

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

### 5.7 Pregunta: el asistente on-device ([análisis de OmniNotch](docs/omninotch.md))
- **Modelo:** `FoundationModels` (`SystemLanguageModel.default`), en el Mac, sin red ni cuentas. Si el Mac no es compatible, Apple Intelligence está apagado o el modelo se descarga, lo dice y lleva a Ajustes del Sistema.
- **La diferencia es el contexto:** OmniNotch responde «no puedo ver tu calendario». Pregunta usa tools sobre lo que Altillo ya tiene:
  - **shelf:** lista lo que hay arriba y lee texto, Markdown, código, RTF y PDF;
  - **calendario:** solo si ya hay permiso, nunca lo pide;
  - **música:** solo si Música o Spotify ya están abiertos;
  - **portapapeles:** solo el texto actual; ignora lo marcado como contraseña o transitorio.
  - Más adelante: uso de IA (fase 3) y agentes (fase 4).
- **Integración:** «Súbelo» convierte la respuesta en un texto del shelf que puedes arrastrar a cualquier app. Las sugerencias salen de lo que hay (por ejemplo, «Resume *informe.pdf*» si hay un PDF arriba).
- **Invocación:** pestaña propia y atajo global ⌃⌥A (configurable: ⌥Espacio, ⌃⌥Espacio o ninguno), que abre el notch con el cursor en el campo. Mientras escribes o esperas respuesta, el notch no se cierra al apartar el puntero.
- **Privacidad:** la conversación vive solo en memoria y no se guarda. Si la respuesta termina con el notch cerrado, asoma un aviso.
- **Enrutado (24-09-2026):** el modelo pequeño usaba las tools para todo, así que Altillo clasifica cada pregunta antes de enviarla:
  - **charla** (saber general, redacción, traducción, cuentas): sin tools. Los porcentajes y operaciones se calculan exactos y se le pasan al modelo;
  - **tus cosas:** solo las tools locales;
  - **en vivo:** Altillo busca en la web y le pasa los resultados.
- **Web, opcional y desactivada por defecto:**
  - Busca en DuckDuckGo, con Bing y Wikipedia de respaldo. El tiempo lo saca de Open-Meteo, al que solo le envía el nombre del sitio.
  - Máximo 2.500 caracteres, sin cookies y con tiempo límite de 6 s.
  - Con la web apagada no sale nada del Mac. Si hace falta algo en vivo, ofrece «Buscar en la web» solo para esa pregunta, «Permitir siempre» o «Abrir en el navegador».
  - Las respuestas que han usado la web muestran sus fuentes.

### 5.8 Avisos en vivo (peeks)
- `NotchAlert`: el notch crece a una línea unos segundos y vuelve solo. Si pasas el puntero se queda; con clic (o descansando encima) abre la sección del aviso.
- **Nunca interrumpe:** no aparece con el notch abierto, durante un arrastre ni en escenarios de diseño. Un aviso nuevo sustituye al anterior.
- **Fuentes, todas por eventos y sin sondeo:**
  - calendario, 5 min antes, con un temporizador hasta el siguiente evento;
  - canción nueva, por notificaciones distribuidas de Música y Spotify. Desactivado por defecto.
  - Después: agente que espera (fase 4) y umbral de uso (fase 3).

### 5.9 Movimiento e interacción
- **Apertura «líquida»:** resorte con un rebote sutil, y el contenido entra desenfocado y se enfoca detrás de la forma. Al cerrar, desenfoque rápido y sin rebote. Con Reducir movimiento, fundidos.
- **Cambio de sección con dirección:** el contenido se desliza hacia donde vas, con clic, ⌘1…⌘9, ⌃Tab o **swipe con dos dedos**. En los extremos, efecto goma elástica.
- **Hápticos** (trackpad Force Touch, desactivables): solo como respuesta a algo que haces tú, es decir, al cambiar de sección con swipe y al aterrizar algo en el shelf. Un aviso nunca da un toque: bajo una mano en reposo parecería un fallo.

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
| **3. Uso de IA (K+M)** | AltilloUsage (Claude arreglado, Codex y después el resto de proveedores, todos nativos), oreja + pestaña + alertas en el notch | 0 | 1 semana |
| **4. Agentes en vivo (K+M)** | Sesiones sin configurar nada (ficheros de sesión), `altillo-hook`, socket, instalador de hooks seguro (Claude, Codex), peek automático, permitir/denegar/permitir en la sesión desde el notch, ir a la terminal exacta, resumen al terminar, Pregunta sabe de agentes | 2 | 1,5 semanas |
| **5. Altillo iOS v1 (K+I)** | AltilloSync (CKSyncEngine), app de iPhone desde cero: dashboard, agentes, widgets, notificaciones y personalización, con las features que se definan contigo llegado el momento | 3 (puede ir en paralelo con 4) | 2 semanas |
| **6. Dynamic Island + aprobar desde el iPhone (I+M)** | Live Activities, el Mac como proveedor de APNs (spike primero), permitir/denegar desde el iPhone con Face ID | 4, 5 | 1,5 semanas |
| **7. Barra de menú (M)** | Estantería persistente en Altillo, catálogo por zonas, iconos ocultos en el notch y ocultación de secciones en 26 | 2 | 1 semana |
| **8. AirDrop, Now Playing, calendario (M)** | §5.6 | 2 | 1-1,5 semanas |
| **9. Altillo compartido + iPad** | `ShelfItem` en CloudKit, extensión de compartir en iPhone, shelf en iPad, dashboard de iPad | 5 | 2 semanas |
| **10. Publicación** | Icono, nombre, bienvenida, web/README, Homebrew Cask, App Store (iOS) | — | 1 semana |
| **11. Vida: movimiento, avisos y Pregunta (M)** | Apertura «líquida», transiciones con dirección, swipe entre secciones, ⌘1…9, hápticos, avisos en vivo (calendario y música) y el asistente on-device con tools y atajo global (§5.7-5.9) | 1 | 1,5 semanas |
| **12. Utilidades del altillo (M)** | Temporizador (un reloj de cocina que asoma al sonar), nota rápida, portapapeles de solo texto (opt-in, excluye contraseñas), lanzador de Atajos. Pregunta aprende a usarlos («pon 10 min», «apunta esto») | 11 | 1,5 semanas |
| **13. Pregunta con todo el contexto (K+M)** | Los tools de uso y agentes ya llegaron con las fases 3 y 4. Queda: arrastrar un archivo a Pregunta para preguntarle por él, respuestas guardables, acciones (poner un temporizador, crear un recordatorio, responder a un agente) y dictado por voz | 3, 4, 11, 12 | 1 semana |
| **14. Más agentes (K+M)** | Gemini CLI, Copilot CLI y Cursor CLI (hooks), OpenCode (API de `opencode serve`); responder desde el notch cuando un agente espera tu respuesta | 4 | 1 semana |
| **15. Primer arranque (M)** | Bienvenida adelantada de la fase 10, ahora que ya hay releases públicas: plantilla, permisos explicados uno a uno (calendario, Automatización, Accesibilidad) solo cuando hacen falta, ofrecer los hooks y detectar qué proveedores de IA hay en el Mac | 4 | 3-4 días |

**Orden de ejecución (actualizado el 26-09-2026):** 11 ✓ → 2 ✓ → 3 ✓ → 4 ✓ → 15 ✓ → 12 ✓ → 14 ✓ → 13 ✓ → 8 ✓ → 10 ✓ (salvo publicar el tap y la marca) → 5 → 6 → 9. La fase 7 tiene su segunda pasada (iconos nítidos). Lo que queda es la companion de iPhone/iPad (5, 6 y 9), que se define contigo antes de empezar. Los números son identificadores, no el orden.

### Estado

- **Fases 14, 13, 8, 10 y 7 (26-09-2026, 0.6.0):**
  - **Más agentes (14):** Gemini CLI, Copilot CLI y Cursor por hooks; OpenCode sin instalar nada, por la API de `opencode serve`, con permisos y respuestas desde el notch. Cursor usa hooks y no ACP: ACP solo ve sesiones que abre la propia app.
    - **Responder desde el notch:** cuando un agente acaba su turno, el hook espera tu respuesta. Nunca espera si estás en su terminal, suelta en cuanto vuelves a ella y nunca en ejecuciones sin terminal (`-p`, `exec`, tuberías, editores) ni si Altillo no sabe qué terminal es (tmux, SSH). Activado por defecto en instalaciones nuevas de Claude Code y Codex; Gemini, Copilot y Cursor, opt-in.
    - Revisión independiente con 11 fallos corregidos (carreras de Cursor, colas y reconexión de OpenCode, trabajo en reposo sin OpenCode, desinstalación byte a byte).
  - **Pregunta con todo el contexto (13):** soltar un archivo en «Pregúntale» (texto, PDF, Word e imágenes con Vision), respuestas guardadas, recordatorios con deshacer (es/en/ca), dictado on-device y «dile a Claude que…» con tu texto exacto. Sabe qué suena en cualquier app. Revisión independiente con 15 fallos corregidos (falsos positivos de recordatorios y respuestas a agentes, fechas).
  - **Sonando universal (8):** cualquier app vía `mediaremote-adapter` (BSD-3, en `Vendor/`), que corre dentro de `/usr/bin/perl` porque desde macOS 15.4 MediaRemote solo responde a procesos de Apple. Sin sondeo, el ayudante vive solo mientras hace falta y muere con Altillo; si falla, vuelve a AppleScript con Música y Spotify. Arrastrar para saltar. Verificado en macOS 27.
  - **Publicación (10):** web con descarga y funciones reales (sin desplegar), capturas en el README, cask de Homebrew en `packaging/homebrew` con `script/update-cask.sh`, y [comprobación del nombre](docs/nombre.md). **Pendiente, que haces tú:** la búsqueda de marca en EUIPO/OEPM y decidir si creamos `XusBadia/homebrew-tap`.
  - **Cajón (7):** iconos capturados a la escala de la pantalla y sin reescalar; los monocromos se tiñen como plantillas.
  - **Calidad:** la mano que llama y la flecha de la bienvenida ya no animan sin parar (CPU en reposo con un agente esperando). `script/idle-cpu.sh` mide la CPU en reposo y `script/check-localization.py` impide publicar con textos sin traducir. En macOS 27 los tests se compilan en `/tmp` ([detalle](docs/desarrollo.md)).
  - TESTCOUNTS

- **Fase 3 (24-09-2026):** implementación terminada y validación automática en verde.
  - **`AltilloUsage`:**
    - **Claude:** llavero leído con `/usr/bin/security`, sin diálogos, y el fichero como respaldo. Nunca refresca ni escribe tokens; si la sesión caduca, pide abrir Claude Code una vez.
    - **Codex:** `codex app-server` por JSON-RPC, con `wham/usage` de respaldo en solo lectura.
    - ~~**Fuente compatible con OpenUsage**~~: retirada el 24-09-2026 por decisión tuya. Altillo lee todos los proveedores de forma nativa; los demás (Cursor, Copilot, OpenRouter, Z.ai, Grok, Gemini/Antigravity, Devin, OpenCode) llegan como collectors propios.
    - **Verificado en vivo contra la app oficial:** las cifras coinciden al punto (Claude Max 5x sesión 64 %/semana 57 %/Fable 10 %; Codex Pro 5x semana 100 %).
  - **En el notch:**
    - Pestaña Uso con anillos, ritmo («Hasta las 13:22», «Límite alcanzado») y estados de problema en una frase.
    - Estado en la cabecera («Al día · hace 2 min», desactualizado a los 15 min) y botón de actualizar.
    - La oreja de uso, y la oreja contextual solo cuando un límite pasa del primer umbral.
  - **Avisos:** umbrales 80/95 % configurables, límite agotado, se agota antes de recargarse y recargado. Nunca en la primera lectura y uno por ventana.
  - **Refresco:** cada 5 min, en pausa mientras el Mac duerme y una vez al despertar. La última instantánea se guarda en disco y la CPU en reposo es 0 %.
  - **Pregunta:** tiene tool `usage` («¿cuánto me queda de Claude?»).
  - 405 tests en macOS y 102 en `AltilloKit`, todos en verde.
  - **Retirado el 24-09-2026 (decisión tuya):** el escritor del formato antiguo `openusage.mobile.v1` (`OpenUsageMobilePublisher`) y toda la máquina de release para firmarlo con el perfil de iCloud de `iCloud.me.badia.ailimits`. La companion de iPhone/iPad es una app de Altillo desde cero, por definir contigo (fase 5, §6); no hay transición ni puente que mantener. Puedes retirar el bridge y su watchdog cuando quieras, como limpieza opcional ([docs/uso-ia.md](docs/uso-ia.md)).

- **Fases 15 y 12 (25-09-2026, 0.5.0):**
  - **Bienvenida (15):** seis pasos. Abrir el notch de verdad para seguir, plantilla con vista previa, herramientas de IA detectadas con la oferta de hooks (siempre con el diff), solo los permisos que pide lo activado, trucos y abrir al iniciar sesión, y tu primer archivo. Se vuelve a abrir desde el menú y desde Acerca de.
  - **Utilidades (12), opt-in y nunca activadas solas:**
    - **Temporizador:** reloj de cocina que se gira arrastrando, varios a la vez, sin sondeo; asoma y suena al terminar y sale en la oreja contextual.
    - **Nota:** se guarda sola, se arrastra fuera o se sube al altillo, y guarda un historial de 5.
    - **Portapapeles:** solo texto, nunca contraseñas ni nada copiado desde un gestor de contraseñas. El historial se guarda en memoria por defecto. La CPU pasa de 0,11 a 0,14 %.
    - **Atajos:** favoritos y buscador; solo se ejecutan con clic.
  - **Pregunta actúa:** pone temporizadores, apunta en la nota, lee el historial del portapapeles y ejecuta un atajo solo si se lo pides por su nombre. Siempre confirma qué ha hecho y se puede deshacer.
  - Las builds de desarrollo ya no le quitan el enlace del hook a la app instalada.
  - 539 tests en macOS y 305 en `AltilloKit`, todos en verde.

- **Fase 4 (25-09-2026, 0.4.0):** implementación terminada y validación automática en verde.
  - **Sin configurar nada:** Altillo muestra las sesiones de Claude Code y Codex leyendo solo el final de sus ficheros de sesión, cuando cambian y sin sondeo.
  - **Con hooks:** `altillo-hook` tarda unos 5 ms en arrancar.
    - Si Altillo está cerrado, sale al instante sin escribir nada. Si Altillo está congelado, pierde como mucho unos 3 s.
    - Permitir, Denegar y Permitir en esta sesión funcionan desde el notch; se probaron en vivo con Claude.
    - Nunca aprueba por su cuenta. Los comandos peligrosos se aprueban manteniendo pulsado el botón.
  - **Instalador:** enseña el diff, hace copia de seguridad, se puede repetir sin duplicar nada y se desinstala con un clic. Se probó sobre copias de los ficheros reales. Codex exige confiar en los hooks con `/hooks`.
  - **En el notch y en Pregunta:** ir a la terminal exacta, avisos (toc, toc, pregunta, terminado con resumen, fallo), oreja de agentes, oreja contextual y tool `agents` en Pregunta.
  - **Revisión independiente:** no encontró ningún camino que envíe una decisión que el usuario no haya tomado. Se corrigieron la espera sin límite al escribir en el socket, que otra instancia de Altillo pudiera quitarle el socket, y una carrera con `umask`.
  - 459 tests en macOS y 305 en `AltilloKit`, todos en verde.
  - **Pendiente, que haces tú:** instalar los hooks desde Ajustes › Secciones › Agentes, confiar en ellos en Codex con `/hooks`, y probar aprobar desde el notch con un trackpad real.
  - **Sin verificar en vivo:** los payloads de herramientas y permisos de Codex, porque la cuenta estaba en su límite de uso; se cubren con fixtures del esquema publicado.

- **Independencia del uso de IA (24-09-2026, 0.3.1):**
  - Fuera la lectura de otras apps.
  - Altillo lee por sí mismo **10 proveedores**: Claude, Codex, Cursor, GitHub Copilot, Gemini (Antigravity), Grok, OpenRouter, Z.ai, Devin y OpenCode. Usa las credenciales que ya guardan sus propias herramientas, en solo lectura y sin renovar nunca un token.
  - Verificado en vivo: Claude, Codex, Copilot (Free) y Grok (SuperGrok). Los demás muestran cómo configurarlos.
  - openusage (MIT) es solo referencia, con atribución en `ThirdPartyNotices`.
  - Sus cambios se vigilan con `script/openusage-upstream.sh` y un workflow semanal que abre un issue ([docs/proveedores.md](docs/proveedores.md)).

- **Ronda de feedback de la 0.2.0 (24-09-2026):**
  - El notch abierto es más alto y respira (unos 250-290 pt; el panel pasa a 780×440).
  - Zonas de clic de 28 pt como mínimo, iconos de 13 pt como mínimo y textos de 11 pt como mínimo. El texto terciario tiene más contraste.
  - La ventana de Ajustes tiene barra de pestañas propia, sin solaparse con el título.
  - Calendario con vista de mes: mes, agenda, o mes y agenda. Se eligen los calendarios visibles y si se ven los eventos de todo el día, y los ocultos tampoco salen en orejas, avisos ni Pregunta.
  - Pregunta enruta las preguntas y puede buscar en la web si lo permites (§5.7).
  - Publicado como 0.2.1.

- **Fase 2 (23-09-2026):** implementación terminada y validación automática en verde.
  - **Modo edición del notch:** clic derecho en el notch cerrado, clic derecho en la banda del abierto, el menú «Personalizar el notch…» o Ajustes › Secciones.
    - Las pestañas tiemblan y se reordenan arrastrando; con «−» se guardan en una caja y con «+» vuelven.
    - Las orejas se eligen arrastrando fichas a los huecos junto al notch, con la opción «Si hay algo / Siempre».
    - Tres plantillas (Mínimo, Desarrollador, Todo). Todo se puede deshacer con ⌘Z y el botón «Hecho» cierra el modo.
    - Funciona con teclado (flechas y espacio) y VoiceOver. Con Reducir movimiento no tiembla.
  - **Orejas reales, todas por eventos:** cosas en el altillo, próximo evento («10:30» / «en 12 min») y un ecualizador mientras suena música. Uso y agentes están marcados como «muy pronto».
  - **Pantallas:**
    - Se puede elegir dónde aparece: la del notch, la de la barra de menús, todas o la del puntero.
    - Sobre una app a pantalla completa, por defecto solo aparece al arrastrar algo.
    - Detección de pantalla completa sin permisos, con `CGWindowList` y en cada cambio de espacio.
    - Reposo, reactivación, conexión de pantallas y cambio de usuario sin paneles duplicados.
  - **Release:**
    - Sparkle 2.10.0, con «Buscar actualizaciones…» en el menú y en Ajustes › Acerca de.
    - Entitlements de cámara, Apple Events y calendario, que el hardened runtime exigía.
    - `script/release.sh`, con CI en tags `v*` y [docs/release.md](docs/release.md).
    - Ensayo real firmado con Developer ID, con DMG y appcast. Falta la notarización, que necesita tu perfil.
  - **Cajón:** sin sondeo. Caché de iconos, refresco por eventos (AX, apps, espacios, pantallas) y comprobación de permisos acotada a 2 min.
  - **Accesibilidad del panel:** grupo «Altillo» para VoiceOver, Esc cierra y «Abrir Altillo» da el foco de teclado.
  - **Rendimiento:** CPU en reposo 0,0 % (15 muestras de 1 s, con el Cajón activado) y 24 MB de memoria.
  - 300 tests en macOS y 31 en `AltilloKit`, todos en verde. La app de iOS compila.
  - **Pendiente, que haces tú:** la configuración de la release (ver [docs/release.md](docs/release.md)), publicar la 0.2.0, instalarla en el MacBook y recorrer la lista de macOS 27 y del notch real. No se marca la fase como aceptada hasta pasar una semana sin bugs en los dos Macs.

- **Fase 11 (23-09-2026):** implementación terminada y validación automática en verde.
  - **Movimiento:**
    - Apertura con resorte 0,4 s / rebote 0,3: pico a unos 280 ms y un 3-5 % de sobrepaso. El contenido entra con desenfoque 10 y escala 0,95 y se enfoca. Al cerrar no hay rebote, con el 90 % recogido a los 130 ms.
    - Anchura y altura se animan por separado, así que lo que crece rebota y lo que encoge no.
    - Los peeks crecen primero hacia los lados y luego bajan.
    - Las secciones se deslizan en la dirección del cambio, con goma elástica en los extremos. Todo tiene su versión con Reducir movimiento.
    - Grabado en pantalla y comparado con OmniNotch.
  - **Interacción:** swipe con dos dedos entre secciones (fuera de la fila del altillo), ⌘1…⌘9, ⌃Tab y hápticos desactivables.
  - **Avisos en vivo:**
    - Reunión 5 min antes, con un solo temporizador hasta el siguiente evento y sin pedir permisos.
    - Canción nueva, por notificaciones distribuidas y desactivado por defecto.
    - Pasar el puntero mantiene el aviso y el clic abre su sección.
  - **Pregunta:**
    - Foundation Models con 4 tools: altillo (lee texto, Markdown, código, RTF, Word y PDF), calendario, música y portapapeles.
    - Streaming, parar, conversación nueva, «Súbelo al altillo», sugerencias según el contexto y aviso si la respuesta acaba con el notch cerrado.
    - Atajo global ⌃⌥A. Mientras escribes, el notch no se cierra.
    - Probado con el modelo real: responde en español y usa las tools. La conversación solo vive en memoria.
  - Ajustes › Comportamiento: atajo, hápticos y avisos. Una sección nueva llega activada a quien ya tenía la app (`knownModules`).
  - 223 tests en macOS y 29 en `AltilloKit`, todos en verde. La app de iOS compila.
  - **Pendiente, que haces tú:**
    - Probar el swipe con un trackpad de verdad y los hápticos en un Force Touch.
    - Confirmar el aviso de canción nueva con Música o Spotify abiertos: las claves de `userInfo` siguen la documentación conocida, pero no se han visto en vivo.
    - Probar el notch real del MacBook.
  - **Detectado fuera de la fase y ya resuelto en la fase 2:** el Cajón refrescaba y capturaba iconos cada 2 s. Ahora funciona por eventos.

- **Cajón / Drawer (20-09-2026, primera implementación de fase 7):** estantería persistente sobre la navegación, con catálogo AX y dos zonas de configuración. Los movimientos entre zonas usan ⌘-arrastre público y verificación AX; la ocultación es opt-in en macOS 26 y la recuperación es segura. La apertura vuelve a mostrar el grupo para dar al menú un anclaje visible. Si la barra sigue llena, explica el límite y no abre un menú fuera de pantalla. Pendiente aceptación física con notch, varias pantallas y barra autooculta; [detalle](docs/cajon.md).

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
- **3:** los datos de Claude y Codex coinciden con los de las apps oficiales.
- **4:** apruebas un permiso de Claude Code desde el notch. Con Altillo cerrado, Claude Code se comporta exactamente igual que sin hooks.
- **5:** el iPhone muestra los usos y agentes de los dos Macs y los widgets se actualizan solos.
- **6:** la Dynamic Island avisa en < 5 s cuando un agente espera permiso.
- **7:** en el MacBook, un icono tapado por el notch se abre desde Altillo con un clic.
- **11:**
  - Grabada a 60 fps, la apertura muestra el rebote y el enfoque del contenido y el cierre no rebota. Con Reducir movimiento todo son fundidos.
  - «¿Qué tengo hoy?» y «Resume el PDF que he subido» responden con datos reales, sin salir del Mac.
  - ⌃⌥A abre Pregunta desde cualquier app.
  - Una reunión asoma 5 min antes sin gastar CPU en reposo.

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
