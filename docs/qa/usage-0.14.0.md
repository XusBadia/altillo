# Validación de Altillo 0.14.0

Publicada el 8 de noviembre de 2026: [release y DMG](https://github.com/XusBadia/altillo/releases/tag/v0.14.0). Build **219**, fuente `8c206786af730d8177090fa3834417023ae22a2e`.

- [CI del SHA distribuido](https://github.com/XusBadia/altillo/actions/runs/42516397121): seis jobs correctos, incluidos paquete, macOS, iOS, web/Playwright, escaneo de secretos y puertas de publicación.
- Suite local del alcance distribuido: 919 tests macOS en 71 suites. Español: 0 de 1646 cadenas pendientes. Siete pruebas del validador de perfil correctas.
- Archive/export universal con Developer ID, perfil explícito de Altillo, sin permiso de depuración. Keychain privado: add/read/delete de un registro sintético con los entitlements exportados y `WhenUnlockedThisDeviceOnly`.
- Notarización de app aceptada: `1ea9e891-bbcb-4af9-a808-db68ab36231f`. DMG aceptado: `a02b65e9-530d-4714-afb5-0c867f8ca62f`.
- Smoke del DMG generado y de la descarga pública: Gatekeeper acepta como Notarized Developer ID, firma profunda/embebidos correctos, arranque correcto.
- Descarga pública HTTP 200; SHA-256 idéntico al artefacto local: `4fbca5039f96171e51a543963dd7f787e099904da3cc05c5286acf044d4e16ec`. Tamaño: 18271588 bytes.
- `https://altillo.app/appcast.xml` y `https://xusbadia.github.io/altillo/appcast.xml` responden 200 y ofrecen 0.14.0 con la misma URL, longitud y firma EdDSA.
- Actualización real mediante Sparkle desde `/Applications/Altillo.app` 0.13.0 (217) a **0.14.0 (219)**, con descarga, instalación y relanzamiento correctos. El enlace `altillo://usage` abre Ajustes › Uso.
- La app instalada recupera `xus@badia.me`, Connected · Max, sin nuevo consentimiento. El hook estable conserva `/Applications/Altillo.app/Contents/MacOS/altillo-hook`.

El smoke de distribución ahora restaura el enlace previo del hook después de cerrar su copia temporal, sin sobreescribir un cambio concurrente. La segunda prueba con el DMG descargado acredita esa restauración.

## Alcance y pendientes

Claude/Codex conectan sesiones propias, independientes del CLI. Claude tiene consentimiento y lectura reales verificados. Codex y la rotación real del refresh token siguen pendientes de QA; las notas públicas lo explican. El correo nativo no se incluye: se conserva en `feat/native-mail-accounts` y Mail mantiene el puente publicado en 0.13.0.

Xus confirmó **@XusBadia**, la cuenta que usa Aurio, como destino del anuncio. Programado en Buffer mediante su sesión existente de Chrome para **8 noviembre 2026 a las 22:45 Europe/Madrid**. Confirmación de Buffer y lectura posterior de la cola: un único anuncio de Altillo, con texto y fecha correctos. No publicado todavía. El borrador anterior de @_flixmd no está programado y no se utiliza.
