# Plan 010: El usuario puede pedir ayuda y retirar Altillo sin hooks rotos

> Drift: `git diff --stat 7f80680..HEAD -- Apps/macOS/Settings Apps/macOS/Modules/Agents website packaging/homebrew README.md docs`

## Estado

- **Prioridad**: P1 · **Esfuerzo**: S/M · **Riesgo**: MED · **Depende de**: 006
- **Categoría**: dx/docs · **Planned at**: `7f80680`, 26-09-2026

## Por qué importa

About no ofrece soporte (`SettingsAboutPane.swift:52-90`) y la web solo enlaza
licencia. El cask borra Application Support/caches/preferences
(`packaging/homebrew/Casks/altillo.rb:15-19`), pero los hooks viven en configs
de Claude/Codex/etc. Borrar la app puede dejar comandos apuntando a un binario
inexistente.

## Alcance

About, web ES/EN, docs, issue template, instalador de hooks y cask. No borrar
ficheros de configuración completos ni tocar hooks ajenos.

## Pasos

1. Añade “Report a problem” y “Privacy” en About y web, con versión/build y
   una forma segura de copiar diagnóstico redactado.
2. Documenta “antes de borrar: Settings › Agents › Remove” y actualiza el bug
   template, que aún dice “phase 0”.
3. Añade “Prepare to uninstall”: preview del diff, backups, retirada idempotente
   de todos los fragmentos propiedad de Altillo y confirmación por target.
4. Decide explícitamente si `brew uninstall --zap` puede invocar esa retirada;
   si no puede hacerlo con seguridad, documenta el límite en vez de borrar
   configuraciones ajenas.

## Verificación

Tests del instalador: config vacía, config compartida, doble retirada, backup,
fallo parcial y hooks ajenos intactos. Después:

```sh
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -derivedDataPath /tmp/altillo-dd-ci test
cd website && CI=1 npm test -- --workers=1 && npm run build
```

Hecho: enlaces visibles ES/EN; uninstall deja cero comandos Altillo y conserva
byte a byte contenido ajeno; no se exportan rutas/credenciales.

## STOP

Si no se puede atribuir inequívocamente un bloque a Altillo, no lo borres:
muestra el fichero y la instrucción manual exacta.
