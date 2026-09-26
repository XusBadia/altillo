# Auditoría UI/UX de Altillo — 26 de septiembre de 2026

**Estado:** revisión de la fuente en `d362352` más los cambios locales existentes en Drawer y Settings. Son mejoras propuestas; no se han implementado en esta auditoría. La app instalada inspeccionada visualmente en las cinco pestañas de Settings mostraba versión 0.1.0 y no coincidía por completo con el árbol actual (por ejemplo, faltaba Keep Awake). Por ello, sus observaciones visuales sirven de contexto, no de validación del HEAD. También se revisaron las capturas locales de reposo, destino de arrastre y Agents. No se ejecutaron pruebas nuevas ni una sesión de la build actual.

El alcance cubre el chrome del notch en reposo, abierto, peek, recepción de archivos y edición; las doce secciones, Drawer, las cinco pestañas de Settings, las seis páginas condicionales de bienvenida y los targets iOS y Widget. La evaluación separa defectos demostrables por código de riesgos de layout o accesibilidad pendientes de comprobar en una build del HEAD. El criterio principal es si el usuario entiende el estado, puede actuar con teclado y VoiceOver y recibe una vía de recuperación cuando algo falla.

## Inventario de pantallas y estados

| Superficie | Estados y rutas revisados | Fuente |
| --- | --- | --- |
| Chrome | Reposo con indicadores laterales, notch/isla abierto, selección de pestaña, peek, arrastre y destino de archivo, edición y presets | `Apps/macOS/Views/Desvan/DesvanExpanded.swift`, `DesvanDrop.swift`, `Edit/DesvanEditBody.swift` |
| Shelf | Vacío, archivos y selección, menú de acciones, arrastre de salida, recepción, error | `Apps/macOS/Views/Desvan/DesvanShelf.swift` |
| Ask | Bienvenida, prompt, respuesta en streaming, búsqueda web, fuentes, adjuntos y respuestas guardadas | `Apps/macOS/Views/Desvan/Modules/DesvanAssistant.swift`, `DesvanAssistantParts.swift` |
| Usage | Proveedores, barras y ventanas de consumo, actualización y datos antiguos, estados de proveedor | `Apps/macOS/Views/Desvan/DesvanUsage.swift` |
| Agents | Sesión, petición de permiso, canal de respuesta, cuenta atrás, terminal, resultado y expiración | `Apps/macOS/Views/Desvan/DesvanAgents.swift` |
| Calendar | Acceso desconocido/denegado, carga, vacío y eventos; agenda, mes, día, navegación y opciones | `Apps/macOS/Views/Desvan/Modules/DesvanCalendar.swift`, `Calendar/DesvanCalendarBoard.swift`, `Calendar/DesvanCalendarDay.swift` |
| Mirror | Sin cámara, acceso desconocido/denegado, vista previa, cambio de cámara y espejo | `Apps/macOS/Views/Desvan/Modules/DesvanMirror.swift`, `Apps/macOS/Modules/MirrorStore.swift` |
| Now playing | Automation denegada, reproductor inactivo, reproducción, carátula, controles y scrub | `Apps/macOS/Views/Desvan/Modules/DesvanNowPlaying.swift` |
| Timer | Nuevo, en marcha, pausa, alarma, varios temporizadores y etiquetas | `Apps/macOS/Views/Desvan/Modules/DesvanTimer.swift` |
| Note | Edición, copiar, shelf, arrastre, nueva nota, historial, borrar y deshacer | `Apps/macOS/Views/Desvan/Modules/DesvanNote.swift` |
| Clipboard | Desactivado, vacío, búsqueda sin resultados, entradas, fijar, copiar, borrar, shelf y deshacer | `Apps/macOS/Views/Desvan/Modules/DesvanClipboard.swift` |
| Shortcuts | App ausente, error, carga, vacío, favoritos, búsqueda, lista, ejecución y resultado | `Apps/macOS/Views/Desvan/Modules/DesvanShortcuts.swift` |
| Keep Awake | Inactivo, sesión temporal e indefinida | `Apps/macOS/Views/Desvan/Modules/DesvanKeepAwake.swift` |
| Drawer | Permisos Accessibility y Screen Recording, carga, vacío, iconos, movimiento, reordenación y errores | `Apps/macOS/Views/Desvan/Modules/DesvanDrawer.swift`, `Apps/macOS/Settings/SettingsDrawerPane.swift` |
| Settings | Sections (ears, orden, Calendar, Usage, Agents, presets), Drawer (on/off, permisos, soporte parcial, carga/error/vacío), Size (slider, presets, previews), Behaviour (apertura, pantallas, login, Ask, alertas, caducidad), About (actualizaciones configuradas o no, tour, enlaces) | `Apps/macOS/Settings/SettingsRootView.swift` y los cinco `Settings*Pane.swift` |
| Menú de app y superficies auxiliares | Open, Customize, Settings, Welcome, Updates, Design Review, deshacer, vaciar y salir; revisión de hooks con diff, cancelación, instalación/eliminación y backups; Spike Log con filtro, scroll, copia y limpieza | `Apps/macOS/App/AltilloApp.swift`, `Apps/macOS/Modules/Agents/Installer/AgentHooksSettingsGroup.swift:399`, `Apps/macOS/Debug/SpikeLog.swift:76` |
| Bienvenida | Hello, Preset, AI Tools (detección y revisión de hooks), Permissions (cuatro permisos y estados), Tricks, Done; navegación, Skip y cierre | `Apps/macOS/Onboarding/OnboardingRootView.swift`, `OnboardingLogic.swift` y páginas respectivas |
| iOS y Widget | Pantalla “Coming soon” y widget estático de texto. Son scaffolds declarados y no publicados | `Apps/iOS/AltilloApp.swift:13`, `Apps/Widgets/AltilloWidgets.swift:4`, `README.md:165` |

