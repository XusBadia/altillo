# FAQ y notas de prensa

Respuestas de referencia: una persona las adapta a la pregunta real antes de enviar. No publicar respuestas generadas en HN/DEV; ver política de cada sitio. Sin estadísticas, testimonios ni previsiones inventadas.

| Pregunta | EN | ES |
|---|---|---|
| 1. What is Altillo? | A native Mac utility that puts a temporary file shelf, AI usage and coding-agent requests at the top of the screen. | Una utilidad nativa para Mac con una estantería temporal para archivos, consumo de IA y peticiones de agentes arriba de la pantalla. |
| 2. Does it cost anything? | It's free, with MIT source available. No subscription or launch discount is needed. | Es gratuita y su código está disponible con licencia MIT. No hay suscripción ni hace falta un descuento de lanzamiento. |
| 3. Which Macs work? | macOS 26+. It uses a physical notch or a virtual island on displays without one. Ask also depends on Apple Intelligence availability; don't assume every module works on every configuration. | macOS 26+. Usa el notch físico o una isla virtual en pantallas sin notch. Pregunta depende además de la disponibilidad de Apple Intelligence; cada módulo tiene sus requisitos. |
| 4. Is Shelf storage or a backup? | It's a temporary holding place, not a backup. Stable files can be referenced in their original location; temporary or promised files are copied to the local Inbox. Keep your normal storage and backups. | Es un sitio temporal, no una copia de seguridad. Los archivos estables pueden conservar su referencia; los temporales o prometidos se copian al Inbox local. Conserva tu organización y copias de seguridad habituales. |
| 5. Can agents approve their own actions? | No. Altillo shows requests and lets you approve or deny them explicitly. It never approves automatically. | No. Altillo muestra las peticiones y te deja aprobarlas o denegarlas. Nunca aprueba automáticamente. |
| 6. Do credentials ever leave the Mac? | Optional usage checks present the credential already stored by the provider's own tool directly to that same provider. Altillo doesn't receive it on a backend or keep a separate copy. | Las consultas opcionales de uso presentan la credencial que ya guarda la herramienta del proveedor únicamente a ese mismo proveedor. No llega a un servidor de Altillo ni se conserva otra copia. |
| 7. Is everything offline? | No. Ask's model runs on-device, but web lookups contact external services. Optional usage checks, lyrics, updates and external links also use the network. There is no Altillo app analytics. | No. El modelo de Pregunta se ejecuta en el Mac, pero las consultas web contactan con servicios externos. Las consultas de uso, letras, actualizaciones y enlaces también utilizan la red. La app no tiene analítica de Altillo. |
| 8. Why Accessibility or Screen Recording? | Drawer needs Accessibility to read and open menu bar items. Screen Recording is optional, used to capture their actual icon images; Drawer works with app icons without it. Other modules request relevant permissions when enabled. | Cajón necesita Accesibilidad para leer y abrir elementos de la barra de menús. Grabación de pantalla es opcional para capturar sus iconos reales; sin ella usa iconos de apps. Los demás módulos piden sus permisos al activarlos. |
| 9. Can Drawer hide menu bar icons? | On macOS 27 it can hide selected app icons. On macOS 26 it lists and opens them while originals remain visible. Quitting Altillo, disabling Drawer or revoking Accessibility restores icons. | En macOS 27 puede ocultar iconos seleccionados. En macOS 26 los lista y abre, y los originales siguen visibles. Salir de Altillo, desactivar Cajón o revocar Accesibilidad devuelve los iconos. |
| 10. Is this finished, and where do I report a bug? | It's a working pre-1.0 release, signed and notarized. Download from altillo.app; report reproducible bugs in GitHub Issues with version, macOS and steps, without credentials or private files. | Es una versión funcional pre-1.0, firmada y notarizada. Se descarga en altillo.app; informa de fallos reproducibles en GitHub Issues con versión, macOS y pasos, sin credenciales ni archivos privados. |

Source/privacy: https://altillo.app/privacy/ · https://altillo.app/es/privacidad/ · https://github.com/XusBadia/altillo/issues.

## Press blurb EN · 100 words

```text
Altillo turns the Mac's notch into a temporary shelf for files, with Claude and Codex usage and coding agent requests within reach. Drop a file at the top, find its destination, then drag it out. Built in Swift for macOS 26+, it also creates a virtual island on displays without a notch. Altillo is free, MIT open source, signed and notarized. There is no Altillo backend or analytics. Optional usage checks connect directly to their provider. Ask uses an on-device model, with external services for web lookups. The launch week begins October 19. Download and source links are at altillo.app.
```

## Nota breve ES · 100 palabras

```text
Altillo convierte el notch del Mac en una estantería temporal para archivos, con consumo de Claude y Codex y peticiones de agentes al alcance. Deja un archivo arriba, busca su destino y arrástralo después. Nativa para macOS 26+, también crea una isla virtual en pantallas sin notch. Es gratuita, de código abierto con licencia MIT, firmada y notarizada. No hay servidores de Altillo ni analítica. Las consultas de uso contactan al proveedor. Pregunta ejecuta su modelo en el Mac y consulta servicios externos para búsquedas web. La semana de lanzamiento empieza el 19 de octubre. Descarga y código en altillo.app.
```

Cada nota tiene 100 palabras, contadas por espacios. Revisar fecha y tono antes de enviar.
