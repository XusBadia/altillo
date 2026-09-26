# Plan 005: Decidir con evidencia si Altillo puede ofrecer un HUD público de volumen

> **Instrucciones**: este es un spike, no una autorización para enviar la
> función. Trabaja en una carpeta experimental y termina con GO/NO-GO. No uses
> API privada, Accessibility, CGEventTap ni sustituyas el HUD del sistema.
>
> **Drift check**:
> `git diff --stat 5033311..HEAD -- Apps/macOS/Modules Apps/macOS/Notch Tests/AltilloMacTests docs`

## Estado

- **Prioridad**: P2
- **Esfuerzo**: S
- **Riesgo**: MED
- **Depende de**: ninguno
- **Categoría**: direction
- **Planificado en**: commit `5033311`, 26-09-2026

## Por qué importa

El HUD de volumen es una de las funciones más visibles de NotchView y encaja
mejor que CPU/memoria en una superficie efímera. Pero un clon que sondea, pide
Accessibility o muestra dos HUDs empeora confianza y acabado. Este plan compra
información barata antes de comprometer arquitectura o marketing.

## Estado actual

- Altillo resuelve actividad contextual en `NotchActivityLogic` y ya tiene
  peeks event-driven para calendario, agentes y temporizador.
- `NotchCoordinator` gobierna panel/estado; ningún módulo observa audio.
- El proyecto prioriza CPU cercana a cero en reposo y APIs públicas.
- El competidor afirma reemplazar volumen/brillo, pero esa implementación no es
  evidencia de que el enfoque sea público o robusto.

## Comandos

| Propósito | Comando | Resultado esperado |
|---|---|---|
| Buscar precedentes | `rg -n 'CoreAudio|AudioObject|volume|CGEventTap|Accessibility' Apps Packages Tests` | inventario documentado |
| Compilar spike | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-005 build` | exit 0 si se crea código |
| Línea base CPU | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xctrace list templates` | exit 0; instrumento disponible o bloqueo documentado |

## Alcance

**Dentro**: `docs/spikes/volume-hud.md`; opcionalmente un prototipo aislado bajo
`Apps/macOS/Modules/VolumeSpike/` y tests correspondientes. Se puede usar
CoreAudio público para observar el dispositivo de salida y su propiedad de
volumen/mute.

**Fuera**: código de producción conectado al notch, brillo, teclas multimedia,
event taps, Accessibility, MediaRemote privado, ocultar/modificar el HUD nativo,
Settings o promesas en web.

## Git

- Rama: `spike/volume-hud`.
- Commit: `docs(spike): evaluate a public volume HUD`.
- Borrar el prototipo si el resultado es NO-GO; conservar el informe.

## Pasos

### 1. Definir la puerta GO/NO-GO antes de experimentar

GO exige: callbacks públicos al cambiar volumen/mute; dispositivo correcto tras
hot-plug; cero polling; sin permiso; coste de reposo despreciable; y una decisión
de producto aceptable sobre coexistir con el HUD nativo. Todo lo demás es NO-GO.

**Verificar**: criterios copiados como checklist en `docs/spikes/volume-hud.md`.

### 2. Probar observación CoreAudio aislada

Crear el adaptador mínimo con listener de propiedades del dispositivo de salida.
Registrar valor, mute, cambio de dispositivo y timestamp. No conectar vistas.
Probar altavoces, auriculares, AirPods y al menos una salida sin volumen
controlable (HDMI/DisplayPort si está disponible).

**Verificar**: tabla manual con cada dispositivo y PASS/FAIL; test unitario del
mapeo de callbacks mediante backend falso.

### 3. Medir comportamiento y coexistencia

Medir 10 minutos idle y una ráfaga de cambios. Confirmar que no hay timer.
Observar el HUD nativo: documentar si una futura presentación de Altillo sería
duplicada. No intentar suprimirlo durante el spike.

**Verificar**: números, comandos/herramienta y captura de resultado en el informe.

### 4. Emitir decisión

Escribir GO solo si se cumplen todos los criterios. Un GO debe proponer un plan
nuevo separado para un peek efímero, no un módulo permanente. NO-GO debe citar
el criterio fallido y retirar el prototipo.

**Verificar**: `docs/spikes/volume-hud.md` contiene `Decision: GO` o
`Decision: NO-GO`, evidencia y siguientes pasos exactos.

## Plan de tests

- Backend falso: volumen, mute, cambio de device, listener removal.
- Manual: built-in, Bluetooth y salida no controlable.
- Reposo: cero timers/callback storm y listener retirado al stop.

## Hecho cuando

- [ ] Hay decisión binaria respaldada por evidencia.
- [ ] No se usó ninguna API/permisos prohibidos.
- [ ] No quedó código de producción conectado.
- [ ] Un NO-GO no deja prototipo; un GO enlaza un plan nuevo.
- [ ] El índice queda actualizado.

## STOP

- La única detección fiable requiere sondeo, Accessibility, eventos globales o
  una API privada.
- No se dispone de al menos dos clases de salida para verificar.
- El prototipo modifica el volumen o intercepta teclas en vez de observar.
- Se intenta suprimir el HUD nativo dentro de este spike.

## Mantenimiento

Repetir solo si Apple publica una API nueva o cambia el comportamiento del HUD.
Un resultado GO para volumen no autoriza brillo: es otro problema técnico.
