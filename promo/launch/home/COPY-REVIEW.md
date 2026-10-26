# Revisión de copy · Casa / Home · 17/10/2026

Recomendación:
- **Frase de marca:** «Home Assistant, in your notch.» / «Tu casa, en el notch.»
- **Una línea de mecanismo** para títulos y fichas sin vídeo: «Control your Home Assistant lights, blinds and scenes from your Mac's notch.»
- **CTA:** descargar en altillo.app; en el foro, código en GitHub.

Panel igual que en el kit principal: escéptico, desconocido, competidor, usuario y editor, de 0 a 20 cada uno. Son **juicios heurísticos**, no rendimiento medido. Se generaron 14 ángulos y sobreviven 11. Se descartaron tres:
- «Everything in Home Assistant, in your notch»: falso.
- «The fastest way to control Home Assistant on a Mac»: sin medición.
- «Works with Home Assistant»: programa de certificación ajeno.

| Copy | Ángulo | E / D / C / U / Ed | Total |
|---|---|---|---|
| Home Assistant, in your notch. | Marca / categoría | 18 / 17 / 17 / 18 / 19 | 89 |
| Control your Home Assistant lights, blinds and scenes from your Mac's notch | Mecanismo / recomendada para títulos | 20 / 20 / 16 / 18 / 18 | 92 |
| Your lights, in their real colours | Detalle visual | 19 / 16 / 17 / 18 / 19 | 89 |
| Drag to dim. Click for movie night. | Acción concreta | 19 / 17 / 15 / 19 / 18 | 88 |
| Ding-dong. See who it is. | Timbre / vídeo | 17 / 14 / 18 / 18 / 18 | 85 |
| Signs in with Home Assistant's own login. No token to copy. | Objeción / onboarding | 20 / 18 / 17 / 19 / 18 | 92 |
| Straight from your Mac to your Home Assistant. No Altillo server. | Privacidad | 19 / 18 / 16 / 19 / 18 | 90 |
| Free, MIT, macOS 26+, and a beta | Oferta / honestidad | 20 / 17 / 14 / 18 / 18 | 87 |
| Not yet: climate, locks, live camera | Límite explícito / confianza | 20 / 18 / 15 / 18 / 19 | 90 |
| Locks stay out until they need a press-and-hold | Opinión de diseño | 19 / 18 / 17 / 17 / 19 | 90 |
| I added Home Assistant to my open-source notch app | Maker / foro | 19 / 18 / 15 / 18 / 18 | 88 |

«Ding-dong. See who it is.» funciona en el vídeo, pero sola no dice qué es Altillo; no usarla como título. ES conserva la misma afirmación, no una traducción que prometa más.

## Afirmaciones contra el código

Auditoría de lectura de `~/Developer/altillo-h2`, rama `release/home-0.11.0` (HEAD `abc2681`), el 17/10. Sin ejecutar la app.

| Afirmación usada en el kit | Veredicto | Evidencia |
|---|---|---|
| Luces: clic, arrastrar para atenuar, color real en la baldosa | Cierto | `HomeModel.swift:75` (rgb_color/kelvin), `DesvanHomeParts.swift:20` |
| Detalle: brillo, temperatura de blanco, 8 colores | Cierto, si la luz lo admite | `DesvanHomeDetail.swift:1081-1090` |
| Interruptores, `input_boolean`, ventiladores on/off | Cierto (ventilador solo on/off) | `HomeAssistantMapping.swift:106-121`, `DesvanHomeDetail.swift:25` |
| Persianas con posición y Parar | Cierto, según capacidades de la persiana | `DesvanHomeDetail.swift:233,271-274` |
| Escenas y scripts con un clic | Cierto | `HomeModel.swift:70` |
| Fila de sensores | Cierto | `DesvanHome.swift:137,213` |
| Chips de estancia (áreas) y páginas propias | Cierto; la estancia muestra luces, persianas, interruptores, ventiladores, escenas y scripts, **no todo** | `DesvanHome.swift:104`, `HomeStore+Notch.swift:16` |
| Renombrar, icono, tamaño, ocultar, reordenar, «Open in Home Assistant», hasta 8 sugeridos | Cierto | `HomeLayout.swift`, `DesvanHomeParts.swift:406-448`, `HomeStore.swift:54` |
| Timbre con `event.*`/`binary_sensor` y foto de cámara | Cierto; **instantánea**, no directo | `HomeAssistantMapping.swift:265-271,353` |
| Oreja: puerta/ventana/garaje ≥ 10 min; luces sin nadie (`zone.home`) | Cierto; puertas/ventanas solo si son favoritas | `HomeEarLogic.swift`, `NotchActivity.swift:22,90` |
| Descubrimiento mDNS + `homeassistant.local:8123` | Cierto | `HomeDiscovery.swift:65-66`, `project.yml:81-82,98` |
| OAuth 2 + PKCE, loopback 127.0.0.1, token «Altillo (Mac)» en el Llavero; pegar token | Cierto | `HomeAuthFlow.swift:112-116,141,189-207,275`, `HomeTokenStore.swift:15` |
| http solo en LAN; remoto https | Cierto | `project.yml:77-78`; texto «Outside your local network, Altillo needs an https:// address» (`HomeStrings.swift:23-24`) |
| Certificado propio: confiar una vez y fijar huella | Cierto | `.needsTrust`, `pinnedCertificateSHA256` |
| Por eventos, solo entidades vigiladas, ping 60 s | Cierto | `HomeAssistantClient.swift:421,531` |
| Sin servidor de Altillo | Cierto (no hay backend; política de privacidad) | `website/privacy/index.html:53` |
| Opt-in | Cierto | `NotchModule.swift:73` |
| Bienvenida «Your home in the notch?» | Cierto | `OnboardingHomePage.swift:140-185` |

