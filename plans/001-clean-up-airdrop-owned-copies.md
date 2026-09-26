# Plan 001: Eliminar las copias temporales de AirDrop cuando termina el compartir

> **Instrucciones**: ejecuta el plan paso a paso y todas las verificaciones. Si
> aparece una condición STOP, detente e informa; no improvises. Al terminar,
> marca este plan como `DONE` en `plans/README.md`.
>
> **Drift check (primero)**:
> `git diff --stat 5033311..HEAD -- Apps/macOS/DragDrop/FileIngest.swift Apps/macOS/Modules/Assistant/AssistantAttachment.swift Apps/macOS/Notch/NotchCoordinator.swift Tests/AltilloMacTests/DropZoneTests.swift Tests/AltilloMacTests/FileIngestTests.swift`
> Si cambió un archivo, compara el estado actual inferior con el código vivo.

## Estado

- **Prioridad**: P1
- **Esfuerzo**: M
- **Riesgo**: MED
- **Depende de**: ninguno
- **Categoría**: bug
- **Planificado en**: commit `5033311`, 26-09-2026

## Por qué importa

Un drop de una imagen o file promise puede crear una copia propiedad de Altillo
en `Application Support/Altillo/Inbox`. El flujo Ask la borra después de leerla,
pero AirDrop entrega el payload a `NSSharingService` y pierde la referencia: la
copia puede quedar en disco para siempre. La solución debe esperar a que el
servicio termine o falle; borrarla justo después de `perform` rompería AirDrop.

## Estado actual

- `DropTargetView.receive` ingiere antes de discriminar la zona.
- `FileIngest.ingest(data:)` e `item(forReceivedFile:)` marcan copias con
  `isOwnedCopy: true`.
- `NotchCoordinator.sendViaAirDrop` crea un `NSSharingService` local, llama
  `perform(withItems:)` y no conserva delegate ni limpia archivos.
- `AssistantAttachment.discardCopy` ya implementa la regla segura: solo borrar
  dentro de Inbox y retirar el directorio-slot si queda vacío.
- `DropZoneTests.airDropZoneDeliversToAirDropNotTheShelf` solo prueba texto.

Fragmento clave actual (`Apps/macOS/Notch/NotchCoordinator.swift:582`):

```swift
private func sendViaAirDrop(_ items: [ShelfItem]) {
    let payload: [Any] = items.compactMap { /* file, link or text */ }
    guard !payload.isEmpty,
          let service = NSSharingService(named: .sendViaAirDrop),
          service.canPerform(withItems: payload) else { return }
    service.perform(withItems: payload)
}
```

Exemplar de borrado (`Apps/macOS/Modules/Assistant/AssistantAttachment.swift:126`):

```swift
static func discardCopy(at url: URL, inboxRoot: URL = FileIngest.standard.inboxRoot) -> Bool
```

## Comandos

| Propósito | Comando | Resultado esperado |
|---|---|---|
| Generar proyecto | `xcodegen generate` | exit 0 |
| Tests dirigidos | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-001 test -only-testing:AltilloMacTests/DropZoneTests -only-testing:AltilloMacTests/FileIngestDiskTests` | exit 0 |
| Suite completa | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-001-full test` | exit 0 |

## Alcance

**Dentro**: los cinco archivos del drift check. Se puede crear un helper pequeño
en `Apps/macOS/DragDrop/` y su test si separa el ciclo de vida del servicio.

**Fuera**: rediseño visual, selección del shelf, otros servicios de compartir,
cambiar la clasificación de ficheros o borrar cualquier URL no poseída.

## Git

- Rama: `fix/airdrop-owned-copy-lifecycle`.
- Commits convencionales, por ejemplo `fix(drop): clean owned copies after AirDrop`.
- No hacer push ni abrir PR sin instrucción.

## Pasos

### 1. Extraer una operación de compartir retenida

Crear un objeto `@MainActor` que adopte `NSSharingServiceDelegate`, conserve el
servicio mientras esté activo y reciba `[ShelfItem]`. Debe exponer finalización
inyectable para tests. El coordinator debe retener las operaciones activas por
identidad hasta callback de éxito o fallo.

**Verificar**: compilar con el comando de tests dirigidos; debe llegar a tests.

### 2. Limpiar exactamente las copias propiedad de Altillo

Al finalizar o fallar, recorrer solo casos `.file(url, isOwnedCopy: true)` y
usar la misma comprobación canónica de `AssistantAttachment.discardCopy`.
Mover esa función a un helper neutral de DragDrop si hace falta; no duplicar la
regla. Si `canPerform` es falso o el payload queda vacío, limpiar igualmente
porque la ingestión ya ocurrió. Nunca borrar referencias estables, links o texto.

**Verificar**: un test con root temporal demuestra que éxito, fallo y servicio
no disponible eliminan copia y slot; una URL `isOwnedCopy: false` permanece.

### 3. Cubrir file promises/datos y múltiples operaciones

Añadir pruebas de dos operaciones simultáneas para evitar que retener una
reemplace a otra. Extender el test de drop con una imagen/data o item poseído;
la prueba no debe abrir el chooser real: inyectar el adaptador de sharing.

**Verificar**: tests dirigidos, exit 0 y todos pasan sin UI del sistema.

### 4. Ejecutar la suite completa

Ejecutar el comando completo. Si persiste únicamente el fallo de geometría
documentado en `plans/README.md`, informar que es línea base y no tocar esos
archivos; no declarar suite verde.

## Plan de tests

- Éxito y error del delegate limpian una copia poseída.
- Servicio inexistente/no compatible limpia la copia.
- Referencia no poseída nunca se borra.
- Varios items y operaciones concurrentes limpian cada uno una vez.
- Una ruta fuera de Inbox se rechaza incluso si llega mal marcada como poseída.

## Hecho cuando

- [ ] No hay ruta de salida de AirDrop que deje copias poseídas.
- [ ] La limpieza ocurre tras callback, nunca antes de que AirDrop consuma el archivo.
- [ ] Los tests nuevos pasan sin abrir UI.
- [ ] La suite completa pasa o solo conserva una línea base documentada y ajena.
- [ ] No se modifican archivos fuera del alcance.
- [ ] El índice queda actualizado.

## STOP

- El callback de `NSSharingServiceDelegate` no distingue de forma fiable éxito/fallo.
- La solución exige polling, dormir un tiempo arbitrario o borrar todo Inbox.
- Una URL exterior puede alcanzar el borrado sin la comprobación canónica.
- Los fragmentos han cambiado de forma sustancial desde `5033311`.

## Mantenimiento

El plan 003 debe usar esta operación, no crear una segunda integración de
AirDrop. Revisar especialmente retención, callbacks múltiples y cancelación del
chooser.
