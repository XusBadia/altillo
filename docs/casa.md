# Casa / Home: domótica en el notch (propuesta)

> Estado: propuesta del 15-10-2026, sin implementar. Origen: [House Control](https://github.com/0xProbabillity/house-control) (MIT, 5,6k likes y 257k vistas en X el 13-10-2026), que pone un modelo 3D del piso en el notch y controla Smart Life, Home Assistant, Hue y Apple Home. Lo usamos solo como referencia: todo se implementa de forma nativa y con atribución en ThirdPartyNotices si portamos lógica.

La interfaz está en inglés (**Home**); en español la llamamos **Casa**. Es una sección más del notch, opt-in como las utilidades.

## Por qué

- **Encaja:** el notch es el sitio perfecto para lo que haces diez veces al día sin querer abrir una app: apagar la luz del despacho, poner «Peli», ver si la puerta del garaje quedó abierta.
- **Marketing:** el tuit demuestra que hay demanda. La comunidad de Home Assistant es enorme (r/homeassistant, foro oficial, «Made for HA») y comparte todo lo que se integra bien. Llegar rápido con algo **más pulido y más útil** que un modelo 3D es la jugada.
- **Diferencia frente a House Control:** ellos son un modelo 3D bonito con lámparas y aires. Nosotros no dibujamos el piso: hacemos lo que solo un notch hace bien, **avisos en vivo** (timbre con foto, lavadora terminada, puerta abierta), una oreja que te dice el estado de la casa sin abrir nada, atajos de teclado por escena y **Pregunta** («apaga todo menos el salón»). Además, Altillo está firmado y notarizado (ellos son ad hoc y piden `xattr`).

## Plataformas

| Plataforma | Mac | iPhone | Cómo | Fase |
|---|---|---|---|---|
| **Home Assistant** | ✓ completo | Fase 5 (la companion aún no tiene sync) | API WebSocket local, token (H1) y OAuth (H2) | H1 |
| **Philips Hue** | ✓ completo | Fase 5 | API CLIP v2 del Bridge + event stream, emparejar con el botón | H3 |
| **Apple Home** | Escenas y acciones vía **Atajos** | ✓ completo (HomeKit) | Mac: `shortcuts run`; iPhone: `HMHomeManager` | H3 (Mac), fase 5 (iPhone) |
| **Matter, Tuya, Google, Alexa, SmartThings** | vía Home Assistant | vía HA | — | — |

**Apple Home en el Mac, sin trampas.** HomeKit solo existe para apps de iOS/iPadOS y apps Mac Catalyst **del Mac App Store**; con Developer ID no se puede aprovisionar. House Control solo *lista* los dispositivos en el Mac (los recibe del iPhone) y los deja simulados. Nosotros:

1. **Atajos (H3):** Atajos de macOS sí controla Casa («Controlar Casa», «Obtener estado de Casa»). Altillo ya tiene el lanzador de Atajos (`ShortcutsCLI`). La sección Home permite fijar atajos como baldosas/escenas, y ofrecemos atajos plantilla firmados («Altillo · Peli», «Altillo · Apagar todo») que el usuario edita. En el Mac, Apple Home es **solo escritura** (escenas y acciones). Leer estado con un atajo que devuelva texto (`--output-path`) es un experimento, no una promesa: no está comprobado que las acciones de Casa corran sin interfaz, rápido y sin pedir nada bajo `shortcuts run`, y `ShortcutsCLI.runArguments` todavía no pasa `--output-path`. Honesto en la UI: «Apple Home en el Mac funciona con Atajos».
2. **iPhone (fase 5):** la companion de iPhone usa HomeKit de verdad, con widgets y controles de Centro de Control. No hacemos relevo Mac→iPhone para ejecutar órdenes: iOS no deja usar HomeKit en segundo plano, así que sería poco fiable.
3. **Puente recomendado:** quien tenga HA puede meter sus accesorios de Apple Home/Matter en HA (HomeKit Controller o Matter multi-admin) y tenerlo todo en el Mac.

Descartados: un helper Catalyst del Mac App Store (sería otro producto con su revisión y su IPC para algo que HA ya cubre) y `Matter.framework` (Altillo tendría que ser su propio controlador Matter). Tuya/Smart Life directo también queda fuera: depende de credenciales de la nube de Tuya que no son nuestras, y en un repo abierto cualquier credencial incrustada sería pública. La ruta es la integración oficial de Tuya en HA.

## Arquitectura

Nuevo target **`AltilloHome`** en AltilloKit (Mac e iOS), sin UI:

- **Modelo común** `HomeEntity`: `id` con identidad de servidor desde el primer día (`ha:<uuid del servidor>:light.salon`, `hue:<bridge id>:<rid>`, `shortcut:<name>`), para que dos instancias de HA o un cambio de URL no rompan los favoritos, `name`, `area`, `kind` (`light`, `switch`, `climate`, `cover`, `lock`, `fan`, `mediaPlayer`, `sensor`, `binarySensor`, `event` (los timbres modernos son `event.*`), `scene`, `script`, `camera`, `action`), `capabilities` (dim, temperatura de color, color, rango de consigna, modos, posición), `state` y `lastChanged`. Una sola gramática para la UI y para Pregunta.
- **Protocolo** `HomeProvider`: `connect`, `entities()`, `states: AsyncStream<HomeChange>`, `perform(HomeCommand)`, `disconnect`. Proveedores: `HomeAssistantProvider`, `HueProvider`, `ShortcutsHomeProvider` (Mac), `HomeKitProvider` (iOS).
- **`HomeStore`** (`@Observable`, en el Mac junto a `NotchModel`): fusiona proveedores, guarda favoritos/orden y aplica **actualización optimista**: la baldosa cambia al instante y queda «pendiente» hasta el siguiente diff de estado. Solo vuelve atrás (y lo dice) si `call_service` devuelve error; un plazo fijo fallaría con persianas y transiciones largas.
- **Home Assistant por WebSocket** (`/api/websocket`): `auth` → registros una sola vez para la lista completa → `subscribe_entities` **solo con `entity_ids` de favoritos y avisos** (diffs comprimidos; sin filtro mandaría todas las entidades, y eso es lo que mantiene bajos memoria y CPU) → `config/area_registry/list`, `config/device_registry/list`, `config/entity_registry/list` para áreas y nombres → `call_service` para actuar. Sin sondeo: cumple «por eventos y sin sondeo» (§5.8) y `script/idle-cpu.sh`; el único latido es un ping de WebSocket cada 60 s mientras hay conexión y el Mac está despierto. Reconexión con backoff, pausa en reposo/sleep, reanudación al despertar. URL interna y externa (Nabu Casa) con preferencia por la local.
- **Credenciales en el Llavero** (nuevo `KeychainStore` con `SecItemAdd`; hoy no hay ninguno que escriba). Nunca en UserDefaults ni en logs.
- **Descubrimiento** por Bonjour (`_home-assistant._tcp`, `_hue._tcp`) con `NWBrowser`. Requiere `NSLocalNetworkUsageDescription` y `NSBonjourServices` en `project.yml`; ATS: `NSAllowsLocalNetworking` para `http://homeassistant.local:8123`.
- **Certificados autofirmados:** el Bridge de Hue y los HA servidos por `https`/`wss` con certificado propio se confían la primera vez y se fija la huella (TOFU); `NSAllowsLocalNetworking` no cubre este caso.
- **Cámaras:** instantánea por `/api/camera_proxy/<entity>` con el token en `Authorization: Bearer`, solo al mostrar un aviso o la ficha.
- **Laboratorio:** `script/home-lab.sh` levanta HA en Docker con la integración `demo` (luces, clima, persianas, cerraduras, cámara) para desarrollo, tests de integración y para grabar el vídeo sin tocar una casa real.

## UI en el notch (Desván)

**Sección abierta (Home):**

- Cabecera: nombre de la casa y **chips de estancias** (áreas de HA) para filtrar; «Favoritos» por defecto.
- **Baldosas** en rejilla, unas 8 visibles y el resto con scroll, con el lenguaje Desván: interruptores de latón/baquelita, la baldosa de una luz encendida brilla cálida con su color real. Interacciones:
  - clic: alternar;
  - arrastrar en horizontal sobre la baldosa: atenuar (luz) o posición (persiana), con háptico en los topes; el clima usa botones − / + para la consigna;
  - clic en el chevron o clic largo: ficha de detalle que sustituye a la rejilla dentro del notch (brillo, temperatura de blanco, modos de clima, ventilador; el color completo llega en H3).
- **Apertura:** al abrir la sección, las baldosas se encienden una a una con el color real de cada bombilla. Es nuestra respuesta al «la casa cae del notch» del modelo 3D, y lo que abre el vídeo.
- **Fila de escenas** arriba, como botones grandes. Escenas, scripts de HA y atajos de Apple Home conviven aquí.
- **Sensores** en línea compacta debajo (temperatura, humedad, consumo).
- **Peligrosos** (cerraduras, alarma, garaje): nunca con un clic suelto; piden mantener pulsado 0,6 s con un anillo que se llena, como «permitir» en agentes.
- Estados: desconectado (con «Reconectar»), cargando (esqueletos), vacío («Elige tus favoritos»), entidad no disponible (atenuada).

**Notch cerrado:**

- **Oreja contextual** (`NotchActivity.home`): solo cuando hay algo que contar, por ejemplo «Garaje abierto · 12 min», «Lavadora 0:08», «3 luces encendidas» al salir de casa (la presencia viene de `person`/`zone.home` de HA, nunca del Mac). Prioridad por debajo de agente esperando y evento inminente.
- **Avisos (peeks)** por eventos de HA, elegidos por el usuario: timbre (con miniatura de la cámara), puerta/ventana abierta más de N min, electrodoméstico terminado, alarma. Clic en el aviso abre la sección; el timbre muestra la cámara en grande.

**Atajos y Pregunta:**

- Atajo global configurable por escena (⌃⌥1…) y ⌘1…9 dentro de la sección.
- Pregunta: tool de lectura `HomeStatusTool` en la ruta *context* («¿qué luces hay encendidas?») y una ruta de acción `.home` con `HomeControlTool` y el mismo guard de una sola vez de `.shortcut`. Las acciones peligrosas se confirman en la UI, nunca solo por el modelo. Al modelo solo se le pasan los nombres de los favoritos, no todas las entidades.

## Configuración (Ajustes → Sections → Home)

1. **Conectar Home Assistant:** Altillo busca servidores en la red y los lista con «Conectar». H1: dirección + **token de larga duración** pegado (es lo que los usuarios de HA hacen a diario), con enlace directo a la página de tokens de su servidor. H2: «Conectar» abre el **login de HA (OAuth)** con `ASWebAuthenticationSession(callbackURLScheme: "altillo")`: `client_id` = `https://altillo.app/` con `<link rel="redirect_uri" href="altillo://ha-auth">` en la web y `CFBundleURLTypes` nuevo en `project.yml`; el refresh token va al Llavero. El servidor HA tiene que poder descargar `https://altillo.app/` para validar el redirect, así que las instalaciones aisladas siguen con el token.
2. **Elegir favoritos:** lista por estancia con buscador y casillas; Altillo propone una selección inicial (luces, clima y escenas de las áreas más usadas, nada de entidades técnicas ni `diagnostic`). Arrastrar para ordenar; por baldosa se puede cambiar nombre e icono. También desde el **modo edición** del notch, como el resto de secciones.
3. **Avisos:** qué entidades asoman (timbres `event.*`/`binary_sensor` y puertas/ventanas sugeridos), umbral «abierto más de N min».
4. **Hue / Apple Home (Atajos)** como conexiones adicionales en la misma pantalla.
5. **Desconectar** revoca el token (`/auth/revoke`) y borra el Llavero.

Privacidad: todo local entre el Mac y tu casa, nada pasa por servidores de Altillo. La sección Home entra en `website/privacy` y `website/es/privacidad` **antes** de publicar el vídeo.

## Fases

| Fase | Contenido | Estimación |
|---|---|---|
| **H1. Home Assistant beta (para el momento)** | `AltilloHome`, proveedor HA (WebSocket, URL manual + token, Llavero, TOFU), sección Home con baldosas (luces, interruptores, escenas, scripts, persianas), arrastrar para atenuar, favoritos en Ajustes, oreja contextual y aviso de timbre con cámara, política de privacidad, laboratorio Docker y tests con un servidor HA falso | 1 semana |
| **H2. Vida** | OAuth y Bonjour, clima y ventiladores, resto de avisos (puertas, electrodomésticos), peligrosos con mantener pulsado, atajos por escena, Pregunta (estado + acciones) | 1 semana |
| **H3. Más plataformas** | Hue directo, Apple Home vía Atajos con plantillas, ficha de detalle de color completa, media players | 1 semana |
| **H4 (opcional)** | Vista de plano 2.5D por estancias si el vídeo lo pide; Apple Home completo en la companion de iPhone (fase 5) | — |

Lanzamiento: H1 sale como **beta** y es lo que se enseña; el tuit es del 13-10, así que cada semana cuenta. Vídeo de 20-30 s rápido y enseñando el producto: hover → las baldosas se encienden con el color real de cada bombilla → luces del salón se atenúan con un arrastre → suena el timbre y asoma la cámara → «apaga todo» con un atajo de escena (Pregunta entra en el vídeo de H2). Post en r/homeassistant y foro de HA con el enlace a GitHub; respuesta al hilo viral solo si el vídeo está listo.

## Riesgos

- **Alcance:** HA tiene decenas de dominios. Solo soportamos los de la tabla; el resto se puede fijar como baldosa genérica de solo lectura.
- **Red:** fuera de casa la URL local falla. Usamos la externa si existe; si no, la sección dice «Fuera de casa» en vez de errores.
- **Permiso de red local** de macOS: desde macOS 15 salta en la primera conexión a una IP de la LAN, no solo al buscar por Bonjour. Se explica antes de conectar y «denegado» es un estado con nombre y con instrucciones para arreglarlo.
- **Apple Home en el Mac** queda limitado a Atajos; se dice claro en la UI y en la web para no prometer lo que Apple no permite.
