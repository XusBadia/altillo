# Spike: HUD de volumen con APIs públicas

Fecha: 26-09-2026. Entorno probado: macOS 26, Mac mini, salida integrada
“Mac mini Speakers”.

**Decision: NO-GO** para integrar el HUD en esta iteración.

CoreAudio demuestra que la observación básica es viable y barata, pero este
entorno solo ofrece una clase de salida. No se pudo verificar el cambio de
dispositivo, Bluetooth ni una salida HDMI/DisplayPort sin volumen controlable.
El criterio acordado exige esas pruebas antes de conectar una superficie tan
visible al notch. No queda código experimental dentro de la app.

## Criterios definidos antes de la prueba

- [x] Solo API pública.
- [x] Callback al cambiar volumen/mute, sin polling.
- [ ] Cambio fiable del dispositivo de salida durante hot-plug.
- [ ] Comportamiento definido para salidas sin volumen controlable.
- [x] Sin permiso de Accessibility, Input Monitoring ni Screen Recording.
- [x] Coste de reposo despreciable.
- [ ] Decisión visual validada sobre coexistencia con el HUD nativo.

Todos los criterios deben pasar para un GO.

## Evidencia

Se compiló fuera del proyecto un observador mínimo contra el SDK público de
CoreAudio. Usó:

- `kAudioHardwarePropertyDefaultOutputDevice` en el system object.
- `kAudioDevicePropertyVolumeScalar` y `kAudioDevicePropertyMute` en scope de
  salida.
- `AudioObjectAddPropertyListenerBlock` y su remove correspondiente.

El SDK local documenta las tres propiedades en
`CoreAudio.framework/Headers/AudioHardware.h`. La salida integrada reportó:

```text
device=71 hasVolume=true hasMute=true
volume-listener-status=0
device-listener-status=0
```

Se cambió el volumen de 0 a 1 mediante AppleScript mientras la salida seguía
silenciada y después se restauró el valor original. CoreAudio entregó callbacks
con selector `1987013741` (`volm`). No hubo timer ni lectura periódica.

El listener permaneció diez minutos esperando eventos:

```text
elapsed=09:38  cpu=0.0%  rss=10720 KB
listeners-removed
```

`xcrun xctrace list templates` confirmó que el entorno dispone de Audio System
Trace, System Trace y Time Profiler. `system_profiler SPAudioDataType -json`
solo enumeró la salida integrada; por eso no se fabricó una validación de
Bluetooth/HDMI.

## Riesgos observados

- Algunos dispositivos exponen volumen solo por canal o no lo exponen.
- El default output puede cambiar y obliga a retirar listeners del dispositivo
  anterior antes de instalar los del nuevo.
- Mostrar un peek de Altillo junto al HUD nativo puede producir dos indicadores.
  Este spike no intentó ocultar el HUD del sistema: hacerlo mediante eventos
  globales, Accessibility o APIs privadas está expresamente descartado.
- Un resultado válido para volumen no demuestra nada sobre brillo.

## Condición para reabrir

Repetir el spike cuando haya disponibles, como mínimo, salida integrada,
Bluetooth y HDMI/DisplayPort. Si callbacks, hot-plug y salida no controlable
pasan, crear un plan separado para un peek efímero; no un módulo ni un panel de
sistema permanente. Mantener las mismas prohibiciones: cero polling, cero
Accessibility/event taps y ninguna API privada.