No aparece un defecto sólido que justifique cambios en Now playing, Timer o Keep Awake tras esta revisión de fuente. La UI visual existente muestra un lenguaje coherente de madera, papel y acento cálido; no hay evidencia para rediseñarla por completo.

## Hallazgos priorizados

**P1 — Bloqueos funcionales o información crítica que desaparece. P2 — Fricción frecuente o recuperación débil. P3 — Pulido y riesgos que requieren validación visual/manual.** Esfuerzo: S = horas, M = aproximadamente un día, L = varios días. La confianza expresa certeza del diagnóstico en la fuente, no que se haya reproducido en el HEAD.

| ID | Prioridad | Superficie | Esfuerzo | Riesgo | Confianza |
| --- | --- | --- | --- | --- | --- |
| UI-01 | P1 | Mirror: permiso y cámara conectada | S–M | MED | HIGH/MED |
| UI-02 | P1 | Mirror: arranque de captura | M | MED | MED en el síntoma |
| UI-03 | P1 | Edición: doce pestañas | M | MED | HIGH/MED |
| UI-04 | P2 | Ask: scroll en streaming | S–M | LOW | HIGH |
| UI-05 | P2 | Agents: canal vencido | S | LOW | HIGH |
| UI-06 | P2 | Note: botón sin acción | S | LOW | HIGH |
| UI-07 | P2 | Shelf: error con contenido | S | LOW | HIGH |
| UI-08 | P2 | Onboarding: progreso AI Tools | S | LOW | HIGH |
| UI-09 | P2 | Calendar: carga de otro día | S | LOW | HIGH |
| UI-10 | P2 | Drop: contraste normal | S | LOW | MED |
| UI-11 | P2 | Ask: respuestas guardadas | S–M | LOW | HIGH |
| UI-12 | P3 | Layout y nombres largos | S–M | LOW | MED |
| UI-13 | P3 | Settings: alternativa al drag | S | LOW | HIGH/MED |
| UI-14 | P3 | Drawer: carga y vacío | S | LOW | HIGH |

### [UI-01 · P1] Recuperar Mirror tras conceder acceso o conectar una cámara

