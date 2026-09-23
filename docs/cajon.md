# Cajón / Drawer

Drawer guarda un grupo de iconos de la barra de menús y permite abrir sus menús desde Altillo. El nombre sigue la idea doméstica de Shelf y Altillo: un cajón para las cosas que quieres tener a mano sin dejarlas a la vista. La interfaz está en inglés; en español lo llamamos **Cajón**. Cuando está activo, su estantería compacta aparece siempre en la parte superior de Altillo, por encima de los modos y las opciones, independientemente de la sección que esté abierta.

## Uso

1. Abre **Altillo → Drawer Settings…** (también está en Ajustes → Drawer).
2. Activa **Use Drawer** y concede los permisos solicitados: Accesibilidad para mover y pulsar los elementos de la barra, y Grabación de Pantalla para ver sus imágenes exactas. Las dos zonas se muestran cuando ambos están concedidos. Altillo vuelve a comprobar el acceso al regresar de Ajustes del Sistema.
3. Activa **Use Drawer**. Aparecen dos zonas: **Altillo** y **Menu Bar**, cada una con su propio scroll. Los símbolos reales se recortan a su contenido visible y comparten una caja óptica de 18 puntos, conservando los píxeles Retina de la captura. Los indicadores con texto, como el reloj, ocupan varias celdas para seguir siendo legibles. Todos muestran su nombre al dejar el puntero encima. Arrastra cada icono a la zona donde quieres que permanezca y reordénalos dentro de **Altillo**; el orden se conserva entre lanzamientos. El menú contextual ofrece las mismas acciones.
4. Al completar el movimiento, el grupo elegido se oculta automáticamente. Pulsa un icono del cajón para abrir sus opciones junto a él, sin devolver el icono original a la barra. Los menús estándar conservan las acciones de la app; los paneles personalizados se colocan junto al icono cuando macOS permite mover su ventana.

**Show icons** vuelve a mostrar el grupo. El movimiento entre **Altillo** y **Menu Bar** en ajustes se aplica mediante el arrastre nativo de macOS con ⌘, usando eventos públicos de `CGEvent`, y se comprueba volviendo a leer la posición con Accesibilidad. Si macOS no permite mover un elemento, se conserva en su zona actual y se explica el motivo. Desactivar la opción, cerrar Altillo o retirar Accesibilidad muestra los iconos.

## Decisiones de implementación

- **macOS 26:** dos `NSStatusItem` con nombres de autosave estables. Uno es el control siempre accesible; el otro aumenta su longitud para desplazar los iconos situados a su izquierda. La configuración usa un arrastre ⌘ automatizado con APIs públicas de `CGEvent`, seguido de una lectura AX que confirma la colocación. No se usan APIs privadas ni se deja un cambio confirmado solo porque el gesto haya terminado.
- **Otras versiones:** la ocultación está deshabilitada. Se mantiene el catálogo por Accesibilidad; su disponibilidad depende de lo que expongan las apps. No se incorporan frameworks privados ni se promete compatibilidad del separador con versiones no verificadas.
- **Catálogo:** un actor Swift recorre exclusivamente `AXExtrasMenuBar`. Los mensajes AX tienen timeout y el trabajo se cancela entre apps/elementos. No se recorre el árbol de documentos ni los menús principales de las apps.
- **Imágenes:** ScreenCaptureKit captura las ventanas individuales de los elementos de la barra, identificadas por propietario y posición. Se conservan en memoria para mostrarlas también cuando están ocultas. Sin Grabación de Pantalla se muestra el paso de permiso y se ocultan las cuadrículas; nunca se sustituye el icono de barra por el logo de la aplicación. No se solicita Monitorización de Entrada.
- **Menús estándar:** se lee el árbol AXMenu sin abrir el menú original. Un NSMenu de Altillo presenta títulos, estados, atajos y submenús debajo del botón; cada comando conserva su destino AX y ejecuta la acción de la app. No se revela el icono ni se mueve el puntero. Si una vista personalizada no expone todos sus controles, se indica en el menú.
- **Paneles personalizados:** se activa el elemento mediante AX sin revelar la barra. Se consideran únicamente ventanas nuevas del propietario y se recoloca el panel mediante AXPosition, verificando la posición efectiva en WindowServer. No se mueve una ventana de documento que ya estaba abierta. Cuando el sistema no permite colocar el panel, se informa del límite en vez de revelar el icono como alternativa.
- **Cierre:** cancelar el menú local no cambia la barra. Los paneles propios de otras apps mantienen su interacción nativa. El seguimiento de la sesión evita que el hover de Altillo interfiera mientras el panel está abierto.
- **Recuperación:** los cambios de población de apps actualizan el catálogo sin revelar el grupo. Si cambia la pantalla, se pierde Accesibilidad o falla la lectura de iconos, el sistema vuelve a mostrarlos. Al iniciar se recupera la ocultación del grupo elegido cuando los permisos están disponibles.
- **Reposo sin sondeo:** con el Cajón activo y el notch cerrado, Altillo no ejecuta ningún temporizador. El catálogo se marca como obsoleto con eventos: apps que se abren o cierran, reactivación, cambios de pantalla y de Space, y notificaciones AX (`AXObserver`) de creación, destrucción, movimiento o cambio de tamaño de los elementos de la barra. Abrir el notch o el panel de ajustes es el punto de refresco perezoso: se vuelve a leer el catálogo solo si está obsoleto o tiene más de 30 s, con una espera corta que agrupa ráfagas de eventos (máximo 2 s). Los cambios de población de apps y de pantalla sí refrescan aunque no haya nada visible, porque afectan al grupo oculto.
- **Caché de imágenes:** cada glifo se guarda con su clave (bundle id de la app, identidad del elemento, tamaño y apariencia de la barra con su escala). La posición no forma parte de la clave, porque ocultar el grupo mueve todos los iconos sin cambiar sus píxeles. Solo se vuelve a capturar un glifo nuevo o con la clave cambiada. Al mostrarse el Cajón también se renuevan los que tienen más de 60 s, para que los indicadores con texto, como el reloj o la batería, no se queden atrasados. El botón de refrescar de Ajustes recaptura todo. Si nada cambió, no se enumeran ventanas ni se captura nada.
- **Permisos:** retirar o conceder Accesibilidad llega por la notificación distribuida `com.apple.accessibility.api` y se comprueba al volver a Altillo. Grabación de Pantalla no tiene notificación. Tras pulsar un botón de permiso hay una ventana de comprobación de 2 minutos, cada 2 s, que termina en cuanto los dos permisos están concedidos. Las propiedades de `NSRunningApplication` se resuelven una sola vez por proceso.
- **UI estrecha:** cuando las pestañas no caben junto a la cámara, un menú con el nombre de la sección mantiene todas las secciones accesibles.

