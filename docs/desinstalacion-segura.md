# Desinstalación segura / Safe uninstall

## Español

Los hooks viven en la configuración de cada CLI, fuera de `Altillo.app`. Por
eso hay que retirarlos antes de borrar la app:

1. Abre **Altillo › Ajustes › Secciones › Agentes**.
2. Pulsa **Preparar la desinstalación…**.
3. Revisa el diff de cada agente, marca las CLI que quieras limpiar y confirma.
4. Comprueba la confirmación individual de cada agente. Altillo guarda antes
   una copia privada en `~/Library/Application Support/Altillo/Backups`.
5. Si un fichero no se puede atribuir o interpretar con seguridad, Altillo no
   lo cambia: muestra su ruta y la instrucción manual. Elimina únicamente la
   entrada completa cuyo campo `command`, `bash` o `exec` ejecute
   `altillo-hook`; no borres el fichero ni otros hooks.
6. Cuando todos los agentes estén limpios, borra Altillo o ejecuta
   `brew uninstall --zap altillo`.

La retirada es idempotente: repetirla no cambia nada. `--zap` elimina los datos
propios de Altillo, pero deliberadamente no edita `~/.claude`, `~/.codex`,
`~/.gemini`, `~/.copilot` ni `~/.cursor`, porque son configuraciones compartidas.

## English

Hooks live in each CLI's configuration, outside `Altillo.app`, so remove them
before deleting the app:

1. Open **Altillo › Settings › Sections › Agents**.
2. Click **Prepare to Uninstall…**.
3. Review every diff, select the CLIs to clean, and confirm.
4. Check the result shown for each agent. Altillo first saves a private backup
   under `~/Library/Application Support/Altillo/Backups`.
5. If a file cannot be parsed or attributed safely, Altillo leaves it alone and
   shows the exact path and manual instruction. Remove only the complete entry
   whose `command`, `bash`, or `exec` value runs `altillo-hook`; never delete the
   whole file or unrelated hooks.
6. After every agent is clean, delete Altillo or run
   `brew uninstall --zap altillo`.

Removal is idempotent. `--zap` removes Altillo's own data, but deliberately does
not edit `~/.claude`, `~/.codex`, `~/.gemini`, `~/.copilot`, or `~/.cursor`,
because those are shared third-party configuration directories.
