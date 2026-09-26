# Plan 007: La privacidad pública describe exactamente cada salida de red

> Drift: `git diff --stat 7f80680..HEAD -- README.md website Apps/macOS/Settings Packages/AltilloKit/Sources/AltilloUsage Apps/macOS/Modules/Assistant`

## Estado

- **Estado**: DONE · política ES/EN, enlaces públicos y guards de claims verificados el 26-09-2026
- **Prioridad**: P0 · **Esfuerzo**: S/M · **Riesgo**: LOW · **Depende de**: 006
- **Categoría**: docs/security · **Planned at**: `7f80680`, 26-09-2026

## Por qué importa

`README.md:176-183` y `SettingsModulesPane.swift:729-730` se pueden leer como
“tokens y cifras nunca salen del Mac”. Sin embargo Claude envía el token a
`api.anthropic.com` (`ClaudeCollector.swift:68-79`) y Codex a `chatgpt.com`
como fallback (`CodexCollector.swift:98-118`). La promesa correcta es: nada se
envía a Altillo; cada credencial solo se usa contra su proveedor; búsqueda web
es opt-in y envía la consulta.

## Alcance

README, web ES/EN, onboarding/Settings/About, catálogo de strings y una página
de privacidad versionada. No cambiar collectors ni añadir tracking.

## Pasos

1. Inventaría endpoints y datos enviados por cada collector y por Ask web,
   citando el código; no inventes garantías que el transporte no pruebe.
2. Escribe la política ES/EN: datos locales, salidas al proveedor, búsqueda
   web opt-in, almacenamiento/retención, logs redactados y ausencia de
   telemetría de Altillo.
3. Enlázala desde web, README, onboarding de Usage y About. Corrige además la
   mención obsoleta de compatibilidad OpenUsage en `README.md:203-208`.
4. Añade tests de claims que impidan reaparecer “never leave this Mac” sin el
   matiz del proveedor.

## Verificación

```sh
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-ci test
script/check-localization.py /tmp/altillo-dd-ci
cd website && npm run build && CI=1 npm test -- --workers=1
rg -n 'compatible with OpenUsage|numbers never leave this Mac' README.md website Apps/macOS
```

Hecho: suites verdes; último `rg` sin claims obsoletos; todos los enlaces ES/EN
resuelven; la política enumera destinos reales.

## STOP

Si aparece un endpoint cuya titularidad o dato enviado no puede verificarse,
descríbelo como pendiente y no publiques una garantía absoluta.