- **Evidencia:** `Apps/macOS/Modules/MirrorStore.swift:46` fija el estado de permiso al inicializar; `MirrorStore.swift:63-73` vuelve a buscar cámaras pero, si el estado sigue `.denied`, no consulta de nuevo al sistema. `Apps/macOS/Views/Desvan/Modules/DesvanMirror.swift:53-60` pide abrir System Settings y reabrir el notch. No hay observador de conexión/desconexión de dispositivos en el store.
- **Impacto:** tras conceder Camera en System Settings, reabrir Mirror puede seguir mostrando “The camera is off” hasta reiniciar la app. Conectar una cámara después de entrar en el estado “sin cámara” tampoco tiene una ruta de actualización visible.
- **Mejora:** reconsultar permiso y dispositivos al iniciar o al volver a primer plano, y actualizar la vista al conectar/desconectar cámaras.
- **Aceptación:** tras otorgar acceso, cerrar y abrir Mirror muestra la vista previa sin reiniciar Altillo; conectar o desconectar una cámara actualiza el estado con la pestaña abierta.
- **Esfuerzo:** S–M. **Riesgo:** MED, por el ciclo de vida de captura y los cambios de dispositivo. **Confianza:** HIGH para permiso persistente; MED para hotplug en ejecución.

### [UI-02 · P1] Mostrar si la sesión de Mirror no llega a arrancar

- **Evidencia:** `Apps/macOS/Modules/MirrorStore.swift:101-107` marca `isRunning = true` inmediatamente después de enviar `engine.start` a una cola; `MirrorStore.swift:170-178` configura y arranca la sesión de forma asíncrona; `MirrorStore.swift:197-204` descarta sin informar el fallo al crear/añadir el input.
- **Impacto:** una cámara ocupada o una configuración fallida puede dejar una vista negra que la UI interpreta como sesión activa, sin error ni recuperación.
- **Mejora:** separar estados iniciando/activo/error desde el resultado real del engine; ofrecer reintento o cambio de cámara.
- **Aceptación:** si la captura falla, Mirror presenta un mensaje específico y una acción de recuperación, y `isRunning` solo refleja una sesión realmente activa.
- **Esfuerzo:** M. **Riesgo:** MED, por sincronización entre cola de captura y actor principal. **Confianza:** HIGH para la falta de confirmación en código; MED para la manifestación concreta en una cámara real.

### [UI-03 · P1] Hacer alcanzables las doce pestañas del modo edición

- **Evidencia:** `Apps/macOS/Notch/NotchModule.swift:5` define doce módulos; `Apps/macOS/Views/Desvan/Edit/DesvanEditBody.swift:15-16` reserva 70 pt a la leyenda y `DesvanEditBody.swift:119-133,179-182` reparte el ancho restante entre todas las fichas, sin scroll. En 440 pt, descontando el inset de contenido de 26 pt, leyenda y huecos, cada ficha queda en torno a 21 pt. La bandeja de módulos guardados usa otro `HStack` sin scroll (`DesvanEditBody.swift:499-518`).
- **Impacto:** con todas las secciones activas, los iconos y los controles de quitar quedan comprimidos y cuesta identificarlos o apuntar a ellos; con muchas secciones guardadas, el extremo de la bandeja puede quedar fuera del área utilizable.
- **Mejora:** establecer un ancho mínimo operativo por ficha y una forma desplazable o adaptable de acceder a todas; aplicar lo mismo a la bandeja.
- **Aceptación:** a 440, 560 y 760 pt, con doce módulos activos o once guardados, cada ficha y acción sigue visible/alcanzable con ratón, teclado y VoiceOver.
- **Esfuerzo:** M. **Riesgo:** MED, porque cambia geometría y destino del drag. **Confianza:** HIGH para la compresión calculada; MED para el alcance exacto del desbordamiento sin captura del HEAD.

### [UI-04 · P2] Evitar que Ask quite la lectura mientras llega una respuesta

- **Evidencia:** `Apps/macOS/Views/Desvan/Modules/DesvanAssistant.swift:406-414` desplaza siempre la conversación al fondo en cada cambio del último texto o estado, sin comprobar si el usuario ha subido a leer.
- **Impacto:** al revisar una parte anterior mientras la respuesta continúa, cada fragmento nuevo devuelve el scroll al final.
- **Mejora:** seguir automáticamente solo cuando la persona ya está cerca del fondo; ofrecer una acción para volver a la respuesta actual si ha subido.
- **Aceptación:** desplazarse hacia arriba durante streaming mantiene la posición; permanecer al fondo sigue la respuesta.
- **Esfuerzo:** S–M. **Riesgo:** LOW, limitado al seguimiento del scroll. **Confianza:** HIGH.

