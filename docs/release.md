# Release: notarización y Sparkle

Cómo se firma, notariza y publica Altillo, y cómo funcionan las
actualizaciones automáticas (Sparkle). Para el resto del flujo de desarrollo,
ver [desarrollo.md](desarrollo.md). Decisión de distribución: [PLAN.md §0](../PLAN.md#0-decisiones-tomadas).

Todo esto solo hace falta si vas a publicar una release real. Para compilar
y desarrollar Altillo no necesitas nada de esto — ver
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Cómo funciona

- La app se distribuye **firmada con Developer ID** (equipo `9L2TD7KVV9`),
  **notarizada por Apple** y **sin sandbox**, con hardened runtime. Las
  entitlements (`Apps/macOS/App/Altillo.entitlements`) solo piden lo que
  hardened runtime bloquearía por defecto: cámara (Espejo), Apple Events a
  Música/Spotify (Now Playing) y Calendario — nada de sandboxing real.
- Las releases añaden además **iCloud** (solo si hay perfil, ver
  [iCloud (transición)](#icloud-transición)): `Altillo.release.entitlements`
  + el perfil Developer ID embebido, para que la app escriba el fichero que
  lee la app antigua de iPhone. Las builds de desarrollo no cambian.
- Las actualizaciones usan **[Sparkle 2](https://sparkle-project.org/)**: la
  app comprueba un feed (`appcast.xml`) publicado en GitHub Pages
  (`https://xusbadia.github.io/altillo/appcast.xml`, rama `gh-pages`) y
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
  publicación (crear el release de GitHub y subir `appcast.xml` a
  `gh-pages`) solo ocurre con `--publish`; sin ese flag el script se detiene
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
que es lo que usa `script/release.sh` por defecto en local. (En CI se usan
en su lugar los secretos `ALTILLO_NOTARY_*`, ver más abajo.)

### 3. GitHub Pages para el appcast

En la configuración del repo (`XusBadia/altillo` → Settings → Pages), activa
Pages sirviendo desde la rama `gh-pages` (carpeta raíz). La primera
publicación (`script/release.sh <version> --publish`, o el workflow de CI)
crea esa rama si no existe todavía.

### 4. Secretos de CI (`.github/workflows/release.yml`)

Solo hacen falta si quieres que las releases se publiquen automáticamente al
empujar una etiqueta `vX.Y.Z`. Configúralos en Settings → Secrets and
variables → Actions:

| Secreto | Qué es |
|---|---|
| `ALTILLO_CERTIFICATE_P12` | El certificado "Developer ID Application" (equipo `9L2TD7KVV9`), exportado desde Acceso a Llaveros como `.p12`, codificado en base64 (`base64 -i cert.p12 \| pbcopy`). |
| `ALTILLO_CERTIFICATE_PASSWORD` | La contraseña que le pusiste a ese `.p12` al exportarlo. |
| `ALTILLO_NOTARY_APPLE_ID` | El Apple ID con acceso al equipo `9L2TD7KVV9`. |
| `ALTILLO_NOTARY_APP_PASSWORD` | Una contraseña específica de app para ese Apple ID (la del paso 2, o una nueva). |
| `ALTILLO_NOTARY_TEAM_ID` | `9L2TD7KVV9`. |
| `ALTILLO_SPARKLE_PUBLIC_KEY` | La clave pública EdDSA (no es secreta, pero así queda junto a las demás). |
| `ALTILLO_SPARKLE_PRIVATE_KEY` | La clave privada EdDSA exportada en base64 (paso 1). **Esta sí es secreta de verdad.** |
| `ALTILLO_ICLOUD_PROFILE_BASE64` | Opcional. El perfil Developer ID con iCloud en base64 (`base64 -i Config/Provisioning/Altillo_DeveloperID_iCloud.provisionprofile \| pbcopy`, ver [iCloud (transición)](#icloud-transición)). Sin él, CI publica una release sin iCloud (con un aviso en el log). |

Cuando estén todos, crea la variable de repositorio `ALTILLO_CI_RELEASE` con valor `true`
(Settings → Secrets and variables → Actions → Variables). Sin ella, empujar una etiqueta no lanza el
workflow, que es lo correcto mientras las releases se publican en local: `script/release.sh … --publish`
crea la etiqueta y, si no, dispararía una segunda ejecución sin secretos.

`GITHUB_TOKEN` lo proporciona GitHub Actions automáticamente (con permiso
`contents: write` declarado en el workflow) — no hay que crearlo.

## iCloud (transición)

Mientras no exista Altillo para iOS, las releases escriben también el formato
antiguo `openusage.mobile.v1` en el contenedor **existente**
`iCloud.me.badia.ailimits`, para que la app de TestFlight (`me.badia.ailimits`)
siga recibiendo datos y se pueda retirar el bridge
([uso-ia.md](uso-ia.md#transición-altillo-escribe-el-formato-antiguo-fase-3)).

Usar iCloud fuera del sandbox con Developer ID exige un **perfil de
aprovisionamiento Developer ID** embebido en la app. Sin él, una app que pide
entitlements de iCloud ni siquiera arranca. Por eso:

- **Debug/desarrollo:** nada cambia. `Altillo.entitlements`, firma Apple
  Development, sin perfil y sin iCloud. El exportador se queda inactivo.
- **Release con perfil:** `script/release.sh` exporta la app como siempre
  y después:
  1. copia el perfil a `Contents/embedded.provisionprofile`;
  2. añade `NSUbiquitousContainers` al `Info.plist`, igual que el bridge
     (no es público, así que no aparece en iCloud Drive). Solo se añade en
     release: sin entitlement no sirve para nada, y así el `Info.plist` de
     desarrollo y el de los forks no mencionan un contenedor ajeno;
  3. vuelve a firmar solo el bundle exterior (`codesign --force --timestamp
     --options runtime`, sin `--deep`: Sparkle y `altillo-hook` conservan su
     firma). Usa `Altillo.release.entitlements` más
     `com.apple.application-identifier` y `com.apple.developer.team-identifier`
     sacados del perfil. Xcode los inyectaría solo, pero `codesign` no, y sin
     ellos taskgated no deja arrancar la app;
  4. comprueba que `codesign -d --entitlements -` muestra el application
     identifier, el team, el contenedor y `CloudDocuments`.

  Antes de compilar valida el perfil: equipo, application identifier
  (`9L2TD7KVV9.<ALTILLO_BUNDLE_PREFIX>`), que permita el contenedor, que no
  sea de desarrollo, que no haya caducado y que incluya el certificado con el
  que se firma. Si el perfil está configurado pero algo falla, **la release
  se para**: no se cae a una build sin iCloud sin avisar.
- **Release sin perfil:** se compila exactamente como antes, sin iCloud, con
  un `WARNING` al principio y al final del log.

### Configuración (una vez)

1. **Asignar el contenedor al App ID (a mano).** La API de App Store Connect
   no puede asignar contenedores de iCloud (ni siquiera leerlos con una clave
   de API), así que este paso se hace en la web:
   1. <https://developer.apple.com/account/resources/identifiers/list> →
      `me.badia.altillo` (Altillo).
   2. En *Capabilities*, iCloud ya está marcado: pulsa **Edit/Configure** a
      su lado.
   3. Marca **solo** el contenedor existente `iCloud.me.badia.ailimits` y
      pulsa *Continue* → *Save*. **No pulses "+"**: crear un contenedor nuevo
      es irreversible.
   4. Acepta el aviso de que cambiar las capacidades invalida los perfiles.
2. **Crear y descargar el perfil:**

   ```sh
   script/icloud-profile.py
   ```

   Usa la clave de la API de App Store Connect (`ASC_ISSUER`, `ASC_KEY_ID`,
   `ASC_P8`, del entorno o de `~/.config/aurio/asc/env`; nunca las imprime).
   Busca o crea el bundle ID `me.badia.altillo`, activa iCloud, busca el
   certificado Developer ID del llavero, borra el perfil anterior con el mismo
   nombre y crea "Altillo Developer ID iCloud" (`MAC_APP_DIRECT`). Lo guarda
   en `Config/Provisioning/Altillo_DeveloperID_iCloud.provisionprofile`
   (ignorado por git) y lo apunta en `Config/Local.xcconfig` como
   `ALTILLO_ICLOUD_PROFILE`. Si el perfil nuevo no incluye el contenedor (el
   paso 1 no está hecho), lo borra y te dice qué pulsar. Vuelve a ejecutarlo
   si cambias de certificado o si el perfil caduca.
3. **Probar una build firmada** (sin notarizar):

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   script/release.sh 0.3.0-rc --dry-run
   codesign -d --entitlements - dist/Altillo.app          # application-identifier, team, iCloud
   open -g -n dist/Altillo.app --args -legacyMobileExportSelfTest altillo-selftest
   cat ~/Library/Logs/Altillo/legacy-mobile-export-selftest.json   # "result": "written", containerURL
   ls ~/Library/Mobile\ Documents/iCloud~me~badia~ailimits/OpenUsage/Mobile/v1/
   open -g -n dist/Altillo.app --args -legacyMobileExportSelfTestDelete altillo-selftest
   ```

   El segundo `open` borra el documento de prueba, para que el iPhone no
   muestre un Mac fantasma. La app de autoprueba se cierra sola y no toca el
   Altillo que tengas abierto.
4. **CI (opcional):** secreto `ALTILLO_ICLOUD_PROFILE_BASE64` (tabla de
   arriba).

## Publicar una release

1. Decide la versión (`X.Y.Z`, [SemVer](https://semver.org/lang/es/)).
2. Con todo lo de arriba ya configurado en este Mac, prueba en seco primero
   (no notariza, no publica nada, no toca red de escritura):

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   script/release.sh 0.2.0 --dry-run
   ```

3. Genera la release real (firma y notariza de verdad, pero no publica):

   ```sh
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   script/release.sh 0.2.0
   ```

   Revisa `dist/Altillo.app`, `dist/Altillo-0.2.0.dmg` y `dist/appcast.xml`.

4. Publica (crea el release de GitHub y sube el appcast a `gh-pages`):

   ```sh
   script/release.sh 0.2.0 --publish
   ```

   O, más simple, deja que lo haga CI: etiqueta y empuja.

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

   `.github/workflows/release.yml` hace exactamente los mismos pasos
   (`script/release.sh 0.2.0 --publish`) con las credenciales de los
   secretos.

5. Una vez publicado, las instalaciones existentes de Altillo (con Sparkle
   configurado) lo detectan en su siguiente comprobación programada, o al
   momento si el usuario pulsa "Check for Updates…".

### Versiones de prueba (pre-release)

Una versión con sufijo (`0.2.0-beta.1`) se marca como *prerelease* en GitHub
y se publica en el canal `beta` del appcast (`--channel beta`), no en el
general — solo la ven quienes hayan optado a probar el canal beta.
