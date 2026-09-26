# Plan 003: Compartir y enviar por AirDrop la selección existente del cajón

> **Instrucciones**: ejecuta después de 001 y reutiliza su capa de sharing.
> Verifica cada paso y actualiza `plans/README.md` al terminar.
>
> **Drift check**:
> `git diff --stat 5033311..HEAD -- Apps/macOS/Views/Desvan/DesvanShelf.swift Apps/macOS/Notch/NotchModel.swift Apps/macOS/Notch/NotchCoordinator.swift Tests/AltilloMacTests`

## Estado

- **Prioridad**: P1
- **Esfuerzo**: S
- **Riesgo**: LOW
- **Depende de**: `plans/001-clean-up-airdrop-owned-copies.md`
- **Categoría**: direction
- **Planificado en**: commit `5033311`, 26-09-2026

## Por qué importa

Altillo recibe un drop directamente en AirDrop, pero una vez que algo vive en el
cajón el menú contextual solo ofrece Open, Finder, Quick Look y retirar. El
usuario espera seleccionar varios objetos y compartirlos sin volver a Finder.
Es un hueco pequeño, visible y ya resuelto por el competidor.

## Estado actual

`DesvanShelf.contextMenu` obtiene `menuItems()` respetando Cmd/Shift y muestra:

```swift
Button("Open") { items.forEach(model.actions.open) }
Button("Show in Finder") { model.actions.revealInFinder(items) }
Button("Quick Look") { model.actions.quickLook(items) }
Button("Take it down", role: .destructive) { ... }
```

`NotchActions` no tiene acción share. `NotchCoordinator.sendViaAirDrop` solo es
privado y recibe el drop nuevo. El plan 001 debe haber creado una operación de
sharing con ciclo de vida correcto.

## Comandos

| Propósito | Comando | Resultado esperado |
|---|---|---|
| Tests | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-003 test` | exit 0 |
| L10n | `rg -n 'Share|AirDrop' Apps/macOS/Resources/Localizable.xcstrings` | las nuevas claves ES/EN existen |

## Alcance

**Dentro**: los tres archivos de app del drift check, catálogo de localización y
tests específicos de acciones/selección/shelf.

**Fuera**: cambiar multiselección, quitar items después de compartir, clipboard,
share extensions o rediseñar el menú.

## Git

- Rama: `feat/share-shelf-selection`.
- Commit: `feat(shelf): share the current selection`.
- No push/PR sin instrucción.

## Pasos

### 1. Exponer una acción de compartir

Añadir a `NotchActions` una acción para `[ShelfItem]` y cablearla en
`NotchCoordinator` a la operación creada por 001. Debe aceptar file URLs, links
y texto. Los items del shelf se conservan tras éxito, fallo o cancelación.

**Verificar**: test unitario de wiring/adaptador con payload mixto, sin chooser.

### 2. Añadir Share y AirDrop al menú de la selección

En `DesvanShelf.contextMenu`, usar exactamente `menuItems()` para que clic
simple, Cmd y Shift compartan el mismo conjunto visible. Añadir “Share…” con el
picker estándar si la abstracción de 001 lo permite y “AirDrop”; si exponer el
picker requiere otra arquitectura, implementar AirDrop primero y detener la
parte Share con informe. Mantener las acciones destructivas tras un divisor.

**Verificar**: tests confirman 1 y N items, payload mixto y que no se llama a
`remove`/`removeDeparted`.

### 3. Accesibilidad y localización

Añadir strings ES/EN y nombres accesibles inequívocos. Con VoiceOver, el menú
debe anunciar el número de elementos cuando hay varios.

**Verificar**: búsqueda de localización y suite completa verdes.

## Plan de tests

- Selección individual y múltiple llega completa a la acción.
- Archivo/link/text conservan orden y tipo.
- Compartir/cancelar no muta `model.shelf` ni historial de undo.
- AirDrop no disponible produce feedback y tampoco elimina items.

## Hecho cuando

- [ ] La selección actual se puede enviar por AirDrop desde su menú.
- [ ] Share estándar está disponible o documentado como bloqueo concreto.
- [ ] No se pierde ni duplica ningún item.
- [ ] Strings ES/EN y accesibilidad pasan.
- [ ] Suite completa verde y fila actualizada.

## STOP

- 001 no está terminado o el nuevo flujo tendría que duplicar su lifecycle.
- `menuItems()` ya no representa la selección visible.
- Compartir exige convertir/mover el archivo original.
- El picker solo puede probarse abriendo UI real en tests automáticos.

## Mantenimiento

Toda futura entrada a AirDrop —drop directo, shelf o clipboard— debe pasar por
la misma abstracción retenida. Revisar que “compartir” nunca implique retirar.
