# Correo en Altillo

La sección Correo muestra mensajes nuevos de Apple Mail durante cinco minutos.
Puedes abrir el mensaje en Mail y, cuando Altillo reconoce un único candidato,
copiar su código de acceso o abrir su enlace con el dominio visible.

Es una beta opcional. Mail debe permanecer abierto y recibir correo; Altillo
aprovecha las cuentas que ya tienes allí y no inicia sesión en ellas.

## Conectar

1. En Ajustes de Altillo → Secciones, activa Correo y abre su configuración.
2. Pulsa **Preparar scripts de Mail**. Altillo prepara dos scripts propios
   en la carpeta de scripts de Apple Mail. No cambia las reglas existentes.
3. Abre Mail → Ajustes → Reglas y crea una regla llamada **Altillo Mail**.
4. Elige **Todos los mensajes** y la acción **Ejecutar AppleScript → Altillo Mail**.
   El nombre del script auxiliar «Altillo Mail Bridge» también puede aparecer;
   elige «Altillo Mail».
5. Al guardar, elige **No aplicar** a los mensajes anteriores.
6. Espera un mensaje nuevo. Cuando llega a la sección Correo, Altillo confirma
   **Apple Mail ha entregado un mensaje nuevo a Altillo**. Esa confirmación dura
   solo durante la sesión activa; no certifica las condiciones de tu regla.
   **Comprobar archivos de scripts** verifica únicamente la preparación local.
   Altillo no consulta las reglas de Mail ni necesita el permiso de Automatización
   **Altillo → Mail** para esta integración.

Puedes indicar direcciones completas o nombres de cuentas separados por comas
en los filtros de Altillo. Déjalos vacíos para mostrar todos los mensajes nuevos.
Los filtros se aplican después de la entrega local, no en el servidor de correo.

## Datos y límites

- Los mensajes permanecen solo en memoria: hasta veinte mensajes recientes,
  durante cinco minutos desde su recepción. No se guardan en un archivo de
  correo ni se comparten con Pregunta.
- Desactivar Correo, bloquear la pantalla o poner el Mac en reposo borra los
  mensajes recientes. Al volver, Altillo espera mensajes nuevos.
- El botón de código marca la copia como privada para excluirla del historial
  de Clipboard de Altillo. No borra el portapapeles ni controla otros gestores.
- Los códigos reconocidos son numéricos y etiquetados en inglés o español.
  Los enlaces reconocidos usan HTTPS y un parámetro de acceso compatible;
  el parámetro genérico `token` exige además una ruta de acceso reconocida.
  Si hay varios candidatos, Altillo omite la acción. Comprueba el dominio;
  reconocer un enlace no verifica la identidad del remitente.
- La beta usa el principio del cuerpo del mensaje y limita el tamaño del evento
  y los lotes de entrega. Puede omitir códigos posteriores o aún no descargados,
  y partes de una entrega masiva. Si el cuerpo aún no está disponible,
  muestra el remitente y asunto; solo ofrece acciones reconocidas en el texto
  disponible. Usa **Abrir en Mail** en esos casos.
- Los avisos respetan la política de pantalla completa y no interrumpen un
  arrastre o el notch abierto. El mensaje puede estar disponible en su sección
  aunque no haya aparecido un aviso.

## Desconectar y desinstalar

Desactivar la sección detiene el receptor y borra sus mensajes. **Eliminar la
conexión de Correo de Altillo** también detiene la recepción y conserva tanto
los scripts como las reglas para su retirada manual: no consulta Mail ni intenta
eliminar archivos que una regla podría seguir usando.

Antes de eliminar Altillo o volver a una versión anterior a 0.13.0:

1. Desactiva Correo y retira la regla **Altillo Mail** de Mail → Ajustes → Reglas.
   Si has creado más reglas que ejecutan el script, retíralas también.
2. En la configuración de Correo de Altillo, pulsa **Mostrar scripts**. Retira
   manualmente solo **Altillo Mail.scpt** y **Altillo Mail Bridge.scpt**, una vez
   que ninguna regla los use. No borres otros scripts ni las reglas de tus cuentas.

Si ya has hecho el rollback, abre desde Mail su carpeta de scripts y sigue los
mismos pasos. Los mensajes de Altillo solo estaban en memoria.
