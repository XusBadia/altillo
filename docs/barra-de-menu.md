# Iconos de la barra de menú: investigación (septiembre 2026)

**Contexto:** macOS 27 "Golden Gate" salió el 14-09-2026. En 27 toda la barra de menú es **una sola ventana**, y Apple ha añadido un **chevrón de desbordamiento nativo** para los iconos que tapa el notch.

## Enumerar los iconos

- **`CGWindowListCopyWindowInfo`** (capa 25): da los marcos sin pedir permisos. Pero en Tahoe todas las ventanas pertenecen a **Control Center** (`Item-0`), así que ya no se puede saber de qué app es cada una. Por eso se rompió Ice.
- **Accesibilidad (recomendado):** `AXUIElementCreateApplication(pid)` → `AXExtrasMenuBar` → hijos. De cada hijo se obtienen el marco, `AXDescription`, `AXIdentifier` y las acciones `AXPress` y `AXShowMenu`.
  - Requiere el permiso de Accesibilidad y no funciona en sandbox.
  - Un recorrido completo tarda unos 1,8 s (timeout de 0,1 s por app), así que va en segundo plano y con caché. Se recalcula al lanzar o cerrar apps y al cambiar de pantalla.
  - Hay que descartar los elementos de Control Center con ancho 0.
- **SkyLight privado** (`CGSGetProcessMenuBarWindowList`…): funciona, pero tiene el mismo problema de PID. No hace falta.

## Detectar los que tapa el notch

Rectángulo del notch: `x = auxiliaryTopLeftArea.maxX`, `ancho = auxiliaryTopRightArea.minX − auxiliaryTopLeftArea.maxX`, `alto = safeAreaInsets.top`. Ojo: AX mide desde arriba a la izquierda y AppKit desde abajo.

Un icono está oculto si su marco corta el notch o queda fuera de pantalla. Se confirma con `AXUIElementCopyElementAtPosition`.

## Mostrarlos y pulsarlos

- **Imagen:**
  - Sin permiso, el icono de la app (`NSRunningApplication.icon`).
  - Con **Grabación de Pantalla**, en 26 se puede capturar con ScreenCaptureKit (`SCScreenshotManager`). En 27 no hay captura por icono.
- **Pulsar:** `AXPress` (y `AXShowMenu` para el clic derecho). Funciona aunque el icono esté fuera de pantalla, como hace HiddenBarIcons (MIT).
  - **Hay que recoger el panel del notch antes de pulsar**, porque el menú se abre bajo el notch.
  - Algunos popovers se colocan mal.
- **Moverlos temporalmente** (el "Ice Bar"): ⌘+arrastre simulado con CGEvent. Tarda 1-1,5 s por icono, secuestra el cursor, requiere más de 10k líneas para ser fiable y **no funciona en 27**. Descartado.

## Ocultar y reordenar

- **26:** el separador (un `NSStatusItem` con length de 10.000) funciona con API pública.
- **27:** el sistema expulsa el separador. Hidden Bar usa el framework privado `MenuBarClientCore`, que solo oculta por app. La alternativa nativa es Ajustes › Barra de menús › "Permitir en la barra de menús".
- **Reordenar:** en 26 exige CGEvent + AX; en 27, escribir en un fichero protegido del sistema. **Descartado.**

## Licencias

| Proyecto | Licencia | Uso |
|---|---|---|
| Ice, Thaw, IceMelt | GPL-3 | Solo lectura |
| Dozer | MPL-2.0 | Solo lectura |
| Hidden Bar, HiddenBarIcons, Spill | MIT | Se pueden reutilizar con atribución |

## Alcance en Altillo

| Función | Viabilidad | Permisos | Decisión |
|---|---|---|---|
| (a) Ver y pulsar los iconos tapados desde el notch | Alta | Accesibilidad (+ Grabación de Pantalla opcional) | ✅ Fase 7. En 27: lista y búsqueda |
| (b) Ocultar secciones | Media en 26, baja en 27 | Ninguno en 26 | ✅ Solo en 26; en 27, enlace a Ajustes |
| (c) Reordenar | Baja | Accesibilidad + eventos | ❌ |

**Fuentes:** [Thaw](https://github.com/thaw-app/Thaw), [Hidden Bar](https://github.com/dwarvesf/hidden), [HiddenBarIcons](https://github.com/mekedron/HiddenBarIcons), [Ice #954](https://github.com/jordanbaird/Ice/issues/954), [BTT sobre macOS 27](https://community.folivora.ai/t/macos-27-golden-gate-menu-bar-management-broken-solutions-ice-thaw-bartender-barbee-etc/47232), [heise sobre Bartender 6](https://www.heise.de/en/news/macOS-26-Lag-and-other-issues-with-menu-bar-tool-Bartender-6-11167978.html).
