# Roadmap de Altillo

Última actualización: 1 de noviembre de 2026.

Roadmap de producto para retomar y ampliar entre sesiones, sin fechas fijas.
Reúne **61 iniciativas en nueve áreas**: prioridades cercanas, ampliaciones y
exploraciones. Una idea aquí no es un compromiso de implementarla. Buscamos
entregas pequeñas y completas, alternando features, mejoras e idiomas.

La [investigación de competidores](competitor-profiles/_summary.md) explica
las fuentes y oportunidades. Las propuestas combinan esa investigación con
una revisión del código de Altillo; su valor para nuestros usuarios es una
hipótesis que iremos validando.

## Cómo retomarlo en cada sesión

1. Leer este roadmap, comprobar código y últimas releases y reconciliar lo
   que ya se haya implementado.
2. Si Xus pregunta por el roadmap, resumir estado y recomendar el siguiente
   paso. Esa pregunta por sí sola no autoriza implementar una feature.
3. Cuando Xus elija una, concretar su primera entrega y pasarla a **En curso**.
   Mantener una sola feature principal en curso.
4. Al cerrarla, actualizar su fila y enlazar PR, evidencia o release. Marcar
   **Hecho** por una implementación validada, nunca por escribir un plan.
5. Añadir nuevas ideas con un ID estable, sin renumerar las anteriores. Ajustar
   prioridades con demanda, feedback y dependencias.
6. Conservar aquí los estados; enlazar los planes técnicos desde la fila sin
   crear otros roadmaps que dupliquen prioridades y estados.

Estados: **Pendiente**, **En investigación**, **En curso**, **Bloqueado: motivo**,
**Hecho** y **Descartado: motivo**. R01 está **Hecho**, publicado en 0.13.0;
R61 está **En curso**, con el [plan de cuentas directas](docs/plans/mail-native-accounts.md) revisado por Astra e implementación autorizada por Xus; OAuth real y distribución siguen pendientes. Las demás iniciativas siguen **Pendientes**. Anotar los cambios de estado y su evidencia en la fila correspondiente.

## Dirección de producto

La oportunidad es conectar lo que hoy queda separado: el archivo que vas a
enviar, el agente que espera respuesta, la reunión que empieza y el código de
acceso que acaba de llegar. Completar esas acciones con pocos pasos y conservar
una interfaz tranquila.

- **Archivos listos para entregar:** recoger, transformar una copia y compartir.
- **Agentes con contexto:** distinguir decisiones pendientes, resultados y proyectos.
- **Reuniones preparadas:** entrar con nota y documentos; recuperar acuerdos.
- **Contenido reutilizable:** pegar en secuencia, rellenar plantillas y traducir.
- **Casa y continuidad:** controles frecuentes y acceso desde otros dispositivos.

## Por dónde empezar

Correo e idiomas mantienen la prioridad destacada por Xus. Después, estas
son las candidatas recomendadas para elegir entre sesiones:

