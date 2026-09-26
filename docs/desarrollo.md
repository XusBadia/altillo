# Guía de desarrollo del día a día

Notas prácticas para trabajar en Altillo en local. Para el plan, los
principios y el diseño técnico, ver [PLAN.md](../PLAN.md).

## Dónde compilar (importante)

Compila **fuera de `~/Documents`**. Si la app compilada vive dentro de Documentos, macOS pide permiso de acceso a Documentos en cada arranque:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Altillo.xcodeproj -scheme Altillo \
  -derivedDataPath ~/Library/Developer/AltilloBuild build
open ~/Library/Developer/AltilloBuild/Build/Products/Debug/Altillo.app
```

En CI da igual, porque no hay TCC.

### Tests en macOS 27: derivedData en `/tmp`

En macOS 27, `xcodebuild test` con la derivedData dentro de `~/Documents` (por ejemplo `build/dd`) puede
quedarse colgado antes de que el runner conecte: «The test runner hung before establishing connection». La app
de pruebas se queda parada en `dyld` abriendo sus librerías, esperando a TCC (la protección de Documentos), y no
sale ningún diálogo. Compilar funciona; lo que se cuelga es lanzar el host de los tests.

Usa una derivedData en `/tmp` para los tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Altillo.xcodeproj -scheme Altillo \
  -derivedDataPath /tmp/altillo-dd test
```

En CI no pasa (los runners de GitHub no tienen TCC), así que el workflow sigue con `build/dd-ci`.

## Xcode y `xcode-select`

Altillo necesita **Xcode 26**, no solo las Command Line Tools. Si tu Mac tiene
solo las CLT instaladas (o `xcode-select` apunta a ellas), verás un error como:

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Compruébalo con:

```sh
xcode-select -p
```

Si no apunta a `/Applications/Xcode.app/Contents/Developer`, arréglalo de
forma permanente (pide contraseña de administrador):

```sh
sudo xcode-select -s /Applications/Xcode.app
```

Si prefieres no tocar el `xcode-select` global de tu Mac (por ejemplo, si
tienes varias versiones de Xcode instaladas), puedes anteponer la variable de
entorno a cualquier comando puntual sin cambiar nada global:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
```

Así es como corre CI (`.github/workflows/ci.yml`): selecciona explícitamente
el Xcode 26 más reciente disponible en el runner en vez de asumir cuál está
activo.

## Generar el proyecto

`Altillo.xcodeproj` no se versiona (está en `.gitignore`): lo genera
[XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir de `project.yml`.

```sh
brew install xcodegen   # una vez
xcodegen generate       # cada vez que cambie project.yml, o tras clonar
open Altillo.xcodeproj
```

Regenera el proyecto **siempre** que cambies `project.yml`, o que añadas,
quites o muevas ficheros de código: nunca edites el `.xcodeproj` a mano desde
Xcode para eso, porque se perdería al regenerar.

## Ejecutar la app

Desde Xcode, elige el esquema **Altillo** (macOS) o **AltilloiOS** (simulador
de iOS) y pulsa ⌘R. También puedes compilar y lanzar desde terminal:

```sh
xcodebuild -project Altillo.xcodeproj -scheme Altillo \
  -derivedDataPath build/dd build
