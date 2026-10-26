# Home v2: diseño (spec de trabajo, 16-10-2026)

Feedback del usuario sobre H1 en su HA real (~15 áreas, ~250 entidades): los botones son rectángulos oscuros planos con iconos finos y «Off», mucho espacio muerto; pide más personalización y organización, mejor onboarding, descubrir HA en la red y presentar HomeKit/Google Home/Alexa. Spec de Fable (advisor) + investigación técnica. Principios de Apple aplicados: respuesta instantánea al pulsar, arrastre 1:1, resortes críticamente amortiguados (damping 1.0, response 0.3–0.4), nada de confirmaciones salvo lo destructivo, sencillez ≠ minimalismo, el camino común primero.

## 1. Baldosas (P0)

- **Material:** una baldosa es una *placa de interruptor*: `desvanCard(radius: 12, fill: woodRaised, grain: 0.6)` con el bisel, y un disco de baquelita de 32 pt (negro, aro `hairlineStrong`) arriba a la izquierda con el glifo. Encendida: la luz real de la bombilla como *luz* — degradado radial `plusLighter` desde el disco (receta de `DesvanBulbGlow` con `tint`), bisel teñido, sombra exterior `tint.opacity(0.45·glow)`. Apagada: cristal oscuro sobre madera; el estado se lee en la lámpara, no en una palabra.
- **Glifos 20 pt `.semibold` (24 pt en anchas):** luz = `DesvanBulbGlyph(size: 20, lit: brillo)` con nuevo `tint: Color` para RGB. Persiana = nuevo `DesvanBlindGlyph(position:)`: marco con lamas que cubren `1 − position` (el glifo *es* la posición). Enchufe/interruptor/ventilador: símbolos SF rellenos, latón (`bulb`) encendidos, `paperSecondary` apagados.
- **Segunda línea:** fuera «Off». Por defecto el nombre de la estancia (11 pt, `paperTertiary`) salvo que haya un *valor* que decir: «70 %», «Abierta 65 %», «Abriendo…», «No disponible», un problema. VoiceOver conserva el estado completo con `accessibilityValue`.
- **Estados:** apagada · encendida (brillo 0,35–1 según brillo) · atenuada (barra de relleno teñida) · color (tint = RGB) · pendiente (el glifo respira 0,6↔1; estático con Reducir movimiento; fuera el punto de 5 pt) · no disponible (40 %, bisel discontinuo, sin brillo).
- **Escenas:** etiquetas kraft de equipaje de 34 pt, la misma receta que las baldosas de Atajos (degradado `kraft` + ojal + tinta). Escenas y atajos de Apple Home parecen de la misma especie.
- **Sensores:** la línea se queda; cifra 13 bold, glifo 13 `.medium`, fila de 28 pt.
- **Tamaños y espacio muerto:** `small` (1 col) y `wide` (2 cols; una luz muestra la pista del regulador con pomo de latón, una persiana el glifo grande). El layout llena la altura fija: `cols = n ≤ 3 ? n : 4`, `rows = ceil(unidades/cols)`, `alto = clamp(disponible/rows, 64, 88)`; más de 2 filas hace scroll. 7 favoritos → 4×2 a ≈ 84 pt. 2 favoritos → dos anchas.
- **Los chips de estancia exploran la estancia:** elegir una estancia muestra *todas* sus luces/persianas/interruptores/escenas (no técnicas), favoritos primero. `HomeStore.watchArea(id)` añade esos ids al conjunto vigilado mientras está elegida (máx. 40, diff, se quitan al salir). Chips = `[Favoritos] + páginas propias + estancias`.

## 2. Personalización (P0 el modelo, P1 páginas propias)

```swift
struct HomeTile: Codable, Identifiable { id: UUID; entity: String; name: String?; symbol: String?; size: HomeTileSize; isHidden: Bool }
struct HomePage: Codable, Identifiable { id: UUID; kind: favourites | custom(name); tiles: [HomeTile] }
struct HomeLayout: Codable { pages: [HomePage] } // pages[0] siempre Favoritos
```
- Las estancias no son páginas: siguen siendo chips de las áreas de HA. Páginas propias («Noche», «Despacho») en P1. Nombre, icono, tamaño, ocultar y orden por baldosa en P0.
- **Dónde se edita:** P0 = clic derecho en la baldosa del notch (`Renombrar…`, `Icono ▸` ~16 curados por tipo, `Tamaño ▸`, `Ocultar`, `Quitar de favoritos`/`Añadir a favoritos`, `Abrir en Home Assistant`) + rejilla en Ajustes que imita el notch (arrastrar para ordenar, clic → inspector); el catálogo por estancias queda debajo como «Añadir desde una estancia» con buscador. P1 = modo edición del notch.
- **Por defecto precioso sin esfuerzo:** al primer conectar con layout vacío, `applySuggestions()` corre solo (luces primero, una por estancia, máx. 8) y el notch muestra una vez «Altillo ha elegido 8 para empezar · Cambiar». Nunca el estado vacío con un servidor funcionando.