1. **R01 Correo — Hecho:** beta opcional publicada en [0.13.0](https://github.com/XusBadia/altillo/releases/tag/v0.13.0); [validación](docs/qa/mail-0.13.0.md).
   **R61 — En curso:** cuentas de correo directas, bandeja de lectura local y transición del puente; [plan revisado por Astra](docs/plans/mail-native-accounts.md). Implementación autorizada; pendiente de validación real OAuth y distribución.
2. **R02 y R03 Idiomas — Pendientes:** catalán y lote francés/alemán/italiano con IA, candidatos para la siguiente sesión.
3. **R04 y R19 Archivos listos para enviar:** ZIP y reducción de imágenes.
4. **R26 Pegado en secuencia:** un flujo completo y fácil de demostrar.
5. **R12 y R33 Agentes:** proyectos y bandeja de peticiones pendientes.
6. **R40 Notas de reuniones:** conectar calendario y notas existentes.
7. **R15 Buscador global:** empezar por Shelf y notas.
8. **R53 Termostatos:** ampliar Casa desde un hueco concreto del código.

El orden es ajustable. Una corrección que desbloquee el uso diario va antes
que una feature nueva.

## Alcance de correo e idiomas

### R01 Correo en el notch

Inspiración: [tweet de GotEmail](https://x.com/uaghazadae/status/2116507133344645423).
El caso de uso es enterarte de un correo importante o usar un código de acceso
sin ir a buscarlo a la bandeja.

La primera implementación usa una regla de Apple Mail que ejecuta AppleScript.
[Apple documenta esa automatización](https://support.apple.com/guide/mail/automate-mail-tasks-mlhlp1120/mac)
y el diccionario de Mail permite recibir el evento y leer contenido. El
[spike de R01](docs/spikes/mail-bridge.md) ya verifica la regla ejecutada por
Mail sobre un mensaje sintético importado, el transporte nativo, código y
magic link en una tarjeta temporal y apertura del mismo mensaje en Mail.
**R01 está hecho y publicado en [0.13.0](https://github.com/XusBadia/altillo/releases/tag/v0.13.0).**
Integra la tarjeta en Altillo con activación opcional, filtros y preparación
local de scripts. La llegada nueva por red mostró la tarjeta, reconoció el
código y abrió el original, sin aplicar reglas manualmente ni inyectar el
transporte. La [ficha de validación](docs/qa/mail-0.13.0.md) recoge las pruebas,
CI, firma, notarización y comprobaciones públicas del artefacto.

La preparación comprueba archivos locales y una entrega real confirma
recepción; no se consultan las reglas de Mail. La regla y los dos scripts se
retiran manualmente; Altillo los conserva al desconectar. La siguiente evolución
en curso es **R61: cuentas directas**, con Google y Microsoft primero. La revisión
de Astra considera el puente una compatibilidad temporal; MailKit conserva la
dependencia de Mail y no resuelve la conexión independiente de cuentas. Véase el
[plan de cambio de estrategia](docs/plans/mail-native-accounts.md).
No se leen bases privadas de Mail ni notificaciones de otras apps.

Primera entrega funcional:

- Aviso breve con remitente y asunto; filtrar qué cuentas o remitentes avisan.
- Abrir el mensaje en Apple Mail mediante una acción explícita.
- Reconocer códigos y magic links en mensajes nuevos, con copia o apertura
  explícita, dominio visible y caducidad breve.
- Procesar localmente; no guardar los accesos en historial persistente ni
  enviarlos a Pregunta. Mantener las exclusiones de privacidad de Clipboard.

La integración inicial requiere Apple Mail ejecutándose y recibiendo correo.
Solo cubre las cuentas configuradas allí y comprobadas en la validación.
Vista breve, resumen on-device al pedirlo y conectores directos de Gmail/Outlook
son posibles iteraciones posteriores. Redacción y envío quedan fuera del MVP.

### R02 y R03 Idiomas

Los catálogos revisados de Mac, AltilloDesign y AltilloHome tienen inglés y
español. El catalán de la web no equivale a tener la app traducida.

Usar IA para traducir en lote, con terminología coherente entre módulos.
Francés, alemán e italiano se entregan juntos. Comprobar interpolaciones,
plurales, accesibilidad y textos cortados, especialmente en alemán; extender el
validador de localización a cada idioma publicado. Incluir onboarding, ajustes,
errores y recursos de AltilloDesign y AltilloHome.


## Catálogo de iniciativas

**Alta:** candidata a una próxima sesión. **Media:** ampliación valiosa tras las
prioridades elegidas. **Explorar:** necesita definir producto o viabilidad.
**S/M/L** compara el tamaño del primer alcance dentro de Altillo; no son días
ni estimaciones comprometidas. Cada fila define una entrega mínima y su límite.
El estado por defecto de las filas es **Pendiente**.

### Correo e idiomas

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R01 | Alta · M | **Correo en el notch — Hecho, publicado en [0.13.0](https://github.com/XusBadia/altillo/releases/tag/v0.13.0).** Módulo opcional, scripts guiados, filtros y acciones efímeras; [guía](docs/correo.md). | Recepción real, apertura del original y desconexión verificadas; 900 pruebas, CI, firma/notarización y descarga/appcasts públicos correctos. [Validación](docs/qa/mail-0.13.0.md). | GotEmail; prueba local |
| R61 | Alta · L | **Cuentas de correo nativas — En curso.** Google y Microsoft con autorización del proveedor, bandeja reciente y lectura local. [Plan y verificación](docs/plans/mail-native-accounts.md). | Código implementado: proveedores Google/Graph, OAuth, bandeja/lector, avisos y migración reversible. 465 tests de paquete + 921 macOS correctos; iOS compila. Pendientes registros OAuth, perfil Developer ID y QA real/distribución; no publicado. iCloud/IMAP y escritura siguen posteriores. | Petición de Xus; revisión de Astra |
| R02 | Alta · S | **Catalán — Pendiente.** Traducir con IA app, onboarding, ajustes y paquetes compartidos. | Validar variables, plurales, terminología y tamaños; ampliar el validador de idiomas. | Decisión de Xus |
| R03 | Alta · M | **Francés, alemán e italiano juntos — Pendiente.** Una entrega conjunta con traducción por IA y revisión de las pantallas principales. | No separar los tres en lanzamientos artificiales; revisar especialmente textos largos e interpolaciones. | Decisión de Xus |
| R07 | Media · M | **Vista breve y resumen de correo.** Ver un extracto y pedir un resumen on-device desde el aviso. | Depende de R01; consentimiento explícito para procesar contenido; probar límites de idioma y longitud. | Idea Altillo |
| R08 | Explorar · L | **Gmail y Outlook directos.** Recibir avisos sin tener Apple Mail abierto, empezando por un proveedor. | Resolver OAuth, permisos, recepción, revocación y coste operativo antes de implementar. | Idea Altillo |
| R14 | Explorar · M | **Siguientes lotes de idiomas.** Portugués y después japonés u otros según solicitudes. | La IA acelera traducción; validar composición, fechas, fuentes y, si procede, escritura de derecha a izquierda. | NotchNook; solicitudes |

### Archivos y Shelf

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R04 | Alta · M | **ZIP desde Shelf.** Compartir o arrastrar varios archivos como un ZIP temporal. | Conservar originales; resolver nombres repetidos, cancelación y limpieza al acabar. | Dropover |
| R10 | Media · M | **Convertir imágenes.** Generar copias PNG o JPEG listas para compartir y arrastrar. | Elegir formatos con soporte nativo comprobado; gestionar transparencia y orientación. | Dragin; Dropover |
| R16 | Media · M | **Colecciones temporales.** Separar archivos de dos entregas o proyectos en grupos con nombre. | Aclarar qué caduca y qué se conserva; no cambiar de golpe la semántica temporal de Shelf. | Dragin |
| R17 | Media · S | **Carpetas de destino favoritas.** Soltar una selección en Trabajo, Facturas o Entregas para copiarla allí. | Destinos elegidos por el usuario; copiar primero, mover solo con intención explícita. | Dropover |
| R18 | Alta · M | **Renombrado por lotes.** Previsualizar prefijo, sufijo y numeración para una selección. | Deshacer y resolver colisiones; distinguir etiquetas del Shelf y nombres reales en disco. | Dropover |
| R19 | Alta · M | **Imágenes listas para enviar.** Reducir dimensiones/peso y quitar metadatos de ubicación de una copia. | Mostrar resultado y tamaño antes de compartir; no prometer un peso exacto sin comprobarlo. | Dropover; Dragin |
| R20 | Media · M | **Crear y combinar PDF.** Ordenar imágenes o PDFs seleccionados y generar un documento nuevo. | No editar originales; tratar PDFs protegidos o incompatibles con un error claro. | Dropover |
| R21 | Media · M | **Acciones al arrastrar.** Mostrar dos o tres acciones pertinentes al tipo: ZIP, reducir imagen o ejecutar un Atajo con la selección. | Compartir y AirDrop ya existen; confirmar qué acciones pueden recibir el contenido sin guardarlo primero. | Dropover |
| R22 | Media · M | **Paquetes de entrega.** Reunir archivos, una nota y una lista de enlaces en una carpeta o ZIP. | Depende de R04; el paquete debe poder abrirse sin Altillo y no subir nada a una nube por defecto. | Idea Altillo |
| R23 | Media · S | **Enviar selección al Shelf.** Servicio o acción rápida de Finder para enviar archivos seleccionados mediante teclado. | Validar Services/App Intents; mantener drag-and-drop y file promises existentes. | Idea Altillo |
| R24 | Media · S | **Caducidad por elemento.** Conservar un archivo hasta terminar la entrega o cambiar su caducidad desde el propio Shelf. | No confundir referencias con copias; que limpiar el Shelf nunca destruya el único original. | Auditoría local |
| R25 | Media · M | **Recuperar archivos inaccesibles.** Explicar un disco desconectado o una referencia rota y permitir volver a localizarla. | Ya hay bookmarks y restauración; mejorar recuperación y UX, no rehacer persistencia. | Auditoría local |

### Portapapeles y texto

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R09 | Media · S | **Transformaciones de texto y enlaces.** Limpiar parámetros de seguimiento, ordenar líneas o dar formato a JSON; copiar el resultado. | Copiar sin formato ya existe; mostrar diferencias y conservar el original. Añadir recordatorios desde fechas como iteración. | Raycast; OneNotch |
| R26 | Alta · M | **Pegado en secuencia.** Elegir varios clips y pegarlos uno a uno en el orden visible. | Cola explícita con pausa y cancelar; probar permisos y no interferir en campos seguros. | Paste; OneNotch |
| R27 | Media · M | **Plantillas con campos.** Guardar respuestas como «Hola, {nombre}» y rellenar antes de copiar. | Los fijados ya existen; empezar por inserción manual, sin capturar todas las pulsaciones. | Raycast |
| R28 | Media · S | **QR de ida y vuelta.** Crear un QR de texto/enlace y leer el de una imagen seleccionada. | Procesamiento local; mostrar el dominio antes de abrir y gestionar contenido excesivamente largo. | Raycast; idea Altillo |
| R29 | Media · M | **Traducir texto seleccionado.** Seleccionar un clip y obtener una traducción copiable con original al lado. | Probar idiomas y disponibilidad del motor local; no subir contenido silenciosamente. | OneNotch |
| R30 | Media · S | **Editar un clip sin perderlo.** Corregir un enlace o fragmento en una copia antes de pegarlo. | Guardar el original y permitir deshacer; no es otra opción de copiar sin formato. | Raycast |
| R31 | Media · S | **Pausa privada del historial.** Pausar temporalmente la captura y borrar solo un intervalo reciente desde una acción visible. | Ya hay exclusiones por app y contenido privado; conservarlas y definir cuándo se reanuda la captura. | Raycast; idea Altillo |

### Agentes y desarrollo

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R12 | Alta · M | **Agentes por proyecto.** Agrupar sesiones del mismo repositorio y filtrar un proyecto. | Ya hay proyecto y orden global por urgencia; mantener visible cualquier petición que requiera atención. | Auditoría local |
| R32 | Explorar · L | **Contexto elegido para agentes.** Compartir una selección de archivos o clips con una sesión mediante un conector local. | Empezar con envío explícito; si se usa MCP, permisos y alcance por sesión, sin exponer todo el historial. | OneNotch; idea Altillo |
| R33 | Alta · M | **Bandeja de peticiones pendientes.** Recorrer permisos y preguntas de distintas sesiones con teclado y contexto de proyecto. | Approve/deny/reply ya existen; no introducir aprobación masiva ni responder a sesiones equivocadas. | Auditoría local |
| R34 | Media · M | **Resultados pendientes de revisar.** Reunir los trabajos terminados desde la última revisión y marcarlos como vistos. | Ya existe extracto final; añadir seguimiento de revisión y enlace a terminal, sin inventar resultados. | Auditoría local |
| R35 | Media · M | **Registro de decisiones.** Consultar qué permiso se aceptó o rechazó, en qué proyecto y cuándo. | Retención local limitada y borrado; no almacenar prompts, secretos ni transcripciones completas por defecto. | Idea Altillo |
| R36 | Media · M | **Salud de las integraciones.** Saber si un hook dejó de enviar eventos, si una terminal se cerró o si falta reinstalar una integración. | Separar sesión inactiva de conexión rota; reutilizar diagnósticos existentes sin mostrar secretos. | Auditoría local |
| R37 | Media · M | **Tareas y builds en el notch.** Recibir inicio, progreso declarado y final de un build o test mediante CLI local. | Progreso solo cuando la herramienta lo envía; nada de estimar porcentajes ni leer terminales arbitrarias. | Idea Altillo |
| R38 | Explorar · L | **PRs y checks a un vistazo.** Ver checks y peticiones de revisión de repositorios elegidos, con enlace al PR. | Primero solo lectura; resolver autenticación, rate limits y actualización sin sondeo agresivo. | Idea Altillo |
| R39 | Media · S | **Sesiones favoritas y notas de contexto.** Nombrar una sesión o añadir una nota breve para recordar qué estabas esperando. | No afirmar que Altillo puede reanudar cualquier agente; abrir la sesión disponible y mostrar límites. | Idea Altillo |

### Reuniones y foco

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R40 | Alta · M | **Notas vinculadas a reuniones.** Abrir una nota desde el evento con título/fecha y guardar acuerdos relacionados. | Calendario, Join y notas ya existen; el valor nuevo es asociarlos y recuperar notas anteriores. | MeetingBar; idea Altillo |
| R41 | Media · M | **Preparar la próxima reunión.** Asociar documentos y enlaces al evento; abrir la selección elegida al entrar. | Seleccionar contenido expresamente; sin leer todo el correo ni iniciar grabaciones. | Idea Altillo |
| R42 | Media · S | **Hueco libre hasta la próxima reunión.** Mostrar cuánto tiempo libre queda y ofrecer un temporizador que termine antes del evento. | Definir solapes, eventos de día completo y cambios de zona horaria; no inferir disponibilidad de otras personas. | Idea Altillo |
| R43 | Media · S | **Zonas horarias de reuniones.** Mostrar hora local y una segunda zona elegida; copiar un horario para compartir. | Probar horario de verano y eventos recurrentes. | Idea Altillo |
| R44 | Media · M | **Preferencias para entrar en llamadas.** Elegir navegador o app por servicio y un atajo para la reunión próxima. | Join y detección de enlaces ya existen; ampliar preferencias y proveedores solo donde falten. | MeetingBar |
| R45 | Explorar · L | **Controles de llamada.** Estado y mute de una app de reuniones soportada, empezando por una. | Probar integración fiable y feedback real; no confundir silenciar el dispositivo con el mute de la llamada. | NotchBay |
| R46 | Media · M | **Foco con objetivo.** Añadir un objetivo a una sesión y una nota de cierre por proyecto. | Pomodoro, intervalos y tiempo diario ya existen; no presentar el cronómetro como una función nueva. | Seam; idea Altillo |
| R47 | Media · M | **Reglas para avisos.** Durante foco, silenciar novedades de música o correo y conservar las peticiones importantes elegidas. | Configurable por módulo; no ocultar fallos ni hacer desaparecer peticiones con plazo sin indicarlo. | Seam; idea Altillo |
| R48 | Media · S | **Rutinas de inicio y cierre.** Un botón para abrir recursos elegidos, iniciar foco y ejecutar un Atajo personal. | El lanzador de Atajos ya existe; lo nuevo es una rutina con pasos visibles, confirmación y fallos explicados. | Idea Altillo |

### Música y voz

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R49 | Media · M | **Elegir salida de audio.** Cambiar entre altavoces y auriculares desde Sonando. | Comprobar API pública y cambios de dispositivos; no asumir control sobre todos los Bluetooth. | Seam |
| R50 | Explorar · M | **Controles para podcasts y clases.** Saltar unos segundos o cambiar velocidad cuando la app lo soporte. | Sonando universal y letras ya existen; disponibilidad por proveedor, sin prometer control universal de navegador. | Notchy |
| R51 | Media · M | **Dictado hacia cualquier app.** Ampliar el dictado actual de Pregunta para devolver texto a la app donde se invocó. | Previsualización/copiar como alternativa; no escribir en otra ventana si cambió el foco. | Seam; NotchBay |
| R52 | Media · S | **Acciones guardadas de Pregunta.** Botones como «resume esto», «corrige el tono» o «extrae tareas» sobre contenido elegido. | Pregunta ya entiende archivos y contexto; definir plantillas reutilizables y mostrar qué contenido usa. | Idea Altillo |

### Casa

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R53 | Alta · M | **Termostatos.** Ver temperatura y cambiar consigna/modo de una entidad climate de Home Assistant. | El modelo reconoce climate pero aún no ofrece sus comandos en favoritos; validar unidades, rangos y estado confirmado. | Auditoría local |
| R54 | Media · M | **Reproductores domésticos.** Controlar una entidad media_player elegida: play/pausa y volumen. | Empezar por capacidades declaradas; distinguir música del Mac y la de otra habitación. | Idea Altillo |
| R55 | Media · M | **Sensores útiles a un vistazo.** Elegir temperatura, CO₂ o potencia instantánea para una tarjeta compacta. | No añadir un dashboard permanente; unidades, antigüedad del dato y desconexión visibles. | Idea Altillo |
| R56 | Media · M | **Avisos domésticos configurables.** Puerta abierta demasiado tiempo o lavadora terminada a partir de entidades elegidas. | Timbre y cámara ya existen; usar eventos/automatizaciones de HA y evitar alertas duplicadas. | Auditoría local |

### Personalización y acceso

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R05 | Media · M | **Perfiles personales.** Guardar módulos y orejas con nombres como Trabajo, Personal o Crear. | Partir de presets existentes; cambiar manualmente primero. | Idea Altillo |
| R06 | Media · S | **Compartir perfiles.** Exportar e importar un perfil con previsualización y deshacer. | Depende de R05; excluir cuentas, rutas, credenciales y contenido personal. | Idea Altillo |
| R11 | Explorar · M | **Perfiles según Concentración.** Cambiar el perfil al activar trabajo o descanso. | Depende de R05; comprobar API pública o usar un Atajo explícito. Permitir anulación manual. | Seam; idea Altillo |
| R15 | Alta · M | **Buscador global de Altillo.** Un atajo para encontrar un archivo, nota, clip, escena o sesión y abrirlo o copiarlo. | Empezar por dos módulos; sin indexar todo el disco ni ejecutar comandos arbitrarios. | Raycast; idea Altillo |
| R57 | Media · M | **Modo presentación.** Activar manualmente una vista discreta que oculte títulos de eventos, correo y nombres de proyectos. | No prometer invisibilidad en todas las capturas; mantener una señal de qué está oculto. | Idea Altillo |
| R58 | Media · M | **Centro de salud y datos.** Ver permisos/conexión por módulo y limpiar datos locales de una sección con alcance claro. | Reutilizar diagnósticos actuales; previsualizar qué se borra y conservar preferencias no seleccionadas. | Auditoría local |

### Companion y continuidad

| ID | Prioridad y tamaño | Iniciativa y primera entrega | Dependencia o criterio de cierre | Inspiración |
| --- | --- | --- | --- | --- |
| R13 | Explorar · L | **Companion de iPhone.** Primera app útil de consulta de cuotas y estado de agentes. | Los targets son scaffolds; definir sync, datos mínimos y reconexión. Aprobación remota requiere un plan aparte. | PLAN.md |
| R59 | Explorar · L | **Preferencias entre Macs.** Sincronizar perfiles y preferencias compatibles mediante iCloud. | Depende de R05/R06; conflictos y opt-in. No sincronizar credenciales, rutas locales ni historial por defecto. | PLAN.md |
| R60 | Explorar · L | **Del iPhone al Shelf.** Extensión de compartir para enviar enlaces o archivos desde el móvil a una bandeja de recepción. | Depende de R13 y un transporte definido; estado de entrega, cuota y borrado claros. Widgets de consulta después. | PLAN.md |

## Mejoras que acompañan cada entrega

- **Arrastre y archivos:** regresiones con Mail, Photos, Safari, archivos grandes,
  cambios de nombre y discos externos. Reutilizar gestión de temporales.
- **Reposo y pantallas:** consumo, sleep/wake, monitores externos, pantalla
  completa, resolución y convivencia con el Cajón.
- **Accesibilidad:** teclado, VoiceOver, textos grandes, Reducir movimiento y
  estados que no dependan solo del color.
- **Confianza:** permisos cuando hacen falta, recuperación sin pérdida de datos,
  errores accionables y diagnósticos sin contenido privado.
- **Descubrimiento:** ayudas breves y notas de versión que enseñen la novedad
  sin repetir onboarding ni interrumpir continuamente.

Convertir cada problema real en una tarea con evidencia; evitar tareas genéricas
de «pulir UX» que nunca se puedan cerrar.

## Cómo elegir y cerrar una iniciativa

Priorizar una fricción observada, aprovechar módulos existentes y poder
demostrar el antes/después en medio minuto. La primera entrega debe funcionar
por sí sola, admitir cancelación o deshacer cuando corresponda y tener estados
de error. Pasar checks del área y puertas de release; probar el artefacto
firmado antes de distribuir.

Una exploración puede terminar en una decisión técnica documentada. Eso cierra
la investigación, no convierte la feature en **Hecho**. Resolver compatibilidad
antes de prometerla. Tras publicar, recoger feedback y fallos antes de ampliar.
No añadir telemetría remota por defecto para medir este roadmap. Preparar
changelog y demo cuando aporten valor; publicar o enviar anuncios requiere
aprobación de Xus.

## Ideas aparcadas y límites de producto

- **HUDs de volumen/brillo:** el spike previo sigue en NO-GO; revisar solo con
  evidencia nueva sobre compatibilidad y convivencia con el HUD del sistema.
- **CPU/RAM permanentes, clima y bolsa:** baja prioridad para la promesa actual;
  una lista larga no justifica sondeo ni ruido constante.
- **Grabar y transcribir todas las reuniones:** proyecto aparte. Los controles
  de llamada de otro producto no demuestran necesidad de grabación.
- **Aprobaciones automáticas o en lote de agentes:** mantener decisión explícita
  y contexto por petición.
- **Terminal completa, gestor de ventanas o marketplace genérico:** reconsiderar
  solo con un caso concreto que no resuelvan Atajos o la CLI.
- **macOS 14/15:** investigación de arquitectura separada, no un ajuste pequeño.
- **Costes y predicciones de cuotas:** se retiraron deliberadamente en 0.12.0.

## Contexto y evidencia

- Base revisada: commit `13d1328`, notas hasta [0.12.1](docs/releases/0.12.1.md).
  Comprobar el estado real al retomar.
- [README](README.md#what-it-does): ya existen OCR, filtros y fijados de
  Clipboard, AirDrop, Join, Pomodoro, notas con historial, dictado de Pregunta,
  permisos/respuestas de agentes y Casa con luces, persianas, escenas,
  ventiladores y timbre/cámara. No planificarlos como novedades.
- Auditoría local: `ShelfStore.swift`, `ClipboardHistory.swift`,
  `TimerLogic.swift`, `NoteStore.swift`, `AgentsPresentation.swift`,
  `AltilloCore/Agents.swift` y `AltilloHome/HomeModel.swift`.
- [Perfiles competitivos](competitor-profiles/_summary.md): fuentes oficiales,
  límites de la revisión y propuestas derivadas.
- [0.12.0](docs/releases/0.12.0.md): decisión sobre cuotas observadas.
- [PLAN.md](PLAN.md): arquitectura y fases históricas.
- [Planes técnicos](plans/README.md): auditorías y tareas detalladas.
- Decisiones de Xus: roadmap sin fechas, distintas sesiones, correo como feature
  propia y francés/alemán/italiano en un mismo lote.
