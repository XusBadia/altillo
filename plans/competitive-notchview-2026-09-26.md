# Auditoría competitiva: NotchView

Fecha: 26-09-2026. Fuentes públicas consultadas: [post de lanzamiento](https://x.com/0xhrushi/status/2103392921559126157),
[web del producto](https://notchview-site.vercel.app/) y
[releases públicas](https://github.com/Hrushi2406/notchview-releases/releases).
No se compró ni ejecutó la app; las afirmaciones dinámicas del competidor se
tratan como promesas, no como hechos verificados.

## Resumen ejecutivo

NotchView gana hoy la comparación de treinta segundos: encadena música,
archivos, reuniones, volumen, portapapeles, batería y Claude en un vídeo de 25
segundos y cuesta 5 $ una vez. Su ventaja observable es amplitud empaquetada,
no profundidad técnica. Altillo ya es superior en agentes (acciones explícitas,
seguridad, más proveedores), calendario, música universal, cajón y confianza de
distribución; varias de esas ventajas no se prueban ni se cuentan bien todavía.

La respuesta correcta no es copiar su panel de CPU. Primero hay que cerrar dos
riesgos propios —copias huérfanas de AirDrop y validación real de Codex—, hacer
que el cajón comparta lo que ya contiene y añadir una utilidad pequeña y
coherente como Keep Awake. El HUD de volumen merece un spike; brillo, CPU,
memoria y descargas universales no pasan el filtro de APIs públicas, reposo y
foco del producto.

## Inventario observado de NotchView

| Área | NotchView | Estado comparable en Altillo |
|---|---|---|
| Música | Carátula, transporte y progreso; Apple Music, Spotify, Podcasts, TV, IINA | Ya hay proveedor universal MediaRemote + fallback y scrub |
| Archivos | Tray, drag-out, selección múltiple, copiar, retirar y AirDrop | Cajón más completo; falta Share/AirDrop sobre lo ya guardado |
| Reuniones | Próxima reunión, cuenta atrás y Join | Ya existe calendario mensual/agenda, cuenta atrás y enlaces de 10 proveedores |
| Agentes | Alertas Claude/Codex y salto al terminal | Altillo añade sesiones, acciones allow/deny, peligro, reply y más proveedores; falta validar permisos Codex en vivo |
| Uso IA | Claude y Codex | Altillo cubre 10 proveedores |
| Clipboard | Texto, imágenes, enlaces, fijados, retención, exclusiones, persistencia cifrada | Texto/enlaces, fijados, búsqueda, exclusiones y persistencia 0600; no imágenes ni cifrado con clave propia |
| Sistema | Volumen, brillo, batería, AirPods, CPU/memoria, Keep Awake | Timer sí; el resto no |
| Capturas/descargas | Capturas al tray y progreso/velocidad | No |
| Instalación | macOS 14+, Sparkle; FAQ admite Gatekeeper “Open” | Altillo macOS 26+, actualización y distribución notarizada previstas |
| Precio | 5 $/₹399 una vez | No copiar sin una decisión de sostenibilidad |

## Fortalezas y debilidades del competidor

Fortalezas: demo muy legible, abundancia percibida, precio impulsivo, soporte
macOS 14+, y profundidad suficiente en Tray/Clipboard para uso recurrente. El
post mostraba aproximadamente 64 mil vistas, 1.014 likes y 601 guardados el día
de la auditoría: señal de interés en la categoría, no prueba de ventas o
retención.

Debilidades: la FAQ instruye a saltar la verificación de macOS; el dominio
canónico no resolvía y faltaban páginas públicas de privacidad, soporte y
términos. La promesa “todo local” exige confianza especial porque la app cerrada
pide acceso a calendario, portapapeles, Bluetooth y configuración de Claude.
La web muestra alertas y retorno al terminal, no prueba aprobación dentro del
notch. Su repositorio público es de releases, no código, y tenía apenas dos
versiones del mismo día.

## Matriz de decisión

| Hueco | Valor | Encaje | Coste/riesgo | Decisión |
|---|---:|---:|---:|---|
| Limpiar copias temporales de AirDrop | Alto | Alto | Medio | Hacer ya (001) |
| Probar Codex y alinear mensajes | Alto | Alto | Medio | Hacer ya (002) |
| Share/AirDrop desde Shelf | Alto | Alto | Bajo | Hacer ya (003) |
| Keep Awake | Medio | Alto | Medio | Hacer (004) |
| HUD de volumen | Medio | Medio | Incertidumbre API | Spike acotado (005) |
| Imágenes en Clipboard | Medio | Medio | Alto privacidad/disco | Medir demanda |
| macOS 14/15 | Alto mercado | Medio | Muy alto | Spike separado |
| Batería/AirPods | Medio | Medio | Medio | Backlog después de 004 |
| Capturas automáticas | Medio | Alto con Shelf | Medio | Backlog, opt-in |
| Brillo, CPU/memoria, descargas | Bajo | Bajo | Alto | No copiar |

## Ventaja que Altillo debe demostrar

1. **Agentes en contexto y con control humano**: proyecto, motivo, terminal
   exacto, permitir/denegar explícitamente y nunca autoaprobar.
2. **El cajón como producto, no como widget**: recibir, conservar, previsualizar,
   seleccionar, arrastrar y compartir sin perder nada.
3. **Confianza verificable**: código abierto, build firmado/notarizado, permisos
   explicados antes de pedirlos, datos locales y retención documentada.
4. **Calma**: módulos opt-in y trabajo dirigido por eventos. No convertir el
   notch en un dashboard que sondea el sistema.

## Huecos de comunicación detectados en Altillo

- `website/index.html` y `website/en/index.html` reducen Now Playing a Apple
  Music/Spotify aunque el proveedor actual es universal.
- La demo web todavía rotula agentes como “función en desarrollo” aunque la
  fase 4 está implementada.
- `README.md` dice 0.5.0 y presenta iOS/widgets como producto, mientras
  `Apps/iOS/AltilloApp.swift` y `Apps/Widgets/AltilloWidgets.swift` son placeholders.

El plan 002 convierte estas discrepancias en una puerta de release. El vídeo se
deja fuera, tal como pidió el propietario del producto.

## Señales a medir después

- Uso semanal y repetido por módulo, con telemetría local/voluntaria o estudio
  manual; no añadir tracking silencioso.
- Cuántas acciones del cajón acaban en drag-out, Quick Look, copiar o AirDrop.
- Cuántas aprobaciones de agentes se resuelven en Altillo y cuántas vuelven al
  terminal.
- Solicitudes reales de imágenes en Clipboard y de compatibilidad pre-macOS 26.
- Descarga → primera apertura → finalización del onboarding, sin inferir negocio
  desde las vistas del tweet del competidor.
