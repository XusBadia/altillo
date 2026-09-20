import "./demo.css";
import "./demo-modules.css";
import { providerLogo } from "./brand-logos.js";
import { createDemoCopy } from "./demo-copy.js";
import { iconPaths } from "./icons.generated.js";

const icons = {
  shelf: "house", folder: "folder", chevron: "chevron-left",
  grid: "layout-grid", check: "check", close: "x", reset: "rotate-ccw",
  up: "arrow-up", external: "arrow-up-right", search: "search",
  recent: "clock", desktop: "monitor", downloads: "download", laptop: "laptop",
  safari: "compass", terminal: "terminal", trash: "trash-2",
  wifi: "wifi", battery: "battery-medium", command: "command", star: "asterisk",
  request: "corner-down-right", enter: "corner-down-left",
  calendar: "calendar", music: "music-note", play: "play", pause: "pause",
  previous: "skip-back", next: "skip-forward", mirror: "camera", flip: "flip",
  drawer: "archive", more: "dots-three", cloud: "cloud", bluetooth: "bluetooth",
  video: "video", speaker: "speaker-high", bell: "bell",
};
const svg = (name, size = 18) =>
  `<svg data-icon="${name}" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${iconPaths[icons[name] || icons.folder]}</svg>`;
const sampleDocs = [
  { id: "ideas", name: "Ideas.pdf", kind: "paper", meta: "PDF · 240 KB" },
  { id: "photo", name: "Escapada.jpg", kind: "photo", meta: "JPEG · 2,4 MB" },
  { id: "notes", name: "Notas.txt", kind: "notes", meta: "Texto · 4 KB" },
];
const art = (doc) =>
  `<span class="ad-file-art ad-file-${doc.kind}" aria-hidden="true">${doc.kind === "photo" ? "<i></i>" : `<span>${doc.kind === "paper" ? "Ideas para<br>el próximo<br>proyecto." : "Pendiente\n—\nRevisar portada\nEnviar propuesta"}</span><i></i><i></i><i></i>`}</span>`;
const traffic =
  '<span class="ad-traffic" aria-hidden="true"><i></i><i></i><i></i></span>';

