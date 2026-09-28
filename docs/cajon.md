# Cajón / Drawer

Drawer guarda los iconos de la barra de menús que casi no usas y abre sus menús desde Altillo. El nombre sigue la idea doméstica de Shelf y Altillo: un cajón para las cosas que quieres a mano sin tenerlas a la vista. La interfaz está en inglés; en español lo llamamos **Cajón**. Cuando está activo, su estantería compacta aparece en la parte superior de Altillo, por encima de las secciones.

## Uso

1. Abre **Altillo → Drawer Settings…** (también en Ajustes → Drawer) y activa **Use Drawer**.
2. Concede **Accesibilidad**, el único permiso que necesita: Altillo lee los iconos de la barra y abre sus menús. Además del botón, puedes arrastrar el icono de Altillo a la lista de Accesibilidad de Ajustes del Sistema.
3. Arrastra iconos entre **Altillo** y **Menu Bar**, o usa su menú contextual. Se mueve la app entera: todos los iconos de una misma app van juntos. Los elementos de macOS (reloj, Wi‑Fi, Centro de Control…) llevan un candado y se quedan en la barra.
4. En macOS 27, con **Hide Drawer icons from the menu bar** activado, los iconos del Cajón salen de la barra al momento y viven en Altillo. Pulsa un icono de la estantería para abrir su menú junto a él.
5. **Show hidden icons** (en Ajustes o en el menú de Altillo) los devuelve a la barra hasta que pulses **Hide them again**.
6. **New menu bar icons**: los iconos de apps que Altillo no ha visto antes se quedan en la barra (por defecto) o van directos al Cajón.

Salir de Altillo, desactivar el Cajón o retirar Accesibilidad devuelve todos los iconos a la barra.

## Cómo oculta (macOS 27)

MenuBarAgent, el proceso que dibuja la barra en macOS 27, tiene una lista de permitidos pensada para el modo examen (Assessment Mode): mientras una app mantiene la aserción `MBAssessmentModeAssertion` (framework privado `MenuBarClientCore`), la barra solo dibuja las apps y los elementos del sistema de la lista. Bartender 7 usa el mismo mecanismo. Las mediciones están en [spikes/macos27-menubar-assessment.md](spikes/macos27-menubar-assessment.md).

- **Lista:** todas las apps en ejecución menos las del Cajón, más Altillo y los elementos alojados por macOS; los elementos del sistema van por número (0…31, todos permitidos). La pertenencia es por app porque la lista es por bundle id.
- **Sin parpadeos:** reactivar la aserción con una lista más larga muestra lo nuevo sin tocar el resto, pero una lista más corta se ignora. Por eso la lista solo crece mientras vive la aserción: una app que se abre se añade al instante, una que se cierra se queda en la lista. Solo un gesto explícito (meter una app en el Cajón, volver a ocultar tras «Show hidden icons») la reduce, y entonces macOS muestra todo cerca de un segundo antes de volver a ocultar.
- **Seguridad:** la API privada se resuelve en tiempo de ejecución (`dlopen`, `NSClassFromString`, selectores comprobados). Si falta algo, ocultar no está disponible y no se oculta nada. La aserción pertenece al proceso de Altillo: al salir o fallar, macOS muestra todos los iconos. Sin Accesibilidad no se oculta, porque los iconos no se podrían abrir desde Altillo.
- **Sin divisor ni arrastres:** no hay elementos propios en la barra, ni flecha, ni huecos, ni arrastres ⌘ sintéticos, ni ficheros de preferencias de macOS modificados.
- **Límites:** una app firmada ad hoc o que no se ejecuta desde `/Applications` (p. ej. una build de Debug) no se puede permitir por bundle: sus iconos se ocultan mientras la aserción esté activa. Las píldoras tipo Live Activity de MenuBarAgent tampoco están cubiertas y se ocultan igual.

En **macOS 26** el Cajón lista los iconos y abre sus menús, pero no los oculta.

## Decisiones de implementación

- **`MenuBarDrawerStore`:** pertenencia (`DrawerMembership`, bundle ids en `drawer.bundleIDs`), orden de la estantería por icono (`drawer.order`), catálogo AX y apertura de menús. Todo cambio que afecta a la barra pasa por `applyConcealment()`, serializado y calculado en el momento de ejecutarse.
- **`MenuBarConcealing`:** protocolo con la implementación real (`MenuBarConcealer`) y una vacía para macOS 26. Los tests usan una falsa y nunca activan la aserción real.
- **Migración:** el Cajón anterior guardaba iconos (`drawer.chosenIDs`); sus apps pasan a ser la pertenencia nueva. Se borran las posiciones y nombres de autosave del divisor, la flecha y los espaciadores antiguos.
- **Catálogo:** un actor recorre exclusivamente `AXExtrasMenuBar`, con timeouts. macOS sigue exponiendo los iconos ocultos con su acción `AXPress`. En reposo no hay sondeo: los eventos marcan el catálogo como obsoleto y se vuelve a leer al mostrarse la estantería o Ajustes (máximo cada 30 s, agrupando ráfagas hasta 2 s).
- **Iconos:** símbolos SF para los elementos de macOS y el icono de la app para el resto. Los iconos ocultos no se dibujan, así que no se pueden capturar; por eso no hace falta Grabación de Pantalla.
- **Menús estándar:** se lee el árbol AXMenu y un NSMenu de Altillo lo presenta junto al icono; cada comando ejecuta la acción original.
- **Paneles personalizados:** se activa el elemento por AX sin mostrarlo y se recoloca la ventana nueva del propietario junto a la estantería, verificando la posición. Si macOS no lo permite, se explica.
- **Apps nuevas:** `drawer.knownBundleIDs` recuerda las apps que ya han tenido icono; el primer catálogo es el punto de partida, no «nuevo». Con **Go to the Drawer**, una app desconocida no entra en la lista y sus iconos aparecen en el Cajón.

## Verificación manual

Con la build firmada instalada en `/Applications` y Accesibilidad concedida:

- `screencapture -x -R0,0,<ancho>,40 a.png`; activar el Cajón con dos apps; capturar: sus iconos desaparecen, sin hueco.
- Abrir cada icono desde la estantería (un menú estándar y un panel personalizado).
- Abrir una app nueva: su icono aparece en la barra en menos de un segundo (o en el Cajón con **Go to the Drawer**).
- **Show hidden icons** y **Hide them again**; mover una app de vuelta a **Menu Bar**.
- `kill -9` de Altillo: la captura vuelve a coincidir con `a.png`. Revocar Accesibilidad: los iconos vuelven.
- MacBook con notch y monitor externo; barra autooculta; pantalla completa; VoiceOver.

## Referencias

- Apple: [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout).
- Bartender 7 (7.0.4): enfoque de referencia (aserción de Assessment Mode, permisos, onboarding), sin incorporar código.

La investigación previa está en [barra-de-menu.md](barra-de-menu.md).
