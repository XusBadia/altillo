# Cajón / Drawer

Drawer guarda un grupo de iconos de la barra de menús y permite abrir sus menús desde Altillo. El nombre sigue la idea doméstica de Shelf y Altillo: un cajón para las cosas que quieres tener a mano sin dejarlas a la vista. La interfaz está en inglés; en español lo llamamos **Cajón**.

## Uso

1. Abre **Altillo → Drawer Settings…** (también está en Ajustes → Drawer).
2. Pulsa **Allow access** y concede Accesibilidad a Altillo en los ajustes de macOS. El permiso permite leer y pulsar los menús de otras apps.
3. Activa la opción de guardar iconos. Aparecen un separador `│` y un botón para mostrar u ocultar el grupo.
4. Mantén **⌘** y arrastra a la **izquierda del separador** los iconos que quieres guardar. Los de la derecha permanecen visibles. Mantén el botón de Drawer a la derecha.
5. Pulsa **Hide icons**. Abre la sección **Drawer** en Altillo para buscar un icono y abrir su menú. Al abrirlo, el grupo vuelve a la barra para que macOS pueda colocar el menú en pantalla. El clic secundario ofrece la acción de menú alternativo cuando la app la admite.

**Show icons** vuelve a mostrar el grupo. Puedes sacar un icono del cajón con ⌘-arrastre hacia la derecha del separador. macOS conserva las posiciones. Desactivar la opción, cerrar Altillo o retirar Accesibilidad muestra los iconos.

## Decisiones de implementación

- **macOS 26:** dos `NSStatusItem` con nombres de autosave estables. Uno es el control siempre accesible; el otro aumenta su longitud para desplazar los iconos situados a su izquierda. Configurar el grupo usa el gesto de macOS, sin secuestrar el cursor ni simular eventos.
- **Otras versiones:** la ocultación está deshabilitada. Se mantiene el catálogo por Accesibilidad; su disponibilidad depende de lo que expongan las apps. No se incorporan frameworks privados ni se promete compatibilidad del separador con versiones no verificadas.
- **Catálogo:** un actor Swift recorre exclusivamente `AXExtrasMenuBar`. Los mensajes AX tienen timeout y el trabajo se cancela entre apps/elementos. No se recorre el árbol de documentos ni los menús principales de las apps.
- **Imágenes:** iconos de aplicación y etiquetas accesibles. No son capturas exactas del glifo de la barra. No se solicita Grabación de Pantalla ni Monitorización de Entrada.
- **Apertura:** Altillo muestra el grupo, recoge su panel y actualiza las referencias antes de ejecutar `AXPress` o `AXShowMenu`. Pulsar un icono aún desplazado puede abrir su menú fuera de pantalla: se comprobó con una app de prueba. El grupo permanece visible durante el uso del menú; **Hide icons** lo recoge de nuevo. Si la app no admite la acción o el elemento ha desaparecido, se comunica el fallo. Un timeout de `AXPress` es un resultado indeterminado: algunos menús ya se han abierto y mantienen la llamada bloqueada hasta cerrarse; no se presenta ese timeout como un fracaso confirmado.
- **Recuperación:** cambios de pantalla y de población de apps muestran el grupo para no dejar nuevos iconos inaccesibles. Si se pierde Accesibilidad o falla la lectura de iconos del grupo, el sistema vuelve a mostrarlos. No se oculta nada por defecto.
- **UI estrecha:** cuando las pestañas no caben junto a la cámara, un menú con el nombre de la sección mantiene todas las secciones accesibles.

No hay switches por icono: ocultar iconos arbitrarios dispersos requeriría mover físicamente los elementos de otras apps con arrastres sintéticos. La selección por posición es explícita, reversible y utiliza la interacción nativa.

## Verificación manual

Verificado en macOS 26.6: 114 tests de la app y 23 del paquete; catálogo AX real; ocultar/mostrar dos iconos de una app de prueba sin seleccionar iconos ajenos; recuperación ante IDs desconocidos y falta de espacio; apertura de un menú de prueba completamente visible, sin error falso tras cerrarlo. También se revisó el render de ajustes y del notch a 440 y 560 pt.

Las pruebas automáticas cubren identidad, geometría, versiones y preferencias. La aceptación con otras apps, TCC y distintas pantallas sigue esta matriz usando una build con permiso real de Accesibilidad:

- Sin permiso: se explica el acceso y no se oculta nada.
- Con permiso: elegir dos iconos, ocultar, buscar y abrir cada menú; probar clic secundario y una app sin esa acción.
- Mostrar, mover un icono a la derecha, volver a ocultar: solo desaparece el grupo elegido.
- Reiniciar Altillo y las apps elegidas; comprobar posiciones y ausencia de iconos inaccesibles.
- Revocar Accesibilidad, desconectar una pantalla y salir de Altillo: recuperar los iconos.
- Probar barra autooculta, pantalla completa, MacBook con notch y monitor externo.
- Teclado y VoiceOver; búsqueda sin resultados; 440 pt de ancho con las siete secciones activas.

La forma en que cada app posiciona su popover sigue siendo responsabilidad de esa app. El botón para mostrar el grupo permanece disponible como alternativa.

**Barra completamente llena:** si un icono continúa fuera de pantalla incluso después de mostrar el grupo, Altillo no intenta abrir un menú invisible. Pide cerrar una app de barra que no se esté usando para liberar espacio. Esta primera versión no sustituye la reubicación temporal por icono de un gestor completo; esa operación requeriría arrastres simulados, descartados aquí.

## Referencias técnicas

- Apple: [NSStatusItem.length](https://developer.apple.com/documentation/appkit/nsstatusitem/length), [autosaveName](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property), [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout).
- [Hidden Bar, estrategia de longitud](https://github.com/dwarvesf/hidden/blob/47937b9d8aede0325ca87a7880af13433e7c5cf8/hidden/Features/StatusBar/Engine/LegacyLengthEngine.swift): referencia de arquitectura, sin incorporar código externo.

La investigación previa está en [barra-de-menu.md](barra-de-menu.md). Este documento describe el alcance implementado y sus límites.
