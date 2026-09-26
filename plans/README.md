# Planes de mejora de Altillo

Generados con la skill `improve` el 26-09-2026 a partir de una auditoría del
producto y de NotchView. Ejecutar en el orden indicado salvo que las
dependencias digan lo contrario. Cada ejecutor debe leer su plan completo,
respetar las condiciones de parada y actualizar su fila al terminar.

## Orden y estado

| Plan | Resultado | Prioridad | Esfuerzo | Depende de | Estado |
|---|---|---:|---:|---|---|
| [001](001-clean-up-airdrop-owned-copies.md) | AirDrop no deja copias temporales huérfanas | P1 | M | — | DONE |
| [002](002-prove-release-differentiators.md) | Las ventajas competitivas están probadas y descritas con verdad | P1 | M | — | BLOCKED: falta la matriz física en Mac con notch/trackpad y sesiones/apps reales |
| [003](003-share-shelf-selection.md) | La selección del cajón se comparte y envía por AirDrop | P1 | S | 001 | DONE |
| [004](004-add-keep-awake.md) | Keep Awake opt-in, temporal y sin sondeo | P2 | M | — | DONE |
| [005](005-spike-volume-hud.md) | Decisión técnica sobre un HUD de volumen público y fiable | P2 | S | — | REJECTED: NO-GO hasta probar Bluetooth, HDMI y coexistencia con el HUD nativo |

Estados válidos: `TODO`, `IN PROGRESS`, `DONE`, `BLOCKED: motivo` o
`REJECTED: motivo`.

## Dependencias

- 003 depende de 001: debe reutilizar una única capa de compartir que conozca
  la vida de las copias propiedad de Altillo.
- 002 puede ejecutarse en paralelo con 001; no debe proclamar AirDrop como
  cerrado hasta que 001 y 003 estén terminados.
- 005 es un spike con puerta de salida. Solo se convierte en implementación si
  puede observar volumen mediante APIs públicas, sin Accessibility ni eventos
  globales y sin duplicar el HUD nativo.

## Documento de investigación

- [Auditoría competitiva: NotchView](competitive-notchview-2026-09-26.md)

## Hallazgos considerados y rechazados

- **CPU y memoria en el notch**: requieren sondeo, ocupan espacio permanente y
  contradicen la arquitectura casi inactiva de Altillo; no mejoran su promesa.
- **HUD de brillo**: no hay una ruta pública y estable para todos los monitores;
  no usar APIs privadas ni Accessibility para perseguir paridad visual.
- **Modo cristal/transparente**: debilita la silueta negra y doméstica que hace
  reconocible a Altillo.
- **Historial de archivos en Clipboard**: duplica el cajón. Las URLs de archivo
  deben seguir entrando por Shelf.
- **Imágenes en Clipboard**: hueco real, pero primero medir demanda. Supone
  límites de memoria/disco, miniaturas, borrado seguro, migración del archivo y
  una revisión de privacidad. Abrir un plan separado solo con evidencia de uso.
- **Progreso universal de descargas**: navegadores y apps no ofrecen un contrato
  público común; una implementación basada en observar carpetas sería imprecisa.
- **Compatibilidad macOS 14/15**: ampliaría mercado, pero el proyecto usa macOS
  26, Foundation Models y APIs recientes. Hacer un spike de producto/arquitectura
  separado antes de cambiar el deployment target; no mezclarlo con paridad.
- **Guerra de precio a 5 $**: NotchView no demuestra sostenibilidad ni retención.
  Altillo debe competir en confianza, profundidad de agentes y acabado.

## Línea base conocida

- Commit auditado: `5033311`.
- `cd Packages/AltilloKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` pasa:
  337 tests en 55 suites.
- El test completo de Xcode ejecuta 719 tests. En el árbol de trabajo que había
  durante la auditoría fallaba únicamente
  `SmokeTests.restingIndicatorsKeepBreathingRoom()` por cambios locales no
  comprometidos en la geometría de las orejas. Ningún plan debe ocultar esa
  línea base ni sobrescribir esos cambios.

## Verificación después de implementar

- AltilloKit: 339 tests en 55 suites, todos pasan cuando se ejecuta la suite de
  forma aislada.
- macOS: 738 tests en 53 suites, `TEST SUCCEEDED`; el fallo de geometría de la
  línea base quedó resuelto por los cambios locales que ya estaban en curso.
- Web: 131 tests pasan, 10 skips intencionados; build de producción correcto.
- Ejecutar AltilloKit y Xcode simultáneamente provoca contención en las pruebas
  del socket global de `altillo-hook`; por eso ambas puertas se verifican en
  serie, como hacen sus ejecuciones normales.