## 3. Interacciones (P0)

Clic alterna; arrastre horizontal = nivel; clic derecho = menú; pulsación larga 0,6 s **o** chevron al pasar → **ficha de detalle** que sustituye a la rejilla: regulador grande (pomo de latón como el dial del temporizador), temperatura de color, 8 muestras de color, posición vertical de persiana con Parar, `Esc`/Atrás. Teclado: `⌘1…9` alterna la baldosa n, flechas mueven el foco, Espacio alterna, `←/→` ±10 % en la baldosa con foco. P1: rueda sobre una baldosa ±5 % (ver antes `NotchCoordinator` ~780, que intercepta scroll preciso).

## 4. Conexión y onboarding (P0)

- **Descubrimiento:** al abrir la conexión, `NWBrowser(_home-assistant._tcp)` 2 s en paralelo con `GET http://homeassistant.local:8123/manifest.json`. TXT: `uuid` (id estable de la instancia; úsalo para deduplicar), `location_name`, `version`, `internal_url`, `external_url`, `base_url`. Validar una URL escrita: `GET /api/onboarding` (sin token) y `/manifest.json`. Servidores encontrados como filas «Casa · homeassistant.local:8123 · Conectar»; si hay uno, se rellena.
- **Iniciar sesión con Home Assistant (OAuth, P0, sin web):** loopback + PKCE. `NWListener` en `127.0.0.1:<puerto efímero>`; `client_id = http://127.0.0.1:<puerto>/`, `redirect_uri = http://127.0.0.1:<puerto>/callback` (mismo origen → HA no descarga nada); abrir `<ha>/auth/authorize?...&code_challenge=…&code_challenge_method=S256&state=…` en el navegador; recibir `code`, `POST /auth/token` (grant authorization_code + code_verifier); con ese access token, por WebSocket `auth/long_lived_access_token` (`client_name: "Altillo"`, `lifespan: 3650`) y guardar ESE token en el Llavero como hoy (el cliente no cambia). Página de respuesta en el loopback: «Listo, vuelve a Altillo». Timeout 5 min, cancelable. El token pegado queda como alternativa («Usar un token»).
- **Onboarding:** `OnboardingHomePage` después de la de herramientas de IA: «¿Tu casa en el notch?» con Home Assistant (descubre y conecta con OAuth ahí mismo), Apple Home («Escenas mediante Atajos») y «Hue, Google Home, Alexa, Matter: a través de Home Assistant». Se puede saltar. No tocar `OnboardingAIToolsPage.swift` (otra sesión lo está editando).
- **Conexiones (honesto):** filas con estado, sin interruptores falsos. Home Assistant (Conectado/Configurar) · Apple Home — «Ejecuta escenas con Atajos; el Mac no puede leer el estado de Casa» + «Añadir un atajo como baldosa» (P1 funcional) · Philips Hue — «Hoy a través de Home Assistant; emparejado directo más adelante» · Google Home / Alexa / Matter / Tuya — «A través de Home Assistant» + enlace a la guía.

## 5. Datos y reparto

- `AltilloSettings`: `homeLayout: HomeLayout` (JSON), `homeDidAutoSuggest`; migrar `homeFavourites` → `pages[0]` una vez al cargar; `homeFavourites` queda como shim calculado para los tests.
- `HomeStore`: `layout`, `tiles(for page)`, `entities(inArea:)`, `setOverride`, `setSize`, `hide`, `move`, `watchArea` (diff, máx. 40), `applySuggestions()` automático.
- Paquetes: **C** modelo/store (primero) · **A** notch · **B** Ajustes · **D** descubrimiento/OAuth/onboarding. La otra sesión rediseña el armazón de Ajustes (`SettingsRootView`, `SettingsWindow`, `SettingsModulesPane`, otros paneles, `OnboardingAIToolsPage`): no se tocan; Home vive en sus ficheros con un único enganche `SettingsHomeGroup(settings:store:)`.
