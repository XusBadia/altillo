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
6. Vuelve a Altillo y pulsa **Comprobar regla de Mail**. Debe indicar que la
   regla está conectada. Los mensajes posteriores aparecerán en Correo.
   Para comprobar las reglas y retirar los scripts, macOS necesita el permiso
   **Altillo → Mail** en Ajustes del Sistema → Privacidad y seguridad →
   Automatización. El diálogo de macOS permite concederlo o rechazarlo.
   Si Mail no responde, comprueba también ese permiso; Altillo conserva los
   scripts y las reglas mientras no pueda verificar su estado.

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
  y los lotes de entrega. Puede omitir códigos posteriores, mensajes aún no
  descargados o partes de una entrega masiva. Usa **Abrir en Mail** en esos casos.
- Los avisos respetan la política de pantalla completa y no interrumpen un
  arrastre o el notch abierto. El mensaje puede estar disponible en su sección
  aunque no haya aparecido un aviso.

## Desconectar y desinstalar

Desactivar la sección detiene el receptor y borra sus mensajes. Antes de
eliminar Altillo, desactiva Correo y retira la regla **Altillo Mail** de
Mail → Ajustes → Reglas. Después pulsa **Eliminar la conexión de Correo de
Altillo** con Mail abierto. Altillo conserva las reglas creadas por el usuario;
solo retira sus scripts cuando ya no están vinculados a una regla. Si has
modificado los scripts, los conserva para que puedas revisarlos.

Si vuelves a una versión anterior a 0.13.0, retira primero la conexión. Si ya
has hecho el rollback, elimina manualmente solo la regla **Altillo Mail** de
Mail → Ajustes → Reglas y sus dos scripts de la carpeta que muestra Mail.
No borres otros scripts ni las reglas de tus cuentas.