### [UI-05 · P2] Explicar el vencimiento del canal de respuesta de Agents

- **Evidencia:** `Apps/macOS/Views/Desvan/DesvanAgents.swift:126-129` devuelve `nil` cuando el canal de respuesta ha vencido; `DesvanAgents.swift:364-375` solo explica el caso de permiso vencido o de `session.reply == nil`, no el canal presente pero expirado.
- **Impacto:** desaparece la opción de responder desde Altillo sin indicar por qué; el usuario puede creer que la petición sigue abierta o que se perdió su respuesta.
- **Mejora:** mostrar un estado explícito “la respuesta ya se hace en el terminal” cuando vence el canal y mantener la vía para enfocarlo.
- **Aceptación:** al cruzar `expiresAt`, el botón deja de ofrecer una respuesta imposible y aparece explicación y ruta al terminal.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH.

### [UI-06 · P2] Hacer que “Drag the note out” responda al clic

- **Evidencia:** `Apps/macOS/Views/Desvan/Modules/DesvanNote.swift:162-164` presenta un `Button` etiquetado “Drag the note out” con acción vacía; el trabajo real está en el modificador de arrastre.
- **Impacto:** pulsarlo con clic, Return, Space o VoiceOver no produce nada aunque se anuncia como botón. La acción principal depende de descubrir el gesto.
- **Mejora:** convertirlo en un control que abra Share/guarde el archivo al activarlo, o presentarlo sin semántica de botón y ofrecer alternativa de teclado.
- **Aceptación:** toda activación anunciada como botón produce un resultado; arrastrar la nota sigue funcionando.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH.

### [UI-07 · P2] Mostrar completo el error de Shelf cuando hay archivos

- **Evidencia:** el estado vacío incorpora `problem` en título y detalle (`Apps/macOS/Views/Desvan/DesvanShelf.swift:565-605`); con archivos, `Apps/macOS/Views/Desvan/DesvanExpanded.swift:610-614` sustituye la línea de estado por un icono cuyo texto solo está en `.help` y etiqueta accesible.
- **Impacto:** una importación parcialmente fallida queda reducida a un triángulo y exige hover; quien usa teclado sin VoiceOver no ve qué ocurrió.
- **Mejora:** mostrar mensaje breve en línea con acceso al detalle y acción de recuperación cuando la estantería no está vacía.
- **Aceptación:** el mismo error se puede leer y resolver tanto con Shelf vacío como con elementos presentes, sin hover.
- **Esfuerzo:** S. **Riesgo:** LOW, aunque hay que cuidar el ancho estrecho. **Confianza:** HIGH.

### [UI-08 · P2] Corregir el progreso cuando AI Tools desaparece durante la detección

- **Evidencia:** `Apps/macOS/Onboarding/OnboardingAIToolsPage.swift:35-38` inicia la detección al aparecer; `Apps/macOS/Onboarding/OnboardingLogic.swift:116-118` excluye AI Tools cuando no encuentra nada; `Apps/macOS/Onboarding/OnboardingComponents.swift:41-52,64-67` ya no puede iluminar la página actual y le asigna la posición de la anterior.
- **Impacto:** con Usage/Agents seleccionados y ningún proveedor/agente instalado, la pantalla AI Tools sigue visible mientras la cabecera y VoiceOver anuncian otro paso y ninguna barra aparece activa.
- **Mejora:** mantener la página actual en la secuencia hasta abandonarla o congelar los pasos del flujo durante la visita.
- **Aceptación:** durante y después de una búsqueda vacía, barra y anuncio corresponden a AI Tools; Continue pasa a la siguiente pantalla aplicable.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH.

### [UI-09 · P2] Mantener visible la carga de un día de Calendar

- **Evidencia:** `Apps/macOS/Views/Desvan/Modules/Calendar/DesvanCalendarBoard.swift:174-182` pasa `isLoaded = false` al navegar a un mes aún no cargado; `Calendar/DesvanCalendarDay.swift:101-127` muestra “Checking your calendar…” solo para hoy y no presenta contenido para otro día sin eventos y aún no cargado.
- **Impacto:** el panel de un día futuro puede parecer vacío o roto mientras espera EventKit; después puede aparecer una agenda sin transición explicativa.
- **Mejora:** presentar estado de carga para cualquier día, separado del vacío confirmado.
- **Aceptación:** navegar a un mes pendiente muestra “Checking…” hasta que llega el resultado; solo después se ve “Nothing on this day”.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH.

