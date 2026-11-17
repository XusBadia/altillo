# Release: notarización y Sparkle

Cómo se firma, notariza y publica Altillo, y cómo funcionan las
actualizaciones automáticas (Sparkle). Para el resto del flujo de desarrollo,
ver [desarrollo.md](desarrollo.md). Decisión de distribución: [PLAN.md §0](../PLAN.md#0-decisiones-tomadas).

Todo esto solo hace falta si vas a publicar una release real. Para compilar
y desarrollar Altillo no necesitas nada de esto — ver
[CONTRIBUTING.md](../CONTRIBUTING.md).

Altillo **0.14.1 ya está distribuida públicamente**, firmada y notarizada por
Apple, con actualizaciones Sparkle. Los comandos siguientes describen el
procedimiento para futuras releases. La [validación de 0.14.1](qa/confirmation-pages-0.14.1.md)
registra el instalador público, su firma y el feed de actualizaciones. La
[validación de 0.14.0](qa/usage-0.14.0.md) conserva la prueba de actualización
real desde 0.13.0.

## Cómo funciona

- La app se distribuye **firmada con Developer ID** (equipo `9L2TD7KVV9`),
  **notarizada por Apple** y **sin sandbox**, con hardened runtime. Las
  entitlements (`Apps/macOS/App/Altillo.entitlements`) solo piden lo que
  hardened runtime bloquearía por defecto: cámara (Espejo), Apple Events a
  Música/Spotify (Now Playing) y Calendario — nada de sandboxing real. Las
  builds de release usan las mismas entitlements que las de desarrollo.
- Las actualizaciones usan **[Sparkle 2](https://sparkle-project.org/)**: la
  app comprueba `https://altillo.app/appcast.xml`, que la web sirve desde el
  fichero `website/public/appcast.xml` en Vercel, y
  verifica la firma EdDSA de cada descarga con la clave pública embebida en
  `Info.plist` (`SUPublicEDKey`).
- **Un fork sin configurar Sparkle sigue compilando.** `ALTILLO_SPARKLE_FEED_URL`
  y `ALTILLO_SPARKLE_PUBLIC_KEY` están vacíos por defecto
  (`Config/Shared.xcconfig`); `Updater.swift` trata eso como "no configurado"
  y no arranca ningún `SPUStandardUpdaterController` — el menú y el panel
  Acerca de deshabilitan "Check for Updates…" con una explicación.
- `script/release.sh` hace todo el trabajo: `xcodebuild archive` firmado con
  Developer ID → exportar el `.app` → verificar la firma → notarizar el
  `.app` → construir el DMG → notarizar el DMG → generar/actualizar
  `appcast.xml` con `generate_appcast` de Sparkle. El paso final de
  publicación (crear el release de GitHub) solo ocurre con `--publish`; sin ese flag el script se detiene
  después de dejar los artefactos en `dist/`.

## Configuración única (la haces tú, una sola vez)

### 1. Clave de firma EdDSA de Sparkle

Ya está generada en este Mac (cuenta `altillo` del llavero de inicio de
sesión) y su clave pública está en `Config/Local.xcconfig`
(`ALTILLO_SPARKLE_PUBLIC_KEY`). Si necesitas regenerarla o moverla a otro
Mac (por ejemplo para que CI pueda firmar):

```sh
# El binario vive en los artefactos de SwiftPM ya resueltos (cualquier build del
# proyecto los descarga; script/release.sh usa build/dd-release):
GK="$(find build -path '*artifacts/sparkle/Sparkle/bin/generate_keys' | head -n1)"

# Generar (o reutilizar) la clave, cuenta "altillo":
"$GK" --account altillo

# Ver solo la clave pública (para Config/Local.xcconfig):
"$GK" --account altillo -p

# Exportar la clave PRIVADA a un fichero, para guardarla a buen recaudo o
# dársela a CI (secreto ALTILLO_SPARKLE_PRIVATE_KEY, en base64). Nunca la
# imprimas en un log ni la commitees.
"$GK" --account altillo -x /tmp/altillo-sparkle-private-key
base64 -i /tmp/altillo-sparkle-private-key | pbcopy
shred -u /tmp/altillo-sparkle-private-key 2>/dev/null || rm -P /tmp/altillo-sparkle-private-key
```

Guarda ese `.p8`/export en un gestor de contraseñas. Si se pierde, las
instalaciones existentes de Altillo dejan de poder verificar futuras
actualizaciones firmadas con una clave nueva — tendrían que reinstalar a
mano una vez.

### 2. Credenciales de notarización (notarytool)

Necesitas una contraseña específica de app de tu Apple ID: créala en
<https://account.apple.com> → Inicio de sesión y seguridad → Contraseñas de
apps específicas de apps.

```sh
xcrun notarytool store-credentials altillo-notary \
  --apple-id tu-apple-id@example.com \
  --team-id 9L2TD7KVV9 \
  --password xxxx-xxxx-xxxx-xxxx
```

Esto guarda las credenciales en el llavero bajo el perfil `altillo-notary`,
que es lo que usa `script/release.sh` por defecto en local. (Como alternativa se usan
en su lugar los secretos `ALTILLO_NOTARY_*`, ver más abajo.)

### 3. Feed de actualizaciones en Vercel

La web sirve `website/public/appcast.xml` en `https://altillo.app/appcast.xml`.
El script parte del feed público para conservar las versiones anteriores y
genera el nuevo fichero con los enlaces firmados del DMG.

## Publicar una release

1. Actualiza `MARKETING_VERSION` en `project.yml` y escribe
   `docs/releases/<versión>.md`. Crea el commit de lanzamiento.
2. Ejecuta `script/validate-release.sh`. El script guarda resultados y logs
   locales asociados al SHA exacto.
3. Empuja el commit validado y ejecuta:

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   script/release.sh <versión> --publish
   ```

   El script exige el árbol limpio y la validación del SHA, tanto al arrancar
   como antes de crear el release. Firma, notariza y verifica el DMG.
4. Copia `dist/appcast.xml` a `website/public/appcast.xml`, haz commit y
   publica la web en Vercel. Comprueba que la URL pública entrega la versión
   nueva y que el enlace firmado al DMG funciona.

`script/release.sh <versión> --dry-run` permite empaquetar sin notarizar.
`bash script/release-gates-test.sh` comprueba localmente las puertas de publicación.

## Rollback y hotfix

- **Release defectuosa todavía no anunciada:** marca el release de GitHub como
  pre-release o elimínalo, restaura el `appcast.xml` anterior en Vercel y
  comprueba que `https://altillo.app/appcast.xml` ya no ofrece esa versión.
- **Release ya instalada:** no sustituyas silenciosamente el DMG bajo la misma
  etiqueta. Corrige desde `main`, aumenta la versión patch, escribe sus notas y
  publica un hotfix normal; Sparkle lo entregará como una actualización nueva.
- **Rollback manual del usuario:** cerrar Altillo, instalar el DMG de la release
  anterior y desactivar temporalmente las actualizaciones automáticas. Los
  datos locales no se borran. Si el problema afecta a hooks, usar primero
  **Settings → Agents → Prepare to Uninstall**.
- Tras cualquier rollback, descarga el DMG que siga público y ejecuta
  `script/smoke-release.sh <dmg>`; verifica también que el appcast conserva su
  firma EdDSA y todas las versiones anteriores necesarias.

### Versiones de prueba (pre-release)

Una versión con sufijo (`0.2.0-beta.1`) se marca como *prerelease* en GitHub
y se publica en el canal `beta` del appcast (`--channel beta`), no en el
general — solo la ven quienes hayan optado a probar el canal beta.

## Homebrew

`packaging/homebrew/Casks/altillo.rb` es la fuente de verdad del cask en
este repositorio. No está publicado en ningún tap todavía: es preparación
para cuando decidas distribuir Altillo por Homebrew (fase 10, "Publicación").

### Mantenerlo al día

Después de publicar una release con `script/release.sh <versión> --publish`,
actualiza el cask con:

```sh
script/update-cask.sh <versión>
```

El script descarga el DMG recién publicado desde GitHub Releases, calcula su
sha256 y reescribe `version` y `sha256` en `packaging/homebrew/Casks/altillo.rb`
sin tocar el resto del fichero (depends_on, zap, etc.). Falla con un mensaje
claro si la versión todavía no está publicada (404) o si el cask no tiene las
líneas `version "..."` / `sha256 "..."` esperadas.

### Opción A: tap propio (recomendado a corto plazo)

Mientras Altillo no sea lo bastante conocido para el tap oficial, la forma
más simple de que alguien haga `brew install --cask altillo` es un tap
propio:

```sh
brew tap-new XusBadia/tap
cp packaging/homebrew/Casks/altillo.rb "$(brew --repository)/Library/Taps/xusbadia/homebrew-tap/Casks/altillo.rb"
brew style --cask "$(brew --repository)/Library/Taps/xusbadia/homebrew-tap/Casks/altillo.rb"
brew audit --cask --new "$(brew --repository)/Library/Taps/xusbadia/homebrew-tap/Casks/altillo.rb"
```

Después, crea el repositorio `XusBadia/homebrew-tap` en GitHub (público, MIT
o sin licencia — es solo el índice del tap), sube el cask y publícalo. Con el
tap publicado, cualquiera instala Altillo con:

```sh
brew tap XusBadia/tap
brew install --cask altillo
```

Este repositorio no crea el tap por ti — es una decisión que se toma aparte,
con consentimiento explícito, porque implica publicar un nuevo repositorio
público.

### Opción B: `homebrew/homebrew-cask` oficial (más adelante)

Homebrew acepta casks de terceros en su repositorio oficial solo cuando el
proyecto es "notable" (criterios propios de estrellas, forks, menciones y
descargas — ver su
[`CONTRIBUTING.md`](https://github.com/Homebrew/homebrew-cask/blob/master/CONTRIBUTING.md)
y los requisitos de
[`Acceptable Casks`](https://docs.brew.sh/Acceptable-Casks)). No tiene
sentido intentarlo antes de cumplir ese listón; hasta entonces, la Opción A
cubre la instalación por Homebrew.

### Validación local

Sin tapear el cask, se puede comprobar el estilo directamente sobre el
fichero:

```sh
brew style packaging/homebrew/Casks/altillo.rb
```

`brew audit --cask` no llegó a ejecutarse en esta máquina: Homebrew exige
Xcode 27.0 y aquí solo hay 26.6 instalado, así que aborta antes de auditar
nada, sin relación con el cask en sí. Repite `brew audit --cask --new` una
vez el Xcode del equipo esté al día, o cuando el cask viva ya en un tap real
(Opción A) — algunas comprobaciones del audit solo se resuelven bien con el
cask tapeado.
