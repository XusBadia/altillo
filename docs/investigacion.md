# Investigación: apps de notch en macOS (septiembre 2026)

## Competidores

| App | Qué es | Shelf de archivos | Precio | Notas |
|---|---|---|---|---|
| **NotchNook** (lo.cafe) | Hub completo: tray, AirDrop, calendario, clipboard, widgets | Sí, el más pulido | 25 $ / 3 $/mes / Setapp | **En crisis**: disputa interna, web caída, pagos de Stripe suspendidos, Setapp lo retira el 22-09-2026. No es un cierre limpio, pero no hay que contar con él. [MacMagazine](https://macmagazine.com.br/post/2026/09/16/crise-na-lo-cafe-deixa-notchnook-fora-do-ar-e-usuarios-sem-reembolso/) |
| **Alcove** | Dynamic Island estética: live activities, HUDs, gestos | No | ~15-17 $ | Prima la animación sobre la utilidad. macOS 14+ |
| **TopNotch** | Pinta la barra de menú de negro para "ocultar" el notch | No | Gratis | De los creadores de CleanShot. Es cosmético, no un competidor |
| **Notchy** | Todo en uno: música, pomodoro, clipboard, shelf, OCR, Descargas… | Sí | Gratis | Muchas funciones, fácil perderse. Soporta Macs sin notch |
| **Seam** (getseam.app) | Notch minimalista y muy pulido: foco, dictado local (Whisper), traducción, **Drop Zones**, música, calendario, HUDs, AirPods, batería, modos de concentración | Sí (Drop Zones) | 19,90 $ pago único | Indie (UpSys). Event-driven: 0,1 % CPU y 33 MB. Sin nada de agentes de IA. Referencia estética principal |
| **boring.notch** | Open source, el más popular (~10,8k ★) | Sí, drag out multi-ítem, AirDrop | Gratis | **GPL-3**. Quejas: batería, crashes al despertar, sin notarizar |
| **NotchDrop** | Open source, el shelf original | Sí, caduca a 1 día | Gratis / 1,99 $ en la MAS | **MIT**. Drag out con bugs (#62) |
| **MewNotch** | Open source | Sí, persistente | Gratis | GPL-3. Permite elegir en qué pantallas aparece |
| **Atoll** | Fork de boring.notch | Sí + `open -a Atoll archivo` | Gratis | GPL-3 |
| **DynamicNotchKit** | Librería Swift, no app | — | — | **MIT**. Buena referencia para la forma y la ventana |

**Licencias:** solo NotchDrop y DynamicNotchKit (MIT) permiten reutilizar código sin volver GPL el proyecto. Los demás se leen para aprender, pero no se copian.

## Estética de Seam (extraída del CSS de su web)

- **Colores:** negro cálido `#1C1917`, tarjetas `#292524`, texto `#FFFFFB`, acento ámbar `oklch(73% .23 74)` y azul marino `#1E3A5F` como secundario.
- **Cristal:** `blur(12-30px) saturate(1.5-2)`, degradado blanco translúcido al 8-22 %, reflejo superior en inset, sombra interior abajo y **grano de ruido SVG** (`fractalNoise`) con `soft-light`.
- **Forma:** radio 12 px, botones en cápsula, icono squircle al 22 %.
- **Tipografía:** SF Pro; en la web, un titular en serif itálica (Boska) como acento editorial.
- **Movimiento:** transiciones de 250-400 ms con fundido + desplazamiento del 2 %. "Peek" con el título de la canción en desplazamiento.
- **Filosofía:** "no deberías tener que configurar tu app de notch"; cada función se activa individualmente.

Fuentes: [getseam.app](https://getseam.app/), [features](https://getseam.app/features), [ifun.de](https://www.ifun.de/seam-nutzt-die-mac-notch-fuer-systemanzeigen-274298/).

## Patrones de UX del shelf

Funciona:
- El notch reacciona **en cuanto empieza un arrastre**, no solo cuando el cursor ya está encima (si no, cuesta acertar).
- Copiar lo que es temporal (adjuntos de Mail, imágenes de Safari, Fotos) para que el shelf no se rompa.
- Persistencia configurable (NotchDrop: 24 h; MewNotch: indefinida).
- Seleccionar varios ítems y arrastrarlos juntos fuera.
- AirDrop como acción directa y Quick Look con espacio.

Molesta:
- Que se abra ante cualquier arrastre aunque no vaya dirigido al notch.
- Que tape iconos de la barra de menú.
- Que en Macs sin notch o monitores externos no esté claro qué pasa.
- Binarios sin notarizar (Gatekeeper en cada update).
- Exceso de ajustes (NotchNook, Notchy).

## Hallazgos técnicos clave

- **Ventana:** `NSPanel` `.borderless + .nonactivatingPanel`, nivel `.mainMenu + 3`, `.canJoinAllSpaces/.stationary/.fullScreenAuxiliary`, `canBecomeKey = false`. Tamaño **fijo** y transparente: se anima el contenido SwiftUI, nunca el frame de la ventana.
- **Geometría del notch:** `safeAreaInsets.top` + `auxiliaryTopLeftArea/auxiliaryTopRightArea`. Sin notch → "isla virtual" en el centro superior.
- **Click-through:** `ignoresMouseEvents = true` en reposo. Hover detectado con `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`, que **no pide permiso de Accesibilidad** y funciona en sandbox.
- **Detectar un arrastre global:** en `leftMouseDown` guardar `NSPasteboard(name: .drag).changeCount`; en `leftMouseDragged`, si cambió y hay tipos de archivo/URL/texto, hay un arrastre en curso.
- **Recibir:** AppKit (`registerForDraggedTypes` + `NSFilePromiseReceiver`). El `onDrop` de SwiftUI no gestiona bien las promesas de archivo (Fotos, Mail, Safari).
- **Sacar:** `NSDraggingSource` propio con un `NSDraggingItem` por archivo. El `.draggable` de SwiftUI da problemas.
- **Almacenamiento:** híbrido. Bookmark security-scoped para archivos en rutas estables y copia (`clonefile`, instantánea en APFS) para temporales y promesas.
- **Now Playing:** MediaRemote está bloqueado desde 15.4. El atajo `mediaremote-adapter` (vía `/usr/bin/perl`) funciona hoy, pero es frágil y **no se admite en la App Store**. Plan B: AppleScript para Spotify/Music.
- **Sandbox:** todo el shelf (monitores de ratón, drop, drag out, bookmarks, AirDrop, Quick Look, login item) cabe en sandbox, así que la App Store es viable si nos quedamos en el shelf.
- **Tahoe:** la barra de menú es transparente, así que en reposo hay que dibujar exactamente el tamaño del notch. La silueta es negra opaca y el Liquid Glass va solo en los controles interiores. Hay que respetar Reducir transparencia y Reducir movimiento.
- **Bugs conocidos que evitar:** tirones al cambiar de Space (no recrear vistas), desaparecer tras dormir (reconstruir en wake), conflicto con la barra de menú en pantalla completa, CPU por publicar cada `mouseMoved`.

Código de referencia: [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT), [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL, solo lectura: `DragDetector.swift`, `ShelfDropService`, `ShelfItemView`).