## Afirmaciones suavizadas o retiradas

| Afirmación de partida | Problema | Cómo queda |
|---|---|---|
| Apple Home «via Shortcuts» (encargo, notas 0.11.0) | Fila informativa con «Coming soon» / «Muy pronto»; sin baldosa | «planned / coming soon»; hoy solo la sección Atajos general puede ejecutar un atajo de Casa |
| Clima, cerraduras, persianas «y más» | Clima y cerraduras no son baldosas; cerraduras, alarma y garaje excluidos a propósito (`HomeStore.swift:250-252`) | Lista cerrada + «Not yet» |
| Cámara del timbre | Instantánea por `camera_proxy` | «still snapshot», nunca «live» |
| Estancias «show everything» (notas 0.11.0) | Sin sensores ni tipos de solo lectura | Lista explícita |
| «Disconnecting deletes the token» | Borra el del Mac; **no** llama a `/auth/revoke` para el token de larga duración | Instrucción para borrarlo en el perfil de Home Assistant |
| Nabu Casa / acceso remoto | Sin código específico ni prueba | «an https address you enter»; Nabu Casa «not tested» |
| Hue, Google, Alexa, Matter | Solo a través de Home Assistant | Siempre con «through Home Assistant» |
| «Beta» | La app no muestra esa etiqueta | Se dice en posts y notas; la app no lo indica (posible mejora, fuera de este kit) |
| Versión mínima de Home Assistant | No hay ninguna | Placeholder para que Xus confirme versiones probadas |
| Universal Intel + Apple Silicon | Verificado para 0.10.6 en el kit principal, no para 0.11.0 | Placeholder «confirm» en la FAQ |
| Pregunta controla la casa / atajos por escena / varias casas / iPhone | No implementado | No se menciona salvo como «no» |
| Hilo de Home Assistant de House Control como argumento | Referencia interna; comparar con competidores no aporta | Ningún post compara; respuesta neutra preparada para Itsyhome/HomeOtter/HomeGlance/ha-menu |

## Vídeo

Rótulos en pantalla (`promo/src/casa/Casa.tsx`):

| Tiempo | EN / ES | Veredicto |
|---|---|---|
| 0–2 s | «Your notch can now run your home.» / «Tu casa, ahora en el notch.» | Aceptable como gancho. «Run your home» es amplio, pero el resto del vídeo lo concreta |
| 6,5–10 s | «Hold any tile for its controls.» / «Mantén pulsada una baldosa para ver sus controles.» | EN «any» es amplio; el detalle existe para luces, persianas, interruptores y ventiladores. Menor |
| 13,3–16 s | ~~«Anything in Home Assistant.» / «Todo lo que tengas en Home Assistant.»~~ → **«Straight from your Home Assistant.» / «Desde tu Home Assistant.»** | **Corregido.** El rótulo anterior era falso (clima, cerraduras, reproductores y cámaras como baldosa no están). El nuevo solo dice de dónde salen los dispositivos |

**Hecho (17/10):** `tourSub` cambiado a **«Straight from your Home Assistant.» / «Desde tu Home Assistant.»** y los cuatro MP4 vueltos a renderizar (`npm run render:casa`, `:en`, `:vertical`, `:vertical:en`; `promo/CASA.md`). Mismo tratamiento y tiempos; el fotograma 250 (pósters) no cambia. Ya se pueden subir a YouTube.

Otros rótulos («Your lights. In their real colours.», «Drag to dim», «Movie night. One click.», «Pull up the blind.», «Flip the switch.», «Ding-dong. See who it is.») coinciden con funciones verificadas. El cierre «Free · Open source · altillo.app» es correcto.

Póster EN: la casa de demostración se llama «Casa» también en inglés (es el `location_name` de la demo). No es un error de la app; no requiere cambio.

## Revisión de verdad y estilo

- Marca: «Home Assistant» completo. Sin logo, sin «Works with», aviso de independencia en foro, Reddit y YouTube.
- Sin «seamless», «revolutionize», superlativos ni «not just X but Y». Cada post nombra lo que falta.
- Sin cifras de usuarios, descargas, rendimiento, batería o memoria.
- Las frases personales («lo que más uso», «mi parte favorita», «around 250 entities») las confirma o cambia Xus. Van marcadas o señaladas en cada archivo.
- Foro y Reddit: el texto es un borrador para que Xus lo haga suyo. Las respuestas se escriben a mano.

## Hallazgo lateral (no afecta al copy)

`-designScenario openHome` / `peekDoorbell` y `-demoHome` se leen fuera de `#if DEBUG` (`AppDelegate.swift:13`, `DesignScenario.swift:22-24`, `DesvanHome.swift:411`): una build Release entra en modo demostración con argumentos de lanzamiento. Es inofensivo para el usuario normal. Se anota por si se prefiere limitarlo a DEBUG.

## Lo que no se pudo medir

Audiencia, alcance, tráfico del foro y resultados de las variantes. Tampoco las reglas de r/homeassistant ni las del Discord.
