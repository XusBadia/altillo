# Plan 002: Probar y describir con verdad las ventajas competitivas de Altillo

> **Instrucciones**: sigue todas las puertas de verificación. Este plan requiere
> una sesión real de Codex y hardware Mac con notch; no simules evidencia. Ante
> una condición STOP, informa y deja la fila `BLOCKED` con el motivo.
>
> **Drift check**:
> `git diff --stat 5033311..HEAD -- PLAN.md README.md website Packages/AltilloKit/Sources/AltilloAgents Packages/AltilloKit/Tests/AltilloAgentsTests Apps/iOS Apps/Widgets`

## Estado

- **Prioridad**: P1
- **Esfuerzo**: M
- **Riesgo**: MED
- **Depende de**: ninguno
- **Categoría**: tests/docs
- **Planificado en**: commit `5033311`, 26-09-2026

## Por qué importa

NotchView ya promete alertas para Claude/Codex. La diferencia de Altillo es
resolver decisiones de forma segura desde el notch, pero el propio `PLAN.md`
reconoce que el payload real de permisos Codex no se validó por falta de cuota.
A la vez, la web llama “en desarrollo” a agentes, limita música a dos apps, y el
README presenta iOS como terminado aunque es placeholder. Antes de otro vídeo,
el producto debe tener una matriz de aceptación reproducible y mensajes ciertos.

## Estado actual

- `HookDecisionOutput.swift` documenta Codex 0.152.0 y degrada
  `allowForSession` a `allow`; las pruebas usan fixtures de esquema publicado.
- `PLAN.md:321-322` dice que herramientas/permisos Codex siguen sin verificar
  en vivo.
- `website/src/demo-copy.js` contiene “Solicitud simulada · función en desarrollo”.
- `website/index.html:157` y `website/en/index.html:155` dicen Apple Music y Spotify.
- `README.md:6` dice 0.5.0; `README.md:28-31` describe companion iOS, pero
  `Apps/iOS/AltilloApp.swift:13-20` muestra “Coming soon”.

## Comandos

| Propósito | Comando | Resultado esperado |
|---|---|---|
| Tests package | `cd Packages/AltilloKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 0, todos pasan |
| Tests web | `cd website && npm test` | 0, todos pasan |
| Tests macOS | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-002 test` | 0, todos pasan |
| Buscar claims obsoletos | `rg -n 'feature in development|función en desarrollo|Apple Music and Spotify|Apple Music y Spotify|current version 0\.5\.0' README.md website` | sin matches destinados al usuario |

## Alcance

**Dentro**: fixtures/tests de `AltilloAgents`, documentación del protocolo,
`PLAN.md`, `README.md`, contenido y tests de `website/`. Cambiar código de hook
solo si el payload real contradice el contrato y el ajuste es pequeño y probado.

**Fuera**: vídeo, rediseño de landing, nuevas funciones de agentes, telemetría,
publicación, cambios en iOS/widgets o autoaprobación.

## Git

- Rama: `test/release-differentiators`.
- Commits: `test(agents): validate live Codex permission payloads` y
  `docs: align shipped feature claims`.
- No publicar ni instalar hooks sin mostrar/revisar el diff habitual.

## Pasos

### 1. Capturar payloads Codex reales, saneados

Con una versión registrada en el fixture, provocar al menos una petición de
permiso benigna y reversible. Capturar input del hook y output aceptado para
allow y deny. Eliminar rutas personales, prompts y secretos antes de guardar el
fixture. Registrar versión exacta de Codex. Probar también cancelación/timeout:
no debe imprimir decisión.

**Verificar**: tests específicos de `HookDecisionOutput` pasan y el fixture no
contiene `/Users/`, tokens, emails ni nombres de proyecto reales (`rg`).

### 2. Validar la UX física de agentes

En un Mac con notch y trackpad, verificar: alerta cerrada, apertura, contexto de
proyecto/acción, hold para comando peligroso, allow, deny, salto al terminal
correcto y fallback al terminal si Altillo se cierra. Anotar resultado y versión
en `PLAN.md`; no marcar una variante no probada.

**Verificar**: checklist explícito en `PLAN.md`, cada caso `PASS` o bloqueo con
versión y fecha.

### 3. Ejecutar la matriz de diferenciadores

Probar físicamente Now Playing al menos con Apple Music, Spotify y una tercera
app compatible; cajón con archivo estable, imagen web/file promise, drag-out,
multiselección y Quick Look; calendario con Join. Documentar solo capacidades
observadas. AirDrop queda pendiente hasta 001/003 si no están hechos.

**Verificar**: matriz fechada en `PLAN.md`, sin afirmaciones “universal” basadas
solo en mocks.

### 4. Alinear README y web

Actualizar versión/estado desde la fuente de release vigente. Describir iOS y
widgets como placeholders, no funciones entregadas. Sustituir los claims de
música por el alcance probado y retirar “en desarrollo” de agentes usando copy
exacta: control humano, nunca autoaprueba. Actualizar los tests web que fijan el
copy. No tocar el vídeo.

**Verificar**: búsqueda de claims obsoletos sin resultados y `npm test` verde.

### 5. Cerrar suites

Ejecutar las tres suites. No alterar geometría para silenciar el fallo de línea
base indicado en el índice.

## Plan de tests

- Fixtures reales Codex: allow, deny, timeout y allow-for-session degradado.
- Datos saneados: test/grep evita rutas y credenciales.
- Tests web validan copy ES/EN y que iOS no se anuncia como enviado.
- Checklist manual con versiones para hardware y apps externas.

## Hecho cuando

- [ ] Un payload real de permisos Codex está probado de extremo a extremo.
- [ ] Seguridad y terminal exacto pasan en hardware.
- [ ] Música/cajón/calendario tienen matriz física fechada.
- [ ] Web y README no contradicen el producto.
- [ ] Las tres suites pasan, salvo una línea base ajena documentada.
- [ ] El índice queda actualizado.

## STOP

- No hay cuota/sesión Codex o Mac con notch: no inventar PASS.
- El payload real exige un cambio incompatible o no documentado: capturar el
  mínimo saneado e informar antes de ampliar alcance.
- La versión de producto no tiene una fuente única inequívoca.
- Corregir copy exige publicar o cambiar el vídeo.

## Mantenimiento

Repetir la matriz al actualizar versiones mayores de agentes o MediaRemote. Una
afirmación de marketing debe apuntar a una fila PASS reciente, no a un fixture.