### [UI-10 · P2] Asegurar contraste legible en instrucciones del destino de drop

- **Evidencia:** `Apps/macOS/Views/Desvan/DesvanTheme.swift:26` define `paperSecondary` con opacidad 0,62; `DesvanDrop.swift:89,123,162,165` aplica otra opacidad de 0,6 a los textos secundarios en estado normal. El compuesto de 0,62 × 0,6 deja una opacidad nominal de 0,372 y un contraste estimado cercano a 3,0–3,2:1 sobre superficies oscuras del diseño.
- **Impacto:** instrucciones breves que explican dónde soltar un archivo pueden resultar difíciles de leer para baja visión en su estado normal. Al hacer hover la opacidad sube y mejora. La cifra es estimación de tokens, no medición de píxeles renderizados.
- **Mejora:** usar un color de texto que supere 4,5:1 en los estados normal y hover, y medir sobre la superficie compuesta real.
- **Aceptación:** las instrucciones esenciales alcanzan 4,5:1 en capturas de ambos estados y siguen claras con Reduce Transparency.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** MED hasta medir el render final.

### [UI-11 · P2] Dar acceso completo a las respuestas guardadas de Ask

- **Evidencia:** `Apps/macOS/Views/Desvan/Modules/DesvanAssistantParts.swift:290-296` limita el texto a dos líneas y a seis solo durante hover; no hay control para expandirlo por clic o teclado.
- **Impacto:** una respuesta larga guardada no puede leerse íntegra visualmente desde esa lista usando teclado o ratón sin copiarla fuera; el hover tampoco garantiza el texto completo. No se presupone cómo VoiceOver verbaliza el `Text` truncado.
- **Mejora:** abrir detalle o permitir expansión explícita del elemento, conservando Copy y Shelf.
- **Aceptación:** cualquier respuesta guardada puede leerse completa con teclado/VoiceOver sin exportarla; la lista mantiene su densidad inicial.
- **Esfuerzo:** S–M. **Riesgo:** LOW. **Confianza:** HIGH.

### [UI-12 · P3] Adaptar las pantallas fijas y encabezados largos al espacio real

- **Evidencia:** `Apps/macOS/Onboarding/OnboardingPresetPage.swift:10-44` coloca tres cards y nota en un `VStack` sin scroll; `Apps/macOS/Settings/SettingsAboutPane.swift:28-105` tampoco desplaza contenido; las ventanas fijan altura en `OnboardingWindowController.swift:67-70` y `SettingsWindow.swift:23,106`. En el notch, `Apps/macOS/Views/Desvan/DesvanAgents.swift:217-226` y `DesvanUsage.swift:158-165` fuerzan nombres largos a una línea y `fixedSize`.
- **Impacto:** traducciones, nombres de proyectos/proveedores y tamaños de texto mayores pueden truncar, comprimir u ocultar contenido sin alternativa. El clipping exacto debe verificarse en la build actual.
- **Mejora:** scroll vertical basado en tamaño para Preset/About y truncado con detalle accesible o layout adaptable en cabeceras del notch.
- **Aceptación:** a texto grande y con cadenas largas de prueba, todas las opciones, la nota, la tarjeta de soporte y los nombres siguen alcanzables; el footer del tour permanece utilizable.
- **Esfuerzo:** S–M. **Riesgo:** LOW. **Confianza:** MED.

### [UI-13 · P3] Hacer explícitas las alternativas al arrastre en Settings

- **Evidencia:** `Apps/macOS/Settings/SettingsModulesPane.swift:40-50` pide arrastrar para reordenar; `SettingsModulesPane.swift:486-499` ofrece “Move Earlier/Later” solo en el menú contextual. En Drawer existen acciones AX de movimiento (`SettingsDrawerPane.swift:449-456`) y menú contextual de orden (`SettingsDrawerPane.swift:465-469`), pero `SettingsDrawerPane.swift:278-279` también solo instruye a arrastrar.
- **Impacto:** la reordenación con teclado/VoiceOver depende de descubrir el menú contextual; no se afirma que sea imposible, porque macOS puede abrirlo desde teclado.
- **Mejora:** añadir acciones AX de orden a las filas de Sections, y nombrar la alternativa de menú/teclado en las instrucciones pertinentes.
- **Aceptación:** VoiceOver anuncia “Move Earlier/Later” cuando procede; el orden persiste y el texto visible no presupone ratón.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH para ausencia de acciones explícitas, MED para fricción en ejecución.

