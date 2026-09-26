# Nombre: ¿se mantiene «Altillo»? (25-09-2026)

Validación pedida en el plan (§10, «Pendiente de validar contigo»): disponibilidad de **Altillo** como nombre definitivo — GitHub, Homebrew, App Store, marcas y dominios. «Altillo» es una palabra común del español (desván/buhardilla), justo el concepto de la app, así que el riesgo no es de originalidad sino de colisión con otros usos de la misma palabra.

## GitHub

Búsqueda de repos llamados `altillo` (GitHub Search API, 16 resultados totales, excluyendo `XusBadia/altillo`):

| Repo | Qué es |
|---|---|
| `gastonpaz91/altillo` | vacío, sin descripción |
| `Sebastian0021/altillo_scraper` | scraper de apuntes de elaltillo.com (portal argentino de estudiantes) |
| `nachodha/AltilloGamer`, `xTorettox/Altillo8bits` | juegos/webs personales |
| `MatMassu/altillo-massucco` | tienda de vinilos |
| `Zepeq/inventario-altillo` | inventario doméstico literal (un altillo real) |
| `altillomusicaoficial-musicaweb/*` | web de un grupo de música |
| resto | proyectos personales sin relación, 0-2 estrellas |

**Ninguno es una app de macOS, notch, menú, ni herramienta de desarrollo.** Todos son proyectos pequeños o personales que usan la palabra en su sentido literal ("mi altillo", contenido de un desván real) o el nombre de un portal de apuntes (elaltillo.com, muy conocido en Argentina — de ahí el scraper). No hay colisión de categoría.

**Riesgo: ninguno.**

## Homebrew (cask)

`https://formulae.brew.sh/cask/altillo` → **404** (no existe). Confirmado además que `Casks/a/altillo.rb` no existe en `Homebrew/homebrew-cask` (404 en GitHub). El token `altillo` está libre.

**Riesgo: ninguno.** (Nota: la preparación del cask local en `packaging/homebrew/` es una tarea aparte, no tocada aquí.)

## App Store (iOS / Mac App Store)

Búsqueda en el catálogo de Apple (iTunes Search API) por software con término "altillo": **4 resultados**, ninguno de productividad/menú/notch:

| App | Categoría | Desarrollador |
|---|---|---|
| LAUDE El Altillo School | Educación (app de un colegio en Vigo, "El Altillo") | Double First Ltd |
| EL ALTILLO HOMES INFO | Finanzas/inmobiliaria | Shebel Consultoría |
| Haluro, Recurret | coincidencias débiles, sin relación con "altillo" | — |

Una búsqueda ampliada a todo el catálogo (música, podcasts) devuelve muchísimos resultados con "altillo" en el nombre — canciones, podcasts, un grupo folclórico uruguayo "Los Del Altillo" — todo ruido por ser palabra común, sin relación con software.

**Riesgo: ninguno.** Ningún competidor de productividad/utilidad/menú usa el nombre.

## Marcas

Búsqueda web general de "Altillo trademark" / "marca registrada software" / OEPM clase 9: no aparece ningún litigio, cese de uso ni registro de software conocido bajo "Altillo". Sin embargo, **no se pudo consultar directamente EUIPO eSearch ni OEPM Localizador de Marcas** — ambos dependen de un formulario interactivo en JS que un fetch no puede accionar (comprobado: la página devuelve solo el layout, sin resultados).

Pendiente de verificación manual antes de comprometerse al nombre:
- EUIPO eSearch plus: https://euipo.europa.eu/eSearch/ (buscar "Altillo", filtrar clase Niza 9 y 42)
- OEPM Localizador de Marcas: https://consultas2.oepm.es/LocalizadorWeb/busquedaDenominacion
- USPTO Trademark Search: https://tmsearch.uspto.gov/ (buscar "Altillo")
- WIPO Global Brand Database: https://branddb.wipo.int/

**Riesgo: bajo, pero no confirmado.** "Altillo" es una palabra de diccionario en clase de software (poco distintiva por sí sola), lo que en general hace más difícil que alguien tenga una marca amplia y fácil de hacer valer contra un nombre de app — pero solo una búsqueda manual en esos cuatro registros cierra la duda del todo.

## Dominios

Comprobado con RDAP (registros de Google para `.app`/`.dev`) y whois directo contra el registro correcto (Verisign para `.com`, nic.io para `.io`) — el whois genérico de macOS solo devolvía datos del TLD, no del dominio, así que hubo que consultar los registros correctos directamente:

| Dominio | Estado |
|---|---|
| `altillo.app` | registrado y en uso como dominio oficial |
| `getaltillo.com` | libre ("No match") |
| `altilloapp.com` | libre ("No match") |
| `usealtillo.com` | libre ("No match") |
| `altillo.io` | libre ("Domain not found") |
| `altillo.dev` | libre (RDAP: "not found") |

**Riesgo: ninguno.** Los seis dominios candidatos están libres ahora mismo (25-09-2026); pueden registrarse ya en el momento en que se decida.

## Recomendación final

**Mantener «Altillo»**, sin matices: no hay ninguna app de macOS/notch/productividad con ese nombre en GitHub ni en las App Stores, el token de Homebrew está libre, `altillo.app` ya está registrado como dominio oficial, y no aparece ningún indicio de marca registrada conflictiva en búsqueda web — queda documentada la recomendación de comprobar manualmente EUIPO/OEPM/USPTO (enlaces arriba), ya que esas bases de datos no son accesibles por fetch automatizado.

Dominio definitivo de la web: **[`altillo.app`](https://altillo.app/)** (coherente con el bundle id `me.badia.altillo` y con que la app vive en el ecosistema Apple). `altilloapp.com` puede mantenerse como redirección defensiva si se registra.
