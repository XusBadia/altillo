# Plan 006: La build pública no expone herramientas ni datos de diagnóstico internos

> Ejecuta el plan en orden. Si una condición STOP ocurre, informa y no improvises.
> Drift: `git diff --stat 7f80680..HEAD -- project.yml Apps/macOS/Debug Apps/macOS/App/AltilloApp.swift Apps/macOS/DragDrop`

## Estado

- **Prioridad**: P0 · **Esfuerzo**: M · **Riesgo**: MED · **Depende de**: —
- **Categoría**: security · **Planned at**: `7f80680`, 26-09-2026

## Por qué importa

Release incluye todo `Apps/macOS` (`project.yml:38-41`). `SpikeLog.record`
publica mensaje completo en Unified Logging (`SpikeLog.swift:42-46`) y varias
rutas registran app activa, tipos y rutas completas. El menú público ofrece
“Design review” y “Drag spike log…” (`AltilloApp.swift:63-73`).

## Alcance

Dentro: `project.yml`, `Apps/macOS/Debug/`, `Apps/macOS/App/AltilloApp.swift`,
llamadas `SpikeLog` y tests nuevos. Fuera: quitar toda capacidad de diagnóstico,
telemetría remota o cambiar el flujo del shelf.

## Pasos

1. Define una frontera de build: las escenas/menús de review solo existen en
   Debug. Verifica que Archive Release no contiene sus títulos ni símbolos.
2. Sustituye los logs necesarios en producción por un diagnóstico local
   explícito, redactado: ninguna ruta completa, nombre de fichero, app activa o
   contenido de pasteboard puede ir con `.public`.
3. Añade tests de redacción y un smoke de configuración Release.

## Verificación

```sh
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -configuration Release \
  -derivedDataPath /tmp/altillo-dd-release-audit build
strings /tmp/altillo-dd-release-audit/Build/Products/Release/Altillo.app/Contents/MacOS/Altillo \
  | rg 'Drag spike log|Design review|Spike log'
xcodebuild -project Altillo.xcodeproj -scheme Altillo \
  -derivedDataPath /tmp/altillo-dd-ci test
```

Hecho: build/test exit 0; el `rg` no devuelve coincidencias; tests prueban que
los mensajes exportables no contienen rutas ni nombres sensibles.

## STOP

- Si soporte depende de rutas completas, diseña antes un export opt-in con
  preview y redacción; no las mantengas en el log del sistema.
- Si separar Debug exige duplicar lógica de producto, detente y propone una
  abstracción mínima.
