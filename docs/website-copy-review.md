# Revisión del texto de la web de Altillo

Revisión del 20 de septiembre de 2026 sobre la versión actual de `website/index.html` y `website/src/demo.js`. La investigación visual está en [website-design-research.md](website-design-research.md).

## Qué explica la página

El hero conserva la pareja de marca «Tu Mac ya tenía un altillo» / «Solo le faltaba una puerta». La imagen del Mac con una puerta en el notch representa esa idea; el pie la identifica como una forma de imaginar el producto. La explicación literal aparece junto al titular: **«Deja archivos en el notch. Recógelos en otra ventana.»** Así no hace falta interpretar la metáfora para saber qué hace la app.

La introducción describe una situación concreta: dejar un archivo mientras cambias de ventana. El CTA «Entra y pruébalo» conduce al escritorio interactivo.

## Una demo, tres capítulos

La página mantiene un único escritorio durante el recorrido. No presenta una colección de demos detrás de pestañas. El scroll acompaña los capítulos, y los controles del notch permiten explorar el mismo escritorio directamente.

- **Estante:** «Sube un archivo. Sigue a lo tuyo.» El visitante arrastra un documento de ejemplo al notch y después a Entregas. También puede seleccionar el archivo y usar los botones.
- **Consumo de IA:** «Antes de llegar al límite.» La etiqueta «En desarrollo» y el texto sobre cifras de ejemplo evitan presentar Claude y Codex como integraciones terminadas.
- **Agentes:** «Te toca decidir.» La solicitud permite probar Permitir o Denegar. La explicación indica expresamente que es una simulación y que no ejecuta comandos.

La demo distingue los datos ficticios en el escritorio y dentro de los módulos pendientes. El estado de archivos y solicitudes pertenece a esa sesión del navegador. No se accede a cuentas ni a archivos personales.

## Cierre y Aurio

La escena del altillo vuelve a la acción: **«Deja algo arriba. Bájalo cuando lo necesites.»** La sección del proyecto aclara que el estante funciona en la app, que los otros dos módulos siguen en desarrollo y que todavía no existe una descarga pública. El enlace lleva al código, sin una fecha de lanzamiento inventada.

El bloque final cumple la petición de apoyo: **«Nos ayudas probando Aurio.»** Explica gastos, cuentas compartidas y patrimonio, enlaza a [la web oficial de Aurio](https://www.aurioapp.com) y utiliza su símbolo oficial. No promete ahorro, rentabilidad, donaciones ni resultados económicos.

## Criterio editorial

La página usa verbos que describen acciones: dejar, subir, recoger, permitir y denegar. La metáfora doméstica se concentra en el hero y en la escena del altillo; las instrucciones de la demo son literales. No necesita promesas de productividad, superlativos, urgencia ni cifras de valoración editorial.

La dirección visual combina fondo oscuro, imágenes de la pieza promocional, texto amplio y un cierre en papel cálido. El movimiento ayuda a recorrer los capítulos; no sustituye instrucciones ni exige esperar para usar los controles. La web conserva lectura estática y respeta la preferencia de movimiento reducido.

## Límites que deben conservarse

- No convertir cifras de ejemplo en afirmaciones sobre consumo real ni quitar «En desarrollo» de los módulos pendientes.
- No afirmar que el archivo original siempre permanece en su carpeta después de sacarlo: la app nativa respeta las operaciones de copia o movimiento del destino.
- No ofrecer «Descargar» hasta verificar una release pública. El requisito macOS 26+ corresponde a la app, no al navegador.
- Mantener equivalentes por botones y teclado para las acciones de arrastre, y avisos accesibles de sus resultados.
- Las imágenes son recursos existentes de `promo/public/film`, convertidos a WebP; no son capturas de una versión publicada ni imágenes generadas para esta web.
