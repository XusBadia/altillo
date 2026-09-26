# Plan 009: Las promesas centrales pasan en hardware real y quedan fechadas

> Drift: `git diff --stat 7f80680..HEAD -- PLAN.md docs/pruebas-drag-drop.md docs/cajon.md plans/002-prove-release-differentiators.md website README.md`

## Estado

- **Prioridad**: P0 · **Esfuerzo**: M · **Riesgo**: LOW · **Depende de**: 006–008
- **Categoría**: tests/direction · **Planned at**: `7f80680`, 26-09-2026

## Por qué importa

`PLAN.md:286-295` bloquea físicamente Codex allow/deny, terminal exacta y hold
peligroso, tres reproductores, Shelf/AirDrop/Quick Look y Calendar Join. La
auditoría UI añade VoiceOver hablado, teclado, Reducir movimiento/transparencia
y cámara física. Son justo las promesas que diferencian Altillo.

## Alcance

QA en MacBook con notch y Mac/monitor sin notch, macOS 26 y 27; actualización
de matrices y claims. No añadir features para “arreglar” un caso sin registrar
primero el fallo.

## Pasos

1. Instala el DMG candidato limpio y fecha hardware/SO/build.
2. Ejecuta completo `docs/pruebas-drag-drop.md`: Finder, Fotos/Mail/browser,
   multi-drag, chats, AirDrop, Quick Look, Spaces/full-screen/wake.
3. Ejecuta Claude y Codex reales: allow, deny, timeout, reply, terminal/pane
   exacto, comando peligroso y Altillo cerrado.
4. Prueba Music, Spotify y tercera app; Calendar Join; cámara; permisos
   concedidos/denegados; VoiceOver; teclado; Reduce Motion/Transparency.
5. Registra PASS/FAIL y corrige solo P0/P1. En macOS 27, el copy de Drawer debe
   decir que agrupa/abre/mueve, pero solo oculta en macOS 26.

## Verificación

Además de la matriz firmada y fechada:

```sh
cd Packages/AltilloKit && swift test
cd ../.. && xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-ci test
cd website && CI=1 npm test -- --workers=1 && npm run build
```

Hecho: cero casillas críticas vacías, cero P0/P1 abiertos y claims públicos
coinciden con capacidades observadas en 26/27.

## STOP

Si un recorrido exige API privada, desactivar seguridad o autoaprobar, degrada
la feature/copy; no cruces ese límite para cerrar una casilla.