export function mountDemo(element, { locale = document.documentElement.lang || "es" } = {}) {
  if (!element) return { setChapter() {}, setModule() {}, reset() {}, destroy() {} };
  element.classList.add("alt-demo");
  element.lang = String(locale).toLowerCase().startsWith("en") ? "en" : "es";
  const { t, localize } = createDemoCopy(locale);
  const docs = sampleDocs.map((doc) => ({ ...doc, name: t(doc.name), meta: t(doc.meta) }));
  const canHover = window.matchMedia("(hover: hover) and (pointer: fine)");
  let hoverOpenTimer, hoverCloseTimer;
  let pinned = false;
  let hoverOpened = false;
  let pointerInside = false;
  const state = {
    open: null,
    shelf: [],
    delivered: [],
    selected: "ideas",
    agent: "idle",
    drawerExpanded: false,
    drawerMenu: false,
    joinedEvent: null,
    track: 0,
    playing: false,
    elapsed: 0,
    audioError: false,
    mirrorFlipped: true,
  };
  const tracks = [
    { title: "Azotea", artist: "Estudio Altillo", src: "/media/music/azotea.mp3", duration: 0 },
    { title: "Luz de tarde", artist: "Estudio Altillo", src: "/media/music/luz-de-tarde.mp3", duration: 0 },
    { title: "Último tranvía", artist: "Estudio Altillo", src: "/media/music/ultimo-tranvia.mp3", duration: 0 },
  ];
  const clockTime = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
  const audio = new Audio();
  audio.preload = "metadata";
  audio.className = "ad-demo-audio";
  let destroyed = false;
  let playRequest = 0;
  let drag = null;
  let suppressClick = false;
  let returnFocus = null;
  element.innerHTML = `
    <div class="ad-desktop" aria-label="Escritorio Mac de demostración">
      <div class="ad-wallpaper" aria-hidden="true"></div>
      <div class="ad-menubar" aria-hidden="true"><div><span class="ad-apple">●</span><b>Finder</b><span>Archivo</span><span>Edición</span><span>Visualización</span></div><div><span>${svg("wifi", 14)}</span><span>${svg("battery", 16)}</span><span>Mar 10:24</span></div></div>
      <div class="ad-notch" data-open="false">
        <div class="ad-notch-bar"><button type="button" data-action="usage" class="ad-usage-trigger" aria-label="Ver consumo de Claude y Codex" aria-expanded="false"><span class="ad-tiny-ring"></span><span>85</span></button><span class="ad-camera" aria-hidden="true"></span><button type="button" data-action="shelf" class="ad-shelf-trigger" aria-label="Abrir estante" aria-expanded="false">${svg("shelf")}<span>0</span></button></div>
        <div class="ad-notch-panel" hidden></div>
      </div>
      <button type="button" class="ad-notch-cue" data-action="shelf" aria-label="Abrir Altillo">${svg("up")}<span class="ad-cue-label">${canHover.matches ? "Acerca el cursor aquí" : "Toca para abrir"}</span></button>
      <section class="ad-finder ad-window" aria-label="Finder: documentos de ejemplo">
        <div class="ad-finder-sidebar"><div class="ad-sidebar-traffic">${traffic}</div><small>Favoritos</small><span>${svg("recent")} Recientes</span><span>${svg("desktop")} Escritorio</span><span class="is-current">${svg("folder")} Documentos</span><span>${svg("downloads")} Descargas</span><small>Ubicaciones</small><span>${svg("laptop")} Mi Mac</span></div>
        <div class="ad-finder-main"><div class="ad-window-title"><span class="ad-mobile-traffic">${traffic}</span><span class="ad-finder-arrows" aria-hidden="true">${svg("chevron")}${svg("chevron")}</span><strong>Documentos</strong><span class="ad-finder-tools" aria-hidden="true">${svg("grid")}${svg("search")}</span></div><div class="ad-finder-files"></div><div class="ad-finder-bottom"><span class="ad-selection-meta"></span><button type="button" data-action="add">${svg("up")} Subir al estante</button></div></div>
      </section>
      <section class="ad-terminal ad-window" aria-label="Terminal de ejemplo"><div class="ad-terminal-title">${traffic}<span>mi-web — claude</span><span aria-hidden="true">${svg("command", 12)}</span></div><div class="ad-terminal-body"><p><span class="ad-terminal-star">${providerLogo("claude")}</span><b>Claude Code</b><span class="ad-terminal-version">v2.1</span></p><p class="ad-terminal-path">~/proyectos/mi-web</p><p class="ad-terminal-line"><span>❯</span> Publica los cambios de la web</p><div class="ad-terminal-result"></div><button type="button" data-action="agent"><span>${svg("request", 12)}</span> Pedir permiso para continuar <span class="ad-terminal-enter">${svg("enter", 12)}</span></button></div></section>
      <button type="button" class="ad-destination" data-action="deliver" aria-label="Llevar el archivo del estante a Entregas"><span class="ad-folder-art" aria-hidden="true"></span><span>Entregas</span><small>Carpeta vacía</small></button>
      <div class="ad-dock" aria-hidden="true"><span class="ad-dock-finder"><i>⌣</i></span><span class="ad-dock-safari">${svg("safari")}</span><span class="ad-dock-notes"><i></i></span><span class="ad-dock-terminal">${svg("terminal")}</span><span class="ad-dock-divider"></span><span class="ad-dock-folder">${svg("folder")}</span><span class="ad-dock-trash">${svg("trash")}</span></div>
      <div class="ad-screen-label">DEMO · DATOS DE EJEMPLO</div>
    </div>
    <div class="ad-demo-caption"><p class="ad-instruction"></p><button type="button" data-action="reset" aria-label="Reiniciar demo">${svg("reset")}<span>Reiniciar</span></button></div>
    <p class="ad-sr" role="status" aria-live="polite" aria-atomic="true"></p>
  `;
  element.append(audio);
  const notch = element.querySelector(".ad-notch");
  const panel = element.querySelector(".ad-notch-panel");
  const status = element.querySelector("[role=status]");
  const cue = element.querySelector(".ad-notch-cue");
  function interaction(source) {
    element.dispatchEvent(new CustomEvent("demo:interaction", { bubbles: true, detail: { source } }));
  }
  function scheduleHoverClose() {
    clearTimeout(hoverCloseTimer);
    hoverCloseTimer = setTimeout(() => {
      if (hoverOpened && !pinned && !pointerInside && !notch.contains(document.activeElement) && !drag) close();
    }, 200);
  }
  notch.addEventListener("pointerenter", (event) => {
    if (event.pointerType !== "mouse" || !canHover.matches) return;
    pointerInside = true;
    clearTimeout(hoverCloseTimer);
    clearTimeout(hoverOpenTimer);
    if (state.open || drag) return;
    hoverOpenTimer = setTimeout(() => {
      if (!pointerInside || state.open || drag) return;
      hoverOpened = true;
      pinned = false;
      open("shelf");
      interaction("hover");
      announce("Altillo abierto. Arrastra un archivo al estante.");
    }, 120);
  });
  notch.addEventListener("pointerleave", (event) => {
    if (event.pointerType !== "mouse") return;
    pointerInside = false;
    clearTimeout(hoverOpenTimer);
    scheduleHoverClose();
  });
  notch.addEventListener("focusin", () => clearTimeout(hoverCloseTimer));
  notch.addEventListener("focusout", scheduleHoverClose);
  const outsidePointerDown = (event) => {
    // Closing here changes the sticky demo height before the module's click.
    if (event.target.closest("[data-module]")) return;
    if (state.open && !notch.contains(event.target) && !cue.contains(event.target)) close();
  };
  document.addEventListener("pointerdown", outsidePointerDown);
  const updateCue = () => {
    cue.querySelector(".ad-cue-label").textContent = t(canHover.matches ? "Acerca el cursor aquí" : "Toca para abrir");
    updateInstruction();
  };
  canHover.addEventListener("change", updateCue);
  const cueObserver = new IntersectionObserver((entries) => {
    if (entries.some((entry) => entry.isIntersecting)) {
      cue.classList.add("ad-cue-introduced");
      cueObserver.disconnect();
    }
  }, { threshold: 0.6 });
  cueObserver.observe(element.querySelector(".ad-desktop"));
  const announce = (message) => {
    status.textContent = t(message);
  };
  const getDoc = (id) => docs.find((doc) => doc.id === id);
  function fileButton(doc, source) {
    return `<button type="button" class="ad-file ${source === "finder" && state.selected === doc.id ? "is-selected" : ""}" data-doc="${doc.id}" data-source="${source}" aria-label="${doc.name}${source === "shelf" ? ", en el estante" : ", documento de ejemplo"}" aria-pressed="${source === "finder" && state.selected === doc.id}">${art(doc)}<span class="ad-filename">${doc.name}</span>${source === "finder" && state.shelf.includes(doc.id) ? `<span class="ad-file-shelved" aria-label="En el estante">${svg("external")}</span>` : ""}</button>`;
  }
  function renderFiles() {
    element.querySelector(".ad-finder-files").innerHTML = docs
      .map((doc) => fileButton(doc, "finder"))
      .join("");
    element.querySelector(".ad-selection-meta").textContent = getDoc(
      state.selected,
    ).meta;
    const add = element.querySelector("[data-action=add]");
    add.disabled = state.shelf.includes(state.selected);
    add.innerHTML = `${svg(state.shelf.includes(state.selected) ? "check" : "up")} ${state.shelf.includes(state.selected) ? "En el estante" : "Subir al estante"}`;
    element.querySelector(".ad-destination small").textContent = state.delivered
      .length
      ? `${state.delivered.length} ${state.delivered.length === 1 ? "archivo recibido" : "archivos recibidos"}`
      : "Carpeta vacía";
    localize(element.querySelector(".ad-finder"));
    localize(element.querySelector(".ad-destination"));
  }
  function renderTerminal() {
    const result = element.querySelector(".ad-terminal-result");
    const button = element.querySelector(".ad-terminal [data-action=agent]");
    result.innerHTML =
      state.agent === "allowed"
        ? '<p class="ad-terminal-success">✓ Cambios publicados en la demo.</p>'
        : state.agent === "denied"
          ? "<p>Permiso denegado. No se ha publicado nada.</p>"
          : state.agent === "waiting"
            ? '<p class="ad-terminal-wait">Esperando tu permiso en Altillo…</p>'
            : "<p>✓ Cambios preparados</p><p>· Necesito permiso para ejecutar git push.</p>";
    button.innerHTML =
      state.agent === "waiting"
        ? `<span>${svg("request", 12)}</span> Ver solicitud en Altillo <span class="ad-terminal-enter">${svg("enter", 12)}</span>`
        : state.agent === "idle"
          ? `<span>${svg("request", 12)}</span> Pedir permiso para continuar <span class="ad-terminal-enter">${svg("enter", 12)}</span>`
          : `<span>${svg("request", 12)}</span> Probar otra solicitud <span class="ad-terminal-enter">${svg("enter", 12)}</span>`;
    localize(element.querySelector('.ad-terminal'));
  }
  function renderDrawer() {
    return `<div class="ad-module-surface ad-drawer-surface"><div class="ad-drawer-intro"><span>${svg("drawer", 24)}</span><div><strong>Una barra más tranquila.</strong><p>Guarda juntos los iconos que no necesitas ver.</p></div></div><div class="ad-drawer-bar"><span class="ad-drawer-bar-label">Menú</span><div class="ad-drawer-icons" ${state.drawerExpanded ? "" : "hidden"}><span aria-label="Bluetooth">${svg("bluetooth")}</span><button type="button" data-action="drawer-menu" aria-label="Abrir menú de Drive" aria-expanded="${state.drawerMenu}">${svg("cloud")}</button><span aria-label="Notificaciones">${svg("bell")}</span></div><span class="ad-drawer-divider" aria-hidden="true"></span><span aria-hidden="true">${svg("wifi")}</span><span aria-hidden="true">${svg("battery")}</span><button type="button" data-action="drawer-toggle" aria-expanded="${state.drawerExpanded}">${svg(state.drawerExpanded ? "chevron" : "more")}<span>${state.drawerExpanded ? "Ocultar grupo" : "Mostrar grupo"}</span></button></div>${state.drawerMenu ? `<div class="ad-drawer-menu"><span>${svg("cloud")}</span><div><strong>Drive</strong><small>Actualizado ahora</small></div>${svg("check")}</div>` : ""}</div><div class="ad-panel-footer"><span>Menú de ejemplo · los iconos se guardan en grupo</span></div>`;
  }
  function renderCalendar() {
    const events = [
      { time: "10:30", until: "11:00", name: "Revisión de diseño", provider: "Google Meet", soon: "En 6 minutos" },
      { time: "12:00", until: "12:30", name: "Café con el equipo", provider: "Zoom", soon: "Más tarde" },
    ];
    return `<div class="ad-module-surface ad-calendar-surface"><div class="ad-calendar-date"><span>Martes</span><strong>20</strong><small>Octubre</small></div><div class="ad-agenda"><div class="ad-agenda-heading"><strong>Tu agenda</strong><span>Hoy</span></div>${events.map((event, index) => `<div class="ad-event"><time>${event.time}<small>${event.until}</small></time><div class="ad-event-copy"><strong>${event.name}</strong><span>${event.provider} · ${event.soon}</span></div><button type="button" data-action="join" data-event="${index}" aria-label="${index === 0 ? "Unirse a Revisión de diseño" : "Unirse a Café con el equipo"}">${svg(state.joinedEvent === index ? "check" : "video", 15)}<span>${state.joinedEvent === index ? "Listo" : "Unirse"}</span></button></div>`).join("")}</div></div>${state.joinedEvent !== null ? '<p class="ad-meeting-status" role="status">Enlace preparado · videollamada simulada</p>' : ""}<div class="ad-panel-footer"><span>Eventos de ejemplo · Google Meet y Zoom</span></div>`;
  }
  function renderMusic() {
    const track = tracks[state.track];
    return `<div class="ad-module-surface ad-music-surface"><div class="ad-album-art ad-album-${state.track}" aria-hidden="true"><i></i><span>${["AZOTEA", "LUZ DE<br>TARDE", "ÚLTIMO<br>TRANVÍA"][state.track]}</span></div><div class="ad-music-body"><div class="ad-music-source">${svg("music", 13)}<span>Estudio Altillo</span><small>Ahora suena</small></div><strong class="ad-track-title">${track.title}</strong><span class="ad-track-artist">${track.artist}</span><div class="ad-music-controls"><button type="button" data-action="music-previous" aria-label="Canción anterior">${svg("previous", 18)}</button><button type="button" class="ad-music-play" data-action="music-play" aria-label="${state.playing ? "Pausar" : "Reproducir"}" aria-pressed="${state.playing}">${svg(state.playing ? "pause" : "play", 20)}</button><button type="button" data-action="music-next" aria-label="Siguiente canción">${svg("next", 18)}</button></div><div class="ad-track-progress" role="progressbar" aria-label="Progreso de la canción" aria-valuemin="0" aria-valuemax="${track.duration}" aria-valuenow="${state.elapsed}"><i style="transform:scaleX(${track.duration ? state.elapsed / track.duration : 0})"></i></div><div class="ad-track-time"><span>${clockTime(state.elapsed)}</span><span>${clockTime(track.duration)}</span></div></div></div><div class="ad-panel-footer"><span>${state.audioError ? "No se pudo reproducir. Pulsa para reintentar." : "Tres canciones originales · audio real"}</span><span>${state.track + 1} / ${tracks.length}</span></div>`;
  }
  function renderMirror() {
    return `<div class="ad-module-surface ad-mirror-surface"><div class="ad-mirror-art" data-flipped="${state.mirrorFlipped}" role="img" aria-label="Retrato ilustrado de ejemplo"><span class="ad-mirror-window"></span><span class="ad-mirror-plant"><i></i><i></i></span><span class="ad-mirror-person"><i class="ad-mirror-head"></i><i class="ad-mirror-hair"></i><i class="ad-mirror-shirt"></i></span></div><div class="ad-mirror-controls"><span>${svg("mirror", 14)}<span>Un vistazo antes de entrar.</span></span><button type="button" data-action="mirror-flip" aria-label="Invertir espejo" aria-pressed="${state.mirrorFlipped}">${svg("flip", 17)}<span>Invertir</span></button></div></div><div class="ad-panel-footer"><span>Vista de ejemplo · cámara apagada</span></div>`;
  }
  function syncPlayback() {
    if (destroyed) return;
    state.playing = !audio.paused && !audio.ended && !state.audioError;
    state.elapsed = Number.isFinite(audio.currentTime) ? audio.currentTime : 0;
    if (Number.isFinite(audio.duration)) tracks[state.track].duration = audio.duration;
    if (state.open !== "music") return;
    const track = tracks[state.track];
    const progress = panel.querySelector(".ad-track-progress");
    progress?.setAttribute("aria-valuenow", String(Math.floor(state.elapsed)));
    progress?.setAttribute("aria-valuemax", String(track.duration));
    if (progress) progress.firstElementChild.style.transform = `scaleX(${track.duration ? state.elapsed / track.duration : 0})`;
    const times = panel.querySelectorAll(".ad-track-time > span");
    if (times[0]) times[0].textContent = clockTime(state.elapsed);
    if (times[1]) times[1].textContent = clockTime(track.duration);
    const button = panel.querySelector('[data-action="music-play"]');
    // timeupdate fires repeatedly while playing. Keep the SVG node intact
    // unless playback actually changes, avoiding repaint flashes in WebKit.
    if (button && button.getAttribute("aria-pressed") !== String(state.playing)) {
      button.setAttribute("aria-label", t(state.playing ? "Pausar" : "Reproducir"));
      button.setAttribute("aria-pressed", String(state.playing));
      button.innerHTML = svg(state.playing ? "pause" : "play", 20);
    }
  }
  function ensureTrack() {
    if (audio.getAttribute("src")?.split("?")[0] !== tracks[state.track].src) audio.src = tracks[state.track].src;
  }
  async function playAudio() {
    const request = ++playRequest;
    const wasError = state.audioError;
    state.audioError = false;
    ensureTrack();
    if (wasError || audio.error) {
      audio.load();
      updateAudioNotice();
    }
    try {
      await audio.play();
    } catch (error) {
      if (destroyed || request !== playRequest || error.name === "AbortError") return;
      state.audioError = true;
      state.playing = false;
      syncPlayback();
      updateAudioNotice();
      announce("No se pudo reproducir. Pulsa para reintentar.");
    }
  }
  function changeTrack(direction, continuePlaying = !audio.paused) {
    ++playRequest;
    audio.pause();
    state.track = (state.track + direction + tracks.length) % tracks.length;
    state.elapsed = 0;
    state.audioError = false;
    ensureTrack();
    if (state.open === "music") renderPanel();
    if (continuePlaying) void playAudio();
  }
  function updateAudioNotice() {
    if (state.open !== "music") return;
    const notice = panel.querySelector(".ad-panel-footer > span");
    if (notice) notice.textContent = t(state.audioError ? "No se pudo reproducir. Pulsa para reintentar." : "Tres canciones originales · audio real");
  }
  const audioEvents = ["timeupdate", "loadedmetadata", "durationchange", "play", "pause"];
  audioEvents.forEach((type) => audio.addEventListener(type, syncPlayback));
  const trackEnded = () => changeTrack(1, true);
  const audioFailed = () => {
    if (destroyed) return;
    state.audioError = true;
    state.playing = false;
    syncPlayback();
    updateAudioNotice();
    announce("No se pudo reproducir. Pulsa para reintentar.");
  };
  audio.addEventListener("ended", trackEnded);
  audio.addEventListener("error", audioFailed);
  function renderPanel() {
    notch.dataset.open = String(Boolean(state.open));
    notch.dataset.view = state.open || "idle";
    element.querySelector(".ad-notch-cue").hidden = Boolean(state.open);
    element
      .querySelector("[data-action=shelf]")
      .setAttribute("aria-expanded", String(state.open === "shelf"));
    element
      .querySelector("[data-action=usage]")
      .setAttribute("aria-expanded", String(state.open === "usage"));
    element.querySelector(".ad-shelf-trigger span").textContent =
      state.shelf.length;
    panel.hidden = !state.open;
    if (!state.open) {
      panel.innerHTML = "";
      updateInstruction();
      return;
    }
    let content = "";
    if (state.open === "shelf") {
      content = `<div class="ad-shelf-wood" data-dropzone="shelf">${state.shelf.length ? state.shelf.map((id) => `<div class="ad-shelf-tile">${fileButton(getDoc(id), "shelf")}<button type="button" class="ad-remove" data-remove="${id}" aria-label="Retirar ${getDoc(id).name}">${svg("close")}</button></div>`).join("") : `<div class="ad-empty-shelf">${svg("shelf")}<span>Deja aquí lo que vas a usar después.</span><small>Arrastra un archivo desde Documentos</small></div>`}<div class="ad-plank" aria-hidden="true"></div></div><div class="ad-panel-footer"><span>${state.shelf.length ? "Arrástralo a Entregas cuando lo necesites." : "Tus archivos, a un gesto de distancia."}</span>${state.shelf.length ? `<button type="button" data-action="deliver">Llevar a Entregas ${svg("external")}</button>` : ""}</div>`;
    } else if (state.open === "drawer") {
      content = renderDrawer();
    } else if (state.open === "calendar") {
      content = renderCalendar();
    } else if (state.open === "music") {
      content = renderMusic();
    } else if (state.open === "mirror") {
      content = renderMirror();
    } else if (state.open === "usage") {
      content = `<div class="ad-usage-cards">${[
        {
          name: "Claude",
          mark: providerLogo("claude"),
          value: 85,
          weekly: 41,
          reset: "1 h 11 min",
          plan: "Max 20×",
          note: "9 puntos por delante del ritmo",
        },
        {
          name: "Codex",
          mark: providerLogo("codex"),
          value: 34,
          weekly: 58,
          reset: "3 h 4 min",
          plan: "Pro",
          note: "Vas a buen ritmo",
        },
      ]
        .map(
          (p) =>
            `<div class="ad-usage-card"><div class="ad-usage-main"><div class="ad-ring" style="--used:${p.value}%" role="img" aria-label="${p.name}: ${p.value}% consumido"><span>${p.value}<small>%</small></span></div><div><strong><i class="ad-provider ${p.name === "Codex" ? "ad-provider-codex" : ""}">${p.mark}</i>${p.name}<small>${p.plan}</small></strong><p>Se repone en ${p.reset}</p><em>${p.note}</em></div></div><div class="ad-week"><span>Semana</span><div role="meter" aria-label="Consumo semanal de ${p.name}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${p.weekly}"><i style="width:${p.weekly}%"></i></div><b>${p.weekly}%</b></div></div>`,
        )
        .join(
          "",
        )}</div><div class="ad-panel-footer"><span>Consumo de ejemplo · función en desarrollo</span><span>Actualizado ahora</span></div>`;
    } else {
      const resolved = ["allowed", "denied"].includes(state.agent);
      content = `<div class="ad-agent-request ${resolved ? "is-resolved" : ""}"><div class="ad-agent-heading"><i class="ad-provider">${providerLogo("claude")}</i><strong>${resolved ? (state.agent === "allowed" ? "Permiso concedido" : "Acción denegada") : "Claude quiere hacer algo en mi-web"}</strong><small>ahora</small></div><div class="ad-agent-command"><span>Bash</span><code>git push origin feat/nueva-web</code></div><div class="ad-agent-controls"><span>${resolved ? (state.agent === "allowed" ? "El agente puede continuar." : "El comando no se ejecutará.") : "Publicar los cambios en el repositorio"}</span>${resolved ? '<button type="button" data-action="agent">Otra solicitud</button>' : '<button type="button" data-action="deny">Denegar</button><button type="button" data-action="allow">Permitir</button>'}</div></div><div class="ad-agent-task"><i class="ad-provider ad-provider-codex">${providerLogo("codex")}</i><strong>api</strong><span>Ejecutando tests · 42 de 118</span><small>••• Trabajando</small></div><div class="ad-panel-footer"><span>Solicitud simulada · función en desarrollo</span></div>`;
    }
    const moduleTitles = { shelf: "Altillo", drawer: "Cajón", calendar: "Calendario", music: "Sonando", mirror: "Espejo", usage: "Tu consumo", agents: "Agentes" };
    panel.innerHTML = `<div class="ad-panel-heading"><strong>${["shelf", "drawer", "calendar", "music", "mirror"].includes(state.open) ? svg(state.open) : ""}${moduleTitles[state.open]}</strong><button type="button" data-action="close" aria-label="Cerrar Altillo">${svg("close")}</button></div>${content}`;
    localize(panel);
    updateInstruction();
  }
  function updateInstruction() {
    const moduleInstructions = {
      drawer: "Muestra el grupo de iconos y abre el menú de Drive. Después, vuelve a guardarlo.",
      calendar: "Consulta tus próximas citas. Prueba «Unirse» sin abrir una videollamada real.",
      music: "Pulsa reproducir y escucha. Cambia entre tres canciones desde el notch.",
      mirror: "Invierte la vista de ejemplo. Tu cámara sigue apagada.",
    };
    const message =
      moduleInstructions[state.open] || (state.open === "usage"
        ? "Claude y Codex, de un vistazo. Pulsa fuera para seguir."
        : state.open === "agents"
          ? "Decide aquí. El agente recibe tu respuesta sin cambiar de ventana."
          : state.shelf.length
            ? "Ahora llévalo a la carpeta Entregas. O déjalo arriba para luego."
            : "Arrastra un documento al notch. También puedes seleccionarlo y pulsar «Subir al estante».");
    element.querySelector(".ad-instruction").textContent = t(!state.open && !state.shelf.length ? (canHover.matches ? "Acerca el cursor al notch para abrir Altillo. Después, arrastra un documento." : "Toca arriba para abrir Altillo. Después, selecciona un documento y súbelo al estante.") : message);
  }
  function open(view, focus = false) {
    returnFocus =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    state.open = view;
    if (view === "music") ensureTrack();
    renderPanel();
    if (focus) panel.querySelector("button")?.focus({ preventScroll: true });
  }
  function close(restore = false) {
    clearTimeout(hoverOpenTimer);
    clearTimeout(hoverCloseTimer);
    pinned = false;
    hoverOpened = false;
    state.open = null;
    renderPanel();
    if (restore && returnFocus?.isConnected)
      returnFocus.focus({ preventScroll: true });
  }
  function add(id) {
    pinned = true;
    hoverOpened = false;
    if (!state.shelf.includes(id)) state.shelf.push(id);
    state.selected = id;
    state.open = "shelf";
    renderFiles();
    renderPanel();
    announce(`${getDoc(id).name} añadido al estante.`);
  }
  function deliver(id = state.shelf[0]) {
    if (!id || !state.shelf.includes(id)) {
      announce("Primero sube un archivo al estante.");
      return;
    }
    state.shelf = state.shelf.filter((item) => item !== id);
    if (!state.delivered.includes(id)) state.delivered.push(id);
    renderFiles();
    renderPanel();
    announce(`${getDoc(id).name} llevado a Entregas.`);
    const folder = element.querySelector(".ad-destination");
    folder.classList.add("is-received");
    setTimeout(() => folder.classList.remove("is-received"), 550);
  }
  function reset() {
    ++playRequest;
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
    cancelDrag();
    close();
    Object.assign(state, {
      open: null,
      shelf: [],
      delivered: [],
      selected: "ideas",
      agent: "idle",
      drawerExpanded: false,
      drawerMenu: false,
      joinedEvent: null,
      track: 0,
      playing: false,
      elapsed: 0,
      audioError: false,
      mirrorFlipped: true,
    });
    renderFiles();
    renderTerminal();
    renderPanel();
    announce("Demo reiniciada.");
  }
  element.addEventListener("click", (event) => {
    if (suppressClick) {
      suppressClick = false;
      event.preventDefault();
      return;
    }
    const button = event.target.closest("button");
    if (!button) {
      if (state.open && !notch.contains(event.target)) close();
      return;
    }
    if (button.dataset.doc) {
      if (button.dataset.source === "finder") {
        state.selected = button.dataset.doc;
        renderFiles();
        element
          .querySelector(`[data-source=finder][data-doc=${state.selected}]`)
          .focus({ preventScroll: true });
      } else
        announce(
          `${getDoc(button.dataset.doc).name}. Arrástralo a Entregas o usa «Llevar a Entregas».`,
        );
      return;
    }
    if (button.dataset.remove) {
      const id = button.dataset.remove;
      state.shelf = state.shelf.filter((item) => item !== id);
      renderFiles();
      renderPanel();
      announce(`${getDoc(id).name} retirado del estante.`);
      element
        .querySelector("[data-action=close]")
        ?.focus({ preventScroll: true });
      return;
    }
    interaction("click");
    switch (button.dataset.action) {
      case "drawer-toggle":
        state.drawerExpanded = !state.drawerExpanded;
        if (!state.drawerExpanded) state.drawerMenu = false;
        renderPanel();
        panel.querySelector('[data-action="drawer-toggle"]')?.focus({ preventScroll: true });
        break;
      case "drawer-menu":
        state.drawerMenu = !state.drawerMenu;
        renderPanel();
        panel.querySelector('[data-action="drawer-menu"]')?.focus({ preventScroll: true });
        break;
      case "join":
        state.joinedEvent = Number(button.dataset.event);
        renderPanel();
        announce("Enlace preparado · videollamada simulada");
        panel.querySelector(`[data-action="join"][data-event="${state.joinedEvent}"]`)?.focus({ preventScroll: true });
        break;
      case "music-play":
        if (audio.paused || state.audioError || audio.error) void playAudio();
        else { ++playRequest; audio.pause(); }
        break;
      case "music-previous":
      case "music-next":
        changeTrack(button.dataset.action === "music-next" ? 1 : -1);
        announce(tracks[state.track].title);
        panel.querySelector(`[data-action="${button.dataset.action}"]`)?.focus({ preventScroll: true });
        break;
      case "mirror-flip":
        state.mirrorFlipped = !state.mirrorFlipped;
        renderPanel();
        panel.querySelector('[data-action="mirror-flip"]')?.focus({ preventScroll: true });
        break;
      case "usage":
        clearTimeout(hoverOpenTimer);
        clearTimeout(hoverCloseTimer);
        if (state.open === "usage" && pinned) close();
        else { pinned = true; hoverOpened = false; open("usage"); }
        break;
      case "shelf":
        clearTimeout(hoverOpenTimer);
        clearTimeout(hoverCloseTimer);
        if (state.open === "shelf" && pinned) close();
        else { pinned = true; hoverOpened = false; open("shelf"); }
        break;
      case "close":
        close(true);
        break;
      case "add":
        add(state.selected);
        panel
          .querySelector("[data-source=shelf]")
          ?.focus({ preventScroll: true });
        break;
      case "deliver":
        deliver();
        break;
      case "agent":
        pinned = true; hoverOpened = false;
        state.agent = "waiting";
        renderTerminal();
        open("agents");
        announce("Claude necesita permiso para continuar.");
        panel
          .querySelector("[data-action=allow]")
          ?.focus({ preventScroll: true });
        break;
      case "allow":
      case "deny":
        state.agent = button.dataset.action === "allow" ? "allowed" : "denied";
        renderTerminal();
        renderPanel();
        announce(
          state.agent === "allowed"
            ? "Permiso concedido en la demo."
            : "Acción denegada en la demo.",
        );
        panel
          .querySelector("[data-action=agent]")
          ?.focus({ preventScroll: true });
        break;
      case "reset":
        reset();
        break;
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      cancelDrag();
      close(true);
    }
  });
  element.addEventListener("dragstart", (event) => event.preventDefault());
  function cancelDrag() {
    if (!drag) return;
    drag.ghost?.remove();
    element.classList.remove("is-dragging");
    notch.classList.remove("is-drop-target");
    element.querySelector(".ad-destination").classList.remove("is-drop-target");
    if (element.hasPointerCapture(drag.pointerId))
      element.releasePointerCapture(drag.pointerId);
    drag = null;
  }
  element.addEventListener("pointerdown", (event) => {
    const file = event.target.closest("[data-doc]");
    if (!file || drag || event.button !== 0 || !event.isPrimary) return;
    const rect = file.getBoundingClientRect();
    drag = {
      id: file.dataset.doc,
      source: file.dataset.source,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      markup: file.outerHTML,
      ghost: null,
    };
    element.setPointerCapture(event.pointerId);
  });
  element.addEventListener("pointermove", (event) => {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const dx = event.clientX - drag.startX,
      dy = event.clientY - drag.startY;
    if (!drag.ghost && Math.hypot(dx, dy) < 6) return;
    if (!drag.ghost) {
      const ghost = document.createElement("div");
      ghost.className = "ad-drag-ghost";
      ghost.innerHTML = drag.markup;
      ghost.setAttribute("aria-hidden", "true");
      Object.assign(ghost.style, {
        left: `${drag.x}px`,
        top: `${drag.y}px`,
        width: `${drag.width}px`,
        height: `${drag.height}px`,
      });
      document.body.append(ghost);
      drag.ghost = ghost;
      element.classList.add("is-dragging");
      if (drag.source === "finder") { pinned = true; hoverOpened = false; open("shelf"); }
    }
    drag.ghost.style.transform = `translate3d(${dx}px, ${dy}px, 0) scale(1.06)`;
    const target =
      drag.source === "finder"
        ? notch
        : element.querySelector(".ad-destination");
    const rect = target.getBoundingClientRect();
    drag.over =
      event.clientX >= rect.left - 12 &&
      event.clientX <= rect.right + 12 &&
      event.clientY >= rect.top - 12 &&
      event.clientY <= rect.bottom + 12;
    target.classList.toggle("is-drop-target", drag.over);
  });
  element.addEventListener("pointerup", (event) => {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const current = drag;
    cancelDrag();
    suppressClick = true;
    if (!current.ghost) {
      if (current.source === "finder") {
        state.selected = current.id;
        renderFiles();
        element
          .querySelector(`[data-source=finder][data-doc=${current.id}]`)
          ?.focus({ preventScroll: true });
      } else {
        announce(
          `${getDoc(current.id).name}. Arrástralo a Entregas o usa «Llevar a Entregas».`,
        );
      }
    } else {
      if (current.over)
        current.source === "finder" ? add(current.id) : deliver(current.id);
      else announce("Archivo sin mover. Suéltalo sobre el destino.");
    }
    setTimeout(() => {
      suppressClick = false;
    }, 0);
  });
  element.addEventListener("pointercancel", cancelDrag);
  window.addEventListener("blur", () => {
    cancelDrag();
    clearTimeout(hoverOpenTimer);
    clearTimeout(hoverCloseTimer);
    pointerInside = false;
    if (hoverOpened && !pinned) close();
  });
  localize(element);
  renderFiles();
  renderTerminal();
  renderPanel();
  return {
    setModule(module) {
      if (!["shelf", "drawer", "calendar", "music", "mirror", "usage", "agents"].includes(module) || drag) return;
      pinned = true; hoverOpened = false;
      clearTimeout(hoverOpenTimer); clearTimeout(hoverCloseTimer);
      if (module === "agents" && state.agent === "idle") {
        state.agent = "waiting";
        renderTerminal();
      }
      open(module);
      announce(element.querySelector(".ad-instruction").textContent);
      interaction("module");
    },
    setChapter(chapter) {
      const module = { shelf: "shelf", day: "calendar", ai: "usage", usage: "usage", agents: "agents" }[chapter];
      if (!module || drag) return;
      pinned = false; hoverOpened = false;
      clearTimeout(hoverOpenTimer); clearTimeout(hoverCloseTimer);
      if (module === "agents" && state.agent === "idle") {
        state.agent = "waiting";
        renderTerminal();
      }
      if (module === "shelf" && !state.shelf.length) close();
      else open(module);
    },
    reset,
    destroy() {
      destroyed = true;
      ++playRequest;
      audioEvents.forEach((type) => audio.removeEventListener(type, syncPlayback));
      audio.removeEventListener("ended", trackEnded);
      audio.removeEventListener("error", audioFailed);
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
      audio.remove();
      document.removeEventListener("pointerdown", outsidePointerDown);
      clearTimeout(hoverOpenTimer);
      clearTimeout(hoverCloseTimer);
      cueObserver.disconnect();
      canHover.removeEventListener("change", updateCue);
      cancelDrag();
    },
  };
}
