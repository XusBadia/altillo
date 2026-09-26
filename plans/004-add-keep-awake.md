# Plan 004: Añadir Keep Awake opt-in, temporal y sin sondeo

> **Instrucciones**: sigue los pasos y verifica cada puerta. Keep Awake nunca
> debe activarse solo ni sobrevivir silenciosamente a un relanzamiento. Actualiza
> el índice al terminar.
>
> **Drift check**:
> `git diff --stat 5033311..HEAD -- Apps/macOS/Notch/NotchModule.swift Apps/macOS/Notch/NotchModel.swift Apps/macOS/Notch/NotchCoordinator.swift Apps/macOS/Modules/Utilities Apps/macOS/Views/Desvan Apps/macOS/Settings Tests/AltilloMacTests`

## Estado

- **Prioridad**: P2
- **Esfuerzo**: M
- **Riesgo**: MED
- **Depende de**: ninguno
- **Categoría**: direction
- **Planificado en**: commit `5033311`, 26-09-2026

## Por qué importa

Keep Awake es una utilidad cotidiana que cabe en la promesa “lo importante
arriba”, no requiere un dashboard y aparece en la demo de NotchView. Debe ser
explícita, temporal y dirigida por eventos: una aserción abandonada que impida
dormir el Mac sería peor que no tener la función.

## Estado actual

- `NotchModule` contiene `timer`, `note`, `clipboard`, `shortcuts`; esas
  utilidades son opt-in.
- `TimerStore` es el patrón: estado observable, fecha absoluta, tarea que duerme
  hasta el siguiente límite, `start/stop`, wake/clock observers y tests con reloj.
- `NotchCoordinator` inicia y conecta stores; `NotchModel` los posee.
- No existe una aserción de energía en el proyecto.

## Comandos

| Propósito | Comando | Resultado esperado |
|---|---|---|
| Generar | `xcodegen generate` | exit 0 |
| Tests dirigidos | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-004 test -only-testing:AltilloMacTests/KeepAwakeTests` | exit 0 |
| Suite | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-004-full test` | exit 0 |
| Manual | `pmset -g assertions` | Altillo aparece solo mientras está activo |

## Alcance

**Dentro**: nuevo store/backend/view en Utilities, módulo/model/coordinator,
Settings, localización y tests. Usar API pública: preferir
`ProcessInfo.beginActivity(options:reason:)` con token balanceado, o IOPM público
encapsulado si las pruebas demuestran que la primera opción no cubre el caso.

**Fuera**: impedir display sleep por defecto, reactivar tras relanzar, calendario
automático, modos focus, batería/AirPods, CPU/memoria y APIs privadas.

## Git

- Rama: `feat/keep-awake`.
- Commits convencionales, `feat(utilities): add bounded Keep Awake`.
- No push/PR sin instrucción.

## Pasos

### 1. Crear backend balanceado y testeable

Definir protocolo con `begin(reason) -> token` y `end(token)`. El store conserva
como máximo un token y garantiza `end` en stop, cancelación, expiración y
terminación. Inyectar backend y reloj/tarea para tests. Doble start no puede
crear dos aserciones.

**Verificar**: tests de conteo prueban exactamente un begin y un end por sesión.

### 2. Modelar duraciones explícitas

Ofrecer 30 min, 1 h, 2 h y “hasta que lo apague”. Guardar una fecha absoluta para
mostrar el final, pero no restaurar una aserción tras abrir la app. Dormir hasta
la expiración; reaccionar a wake/cambio de reloj como `TimerStore`.

**Verificar**: reloj falso cubre expiración, cancelación, wake y cambio de hora
sin polling.

### 3. Añadir módulo opt-in y UI

Crear el módulo localizado, apagado por defecto. La vista debe mostrar estado,
hora de fin y un Stop inequívoco. Una oreja contextual solo mientras está activo
es aceptable; no añadir badge permanente. Al deshabilitar el módulo, liberar la
aserción inmediatamente.

**Verificar**: tests de settings/módulos prueban default off y liberación al
desactivar.

### 4. Verificar con energía real

En build local, iniciar cada duración y observar `pmset -g assertions`; detener,
deshabilitar el módulo y salir de Altillo. En los tres casos debe desaparecer.

**Verificar**: checklist manual fechado en `PLAN.md` y suite completa verde.

## Plan de tests

- idempotencia, expiración, stop, module-off y app termination.
- No restauración al relanzar.
- Cambios de reloj/wake recalculan la fecha.
- Strings ES/EN y Reduce Motion no introducen animación obligatoria.

## Hecho cuando

- [ ] Solo APIs públicas y cero polling.
- [ ] Nunca activo por defecto ni restaurado solo.
- [ ] Todas las rutas liberan exactamente una aserción.
- [ ] `pmset` confirma inicio y fin reales.
- [ ] Suite completa verde e índice actualizado.

## STOP

- La opción elegida impide también display sleep sin que el usuario lo pida.
- Hace falta Accessibility, event taps o API privada.
- No se puede garantizar release al terminar la app normalmente.
- El store requiere sondeo periódico.

## Mantenimiento

Revisar con cada nueva opción de duración que el store siga siendo dueño único
del token. No conectar esta función a calendario o agentes sin consentimiento
explícito de producto.