La vista de ajustes evita switches por icono: presenta todo el catálogo en dos zonas y hace explícita la posición de cada elemento. La selección es reversible, se guarda con identificadores estables y solo se da por aplicada después de comprobar el resultado en la barra.

## Verificación manual

La verificación automatizada cubre identidad de elementos, geometría, versiones y preferencias. También se ha probado el catálogo AX y el flujo de ocultar/mostrar con una app de prueba, incluida la recuperación ante IDs desconocidos y falta de espacio. La aceptación física con varias apps, pantallas y permisos sigue la matriz siguiente.

Las regresiones incluyen concesión con el resultado antiguo de Core Graphics, denegación, concesión posterior y ausencia de solicitudes espontáneas. La aceptación con otras apps, TCC y distintas pantallas sigue esta matriz usando una build con permiso real de Accesibilidad:

- Sin permiso: se explica el acceso y no se oculta nada.
- Con permiso: arrastrar dos iconos a Altillo, comprobar ocultación y abrir cada menú; probar una app sin acción de apertura.
- Mostrar, mover un icono a la derecha, volver a ocultar: solo desaparece el grupo elegido.
- Reiniciar Altillo y las apps elegidas; comprobar posiciones y ausencia de iconos inaccesibles.
- Revocar Accesibilidad, desconectar una pantalla y salir de Altillo: recuperar los iconos.
- Probar barra autooculta, pantalla completa, MacBook con notch y monitor externo.
- Teclado y VoiceOver; destinos vacíos y listas largas; 440 pt de ancho con las seis secciones activas.

La forma en que cada app posiciona su popover sigue siendo responsabilidad de esa app. El botón para mostrar el grupo permanece disponible como alternativa.

**Barra completamente llena o elemento inamovible:** Altillo comprueba la posición real antes de pulsar un icono y mantiene visible el grupo cuando no puede verificar una operación. Algunos elementos del sistema no aceptan el arrastre. Grabación de Pantalla se utiliza para obtener sus imágenes; Accesibilidad, para la interacción.

## Referencias técnicas

- Apple: [NSStatusItem.length](https://developer.apple.com/documentation/appkit/nsstatusitem/length), [autosaveName](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property), [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout).
- [Hidden Bar, estrategia de longitud](https://github.com/dwarvesf/hidden/blob/47937b9d8aede0325ca87a7880af13433e7c5cf8/hidden/Features/StatusBar/Engine/LegacyLengthEngine.swift): referencia de arquitectura, sin incorporar código externo.

La investigación previa está en [barra-de-menu.md](barra-de-menu.md). Este documento describe el alcance implementado y sus límites.