open build/dd/Build/Products/Debug/Altillo.app
```

Altillo es una `MenuBarExtra`: al arrancar no abre ninguna ventana propia,
solo pone un icono en la barra de menú (`square.stack.3d.up`). Desde ese menú
se abre el notch, se vacía el altillo y se accede a las herramientas de
depuración descritas abajo.

## El argumento `-designScenario <nombre>`

Para revisar el aspecto de cada estado del notch sin tener que provocarlo a
mano (arrastrar un archivo, esperar un permiso de un agente, etc.), la app
acepta un argumento de lanzamiento que congela un estado concreto:

```sh
open build/dd/Build/Products/Debug/Altillo.app --args -designScenario openShelf
```

Esto usa el mecanismo estándar de `UserDefaults` de macOS (`-clave valor` se
lee como `UserDefaults.standard.string(forKey: "clave")`), así que también
funciona añadiendo el argumento en el esquema de Xcode (**Product > Scheme >
Edit Scheme… > Run > Arguments**): `-designScenario openShelf`.

Los nombres válidos están en
[`Apps/macOS/Notch/DesignScenario.swift`](../Apps/macOS/Notch/DesignScenario.swift),
como el `rawValue` de cada caso del enum `DesignScenario`. A fecha de escribir
esto:

| Nombre | Qué muestra |
|---|---|
| `idle` | Reposo |
| `idleWithEars` | Reposo con orejas |
| `peekHint` | Peek: pista cuando el altillo está vacío |
| `peekShelf` | Peek: altillo |
| `peekUsageAlert` | Peek: alerta de uso |
| `peekAgentWaiting` | Peek: agente esperando |
| `dragArmed` | Arrastre en curso |
| `dropTarget` | Zona de soltar |
| `openShelfEmpty` | Abierto: altillo vacío |
| `openShelfLoading` | Abierto: guardando una promesa de archivo |
| `openShelfError` | Abierto: error recuperable al guardar |
| `openShelf` | Abierto: altillo con archivos |
| `openUsage` | Abierto: uso de IA |
| `openAgents` | Abierto: agentes |
| `openCalendar` | Abierto: agenda |
| `openMirror` | Abierto: espejo |
| `openNowPlaying` | Abierto: sonando |

También se puede llegar a los mismos escenarios desde el menú de la barra de
menú: **Revisión de diseño** lista todos los casos de `DesignScenario` y los
aplica con un clic; "Volver al modo normal" los quita.

Como esta lista puede quedarse desactualizada, la fuente de verdad siempre es
`DesignScenario.allCases` en el propio fichero.

## La ventana "Registro de pruebas"

Durante la fase 0 (spikes de drag & drop), la app mantiene un registro en
memoria de eventos (`SpikeLog`, en
[`Apps/macOS/Debug/SpikeLog.swift`](../Apps/macOS/Debug/SpikeLog.swift)) para
poder comprobar la matriz de pruebas de arrastre de
[PLAN.md §8](../PLAN.md#8-matriz-de-pruebas-de-drag--drop) sin depurar en
Console.app. Se abre desde el menú de la barra de menú: **"Registro de
pruebas de arrastre…"**. Es una `Window` de SwiftUI (`id:
"spike-log"`) que lista cada entrada con su categoría y su hora.

Este registro vive solo en memoria y se pierde al cerrar la app — no sustituye
a los logs del sistema, solo ayuda a verificar los spikes en el momento.

## Dónde van los logs

- **En pantalla, durante desarrollo:** la ventana "Registro de pruebas"
  (arriba) para los eventos de drag & drop instrumentados con `SpikeLog`.
- **Sistema:** el resto de logging usa `os.Logger` / `NSLog` estándar de
  Apple, visible en **Console.app** filtrando por el proceso `Altillo` (o con
  `log stream --predicate 'process == "Altillo"'` en terminal). Esto incluye
  cualquier traza que no pase por `SpikeLog`, y es lo único disponible en
  builds instaladas fuera de Xcode (ver siguiente sección).
- **xcresult de los tests:** cada `xcodebuild test` deja sus logs y su
  cobertura en `build/<carpeta-derivedData>/Logs/Test/*.xcresult`, abribles
  con Xcode (`open ese.xcresult`) o `xcrun xcresulttool`.

## Probar en el MacBook (el único Mac con notch físico)

Como el desarrollo principal ocurre en un Mac sin notch (ver
[PLAN.md §9, riesgos](../PLAN.md#9-riesgos)), conviene instalar de vez en
cuando la build de Debug en el MacBook con notch para comprobar el
comportamiento real:

1. Compila en el Mac de desarrollo (o directamente en el MacBook, si XcodeGen
   y Xcode 26 están instalados allí también):

   ```sh
   xcodegen generate
   xcodebuild -project Altillo.xcodeproj -scheme Altillo \
     -derivedDataPath build/dd build
   ```

2. Copia `build/dd/Build/Products/Debug/Altillo.app` al MacBook (AirDrop,
   `scp`, un volumen compartido…) y ábrela con doble clic o `open Altillo.app`.
   Al ser una build sin firma de equipo (`ALTILLO_MAC_SIGN_IDENTITY = -` por
   defecto), Gatekeeper puede pedir confirmación la primera vez
   (clic derecho > Abrir, o Ajustes del Sistema > Privacidad y seguridad).

3. Usa el menú de la barra de menú para probar directamente los escenarios de
   `-designScenario`, o dejar la app corriendo en reposo para comprobar CPU
   y comportamiento real del notch (hover, arrastres, multi-pantalla…).

4. Cuando exista una release notarizada con Sparkle (fase 2 del plan), este
   paso se sustituye por una actualización normal de la app instalada — la
   idea es poder dogfoodear en el MacBook de forma continua, según
   [PLAN.md §9](../PLAN.md#9-riesgos).

Si compilas directamente en el MacBook, todo lo anterior de `xcode-select` y
`xcodegen generate` aplica igual allí.
