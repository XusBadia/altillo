# Investigación competitiva para el roadmap de Altillo

1 de noviembre de 2026. Revisión de **13 productos** a partir de páginas,
documentación y repositorios oficiales. Las capacidades comerciales son lo que
sus autores anuncian, no resultados de pruebas de uso. No se instalaron binarios,
no se midieron ventas ni retención y no había herramientas de métricas SEO
conectadas. El objetivo es encontrar flujos útiles, no estimar tamaño de mercado.

## Productos y oportunidades

| Producto y perfil | Señal observada | Oportunidad propuesta para Altillo |
| --- | --- | --- |
| [NotchNook](notchnook.md) · [fuente](https://getnotchnook.com/) | Hub de notch generalista. | R02, R03, R14. |
| [Alcove](alcove.md) · [fuente](https://tryalcove.com/) | Interacción y presentación del notch. | Mejoras continuas; R47, R57. |
| [DynamicLake](dynamiclake.md) · [fuente](https://www.dynamiclake.com/) | Hub amplio e integraciones. | R21, R45; integraciones por validar. |
| [Boring Notch](boring-notch.md) · [fuente](https://github.com/TheBoredTeam/boring.notch) | Alternativa abierta. | R04, R12, R19, R33. |
| [Seam](seam.md) · [fuente](https://getseam.app/changelog) | Foco, voz y contexto. | R11, R46, R47, R49, R51. |
| [Notchy](notchy.md) · [fuente](https://notchy.dev/whats-new/) | Amplitud de herramientas. | R50; mejoras de permisos. |
| [Dropover](dropover.md) · [fuente](https://dropoverapp.com/kb/instant-actions) | Preparación de archivos. | R04, R17–R21. |
| [Dragin](dragin.md) · [fuente](https://getdragin.com/) | Shelf y transformaciones locales. | R10, R16, R19. |
| [OneNotch](onenotch.md) · [fuente](https://www.tryonenotch.com/) | Portapapeles y reutilización. | R26, R29, R32. |
| [Raycast](raycast.md) · [fuente](https://manual.raycast.com/clipboard-history) | Acceso por teclado y acciones. | R09, R15, R27, R28, R30, R31. |
| [Paste](paste.md) · [fuente](https://pasteapp.io/help/using-paste-stack) | Composición desde el portapapeles. | R26. |
| [MeetingBar](meetingbar.md) · [fuente](https://github.com/leits/MeetingBar) | Reuniones desde la barra. | R40, R41, R44. |
| [NotchBay](notchbay.md) · [fuente](https://notchbay.com/) | Llamadas y dictado. | R45, R51. |

MacNotch queda en seguimiento: la lectura de su web no devolvió contenido
utilizable en esta revisión. Las afirmaciones del informe de septiembre no se
han tratado como novedades verificadas hoy.

## Mapa cualitativo

Sin puntuaciones inventadas: NotchNook, DynamicLake y Notchy se presentan como
hubs amplios; Alcove destaca interacción; Boring Notch es una referencia abierta.
Dropover y Dragin se centran en archivos. Paste y OneNotch dan profundidad al
portapapeles. MeetingBar especializa reuniones y Raycast combina acceso por
teclado y acciones. Seam y NotchBay cruzan varios de estos casos de uso.

Estas agrupaciones describen las páginas leídas, no prueban calidad relativa
ni que las apps carezcan de funciones fuera de su grupo.

## Conclusiones para producto

1. **Preparar archivos**, además de guardarlos temporalmente: ZIP, tamaños,
   nombres y documentos listos para entregar.
2. **Componer con el portapapeles:** una cola de pegado y plantillas resuelven
   tareas distintas a buscar una copia antigua.
3. **Organizar la atención:** proyectos, decisiones y resultados pendientes de
   agentes pueden aprovechar metadatos que Altillo ya recibe.
4. **Conectar módulos:** notas y documentos ligados a reuniones, paquetes de
   entrega y búsqueda dentro de Altillo son hipótesis propias con buen encaje.
5. **Mantener la calidad como trabajo continuo:** interrupciones, teclado,
   permisos, pantallas y recuperación importan en un producto que aparece y
   desaparece durante otras tareas.

No hay evidencia aquí para afirmar que estos huecos sean exclusivos ni que
generen más retención. Validarlos con uso diario y feedback antes de ampliar.

## Cómo se convirtió en roadmap

El [roadmap](../ROADMAP.md) contiene 60 iniciativas con IDs estables, prioridad,
primer alcance y dependencias. Su columna de inspiración indica de dónde sale
la idea; no significa que el competidor implemente exactamente esa propuesta.

Se contrastó con código local para no volver a proponer OCR, fijados, filtros,
AirDrop, Join, Pomodoro, notas con historial, approve/deny/reply o controles
domésticos que ya existen. R53, termostatos, corresponde a un hueco concreto:
el modelo reconoce climate pero no ofrece consigna/modo entre sus comandos.

## Trazabilidad y mantenimiento

Cada perfil enlaza su página oficial y la captura textual guardada en
`raw/<producto>/2026-11-01/scrapes/`. Algunas capturas devuelven navegación
o contenido parcial: no asumir que son una exportación completa de la web.
Raycast incluye también el resultado de búsqueda de su documentación oficial
cuando la apertura devolvió principalmente navegación.

Revisar fuentes de una integración concreta antes de implementarla y volver
a verificar precios si se hace una comparación comercial. Conservar las
capturas anteriores y fechar cualquier actualización. Los estados de desarrollo
se mantienen únicamente en ROADMAP.md.