### [UI-14 · P3] Diferenciar búsqueda y vacío en Drawer

- **Evidencia:** `Apps/macOS/Settings/SettingsDrawerPane.swift:268-272` muestra “Finding menu bar icons…” durante carga; `SettingsDrawerPane.swift:341-350` muestra simultáneamente “Drag icons here” en cada zona sin entradas.
- **Impacto:** al abrir Drawer por primera vez, las zonas parecen vacías aunque la búsqueda siga en curso.
- **Mejora:** renderizar estado de carga en las zonas hasta el primer resultado, y reservar el mensaje de vacío para el final.
- **Aceptación:** con `isLoading` y listas vacías solo se comunica carga; al terminar sin iconos aparece la instrucción de estado vacío.
- **Esfuerzo:** S. **Riesgo:** LOW. **Confianza:** HIGH.

## Decisiones y comprobación pendiente

Los puntos siguientes merecen una decisión de producto, pero no se cuentan como defectos confirmados: `CalendarStore.swift:100` y `MirrorStore.swift:63-71` pueden solicitar permisos al abrir la sección antes de que se pulse la CTA explicativa de `DesvanCalendar.swift:130` o `DesvanMirror.swift:44`. Esperar a la CTA haría más predecible la solicitud, pero modificaría el primer uso y requiere contrastarlo con onboarding. El contraste del destino de drop y el clipping de texto deben medirse en una build del HEAD antes de afirmar un incumplimiento visual.

También queda una hipótesis de teclado, **confianza LOW**, para las tarjetas de Calendar (`DesvanCalendar.swift:227,297`), Shortcuts (`DesvanShortcuts.swift:248,343`) y Clipboard (`DesvanClipboard.swift:251`): usan tap y acciones AX en vez de un `Button` enfocable. Hay que probar Tab, Space, Return y VoiceOver antes de considerarlo fallo; si alguna no se activa, el criterio es ofrecer un control semántico sin romper drag ni menú contextual.

Dos mejoras de accesibilidad adicionales quedan pendientes de prueba: las barras de Usage (`DesvanUsage.swift:263-271`) pueden omitir el nombre de la ventana en su variante estrecha, así que hay que comprobar que VoiceOver siempre anuncie el contexto junto al porcentaje; y los ítems de Shelf (`DesvanShelf.swift:291-305,400-405`) podrían exponer “Open” y “Quick Look” como acciones AX directas además del menú contextual. Son recomendaciones de descubribilidad, no bloqueos demostrados.

Se descartó proponer un rediseño visual completo: las capturas y la inspección de Settings muestran un sistema consistente. La pestaña normal del notch dispone de su propia gestión de overflow; el riesgo calculado arriba corresponde al **modo edición**. Ese modo ya tiene navegación y movimiento por teclado y acciones de accesibilidad (`DesvanEditBody.swift:100-145`), por lo que el hallazgo trata el ancho, no una ausencia general de soporte de teclado. iOS y Widget son scaffolds intencionales, no un release móvil roto.

Quick Look, AirDrop y Sparkle se revisaron solo como puntos de entrada de Altillo; sus interfaces nativas o externas no forman parte de esta auditoría. La hoja de revisión de hooks y Spike Log no dieron un hallazgo de producto sólido.

La verificación futura debería usar, en serie, los comandos documentados en `README.md:136-148`: `cd Packages/AltilloKit && swift test`, después `xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-ci test`, y el build de simulador iOS/widget cuando se toque ese target. La revisión manual de la build actual debe recorrer 440/560/760 pt, inglés y español, VoiceOver, teclado, Reduce Motion, Reduce Transparency, permisos concedidos/denegados, carga, vacío y error. Esta auditoría no ejecutó esos pasos.
