// Altillo interactive demo: a macOS desktop with the real notch UI (the kit in
// ../kit/notch.css) that you can hover, drag files onto, and play with.
// Vanilla ES module, no dependencies. Nothing real happens: sample data only
// (the three music tracks are real audio).
//
//   import { mountDemo } from "./demo/demo.js";
//   const demo = mountDemo(el, { locale: "en" });
//   demo.show("agents"); demo.on("agent-allowed", (d) => …);
//
// See README.md for the API, events and theming variables.

// Built URLs of the two stylesheets (hashed by Vite, with url()s rewritten),
// for pages that don't already link them.
import notchHref from "../kit/notch.css?url";
import demoHref from "./demo.css?url";

const KIT_ZOOM = 0.947368; // notch.css: 760 pt of app → 720 px at --an-scale 1
const SCENE_W = 1152;
const MODULES = ["shelf", "ask", "usage", "agents", "calendar", "mirror", "music"];
const ALIASES = { nowplaying: "music", "now-playing": "music", player: "music", cajon: "drawer", assistant: "ask" };
const SHELF_MAX = 8;

// ---------------------------------------------------------------- copy ----
const COPY = {
  en: {
    demoLabel: "Altillo on a sample Mac desktop",
    openAltillo: "Open Altillo", closeAltillo: "Close Altillo",
    hoverCue: "Hover the notch", tapCue: "Tap the notch",
    tabs: { shelf: "Shelf", ask: "Ask", usage: "Usage", agents: "Agents", calendar: "Calendar", mirror: "Mirror", music: "Now playing" },
    sections: "Altillo sections",
    thingsUp: (n) => (n === 1 ? "thing up there" : "things up there"),
    empty: "Empty", toDeliveries: "To Deliveries",
    shelfEmptyTitle: "Nothing up here yet", shelfEmptyText: "Drag a file onto the notch to keep it close.",
    shelfDropTitle: "Let go to put it up here", shelfDropText: "It stays on the shelf until you take it.",
    shelfFull: "The shelf is full. Take something down first.",
    onShelf: "on the shelf",
    upToDate: "Up to date · 2 min ago", refresh: "Refresh",
    week: "Week", refills: (s) => `refills in ${s}`,
    aheadOfPace: (n) => `${n} points ahead of pace`, onPace: "on pace",
    knocking: (n) => `${n} knocking`, working: (n) => `${n} working`, allQuiet: "All quiet",
    wantsCommand: (a, p) => `${a} wants to run a command in <em>${p}</em>`,
    goTerminal: "Terminal", deny: "Deny", allowSession: "Allow for this session", allowSessionShort: "Session", allow: "Allow",
    danger: "This one could be hard to undo. Hold Allow for a second to confirm.",
    holdAllow: "Hold to allow", keepHolding: "Keep holding",
    agoS: (n) => `${n} s ago`, agoMin: (n) => `${n} min ago`,
    runningTests: "Running tests · 42 of 118", done: "Done", workingLabel: "Working", stopped: "Stopped",
    doneIn: "All done. Finished in 6 min 12 s", pushing: "Pushing to origin…", pushed: "Pushed feat/notch-design",
    deniedRow: "Stopped. You said no.", waitingRow: "Waiting for your OK", removedRow: "Removed node_modules",
    join: "Join", joining: "Joining…", joined: "Joined", inMin: (n) => `in ${n} min`, joinedNote: "Simulated call · no camera, no mic",
    joinWith: (e, p) => `Join ${e} with ${p}`,
    mirrored: "Mirrored", asItIs: "As it is", flipTip: "Flip the image left to right",
    sampleCamera: "Sample portrait · camera off", portrait: "Illustrated sample portrait (the camera stays off)",
    prev: "Previous track", next: "Next track", play: "Play", pause: "Pause", progress: "Track progress",
    audioFail: "Couldn't play this track.",
    askTitle: "Ask the attic",
    askIntro: "Privately, on this Mac. I know your shelf, calendar, music, AI usage and agents, set timers and take notes.",
    askPlaceholder: "Ask about your day, your shelf, anything…", askLabel: "Ask Altillo", send: "Send", stop: "Stop",
    thinking: "Thinking…", copy: "Copy", copied: "Copied", putUp: "Put it up", saved: "Save", dictate: "Dictate, privately on this Mac",
    chips: { today: "What do I have today?", clipboard: "Explain what I copied", music: "What's playing?", summarize: (f) => `Summarize “${f}”`, can: "What can you do?" },
    drawerTip: "Choose Drawer icons", drawerOpen: (t, a) => `Open ${t} from ${a}`,
    showIcons: "Show menu bar icons", hideIcons: "Tuck menu bar icons into the Drawer",
    finder: "Documents", favourites: "Favourites", recents: "Recents", desktop: "Desktop", downloads: "Downloads", documents: "Documents",
    putOnShelf: "Put on shelf", alreadyUp: "On the shelf", items: (n) => `${n} items`,
    deliveries: "Deliveries", emptyFolder: "Empty folder", received: (n) => `${n} ${n === 1 ? "file" : "files"}`,
    deliverSelected: "Drop the selected shelf item into Deliveries",
    terminal: "altillo — claude — 80×24", askPush: "Continue: push the branch", askRm: "Try another request", again: "Run it again",
    reset: "Reset", sample: "Sample data · nothing leaves this page",
    tips: {
      closed: "Hover the notch, or drag a file from Documents onto it.",
      closedTouch: "Tap the notch, or drag a file from Documents up to it.",
      shelf: "Drag a thing from the shelf to Deliveries.",
      ask: "Pick a suggestion. Answers come from this sample day.",
      usage: "Your quota, your pace and when it refills.",
      agents: "Claude is waiting on you. Allow or deny from the notch.",
      agentsIdle: "Your agents at a glance. Ask Claude for something else in Terminal.",
      calendar: "Join is simulated: no call starts.",
      mirror: "The camera stays off: this is a drawing.",
      music: "Three original tracks, real audio.",
      drawer: "The menu bar icons now live in the Drawer strip — tap the strip to use them.",
    },
    opened: "Altillo open", closed: "Altillo closed",
    shelvedA: (f) => `${f} is on the shelf.`, deliveredA: (f) => `${f} delivered.`,
  },
  es: {
    demoLabel: "Altillo en un escritorio de Mac de ejemplo",
    openAltillo: "Abrir Altillo", closeAltillo: "Cerrar Altillo",
    hoverCue: "Acerca el cursor al notch", tapCue: "Toca el notch",
    tabs: { shelf: "Altillo", ask: "Pregunta", usage: "Uso", agents: "Agentes", calendar: "Agenda", mirror: "Espejo", music: "Sonando" },
    sections: "Secciones de Altillo",
    thingsUp: (n) => (n === 1 ? "cosa arriba" : "cosas arriba"),
    empty: "Vaciar", toDeliveries: "A Entregas",
    shelfEmptyTitle: "Aún no hay nada arriba", shelfEmptyText: "Arrastra un archivo al notch para tenerlo cerca.",
    shelfDropTitle: "Suelta para subirlo", shelfDropText: "Se queda arriba hasta que lo bajes a otro sitio.",
    shelfFull: "El altillo está lleno. Baja algo primero.",
    onShelf: "en el altillo",
    upToDate: "Al día · hace 2 min", refresh: "Actualizar",
    week: "Semana", refills: (s) => `se repone en ${s}`,
    aheadOfPace: (n) => `vas ${n} ${n === 1 ? "punto" : "puntos"} por delante del ritmo`, onPace: "a buen ritmo",
    knocking: (n) => `${n} ${n === 1 ? "llama" : "llaman"} a la puerta`, working: (n) => `${n} trabajando`, allQuiet: "Todo tranquilo",
    wantsCommand: (a, p) => `${a} quiere ejecutar un comando en <em>${p}</em>`,
    goTerminal: "Terminal", deny: "Denegar", allowSession: "Permitir en esta sesión", allowSessionShort: "Sesión", allow: "Permitir",
    danger: "Esto puede ser difícil de deshacer. Mantén Permitir un segundo para confirmar.",
    holdAllow: "Mantén para permitir", keepHolding: "Sigue pulsando",
    agoS: (n) => `hace ${n} s`, agoMin: (n) => `hace ${n} min`,
    runningTests: "Pasando tests · 42 de 118", done: "Hecho", workingLabel: "Trabajando", stopped: "Parado",
    doneIn: "Todo listo. Terminó en 6 min 12 s", pushing: "Subiendo a origin…", pushed: "Subida feat/notch-design",
    deniedRow: "Parado. Dijiste que no.", waitingRow: "Esperando tu permiso", removedRow: "node_modules eliminado",
    join: "Unirse", joining: "Uniéndote…", joined: "Dentro", inMin: (n) => `en ${n} min`, joinedNote: "Llamada simulada · sin cámara ni micro",
    joinWith: (e, p) => `Unirse a ${e} con ${p}`,
    mirrored: "Como un espejo", asItIs: "Tal cual", flipTip: "Invertir la imagen",
    sampleCamera: "Retrato de ejemplo · cámara apagada", portrait: "Retrato ilustrado de ejemplo (la cámara sigue apagada)",
    prev: "Canción anterior", next: "Canción siguiente", play: "Reproducir", pause: "Pausar", progress: "Progreso de la canción",
    audioFail: "No se pudo reproducir.",
    askTitle: "Pregúntale al altillo",
    askIntro: "En privado, en este Mac. Conozco tu altillo, tu agenda, música, uso de IA y agentes, pongo temporizadores y tomo notas.",
    askPlaceholder: "Pregunta por tu día, tu altillo, lo que sea…", askLabel: "Pregunta a Altillo", send: "Enviar", stop: "Parar",
    thinking: "Pensando…", copy: "Copiar", copied: "Copiado", putUp: "Súbelo", saved: "Guardar", dictate: "Dictar, en privado en este Mac",
    chips: { today: "¿Qué tengo hoy?", clipboard: "Explica lo que he copiado", music: "¿Qué está sonando?", summarize: (f) => `Resume «${f}»`, can: "¿Qué sabes hacer?" },
    drawerTip: "Elige los iconos del Cajón", drawerOpen: (t, a) => `Abrir ${t} de ${a}`,
    showIcons: "Mostrar iconos de la barra", hideIcons: "Guardar iconos de la barra en el Cajón",
    finder: "Documentos", favourites: "Favoritos", recents: "Recientes", desktop: "Escritorio", downloads: "Descargas", documents: "Documentos",
    putOnShelf: "Subir al altillo", alreadyUp: "En el altillo", items: (n) => `${n} elementos`,
    deliveries: "Entregas", emptyFolder: "Carpeta vacía", received: (n) => `${n} ${n === 1 ? "archivo" : "archivos"}`,
    deliverSelected: "Dejar lo seleccionado del altillo en Entregas",
    terminal: "altillo — claude — 80×24", askPush: "Continuar: subir la rama", askRm: "Probar otra solicitud", again: "Repetir",
    reset: "Reiniciar", sample: "Datos de ejemplo · nada sale de esta página",
    tips: {
      closed: "Acerca el cursor al notch o arrastra un archivo de Documentos hasta él.",
      closedTouch: "Toca el notch o arrastra un archivo de Documentos hasta él.",
      shelf: "Arrastra algo del altillo a Entregas.",
      ask: "Elige una sugerencia. Las respuestas salen de este día de ejemplo.",
      usage: "Tu cuota, tu ritmo y cuándo se recarga.",
      agents: "Claude te espera. Permite o deniega desde el notch.",
      agentsIdle: "Tus agentes de un vistazo. Pídele otra cosa a Claude en Terminal.",
      calendar: "Unirse es simulado: no empieza ninguna llamada.",
      mirror: "La cámara sigue apagada: es un dibujo.",
      music: "Tres canciones originales, audio real.",
      drawer: "Los iconos de la barra viven ahora en el Cajón — toca la tira para usarlos.",
    },
    opened: "Altillo abierto", closed: "Altillo cerrado",
    shelvedA: (f) => `${f} está en el altillo.`, deliveredA: (f) => `${f} entregado.`,
  },
};

// ----------------------------------------------------------- sample data ----
const FILES_EN = [
  { id: "proposal", name: "Proposal – Altillo v2.pdf", short: "Propo…Altillo v2", thumb: "pdf", tilt: 0.6, meta: "PDF · 1.2 MB" },
  { id: "shot", name: "Screenshot 10.24.12.png", short: "Screen…10.24.12", thumb: "image", tilt: -0.8, meta: "PNG · 840 KB" },
  { id: "notes", name: "meeting-notes.txt", short: "meeting-notes", thumb: "text", tilt: 1.2, meta: "Text · 4 KB" },
  { id: "assets", name: "altillo-assets.zip", short: "altillo-assets", thumb: "zip", tilt: 0, meta: "ZIP · 18 MB" },
  { id: "link", name: "getseam.app", short: "getseam.app", thumb: "postcard", tilt: -1.3, meta: "Link" },
  { id: "idea", name: "Check the drag matrix before Friday", short: "Check the drag matrix", thumb: "note", tilt: 1, meta: "Text clipping" },
  { id: "invoice", name: "Invoice 0924.pdf", short: "Invoice 0924", thumb: "pdf", tilt: -0.5, meta: "PDF · 96 KB" },
  { id: "holiday", name: "Menorca.jpg", short: "Menorca", thumb: "image", tilt: 0.9, meta: "JPEG · 3.1 MB", hue: 150 },
];
const EVENTS_EN = [
  { title: "Design review", when: "3:00 – 3:30 PM", place: "Studio", provider: "Google Meet", cal: "sky", mins: 12 },
  { title: "Final hand-off", time: "4:00 PM", cal: "sage" },
  { title: "Climbing with Marta", time: "6:30 PM", place: "Sharma Gym", cal: "rose" },
];
// Spanish sample data: same ids, so initialShelf and events line up.
const FILES_ES = [
  { id: "proposal", name: "Propuesta – Altillo v2.pdf", short: "Propu…Altillo v2", thumb: "pdf", tilt: 0.6, meta: "PDF · 1,2 MB" },
  { id: "shot", name: "Captura 10.24.12.png", short: "Captura…10.24.12", thumb: "image", tilt: -0.8, meta: "PNG · 840 KB" },
  { id: "notes", name: "notas-reunión.txt", short: "notas-reunión", thumb: "text", tilt: 1.2, meta: "Texto · 4 KB" },
  { id: "assets", name: "altillo-assets.zip", short: "altillo-assets", thumb: "zip", tilt: 0, meta: "ZIP · 18 MB" },
  { id: "link", name: "getseam.app", short: "getseam.app", thumb: "postcard", tilt: -1.3, meta: "Enlace" },
  { id: "idea", name: "Revisar la matriz de arrastre antes del viernes", short: "Revisar la matriz", thumb: "note", tilt: 1, meta: "Recorte de texto" },
  { id: "invoice", name: "Factura 0924.pdf", short: "Factura 0924", thumb: "pdf", tilt: -0.5, meta: "PDF · 96 KB" },
  { id: "holiday", name: "Menorca.jpg", short: "Menorca", thumb: "image", tilt: 0.9, meta: "JPEG · 3,1 MB", hue: 150 },
];
const EVENTS_ES = [
  { title: "Revisión de diseño", when: "15:00 – 15:30", place: "Estudio", provider: "Google Meet", cal: "sky", mins: 12 },
  { title: "Entrega final", time: "16:00", cal: "sage" },
  { title: "Escalada con Marta", time: "18:30", place: "Rocódromo Sharma", cal: "rose" },
];
const TRACKS = [
  { title: "Azotea", file: "azotea.mp3", art: "AZOTEA" },
  { title: "Luz de tarde", file: "luz-de-tarde.mp3", art: "LUZ DE TARDE" },
  { title: "Último tranvía", file: "ultimo-tranvia.mp3", art: "ÚLTIMO TRANVÍA" },
];
const CLIPBOARD = "TypeError: Cannot read properties of undefined (reading 'map') at routes.ts:42";
const DRAWER_EN = [
  { id: "icloud", icon: "cloud", title: "iCloud Drive", app: "Finder", status: "Up to date", items: ["Open iCloud Drive", "Pause syncing"] },
  { id: "vpn", icon: "shield", title: "VPN", app: "Tailscale", status: "Connected · altillo-mini", items: ["Disconnect", "Exit node: none"] },
  { id: "focus", icon: "moon", title: "Focus", app: "Control Center", status: "Do Not Disturb · off", items: ["Do Not Disturb", "Work"] },
];
const DRAWER_ES = [
  { id: "icloud", icon: "cloud", title: "iCloud Drive", app: "Finder", status: "Al día", items: ["Abrir iCloud Drive", "Pausar la sincronización"] },
  { id: "vpn", icon: "shield", title: "VPN", app: "Tailscale", status: "Conectada · altillo-mini", items: ["Desconectar", "Nodo de salida: ninguno"] },
  { id: "focus", icon: "moon", title: "Concentración", app: "Centro de control", status: "No molestar · desactivado", items: ["No molestar", "Trabajo"] },
];
// Everything else on the sample desktop that speaks: menu bar, clock and
// Claude Code's side of the terminal (commands and npm/git output stay as-is).
const SCENE = {
  en: {
    menus: ["File", "Edit", "View", "Go"], clock: "Sat 27 Sep&nbsp;&nbsp;2:48 PM",
    prompt: "ship the notch redesign", ran: "Ran 128 tests <span class=\"t-ok\">— all passing</span>", committed: "Committed 3 files on <b>feat/notch-design</b>",
    pushWhy: "Pushing the branch so the PR can open.", rmWhy: "Clean install to fix the lockfile drift.",
    bash: "Bash command", proceed: "Do you want to proceed?", waiting: "Waiting for you in Altillo…",
    denied: "<span class=\"t-bad\">⎿  Denied in Altillo.</span> Nothing ran.", stopping: "Understood — stopping here.",
    pushed: "<span class=\"t-ok\">Pushed.</span> The PR is ready for review.", installed: "<span class=\"t-ok\">Clean install done.</span> Lockfile matches.",
  },
  es: {
    menus: ["Archivo", "Edición", "Visualización", "Ir"], clock: "sáb 27 sept&nbsp;&nbsp;14:48",
    prompt: "publica el rediseño del notch", ran: "128 tests ejecutados <span class=\"t-ok\">— todos en verde</span>", committed: "3 archivos confirmados en <b>feat/notch-design</b>",
    pushWhy: "Subo la rama para poder abrir la PR.", rmWhy: "Instalación limpia para arreglar el desfase del lockfile.",
    bash: "Comando Bash", proceed: "¿Quieres continuar?", waiting: "Esperando tu respuesta en Altillo…",
    denied: "<span class=\"t-bad\">⎿  Denegado en Altillo.</span> No se ha ejecutado nada.", stopping: "Entendido, lo dejo aquí.",
    pushed: "<span class=\"t-ok\">Subida.</span> La PR está lista para revisión.", installed: "<span class=\"t-ok\">Instalación limpia hecha.</span> El lockfile cuadra.",
  },
};
const SAMPLE = {
  en: { files: FILES_EN, events: EVENTS_EN, drawer: DRAWER_EN, scene: SCENE.en },
  es: { files: FILES_ES, events: EVENTS_ES, drawer: DRAWER_ES, scene: SCENE.es },
};
const REQUESTS = {
  push: { tool: "Bash", cmd: "git push origin feat/notch-design", danger: false },
  rm: { tool: "Bash", cmd: "rm -rf node_modules && npm ci", danger: true },
};

// ------------------------------------------------------------ helpers ------
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const icon = (name, extra = "") => `<i class="an-i an-i--${name}${extra ? " " + extra : ""}" aria-hidden="true"></i>`;
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

// SwiftUI spring(duration:bounce:) sampled into a CSS linear() easing.
function spring(duration, bounce) {
  const zeta = 1 - bounce;
  const w0 = (2 * Math.PI) / duration;
  const wd = w0 * Math.sqrt(Math.max(1e-6, 1 - zeta * zeta));
  const x = (t) =>
    zeta < 1
      ? 1 - Math.exp(-zeta * w0 * t) * (Math.cos(wd * t) + ((zeta * w0) / wd) * Math.sin(wd * t))
      : 1 - Math.exp(-w0 * t) * (1 + w0 * t);
  let T = duration * 1.6;
  for (let t = 0.1; t < 3; t += 0.01) {
    let ok = true;
    for (let u = t; u < t + 0.25; u += 0.01) if (Math.abs(x(u) - 1) > 0.003) { ok = false; break; }
    if (ok) { T = t; break; }
  }
  const n = 40;
  const pts = [];
  for (let i = 0; i <= n; i++) pts.push(i === n ? 1 : Math.round(x((T * i) / n) * 10000) / 10000);
  return { easing: `linear(${pts.join(", ")})`, ms: Math.round(T * 1000) };
}
const SPRING_OPEN = spring(0.4, 0.3);
const SPRING_SECTION = spring(0.32, 0.15);
const SPRING_FOCUS = spring(0.3, 0);

function ensureStyles() {
  // Each stylesheet sets a marker property on :root, so a page that already
  // has them (linked, or bundled under a hashed name by a build) is left alone.
  const root = getComputedStyle(document.documentElement);
  const want = [
    ["--an-kit", new URL(notchHref, location.href).href],
    ["--dm-kit", new URL(demoHref, location.href).href],
  ];
  const have = [...document.querySelectorAll('link[rel="stylesheet"]')].map((l) => l.href);
  for (const [marker, href] of want) {
    if (root.getPropertyValue(marker).trim() || have.includes(href)) continue;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = href;
    document.head.append(link);
  }
}

function thumbMarkup(file) {
  const style = `--an-tilt:${file.tilt || 0}deg${file.hue ? `;filter:hue-rotate(${file.hue}deg)` : ""}`;
  if (file.thumb === "postcard") return `<div class="an-thumb an-thumb--postcard" style="${style}"><span>${esc(file.name)}</span></div>`;
  if (file.thumb === "note") return `<div class="an-thumb an-thumb--note" style="${style}"><span>${esc(file.name)}</span></div>`;
  return `<div class="an-thumb an-thumb--${file.thumb}" style="${style}"></div>`;
}

const PORTRAIT = `
<svg viewBox="0 0 256 144" preserveAspectRatio="xMidYMid slice" role="img" focusable="false">
  <defs>
    <linearGradient id="dmw" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#e9dcc7"/><stop offset="1" stop-color="#bfa98f"/></linearGradient>
    <radialGradient id="dml" cx="0.12" cy="0.2" r="0.7"><stop stop-color="#fff3d6" stop-opacity=".85"/><stop offset="1" stop-color="#fff3d6" stop-opacity="0"/></radialGradient>
    <linearGradient id="dms" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#3d5a6c"/><stop offset="1" stop-color="#26394a"/></linearGradient>
  </defs>
  <rect width="256" height="144" fill="url(#dmw)"/>
  <rect x="14" y="10" width="54" height="74" rx="2" fill="#f7efe0" stroke="#9c8568" stroke-width="3"/>
  <path d="M41 10v74M14 47h54" stroke="#9c8568" stroke-width="2"/>
  <rect width="256" height="144" fill="url(#dml)"/>
  <rect x="198" y="30" width="44" height="30" rx="2" fill="#6f8a69"/><circle cx="228" cy="40" r="6" fill="#e9a24f"/>
  <path d="M198 60l14-14 10 9 8-6 12 11z" fill="#3f5347"/>
  <g transform="translate(206 86)"><path d="M14 44 12 8M13 26 2 16M13 32l12-15" stroke="#4d6a4b" stroke-width="3" fill="none"/><ellipse cx="3" cy="15" rx="9" ry="4" transform="rotate(34 3 15)" fill="#6c8a5f"/><ellipse cx="25" cy="15" rx="10" ry="4.5" transform="rotate(-38 25 15)" fill="#5b7753"/><path d="M2 40h24l-4 18H6z" fill="#b0714d"/></g>
  <path d="M0 128h256v16H0z" fill="#6d5846"/>
  <g>
    <path d="M84 144c3-34 18-52 44-52s41 18 44 52z" fill="url(#dms)"/>
    <path d="M116 92q12 14 24 0l-3 16h-18z" fill="#c78d6c"/>
    <ellipse cx="128" cy="66" rx="22" ry="26" fill="#dca184"/>
    <path d="M105 66c-2-24 10-37 26-36 17 1 26 14 22 34-5-4-7-11-7-18-10 6-22 8-38 7-1 5-2 9-3 13z" fill="#3b2a24"/>
    <circle cx="120" cy="68" r="2" fill="#2e211c"/><circle cx="137" cy="68" r="2" fill="#2e211c"/>
    <path d="M122 79q6 4 12 0" fill="none" stroke="#9b5e4d" stroke-width="2" stroke-linecap="round"/>
    <path d="M104 56c4-9 12-14 20-15" stroke="#5a4038" stroke-width="2" fill="none" opacity=".6"/>
  </g>
</svg>`;

// ================================================================ mount ====
export function mountDemo(root, options = {}) {
  if (!root) throw new Error("mountDemo: missing element");
  ensureStyles();
  const lang = String(options.locale || document.documentElement.lang || "en").toLowerCase().startsWith("es") ? "es" : "en";
  const t = COPY[lang];
  const { files: FILES, events: EVENTS, drawer: DRAWER_ITEMS, scene: X } = SAMPLE[lang];
  const mediaBase = options.mediaBase || "/media/music/";
  const withCaption = options.caption !== false;
  const autoAgent = options.autoAgent !== false;
  // Optional ids from FILES that start on the shelf (and return there on reset).
  const initialShelf = Array.isArray(options.initialShelf) ? options.initialShelf.slice() : [];

  const mqHover = matchMedia("(hover: hover) and (pointer: fine)");
  const mqReduce = matchMedia("(prefers-reduced-motion: reduce)");
  const timers = new Set();
  const later = (fn, ms) => { const id = setTimeout(() => { timers.delete(id); fn(); }, ms); timers.add(id); return id; };
  const cancel = (id) => { clearTimeout(id); timers.delete(id); };
  let destroyed = false;

  const S = {
    compact: false,
    open: false,
    module: "shelf",
    pinned: false,
    via: null,
    shelf: initialShelf.slice(),
    shelfSel: null,
    landing: null,
    dropLit: false,
    finderSel: "proposal",
    delivered: [],
    drawer: { tucked: false, menu: null, flash: false },
    agent: { phase: "idle", req: "push", since: 0, holding: false },
    session: { status: "idle", text: "" },
    term: [],
    cal: "idle",
    mirror: true,
    music: { track: 0, playing: false, t: 0, d: [50, 54, 48], err: false, played: new Set(), all: false },
    ask: { log: [], busy: false, draft: "" },
    usage: { claude: 85, codex: 34, wClaude: 41, wCodex: 58, shown: false },
  };

  // --------------------------------------------------------- skeleton ----
  root.classList.add("dm");
  root.setAttribute("lang", lang);
  root.innerHTML = `
    <div class="dm-frame">
      <div class="dm-screen" role="group" aria-label="${esc(t.demoLabel)}">
        <div class="dm-scene">
          <div class="dm-menubar">
            <div class="dm-menubar__side"><span class="dm-mb-icon">${icon("apple")}</span><b>Finder</b>${X.menus.map((m) => `<span class="dm-mb-menus">${m}</span>`).join("")}</div>
            <div class="dm-menubar__side">
              <div class="dm-tray">
                <div class="dm-tray__items" aria-hidden="false">${DRAWER_ITEMS.map((d) => `<span class="dm-mb-icon" title="${esc(d.title)}">${icon(d.icon)}</span>`).join("")}</div>
                <span class="dm-tray__divider" aria-hidden="true"></span>
                <button type="button" class="dm-tray__toggle" data-act="drawer-toggle" aria-pressed="false" aria-label="${esc(t.hideIcons)}">${icon("caret-right")}</button>
              </div>
              <span class="dm-mb-icon dm-mb-sys">${icon("wifi")}</span><span class="dm-mb-icon dm-mb-sys">${icon("battery")}</span><span class="dm-mb-icon dm-mb-sys">${icon("search")}</span>
              <span class="dm-clock">${X.clock}</span>
            </div>
          </div>

          <section class="dm-window dm-finder" aria-label="Finder — ${esc(t.finder)}">
            <div class="dm-finder__side">
              <div class="dm-traffic" aria-hidden="true"><i></i><i></i><i></i></div>
              <small>${esc(t.favourites)}</small>
              <span>${icon("recent")}${esc(t.recents)}</span><span>${icon("desktop")}${esc(t.desktop)}</span><span class="is-current">${icon("folder")}${esc(t.documents)}</span><span>${icon("download")}${esc(t.downloads)}</span>
            </div>
            <div class="dm-finder__main">
              <div class="dm-titlebar"><span class="dm-traffic dm-traffic--compact" aria-hidden="true"><i></i><i></i><i></i></span><span class="dm-titlebar__title">${esc(t.finder)}</span></div>
              <div class="dm-files" role="listbox" aria-label="${esc(t.finder)}"></div>
              <div class="dm-finder__foot"><span class="dm-finder__meta"></span><button type="button" class="dm-pill" data-act="shelve">${icon("arrow-up")}<span>${esc(t.putOnShelf)}</span></button></div>
            </div>
          </section>

          <div class="dm-lower">
          <button type="button" class="dm-desk-icon dm-deliveries" data-act="deliver" data-drop="deliveries" aria-label="${esc(t.deliveries)}: ${esc(t.deliverSelected)}">
            <span class="dm-folder"><b class="dm-folder__count"></b></span><span>${esc(t.deliveries)}</span><small class="dm-deliveries__meta">${esc(t.emptyFolder)}</small>
          </button>

          <section class="dm-window dm-terminal" aria-label="Terminal — Claude Code">
            <div class="dm-titlebar"><span class="dm-traffic" aria-hidden="true"><i></i><i></i><i></i></span><span class="dm-titlebar__title">${esc(t.terminal)}</span></div>
            <div class="dm-term" aria-live="polite"></div>
          </section>

          </div>

          <div class="dm-dock" aria-hidden="true"><i class="d-finder is-running"></i><i class="d-safari"></i><i class="d-notes"></i><i class="d-term is-running"></i><i class="d-altillo is-running"></i><i class="d-sep"></i><i class="d-trash">${icon("folder")}</i></div>

          <button type="button" class="dm-cue" data-act="open">${icon("arrow-up")}<span class="dm-cue__label"></span></button>

          <div class="an dm-notch-holder">
            <div class="an-notch dm-notch" data-state="closed">
              <div class="dm-hoverzone" aria-hidden="true"></div>
              <button type="button" class="dm-notch-btn" aria-expanded="false" aria-label="${esc(t.openAltillo)}"></button>
              <div class="dm-clip"><div class="dm-ears" aria-hidden="true"></div><div class="dm-open" hidden></div></div>
            </div>
          </div>
        </div>
      </div>
    </div>
    ${withCaption ? `<div class="dm-caption"><p class="dm-tip"></p><button type="button" data-act="reset">${esc(t.reset)}</button></div>` : ""}
    <p class="dm-sr" role="status" aria-live="polite"></p>`;

  const $ = (sel) => root.querySelector(sel);
  const scene = $(".dm-scene");
  const screen = $(".dm-screen");
  const holder = $(".dm-notch-holder");
  const notch = $(".dm-notch");
  const openEl = $(".dm-open");
  const earsEl = $(".dm-ears");
  const notchBtn = $(".dm-notch-btn");
  const status = $(".dm-sr");
  const audio = new Audio();
  audio.preload = "none";

  const announce = (msg) => { status.textContent = ""; later(() => (status.textContent = msg), 30); };
  function emit(type, detail = {}) {
    root.dispatchEvent(new CustomEvent("altillo-demo", { bubbles: true, detail: { type, ...detail } }));
  }
  root.classList.toggle("dm--reduce", mqReduce.matches);
  root.style.setProperty("--dm-spring-open", SPRING_OPEN.easing);
  root.style.setProperty("--dm-spring-open-ms", SPRING_OPEN.ms + "ms");
  root.style.setProperty("--dm-spring-section", SPRING_SECTION.easing);
  root.style.setProperty("--dm-spring-section-ms", SPRING_SECTION.ms + "ms");
  root.style.setProperty("--dm-spring-focus", SPRING_FOCUS.easing);
  root.style.setProperty("--dm-spring-focus-ms", SPRING_FOCUS.ms + "ms");

  // ----------------------------------------------------------- layout ----
  let kitW = 732; // open body width in kit px (fillets excluded)
  function layout() {
    const w = root.clientWidth;
    const compact = w <= 700;
    if (compact !== S.compact) {
      S.compact = compact;
      root.classList.toggle("dm--compact", compact);
    }
    if (compact) {
      const sw = screen.clientWidth;
      scene.style.removeProperty("--dm-z");
      // Slightly over 1 so the smallest kit text (11.5 pt) renders ≥ 11 px.
      root.style.setProperty("--dm-an", "1.03");
      // Fill the screen minus a little air, in kit px (the fillets hang outside).
      kitW = Math.max(300, Math.floor((sw - 8) / (KIT_ZOOM * 1.03)) - 28);
    } else {
      const sw = screen.clientWidth;
      const z = sw / SCENE_W;
      scene.style.setProperty("--dm-z", z.toFixed(4));
      // Keep the notch legible when the scene is small: text ≥ ~0.85× of real.
      const an = Math.min(1.5, Math.max(1, 0.85 / (KIT_ZOOM * z)));
      root.style.setProperty("--dm-an", an.toFixed(3));
      kitW = 732;
    }
    sizeNotch(false);
    updateCue();
  }

  // ---------------------------------------------------- notch geometry ----
  const BODY_H = { shelf: 150, shelfEmpty: 130, usage: 160, agents: 220, ask: 200, calendar: 180, mirror: 180, music: 180 };
  const BODY_H_COMPACT = { usage: 262, ask: 220, mirror: 150, music: 170, calendar: 150 };
  function bodyH(mod = S.module) {
    if (mod === "shelf") return S.shelf.length || S.dropLit ? BODY_H.shelf : BODY_H.shelfEmpty;
    if (S.compact && mod === "agents") return S.agent.phase !== "waiting" ? 136 : REQUESTS[S.agent.req].danger ? 236 : 196;
    if (S.compact && BODY_H_COMPACT[mod]) return BODY_H_COMPACT[mod];
    if (mod === "agents") return S.agent.phase === "waiting" && REQUESTS[S.agent.req].danger ? 236 : BODY_H.agents;
    return BODY_H[mod];
  }
  const tabsOnRow = () => S.compact || S.drawer.tucked;
  function openHeight() {
    let h = 32;
    if (S.drawer.tucked) h += 8 + 46;
    if (tabsOnRow()) h += 8 + 32;
    return h + 8 + bodyH() + 16;
  }
  function sizeNotch(animate = true) {
    notch.classList.toggle("dm-no-anim", !animate);
    if (S.open) {
      notch.style.setProperty("--an-w", kitW + "px");
      notch.style.height = openHeight() + "px";
      openEl.style.width = kitW + "px";
    } else {
      notch.style.setProperty("--an-w", (S.compact ? 289 : 321) + "px");
      notch.style.height = "32px";
    }
    // Compact: the desktop makes room under the open notch, so the Finder
    // row stays visible (and draggable) while the shelf is open.
    const an = parseFloat(root.style.getPropertyValue("--dm-an")) || 1;
    root.style.setProperty("--dm-push", S.compact && S.open ? `${Math.ceil(openHeight() * KIT_ZOOM * an)}px` : "0px");
    if (!animate) { void notch.offsetWidth; notch.classList.remove("dm-no-anim"); }
  }

  // ------------------------------------------------------------ ears ----
  function renderEars() {
    const ring = `<span class="an-ring an-ear-ring is-warning"><svg viewBox="0 0 100 100" aria-hidden="true"><circle class="an-ring__track" cx="50" cy="50" r="41.4" stroke-width="17.1"/><circle class="an-ring__arc" cx="50" cy="50" r="41.4" stroke-width="17.1" pathLength="100" stroke-dasharray="${S.usage.claude} 100" transform="rotate(-90 50 50)"/></svg></span><span style="color: var(--an-mustard)">${S.usage.claude}</span>`;
    let right;
    if (S.agent.phase === "waiting") right = `<i class="an-knock dm-ear-knock"></i><span class="an-amber">1</span>`;
    else if (S.dropLit) right = `<i class="an-house"></i><span class="an-amber">+</span>`;
    else if (S.music.playing) right = `<span class="dm-eq"><i></i><i></i><i></i></span>`;
    else if (S.session.status === "working") right = `<span class="an-dots an-dots--sm an-dots--live"><i></i><i></i><i></i></span><span>1</span>`;
    else right = `<i class="an-house${S.shelf.length ? "" : " an-house--off"}"></i><span>${S.shelf.length}</span>`;
    earsEl.innerHTML = `<span class="an-ear">${ring}</span><span class="an-ear">${right}</span>`;
    notchBtn.setAttribute("aria-label", `${t.openAltillo} · ${S.shelf.length} ${t.thingsUp(S.shelf.length)}${S.agent.phase === "waiting" ? " · " + t.knocking(1) : ""}`);
  }

  // ------------------------------------------------------ open content ----
  function tabsMarkup() {
    const dense = !tabsOnRow() ? " an-tabs--dense" : "";
    return `<nav class="an-tabs${dense}" role="tablist" aria-label="${esc(t.sections)}">${MODULES.map((m) => {
      const active = m === S.module;
      const ic =
        m === "shelf" ? `<i class="an-house" aria-hidden="true"></i>`
        : m === "agents" ? (S.agent.phase === "waiting" ? `<i class="an-knock dm-tab-knock" aria-hidden="true"></i>` : icon("hand"))
        : icon({ ask: "sparkle", usage: "gauge", calendar: "calendar", mirror: "person-square", music: "music" }[m]);
      return `<button type="button" role="tab" class="an-tab${active ? " is-active" : ""}" data-tab="${m}" id="dm-tab-${m}-${uid}" aria-selected="${active}" aria-controls="dm-panel-${uid}" tabindex="${active ? 0 : -1}" title="${esc(t.tabs[m])}" data-k="tab-${m}">${ic}${active ? `<span>${esc(t.tabs[m])}</span>` : `<span class="dm-sr">${esc(t.tabs[m])}</span>`}</button>`;
    }).join("")}</nav>`;
  }
  function accessoryMarkup() {
    const gear = `<span class="an-accessory__gear" aria-hidden="true">${icon("gear")}</span>`;
    if (S.compact) {
      if (S.module === "shelf") return `<div class="an-accessory"><span class="dm-acc-count" aria-label="${S.shelf.length} ${esc(t.thingsUp(S.shelf.length))}"><i class="an-house${S.shelf.length ? "" : " an-house--off"}"></i><b class="an-figure">${S.shelf.length}</b></span>${gear}</div>`;
      if (S.module === "agents" && S.agent.phase === "waiting") return `<div class="an-accessory"><span class="an-amber">${esc(t.knocking(1))}</span></div>`;
      if (S.module === "usage") return `<div class="an-accessory"><button type="button" class="an-accessory__refresh" data-act="refresh" aria-label="${esc(t.refresh)}" data-k="refresh">${icon("refresh")}</button>${gear}</div>`;
      return `<div class="an-accessory">${gear}</div>`;
    }
    switch (S.module) {
      case "shelf":
        return `<div class="an-accessory"><span><b class="an-figure">${S.shelf.length}</b> ${esc(t.thingsUp(S.shelf.length))}</span>${S.shelfSel ? `<button type="button" class="an-btn an-btn--quiet" data-act="deliver" data-k="to-del">${icon("folder")}${esc(t.toDeliveries)}</button>` : ""}${S.shelf.length ? `<button type="button" class="an-btn an-btn--quiet" data-act="empty" data-k="empty">${esc(t.empty)}</button>` : ""}${gear}</div>`;
      case "usage":
        return `<div class="an-accessory"><span class="an-dot"></span><span>${esc(t.upToDate)}</span><button type="button" class="an-accessory__refresh" data-act="refresh" aria-label="${esc(t.refresh)}" data-k="refresh">${icon("refresh")}</button>${gear}</div>`;
      case "agents": {
        const k = S.agent.phase === "waiting" ? 1 : 0;
        const w = 1 + (S.session.status === "working" ? 1 : 0);
        return `<div class="an-accessory"><span class="an-accessory__agents">${k ? `<span class="an-amber">${esc(t.knocking(k))}</span>` : ""}<span>${esc(t.working(w))}</span></span>${gear}</div>`;
      }
      default:
        return `<div class="an-accessory">${gear}</div>`;
    }
  }
  function drawerMarkup() {
    if (!S.drawer.tucked) return "";
    const menu = S.drawer.menu ? DRAWER_ITEMS.find((d) => d.id === S.drawer.menu) : null;
    const idx = menu ? DRAWER_ITEMS.indexOf(menu) : 0;
    return `<div class="an-drawer${S.drawer.flash ? " dm-flash" : ""}">
      <span class="an-drawer__mark">${icon("archive")}</span>
      <div class="an-drawer__icons">${DRAWER_ITEMS.map((d) => `<button type="button" class="an-drawer__icon${S.drawer.menu === d.id ? " is-open" : ""}" data-act="drawer-item" data-id="${d.id}" data-k="dr-${d.id}" aria-haspopup="menu" aria-expanded="${S.drawer.menu === d.id}" aria-label="${esc(t.drawerOpen(d.title, d.app))}" title="${esc(d.title)}">${icon(d.icon)}</button>`).join("")}</div>
      <button type="button" class="an-drawer__gear" data-act="drawer-toggle" data-k="dr-gear" aria-label="${esc(t.showIcons)}" title="${esc(t.drawerTip)}">${icon("sliders")}</button>
      ${menu ? `<div class="an-menu" role="menu" style="left:${34 + idx * 34}px"><div class="an-menu__head">${icon(menu.icon)}<div><b>${esc(menu.title)}</b><small>${esc(menu.status)}</small></div></div><div class="an-menu__sep"></div>${menu.items.map((it, i) => `<button type="button" role="menuitem" class="an-menu__item" data-act="drawer-menu-item" data-k="dm-${i}">${esc(it)}</button>`).join("")}</div>` : ""}
    </div>`;
  }
  function renderOpen() {
    const row = tabsOnRow();
    openEl.innerHTML = `
      <header class="an-band">${row ? "<span></span>" : tabsMarkup()}${accessoryMarkup()}</header>
      ${drawerMarkup()}
      ${row ? `<div class="an-tabrow">${tabsMarkup()}</div>` : ""}
      <div class="an-body an-body--${S.module === "calendar" || S.module === "mirror" || S.module === "music" ? "module" : S.module} dm-body" id="dm-panel-${uid}" role="tabpanel" aria-labelledby="dm-tab-${S.module}-${uid}" style="--an-body-h:${bodyH()}px">${moduleMarkup()}</div>`;
  }
  const uid = Math.random().toString(36).slice(2, 7);

  // ----------------------------------------------------------- modules ----
  function moduleMarkup() {
    switch (S.module) {
      case "shelf": return shelfMarkup();
      case "usage": return usageMarkup();
      case "agents": return agentsMarkup();
      case "calendar": return calendarMarkup();
      case "music": return musicMarkup();
      case "mirror": return mirrorMarkup();
      case "ask": return askMarkup();
    }
    return "";
  }
  function shelfMarkup() {
    const lit = S.dropLit ? " an-card--lit" : "";
    if (!S.shelf.length) {
      return `<div class="an-card an-shelf${lit}" data-drop="shelf"><div class="an-shelf-empty"><i class="an-house${S.dropLit ? "" : " an-house--off"}"></i><div><h3>${esc(S.dropLit ? t.shelfDropTitle : t.shelfEmptyTitle)}</h3><p>${esc(S.dropLit ? t.shelfDropText : t.shelfEmptyText)}</p></div></div></div>`;
    }
    const fit = S.compact ? Math.floor((kitW - 44) / 110) : 6;
    const more = S.shelf.length > fit ? " an-shelf--more" : "";
    return `<div class="an-card an-shelf${lit}${more}" data-drop="shelf"><div class="an-plank"></div><div class="an-shelf__row" role="listbox" aria-label="${esc(t.tabs.shelf)}">${S.shelf.map((id) => {
      const f = FILES.find((x) => x.id === id);
      const sel = S.shelfSel === id;
      return `<button type="button" role="option" class="an-tile${sel ? " is-selected" : ""}${S.landing === id ? " an-tile--landing" : ""}" data-shelf="${id}" data-k="sh-${id}" aria-selected="${sel}" aria-label="${esc(f.name)}, ${esc(t.onShelf)}"><div class="an-tile__thing">${thumbMarkup(f)}${sel ? '<span class="an-tile__pool"></span>' : ""}</div><div class="an-tile__name">${esc(f.short)}</div></button>`;
    }).join("")}</div></div>`;
  }
  function ringSvg(v, pace, cls) {
    return `<div class="an-ring ${cls}"><svg viewBox="0 0 100 100" aria-hidden="true"><circle class="an-ring__track" cx="50" cy="50" r="47" stroke-width="6"/><circle class="an-ring__arc dm-arc" cx="50" cy="50" r="47" stroke-width="6" pathLength="100" stroke-dasharray="${S.usage.shown ? v : 0} 100" data-v="${v}" transform="rotate(-90 50 50)"/><line class="an-ring__pace" x1="50" y1="-1.5" x2="50" y2="7.5" stroke-width="1.5" transform="rotate(${pace * 3.6} 50 50)"/></svg><span class="an-ring__figure"><span class="dm-count" data-v="${v}">${S.usage.shown ? v : 0}</span><small>%</small></span></div>`;
  }
  function usageMarkup() {
    const u = S.usage;
    const card = (name, glyph, plan, v, pace, refill, paceText, paceCls, week, weekPace, left) => `
      <article class="an-card an-usage-card" aria-label="${name}: ${v} %">
        <div class="an-usage-card__top">${ringSvg(v, pace, v >= 95 ? "is-critical" : v >= 80 ? "is-warning" : "")}
          <div class="an-usage-card__text">
            <div class="an-usage-card__title"><i class="an-glyph an-glyph--${glyph}"></i><span class="an-usage-card__name">${name}</span><span class="an-chip">${plan}</span><span class="an-usage-card__length">5 h</span></div>
            <div class="an-usage-card__refill">${esc(t.refills(refill))}</div>
            <div class="an-pace ${paceCls}">${esc(paceText)}</div>
          </div>
        </div>
        <div class="an-bar-row"><span class="an-bar-row__label">${esc(t.week)}</span><span class="an-bar dm-bar" style="--v:${u.shown ? week : 0}; --pace:${weekPace}" data-v="${week}"></span><span class="an-bar-row__value">${week} %</span><span class="an-bar-row__left">${left}</span></div>
      </article>`;
    return `<div class="an-usage">${card("Claude", "claude", "Max 20×", u.claude, u.claude - 9, "1 h 11 min", t.aheadOfPace(u.claude - 76), "an-pace--warning", u.wClaude, 0.55, "3 d 3 h")}${card("Codex", "codex", "Pro", u.codex, 36, "3 h 4 min", t.onPace, "", u.wCodex, 0.8, "1 d 8 h")}</div>`;
  }
  function agentsMarkup() {
    const a = S.agent;
    const req = REQUESTS[a.req];
    let card = "";
    if (a.phase === "waiting") {
      const ago = Math.max(1, Math.round((Date.now() - a.since) / 1000));
      const session = S.compact ? t.allowSessionShort : t.allowSession;
      card = `<article class="an-card an-card--lit an-agent-card" aria-label="${esc(t.wantsCommand("Claude", "altillo").replace(/<[^>]+>/g, ""))}: ${esc(req.cmd)}">
        <i class="an-glyph an-glyph--claude" style="--s:${S.compact ? 22 : 26}px"></i>
        <div class="an-agent-card__main">
          <div class="an-agent-card__head"><span class="an-agent-card__ask">${t.wantsCommand("Claude", "altillo")}</span><span class="an-agent-card__meta"><i class="an-knock dm-card-knock"></i><span class="an-ago dm-ago">${esc(t.agoS(ago))}</span></span></div>
          <div class="an-slip${req.danger ? " is-danger" : ""}"><span class="an-slip__tool">${req.tool}</span><span class="an-slip__cmd">${esc(req.cmd)}</span></div>
          ${req.danger ? `<div class="an-danger-note">${esc(t.danger)}</div>` : ""}
          <div class="an-agent-card__actions">
            <span class="an-btn an-btn--quiet an-btn--28 dm-hide-compact" style="font-size:12.5px">${icon("open-app")}${esc(t.goTerminal)}</span>
            <span class="an-spacer"></span>
            <button type="button" class="an-btn an-btn--ghost an-btn--28" data-act="deny" data-k="deny">${esc(t.deny)}</button>
            ${req.danger ? `<button type="button" class="an-btn an-btn--hold an-btn--28${a.holding ? " is-holding" : ""}" data-act="hold" data-k="hold">${icon("hand-tap")}<span>${esc(a.holding ? t.keepHolding : t.holdAllow)}</span></button>`
              : `<button type="button" class="an-btn an-btn--ghost an-btn--28" data-act="allow-session" data-k="allow-session">${esc(session)}</button><button type="button" class="an-btn an-btn--primary an-btn--28" data-act="allow" data-k="allow">${esc(t.allow)}</button>`}
          </div>
        </div>
      </article>`;
    }
    const st = S.session.status;
    const own = a.phase === "waiting" ? "" : `<div class="an-card an-agent-row"><i class="an-glyph an-glyph--claude" style="--s:22px"></i><span class="an-agent-row__project">altillo</span><span class="an-agent-row__activity">${esc(S.session.text || t.waitingRow)}</span><span class="an-ago">${esc(t.agoS(3))}</span><span class="an-agent-row__status">${st === "working" ? `<span class="an-dots an-dots--live"><i></i><i></i><i></i></span>${esc(t.workingLabel)}` : st === "done" ? `<span class="an-stamp">${esc(t.done)}</span>` : st === "denied" ? `<span class="an-stamp an-stamp--settled" style="color:var(--an-tomato);border-color:var(--an-tomato);outline-color:transparent">${esc(t.stopped)}</span>` : `<span class="an-dots an-dots--live"><i></i><i></i><i></i></span>`}</span><span class="an-agent-row__end"></span></div>`;
    return `<div class="an-agents">${card}${own}
      <div class="an-card an-agent-row"><i class="an-glyph an-glyph--codex" style="--s:22px"></i><span class="an-agent-row__project">atlas-api</span><span class="an-agent-row__activity">${esc(t.runningTests)}</span><span class="an-ago">${esc(t.agoS(3))}</span><span class="an-agent-row__status"><span class="an-dots an-dots--live"><i></i><i></i><i></i></span>${esc(t.workingLabel)}</span><span class="an-agent-row__end"></span></div>
      ${a.phase === "waiting" && S.compact ? "" : `<div class="an-card an-agent-row"><i class="an-glyph an-glyph--claude" style="--s:22px"></i><span class="an-agent-row__project">portfolio-site</span><span class="an-agent-row__activity">${esc(t.doneIn)}</span><span class="an-ago">${esc(t.agoMin(4))}</span><span class="an-agent-row__status"><span class="an-stamp an-stamp--settled">${esc(t.done)}</span></span><span class="an-agent-row__end"></span></div>`}
    </div>`;
  }
  function calendarMarkup() {
    const [e0, e1, e2] = EVENTS;
    const btn =
      S.cal === "joining" ? `<button type="button" class="an-btn an-btn--primary an-btn--28" data-act="join" data-k="join" aria-busy="true">${icon("spinner", "an-spin")}${esc(t.joining)}</button>`
      : S.cal === "joined" ? `<button type="button" class="an-btn an-btn--ghost an-btn--28" data-act="join" data-k="join" style="color:var(--an-sage);box-shadow:inset 0 0 0 1px rgb(157 184 138 / .6)">${icon("check")}${esc(t.joined)}</button>`
      : `<button type="button" class="an-btn an-btn--primary an-btn--28" data-act="join" data-k="join" title="${esc(t.joinWith(e0.title, e0.provider))}" aria-label="${esc(t.joinWith(e0.title, e0.provider))}">${esc(t.join)}</button>`;
    return `<div class="an-agenda">
      <article class="an-card an-card--lit an-event-card" style="--an-cal: var(--an-${e0.cal})">
        <span class="an-spine"></span>
        <div class="an-event-card__text"><span class="an-event-card__title">${esc(e0.title)}</span><span class="an-event-card__when"><b>${e0.when}</b>·<span>${S.cal === "idle" ? esc(e0.place) : esc(t.joinedNote)}</span></span></div>
        ${S.cal === "idle" ? `<span class="an-countdown is-soon">${icon("clock")}${esc(t.inMin(e0.mins))}</span>` : ""}
        ${btn}
      </article>
      <div class="an-card an-event-row" style="--an-cal: var(--an-${e1.cal})"><span class="an-event-row__dot"></span><span class="an-event-row__time">${e1.time}</span><span class="an-event-row__title">${esc(e1.title)}</span></div>
      <div class="an-card an-event-row" style="--an-cal: var(--an-${e2.cal})"><span class="an-event-row__dot"></span><span class="an-event-row__time">${e2.time}</span><span class="an-event-row__title">${esc(e2.title)}</span><span class="an-event-row__place">${esc(e2.place)}</span></div>
    </div>`;
  }
  function musicMarkup() {
    const m = S.music;
    const tr = TRACKS[m.track];
    const d = m.d[m.track] || 1;
    return `<div class="an-card an-player">
      <div class="an-sleeve"><div class="an-art dm-art-${m.track}"><span>${tr.art}</span></div></div>
      <div class="an-player__col">
        <div><div class="an-player__title">${esc(tr.title)}</div><div class="an-player__by"><span>Estudio Altillo</span><span>·</span><span>Desde el altillo</span></div></div>
        <div class="an-groove-row"><span class="an-groove dm-groove" role="progressbar" aria-label="${esc(t.progress)}" aria-valuemin="0" aria-valuemax="${Math.round(d)}" aria-valuenow="${Math.round(m.t)}" style="--v:${Math.min(100, (m.t / d) * 100).toFixed(2)}"></span><span class="an-groove__time dm-time">${clock(m.t)} / ${clock(d)}</span></div>
        <div class="an-controls">
          <button type="button" class="an-btn an-btn--quiet an-btn--32" data-act="prev" data-k="prev" aria-label="${esc(t.prev)}">${icon("prev")}</button>
          <button type="button" class="an-btn an-btn--primary an-btn--36" data-act="play" data-k="play" aria-label="${esc(m.playing ? t.pause : t.play)}" aria-pressed="${m.playing}">${icon(m.playing ? "pause" : "play")}</button>
          <button type="button" class="an-btn an-btn--quiet an-btn--32" data-act="next" data-k="next" aria-label="${esc(t.next)}">${icon("next")}</button>
          ${m.err ? `<span class="an-ago" style="margin-left:6px;color:var(--an-tomato)">${esc(t.audioFail)}</span>` : ""}
        </div>
      </div>
    </div>`;
  }
  function mirrorMarkup() {
    return `<div class="an-mirror">
      <div class="an-card an-mirror__frame"><div class="an-glass${S.mirror ? " is-mirrored" : ""}" role="img" aria-label="${esc(t.portrait)}">${PORTRAIT}</div></div>
      <div class="an-mirror__controls">
        <button type="button" class="an-btn an-btn--ghost an-btn--28" data-act="flip" data-k="flip" aria-pressed="${S.mirror}" title="${esc(t.flipTip)}">${icon("flip")}${esc(S.mirror ? t.mirrored : t.asItIs)}</button>
        <span class="an-mirror__camera">${icon("camera")}${esc(t.sampleCamera)}</span>
      </div>
    </div>`;
  }
  function askChips() {
    const chips = [{ id: "today", icon: "calendar", text: t.chips.today }];
    if (S.shelf.length) {
      const f = FILES.find((x) => x.id === S.shelf[S.shelf.length - 1]);
      chips.push({ id: "summarize", icon: "align-left", text: t.chips.summarize(f.short) });
    }
    chips.push({ id: "clipboard", icon: "clipboard", text: t.chips.clipboard });
    chips.push({ id: "music", icon: "music", text: t.chips.music });
    return chips.slice(0, S.compact ? 2 : 3);
  }
  function askMarkup() {
    const a = S.ask;
    let top;
    if (!a.log.length) {
      top = `<div class="an-ask-welcome"><div class="an-ask-welcome__title">${icon("bulb")}${esc(t.askTitle)}</div><p>${esc(t.askIntro)}</p><div class="an-chips">${askChips().map((c) => `<button type="button" class="an-chip-btn" data-act="ask" data-q="${c.id}" data-k="chip-${c.id}">${icon(c.icon)}${esc(c.text)}</button>`).join("")}</div></div>`;
    } else {
      top = `<div class="an-ask__scroll dm-ask-scroll">${a.log.map((e, i) => `<div class="an-qslip" style="--an-tilt:${i % 2 ? -0.5 : 0.6}deg">${esc(e.q)}</div>${e.shown === 0 && !e.done ? `<div class="an-thinking">${icon("bulb")}${esc(t.thinking)}</div>` : `<div class="an-answer" data-i="${i}">${e.a.slice(0, e.shown)}</div>`}${e.done ? `<div class="an-answer-actions"><button type="button" class="an-btn an-btn--quiet" data-act="ask-copy" data-k="copy-${i}">${icon(e.copied ? "check" : "copy")}${esc(e.copied ? t.copied : t.copy)}</button><span class="an-btn an-btn--quiet">${icon("put-up")}${esc(t.putUp)}</span><span class="an-btn an-btn--quiet">${icon("bookmark")}${esc(t.saved)}</span></div>` : ""}`).join("")}${a.busy ? "" : `<div class="an-chips" style="margin-top:0">${askChips().filter((c) => !a.log.some((e) => e.id === c.id)).slice(0, 2).map((c) => `<button type="button" class="an-chip-btn" data-act="ask" data-q="${c.id}" data-k="chip-${c.id}">${icon(c.icon)}${esc(c.text)}</button>`).join("")}</div>`}</div>`;
    }
    return `<div class="an-ask">${top}
      <form class="an-prompt" data-act="ask-form">
        <label class="an-field">${icon("sparkle")}<span class="dm-sr">${esc(t.askLabel)}</span><input type="text" name="q" autocomplete="off" placeholder="${esc(t.askPlaceholder)}" value="${esc(a.draft)}" data-k="ask-input" ${a.busy ? "disabled" : ""}><span class="an-field__mic" title="${esc(t.dictate)}">${icon("mic")}</span></label>
        <button type="submit" class="an-send${a.draft.trim() || a.busy ? "" : " is-empty"}" data-k="ask-send" aria-label="${esc(a.busy ? t.stop : t.send)}">${icon(a.busy ? "stop" : "arrow-up")}</button>
      </form>
    </div>`;
  }

  // ------------------------------------------------------------- render ----
  function withFocus(fn) {
    const k = root.contains(document.activeElement) ? document.activeElement.getAttribute("data-k") : null;
    const selStart = document.activeElement?.selectionStart;
    fn();
    if (k) {
      const el = root.querySelector(`[data-k="${k}"]`);
      if (el) {
        el.focus({ preventScroll: true });
        if (selStart != null && el.setSelectionRange) try { el.setSelectionRange(selStart, selStart); } catch {}
      } else if (S.open) root.querySelector(`[data-tab="${S.module}"]`)?.focus({ preventScroll: true });
    }
  }
  function render() {
    withFocus(() => {
      renderEars();
      if (S.open) renderOpen();
      renderFiles();
      renderDeliveries();
      renderTray();
    });
    if (S.open) sizeNotch(true);
    if (S.open && S.module === "usage") animateUsage();
    if (S.open && S.module === "ask") scrollAsk();
    updateTip();
  }
  function renderBody() {
    if (!S.open) return render();
    withFocus(() => renderOpen());
    sizeNotch(true);
    if (S.module === "usage") animateUsage();
    if (S.module === "ask") scrollAsk();
  }
  function renderFiles() {
    $(".dm-files").innerHTML = FILES.map((f) => {
      const up = S.shelf.includes(f.id);
      const sel = S.finderSel === f.id;
      return `<button type="button" role="option" class="dm-file${sel ? " is-selected" : ""}${up ? " is-shelved" : ""}" data-file="${f.id}" data-k="f-${f.id}" aria-selected="${sel}" aria-label="${esc(f.name)}${up ? ", " + esc(t.onShelf) : ""}"><span class="dm-file__art an">${thumbMarkup(f)}</span><span class="dm-file__name">${esc(f.name)}</span></button>`;
    }).join("");
    const f = FILES.find((x) => x.id === S.finderSel);
    $(".dm-finder__meta").textContent = f ? `${f.name} · ${f.meta}` : t.items(FILES.length);
    const b = $('[data-act="shelve"]');
    const up = S.shelf.includes(S.finderSel);
    b.disabled = up || S.shelf.length >= SHELF_MAX;
    b.querySelector("span").textContent = up ? t.alreadyUp : t.putOnShelf;
  }
  function renderDeliveries() {
    const n = S.delivered.length;
    $(".dm-folder__count").textContent = n ? String(n) : "";
    $(".dm-deliveries__meta").textContent = n ? t.received(n) : t.emptyFolder;
  }
  function renderTray() {
    const tray = $(".dm-tray");
    tray.classList.toggle("is-tucked", S.drawer.tucked);
    const b = $(".dm-tray__toggle");
    b.setAttribute("aria-pressed", String(S.drawer.tucked));
    b.setAttribute("aria-label", S.drawer.tucked ? t.showIcons : t.hideIcons);
    b.innerHTML = icon(S.drawer.tucked ? "caret-left" : "caret-right");
    $(".dm-tray__items").setAttribute("aria-hidden", String(S.drawer.tucked));
  }
  function renderTerm() {
    const el = $(".dm-term");
    const a = S.agent;
    const act = [];
    if (a.phase === "idle") act.push(`<button type="button" class="dm-pill" data-act="request" data-req="push" data-k="t-push">${icon("arrow-up")}${esc(t.askPush)}</button>`);
    if (a.phase === "done" || a.phase === "denied") {
      act.push(`<button type="button" class="dm-pill" data-act="request" data-req="${a.req === "push" ? "rm" : "push"}" data-k="t-next">${esc(a.req === "push" ? t.askRm : t.again)}</button>`);
    }
    withFocus(() => {
      el.innerHTML = `<div class="dm-term__lines">${S.term.join("")}</div>${act.length ? `<div class="dm-term__actions">${act.join("")}</div>` : ""}`;
    });
  }
  const line = (html, cls = "") => `<p class="${cls}">${html}</p>`;
  function termReset() {
    S.term = [
      `<div class="dm-term__head"><i class="an-glyph an-glyph--claude"></i><b>Claude Code</b><span class="t-dim">v2.1 · ~/code/altillo</span></div>`,
      line(`<span class="t-dim">&gt;</span> ${X.prompt}`),
      line(`<span class="t-claude">⏺</span> ${X.ran}`),
      line(`<span class="t-claude">⏺</span> ${X.committed}`),
    ];
  }

  // ------------------------------------------------------ open / close ----
  let closeTimer = 0, openTimer = 0;
  function open(mod, via = "api") {
    if (destroyed) return;
    const target = mod && MODULES.includes(mod) ? mod : S.module;
    const wasOpen = S.open;
    const changed = target !== S.module;
    S.module = target;
    cancel(closeTimer);
    if (via !== "hover") S.pinned = true;
    if (!wasOpen) {
      S.open = true;
      S.via = via;
      root.classList.add("is-open");
      notch.dataset.state = "open";
      notchBtn.setAttribute("aria-expanded", "true");
      notchBtn.setAttribute("aria-label", t.closeAltillo);
      renderOpen();
      openEl.hidden = false;
      // Reopening while the close fade is still running: drop it, or its
      // opacity-0 end state would win over the focus-in.
      openEl.classList.remove("dm-focus-in", "dm-focus-out");
      void openEl.offsetWidth;
      openEl.classList.add("dm-focus-in");
      earsEl.classList.add("is-hidden");
      notch.classList.add("dm-opening");
      later(() => notch.classList.remove("dm-opening"), SPRING_OPEN.ms);
      sizeNotch(true);
      emit("opened", { module: S.module, via });
      emit("module-shown", { module: S.module });
      announce(`${t.opened} · ${t.tabs[S.module]}`);
      if (S.module === "usage") animateUsage();
      if (via === "keyboard") later(() => root.querySelector(`[data-tab="${S.module}"]`)?.focus(), 30);
      if (S.module === "agents") onAgentsShown();
    } else if (changed) {
      switchModule();
    }
    updateTip();
    root.classList.add("has-used");
  }
  function switchModule(dir = 1) {
    const body = openEl.querySelector(".dm-body");
    const old = body?.cloneNode(true);
    renderBody();
    const nb = openEl.querySelector(".dm-body");
    if (old && nb && !mqReduce.matches) {
      nb.classList.add("dm-slide-in");
      nb.style.setProperty("--dm-dir", dir);
    }
    emit("module-shown", { module: S.module });
    announce(t.tabs[S.module]);
    if (S.module === "agents") onAgentsShown();
    if (S.module === "usage") animateUsage();
  }
  function close(via = "api") {
    if (!S.open || destroyed) return;
    S.open = false;
    S.pinned = false;
    S.drawer.menu = null;
    root.classList.remove("is-open");
    notch.dataset.state = "closed";
    notchBtn.setAttribute("aria-expanded", "false");
    const hadFocus = openEl.contains(document.activeElement);
    openEl.classList.remove("dm-focus-in");
    openEl.classList.add("dm-focus-out");
    earsEl.classList.remove("is-hidden");
    renderEars();
    sizeNotch(true);
    const out = later(() => { if (!S.open) { openEl.hidden = true; openEl.classList.remove("dm-focus-out"); openEl.innerHTML = ""; } }, mqReduce.matches ? 0 : 200);
    void out;
    if (hadFocus) notchBtn.focus({ preventScroll: true });
    emit("closed", { via });
    announce(t.closed);
    updateTip();
  }
  function scheduleClose(ms = 320) {
    cancel(closeTimer);
    closeTimer = later(() => {
      if (S.pinned || drag || openEl.contains(document.activeElement)) return;
      close("hover");
    }, ms);
  }

  // ---------------------------------------------------------- tips ----
  function updateCue() {
    const label = $(".dm-cue__label");
    if (label) label.textContent = mqHover.matches && !S.compact ? t.hoverCue : t.tapCue;
    updateTip();
  }
  function updateTip() {
    const tip = $(".dm-tip");
    if (!tip) return;
    tip.textContent = S.open
      ? S.drawer.tucked
        ? t.tips.drawer
        : S.module === "agents" && S.agent.phase !== "waiting" ? t.tips.agentsIdle : t.tips[S.module]
      : mqHover.matches && !S.compact ? t.tips.closed : t.tips.closedTouch;
  }

  // --------------------------------------------------------- usage ----
  let usageTick = 0;
  function animateUsage() {
    const first = !S.usage.shown;
    S.usage.shown = true;
    const arcs = openEl.querySelectorAll(".dm-arc");
    const bars = openEl.querySelectorAll(".dm-bar");
    const counts = openEl.querySelectorAll(".dm-count");
    if (first || !arcs[0]?.dataset.anim) {
      arcs.forEach((a) => { a.style.transition = "none"; a.setAttribute("stroke-dasharray", "0 100"); a.dataset.anim = "1"; });
      bars.forEach((b) => { b.style.transition = "none"; b.style.setProperty("--v", 0); });
      counts.forEach((c) => (c.textContent = "0"));
      void openEl.offsetWidth;
      requestAnimationFrame(() => {
        arcs.forEach((a) => { a.style.transition = ""; a.setAttribute("stroke-dasharray", `${a.dataset.v} 100`); });
        bars.forEach((b) => { b.style.transition = ""; b.style.setProperty("--v", b.dataset.v); });
        const t0 = performance.now();
        const dur = mqReduce.matches ? 1 : 900;
        const step = (now) => {
          const k = Math.min(1, (now - t0) / dur);
          const e = 1 - Math.pow(1 - k, 3);
          counts.forEach((c) => (c.textContent = String(Math.round(Number(c.dataset.v) * e))));
          if (k < 1 && !destroyed) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
      });
    }
    clearInterval(usageTick);
    usageTick = setInterval(() => {
      if (!S.open || S.module !== "usage" || destroyed) return clearInterval(usageTick);
      if (S.usage.claude >= 88) return;
      S.usage.claude += 1;
      S.usage.wClaude += 1;
      const arc = openEl.querySelector(".dm-arc");
      const c = openEl.querySelector(".dm-count");
      const bar = openEl.querySelector(".dm-bar");
      if (arc) { arc.dataset.v = S.usage.claude; arc.setAttribute("stroke-dasharray", `${S.usage.claude} 100`); }
      if (c) { c.dataset.v = S.usage.claude; c.textContent = String(S.usage.claude); c.parentElement.classList.remove("dm-tick"); void c.offsetWidth; c.parentElement.classList.add("dm-tick"); }
      if (bar) { bar.dataset.v = S.usage.wClaude; bar.style.setProperty("--v", S.usage.wClaude); bar.nextElementSibling.textContent = `${S.usage.wClaude} %`; }
      const pace = openEl.querySelector(".an-pace--warning");
      if (pace) pace.textContent = t.aheadOfPace(S.usage.claude - 76);
      renderEars();
    }, 4500);
  }

  // -------------------------------------------------------- agents ----
  let knockTimers = [];
  function knock() {
    root.querySelectorAll(".dm-ear-knock, .dm-tab-knock, .dm-card-knock").forEach((k) => {
      k.classList.remove("is-knocking");
      void k.offsetWidth;
      k.classList.add("is-knocking");
    });
  }
  function scheduleKnocks() {
    knockTimers.forEach(cancel);
    knockTimers = [400, 3400, 6400].map((ms) => later(knock, ms));
    const loop = () => { if (S.agent.phase === "waiting") { knock(); knockTimers.push(later(loop, 30000)); } };
    knockTimers.push(later(loop, 36400));
  }
  function request(kind = "push") {
    if (S.agent.phase === "waiting" || S.agent.phase === "running") return;
    S.agent = { phase: "waiting", req: kind, since: Date.now(), holding: false };
    S.session = { status: "waiting", text: t.waitingRow };
    if (kind === "rm" || S.term.length > 12) termReset();
    const cmd = REQUESTS[kind].cmd;
    S.term.push(line(`<span class="t-claude">⏺</span> ${kind === "push" ? X.pushWhy : X.rmWhy}`));
    S.term.push(`<div class="t-box">${line(`<b>${X.bash}</b>`)}${line(esc(cmd), "t-amber")}${line(X.proceed, "t-dim")}${line(`<span class="t-amber">✋</span> ${X.waiting}`)}</div>`);
    renderTerm();
    render();
    scheduleKnocks();
    emit("agent-requested", { command: cmd, danger: REQUESTS[kind].danger });
  }
  function onAgentsShown() { /* the request is already on screen; nothing else to do */ }
  function resolveAgent(allowed, session = false) {
    if (S.agent.phase !== "waiting") return;
    const req = REQUESTS[S.agent.req];
    knockTimers.forEach(cancel);
    S.term = S.term.filter((l) => !l.startsWith('<div class="t-box">'));
    if (!allowed) {
      S.agent.phase = "denied";
      S.session = { status: "denied", text: t.deniedRow };
      S.term.push(line(`<span class="t-claude">⏺</span> Bash(${esc(req.cmd)})`));
      S.term.push(line(`  ${X.denied}`));
      S.term.push(line(`<span class="t-claude">⏺</span> ${X.stopping}`));
      S.term.push(line(`<span class="t-dim">&gt;</span> <span class="dm-term__cursor"></span>`));
      renderTerm();
      render();
      emit("agent-denied", { command: req.cmd });
      return;
    }
    S.agent.phase = "running";
    S.session = { status: "working", text: S.agent.req === "push" ? t.pushing : "npm ci…" };
    render();
    emit("agent-allowed", { command: req.cmd, session });
    const out = S.agent.req === "push"
      ? [
          line(`<span class="t-claude">⏺</span> Bash(${esc(req.cmd)})`),
          line(`  ⎿  To github.com:altillo/altillo.git`, "t-dim"),
          line(`       4f2a91c..9b7e3d0  feat/notch-design -&gt; feat/notch-design`, "t-dim"),
          line(`<span class="t-claude">⏺</span> ${X.pushed}`),
          line(`<span class="t-dim">&gt;</span> <span class="dm-term__cursor"></span>`),
        ]
      : [
          line(`<span class="t-claude">⏺</span> Bash(${esc(req.cmd)})`),
          line(`  ⎿  removed 1,284 packages (412 MB)`, "t-dim"),
          line(`     added 1,279 packages in 9s`, "t-dim"),
          line(`<span class="t-claude">⏺</span> ${X.installed}`),
          line(`<span class="t-dim">&gt;</span> <span class="dm-term__cursor"></span>`),
        ];
    out.forEach((l, i) => later(() => {
      S.term.push(l);
      if (i === out.length - 1) {
        S.agent.phase = "done";
        S.session = { status: "done", text: S.agent.req === "push" ? t.pushed : t.removedRow };
        render();
      }
      renderTerm();
    }, mqReduce.matches ? 0 : 380 * (i + 1)));
  }
  let holdTimer = 0;
  function startHold() {
    if (S.agent.phase !== "waiting" || !REQUESTS[S.agent.req].danger) return;
    S.agent.holding = true;
    const b = openEl.querySelector('[data-act="hold"]');
    if (b) { b.classList.add("is-holding"); b.querySelector("span").textContent = t.keepHolding; }
    cancel(holdTimer);
    holdTimer = later(() => { S.agent.holding = false; resolveAgent(true); }, 1000);
  }
  function endHold() {
    if (!S.agent.holding) return;
    S.agent.holding = false;
    cancel(holdTimer);
    const b = openEl.querySelector('[data-act="hold"]');
    if (b) { b.classList.remove("is-holding"); b.querySelector("span").textContent = t.holdAllow; }
  }
  // Keep the "8 s ago" honest while the card is up.
  const agoTick = setInterval(() => {
    if (S.open && S.module === "agents" && S.agent.phase === "waiting") {
      const el = openEl.querySelector(".dm-ago");
      if (el) el.textContent = t.agoS(Math.max(1, Math.round((Date.now() - S.agent.since) / 1000)));
    }
  }, 1000);

  // ---------------------------------------------------------- music ----
  function trackSrc(i) { return mediaBase.replace(/\/?$/, "/") + TRACKS[i].file; }
  let playedFor = 0, lastT = 0;
  let askGen = 0;
  async function play() {
    const m = S.music;
    if (!audio.src || !audio.src.endsWith(TRACKS[m.track].file)) { audio.src = trackSrc(m.track); playedFor = 0; }
    m.err = false;
    try { await audio.play(); } catch (e) { if (e.name !== "AbortError") { m.err = true; m.playing = false; if (S.module === "music") renderBody(); } }
  }
  function setTrack(i, keepPlaying) {
    const m = S.music;
    m.track = (i + TRACKS.length) % TRACKS.length;
    m.t = 0;
    audio.pause();
    audio.src = trackSrc(m.track);
    playedFor = 0; lastT = 0;
    if (keepPlaying) play();
    if (S.open && S.module === "music") renderBody();
    renderEars();
  }
  audio.addEventListener("play", () => {
    S.music.playing = true;
    emit("track-played", { track: S.music.track, title: TRACKS[S.music.track].title });
    if (S.open && S.module === "music") renderBody();
    renderEars();
  });
  audio.addEventListener("pause", () => { S.music.playing = false; if (S.open && S.module === "music") renderBody(); renderEars(); });
  audio.addEventListener("loadedmetadata", () => { if (isFinite(audio.duration)) S.music.d[S.music.track] = audio.duration; });
  audio.addEventListener("timeupdate", () => {
    const m = S.music;
    const dt = audio.currentTime - lastT;
    if (dt > 0 && dt < 1.5) playedFor += dt;
    lastT = audio.currentTime;
    m.t = audio.currentTime;
    if (playedFor >= 5 && !m.played.has(m.track)) {
      m.played.add(m.track);
      if (m.played.size === TRACKS.length && !m.all) { m.all = true; emit("all-tracks-played", { tracks: TRACKS.map((x) => x.title) }); }
    }
    if (!S.open || S.module !== "music") return;
    const g = openEl.querySelector(".dm-groove");
    const d = m.d[m.track] || 1;
    if (g) { g.style.setProperty("--v", Math.min(100, (m.t / d) * 100).toFixed(2)); g.setAttribute("aria-valuenow", Math.round(m.t)); g.setAttribute("aria-valuemax", Math.round(d)); }
    const tm = openEl.querySelector(".dm-time");
    if (tm) tm.textContent = `${clock(m.t)} / ${clock(d)}`;
  });
  audio.addEventListener("ended", () => setTrack(S.music.track + 1, true));
  audio.addEventListener("error", () => { if (!audio.src) return; S.music.err = true; S.music.playing = false; if (S.open && S.module === "music") renderBody(); });

  // ------------------------------------------------------------ ask ----
  function answerFor(id, raw = "") {
    const m = S.music;
    const q = raw.toLowerCase();
    if (!id) {
      if (/today|calendar|meeting|agenda|hoy|reuni|calendario/.test(q)) id = "today";
      else if (/cop(y|ied)|clipboard|portapapeles|copiado/.test(q)) id = "clipboard";
      else if (/play|music|song|track|sonando|música|canci/.test(q)) id = "music";
      else if (/usage|limit|quota|claude|codex|uso|límite/.test(q)) id = "usage";
      else if (/shelf|file|estante|archivo/.test(q)) id = S.shelf.length ? "summarize" : "shelf";
      else id = "fallback";
    }
    const tr = TRACKS[m.track];
    const shelfFile = S.shelf.length ? FILES.find((x) => x.id === S.shelf[S.shelf.length - 1]) : null;
    const en = {
      today: `Three things today. <b>Design review</b> at 3:00 PM in Studio — that's in 12 minutes, on Google Meet. Then the <b>final hand-off</b> at 4:00, and <b>climbing with Marta</b> at 6:30 at Sharma Gym. You're free between 3:30 and 4:00 if you need a breather.`,
      clipboard: `You copied a JavaScript error: something called <code>.map()</code> on a value that was <code>undefined</code>, at <b>routes.ts</b> line 42. Usually the data hasn't arrived yet or the key is misspelled. Guard it with <code>items ?? []</code>, or check what the response actually returns.`,
      music: m.playing ? `<b>${tr.title}</b> by Estudio Altillo, ${clock(m.t)} in. It's from <i>Desde el altillo</i>, three short original pieces made for this page.` : `Nothing's playing right now. Your queue starts with <b>${tr.title}</b> by Estudio Altillo — press play in Now playing and I'll know.`,
      usage: `Claude is at <b>${S.usage.claude} %</b> of this 5-hour session, a little ahead of pace; it refills in 1 h 11 min. Codex is at <b>34 %</b> and on pace.`,
      summarize: shelfFile ? `<b>${esc(shelfFile.name)}</b> is on your shelf. In this demo I can't open it — on your Mac I'd read it right here and give you the gist in a few lines. Ask runs on-device by default; I'd only reach out to the web if you asked me to and allowed it.` : "",
      shelf: `Your shelf is empty. Drag a file onto the notch and I can tell you about it.`,
      fallback: `This is a demo, so I only know this sample day: your calendar, what you copied, your shelf, the music and your AI usage. Try asking about one of those.`,
    };
    const es = {
      today: `Tres cosas hoy. <b>Revisión de diseño</b> a las 15:00 en el Estudio — en 12 minutos, por Google Meet. Luego la <b>entrega final</b> a las 16:00 y <b>escalada con Marta</b> a las 18:30 en el Rocódromo Sharma. Entre las 15:30 y las 16:00 tienes un respiro.`,
      clipboard: `Has copiado un error de JavaScript: algo llamó a <code>.map()</code> sobre un valor <code>undefined</code>, en <b>routes.ts</b> línea 42. Suele ser que los datos aún no han llegado o que la clave está mal escrita. Protégelo con <code>items ?? []</code> o revisa qué devuelve la respuesta.`,
      music: m.playing ? `<b>${tr.title}</b> de Estudio Altillo, por el ${clock(m.t)}. Es de <i>Desde el altillo</i>, tres piezas originales hechas para esta página.` : `Ahora no suena nada. Tu cola empieza con <b>${tr.title}</b> de Estudio Altillo — dale a reproducir en Sonando y lo sabré.`,
      usage: `Claude va por el <b>${S.usage.claude} %</b> de esta sesión de 5 horas, algo por delante del ritmo; se repone en 1 h 11 min. Codex va por el <b>34 %</b>, a buen ritmo.`,
      summarize: shelfFile ? `<b>${esc(shelfFile.name)}</b> está en tu altillo. En esta demo no puedo abrirlo; en tu Mac lo leería aquí mismo y te daría lo esencial en pocas líneas. Pregunta funciona en el dispositivo por defecto; solo saldría a la web si tú lo pidieras y lo permitieras.` : "",
      shelf: `Tu altillo está vacío. Arrastra un archivo al notch y te cuento.`,
      fallback: `Esto es una demo: solo conozco este día de ejemplo — tu agenda, lo que has copiado, tu altillo, la música y tu uso de IA. Pregúntame por algo de eso.`,
    };
    return { id, html: (lang === "es" ? es : en)[id] || (lang === "es" ? es : en).fallback };
  }
  function ask(id, text) {
    if (S.ask.busy) return;
    const chip = askChips().find((c) => c.id === id);
    const q = text || chip?.text || "";
    if (!q.trim()) return;
    const { id: topic, html } = answerFor(id, text);
    const entry = { id: topic, q, a: html, shown: 0, done: false };
    S.ask.log.push(entry);
    if (S.ask.log.length > 3) S.ask.log.shift();
    S.ask.busy = true;
    S.ask.draft = "";
    renderBody();
    emit("ask-asked", { question: q, topic });
    // Guards the reveal loop below against a reset() or a new question
    // firing mid-reveal — only the loop that started this generation may
    // touch S.ask.busy or keep scheduling itself.
    const gen = ++askGen;
    // Tokens: split on spaces but never inside a tag.
    const tokens = html.match(/(<[^>]+>|[^<\s]+\s*|\s+)/g) || [html];
    let i = 0, acc = "";
    const reveal = () => {
      if (destroyed || gen !== askGen) return;
      if (mqReduce.matches) { acc = html; i = tokens.length; }
      else { acc += tokens[i++]; while (i < tokens.length && tokens[i].startsWith("<")) acc += tokens[i++]; }
      entry.shown = acc.length;
      entry.a = html;
      const el = openEl.querySelector(`.an-answer[data-i="${S.ask.log.indexOf(entry)}"]`);
      if (i >= tokens.length) { entry.done = true; entry.shown = html.length; S.ask.busy = false; if (S.open && S.module === "ask") renderBody(); return; }
      if (el) { el.innerHTML = acc; scrollAsk(); } else if (S.open && S.module === "ask") renderBody();
      later(reveal, 28 + Math.random() * 30);
    };
    later(() => { if (gen !== askGen) return; entry.shown = 0.0001; reveal(); }, mqReduce.matches ? 0 : 650);
  }
  function scrollAsk() { const s = openEl.querySelector(".dm-ask-scroll"); if (s) s.scrollTop = s.scrollHeight; }

  // ---------------------------------------------------------- shelf ----
  function shelve(id, via = "button") {
    if (S.shelf.includes(id)) return false;
    if (S.shelf.length >= SHELF_MAX) {
      announce(t.shelfFull);
      emit("shelf-full", { count: S.shelf.length, attempted: id });
      flashFull();
      return false;
    }
    S.shelf.push(id);
    S.shelfSel = id;
    S.landing = id;
    S.dropLit = false;
    const f = FILES.find((x) => x.id === id);
    if (!S.open) open("shelf", via === "drag" ? "drag" : "api");
    else if (S.module !== "shelf") { S.module = "shelf"; switchModule(); }
    render();
    scrollShelfEnd();
    later(() => { if (S.landing === id) S.landing = null; }, 700);
    emit("file-shelved", { file: f.name, id, count: S.shelf.length, via });
    announce(t.shelvedA(f.name));
    if (S.shelf.length === SHELF_MAX) emit("shelf-full", { count: S.shelf.length });
    return true;
  }
  function flashFull() {
    const s = openEl.querySelector(".an-shelf");
    if (!s) return;
    s.classList.remove("dm-shake"); void s.offsetWidth; s.classList.add("dm-shake");
  }
  function scrollShelfEnd() { const r = openEl.querySelector(".an-shelf__row"); if (r) r.scrollLeft = r.scrollWidth; }
  function deliver(id = S.shelfSel || S.shelf[0]) {
    if (!id || !S.shelf.includes(id)) return false;
    S.shelf = S.shelf.filter((x) => x !== id);
    S.delivered.push(id);
    S.shelfSel = S.shelf.length ? S.shelf[S.shelf.length - 1] : null;
    const f = FILES.find((x) => x.id === id);
    const d = $(".dm-deliveries");
    d.classList.remove("is-received"); void d.offsetWidth; d.classList.add("is-received");
    render();
    emit("file-delivered", { file: f.name, id, delivered: S.delivered.length });
    announce(t.deliveredA(f.name));
    return true;
  }

  // ----------------------------------------------------------- drag ----
  let drag = null;
  function hitRect(el, pad = 0) {
    const r = el.getBoundingClientRect();
    return { l: r.left - pad, t: r.top - pad, r: r.right + pad, b: r.bottom + pad };
  }
  const inside = (p, r) => p.x >= r.l && p.x <= r.r && p.y >= r.t && p.y <= r.b;
  function onPointerDown(e) {
    if (e.button !== 0 || drag) return;
    const file = e.target.closest(".dm-file");
    const tile = e.target.closest(".an-tile[data-shelf]");
    const hold = e.target.closest('[data-act="hold"]');
    if (hold) { e.preventDefault(); startHold(); hold.setPointerCapture?.(e.pointerId); return; }
    if (!file && !tile) return;
    const id = file ? file.dataset.file : tile.dataset.shelf;
    if (file && S.shelf.includes(id)) return;
    // A drag uses viewport points: stop any smooth focus scroll left by the
    // previous action before those points can drift away from the shelf.
    window.scrollTo({ left: scrollX, top: scrollY, behavior: "instant" });
    drag = { id, from: file ? "finder" : "shelf", src: file || tile, x0: e.clientX, y0: e.clientY, pid: e.pointerId, ghost: null, over: null, openedByDrag: false };
  }
  function onPointerMove(e) {
    if (!drag || e.pointerId !== drag.pid) return;
    const dx = e.clientX - drag.x0, dy = e.clientY - drag.y0;
    if (!drag.ghost) {
      if (Math.hypot(dx, dy) < 6) return;
      startGhost(e);
    }
    e.preventDefault();
    drag.ghost.style.transform = `translate3d(${e.clientX - drag.gw / 2}px, ${e.clientY - drag.gh / 2}px, 0) scale(${drag.k})`;
    const p = { x: e.clientX, y: e.clientY };
    if (drag.from === "finder") {
      const nr = hitRect(notch, 0);
      const near = hitRect(notch, 150 * (S.compact ? 0.6 : 1));
      if (!S.open && inside(p, near)) { drag.openedByDrag = true; S.dropLit = true; open("shelf", "drag"); render(); }
      else if (S.open && inside(p, near) && (S.module !== "shelf" || !S.dropLit)) {
        // Already open: light up as a drop target too, so an empty (shorter)
        // shelf grows to its full size before the file arrives.
        S.dropLit = true;
        if (S.module !== "shelf") { S.module = "shelf"; switchModule(); }
        render();
      }
      const over = S.open && inside(p, hitRect(notch, 24)) ? "shelf" : null;
      if (!!over !== S.dropLit || over !== drag.over) {
        drag.over = over;
        if (S.dropLit !== !!over && S.open) { S.dropLit = !!over || inside(p, near); renderBody(); renderEars(); }
      }
      void nr;
    } else {
      const del = $(".dm-deliveries");
      const over = inside(p, hitRect(del, 24)) ? "deliveries" : null;
      if (over !== drag.over) { drag.over = over; del.classList.toggle("is-target", !!over); }
    }
  }
  function startGhost(e) {
    const src = drag.src.querySelector(".an-thumb");
    const f = FILES.find((x) => x.id === drag.id);
    const g = document.createElement("div");
    g.className = "an dm-ghost";
    g.style.setProperty("--an-scale", "1");
    g.innerHTML = thumbMarkup(f);
    document.body.append(g);
    const gr = g.getBoundingClientRect();
    const sr = src.getBoundingClientRect();
    drag.k = Math.max(0.5, (sr.width / Math.max(1, gr.width)) * 1.06);
    drag.gw = gr.width; drag.gh = gr.height;
    drag.ghost = g;
    root.classList.add("is-dragging");
    drag.src.classList.add("dm-lifting");
    try { root.setPointerCapture(e.pointerId); } catch {}
    if (drag.from === "shelf") $(".dm-deliveries").classList.add("is-armed");
  }
  function endDrag(e, cancelled = false) {
    if (!drag || (e && e.pointerId !== drag.pid)) return;
    const d = drag;
    drag = null;
    if (!d.ghost) return; // it was a click
    suppressClick = true;
    later(() => (suppressClick = false), 0);
    root.classList.remove("is-dragging");
    d.src.classList.remove("dm-lifting");
    const del = $(".dm-deliveries");
    del.classList.remove("is-target", "is-armed");
    let ok = false;
    // A lit shelf is a promise: if it's glowing when the file is let go, take
    // it, even if the pointer is just outside the (still growing) panel.
    if (!cancelled && d.from === "finder" && S.open && (S.dropLit || (e && inside({ x: e.clientX, y: e.clientY }, hitRect(notch, 24))))) d.over = "shelf";
    if (!cancelled && d.from === "finder" && d.over === "shelf") ok = shelve(d.id, "drag");
    if (!cancelled && d.from === "shelf" && d.over === "deliveries") ok = deliver(d.id);
    if (d.from === "finder") { S.dropLit = false; if (!ok && d.openedByDrag && S.open) { close("drag"); } else if (S.open) { renderBody(); renderEars(); } }
    if (ok) { d.ghost.classList.add("is-landing"); later(() => d.ghost.remove(), 300); }
    else {
      const r = d.src.getBoundingClientRect();
      d.ghost.style.transition = "transform .28s cubic-bezier(.32,.72,0,1), opacity .28s";
      d.ghost.style.transform = `translate3d(${r.left + r.width / 2 - d.gw / 2}px, ${r.top + r.height / 2 - d.gh / 2}px, 0) scale(${d.k * 0.94})`;
      d.ghost.style.opacity = "0";
      later(() => d.ghost.remove(), 300);
    }
  }
  let suppressClick = false;

  // ---------------------------------------------------------- knock ----
  let knockClicks = [];
  function onCameraClick() {
    const now = performance.now();
    knockClicks = knockClicks.filter((x) => now - x < 900);
    knockClicks.push(now);
    if (knockClicks.length >= 3) {
      knockClicks = [];
      holder.classList.remove("dm-knocked"); void holder.offsetWidth; holder.classList.add("dm-knocked");
      emit("notch-knocked", {});
      return true;
    }
    return false;
  }

  // ------------------------------------------------------- listeners ----
  const onClick = (e) => {
    if (suppressClick) { e.preventDefault(); return; }
    const el = e.target.closest("[data-act], [data-tab], [data-file], [data-shelf], .dm-notch-btn");
    if (!el || !root.contains(el)) {
      // Clicking the empty desktop closes a pinned notch.
      const keep = S.compact ? ".dm-desk-icon, .dm-menubar, button" : ".dm-window, .dm-desk-icon, .dm-menubar";
      if (S.open && !notch.contains(e.target) && scene.contains(e.target) && !e.target.closest(keep)) close("outside");
      return;
    }
    if (el.classList.contains("dm-notch-btn")) {
      const knocked = onCameraClick();
      if (!S.open) open(S.module, e.detail === 0 ? "keyboard" : mqHover.matches ? "click" : "tap");
      else if (!knocked && S.pinned && S.via !== "hover") close("click");
      else S.pinned = true;
      return;
    }
    if (el.dataset.tab) { const i = MODULES.indexOf(S.module); S.module = el.dataset.tab; S.pinned = true; switchModule(MODULES.indexOf(S.module) >= i ? 1 : -1); updateTip(); return; }
    if (el.dataset.file) { S.finderSel = el.dataset.file; renderFiles(); if (e.detail === 2) shelve(el.dataset.file, "double-click"); return; }
    if (el.dataset.shelf) { S.shelfSel = el.dataset.shelf; renderBody(); return; }
    const act = el.dataset.act;
    switch (act) {
      case "open": open(S.module, e.detail === 0 ? "keyboard" : "tap"); break;
      case "shelve": shelve(S.finderSel, "button"); break;
      case "deliver": deliver(); break;
      case "empty": S.shelf = []; S.shelfSel = null; render(); break;
      case "refresh": S.usage.shown = false; openEl.querySelectorAll(".dm-arc").forEach((a) => delete a.dataset.anim); animateUsage(); break;
      case "deny": resolveAgent(false); break;
      case "allow": resolveAgent(true, false); break;
      case "allow-session": resolveAgent(true, true); break;
      case "hold": if (e.detail === 0) { startHold(); } break; // keyboard: Enter starts the hold
      case "request": request(el.dataset.req); if (!S.open || S.module !== "agents") open("agents", "api"); break;
      case "join":
        if (S.cal !== "idle") break;
        S.cal = "joining"; renderBody();
        later(() => { S.cal = "joined"; if (S.open && S.module === "calendar") renderBody(); emit("joined-call", { event: EVENTS[0].title, provider: EVENTS[0].provider }); announce(t.joined); }, mqReduce.matches ? 200 : 1400);
        break;
      case "flip": S.mirror = !S.mirror; renderBody(); emit("mirror-flipped", { mirrored: S.mirror }); break;
      case "play": if (S.music.playing) audio.pause(); else play(); break;
      case "prev": setTrack(S.music.track - 1, S.music.playing); break;
      case "next": setTrack(S.music.track + 1, S.music.playing); break;
      case "ask": ask(el.dataset.q); break;
      case "ask-copy": { const i = [...openEl.querySelectorAll('[data-act="ask-copy"]')].indexOf(el); const en = S.ask.log[i]; if (en) { en.copied = true; renderBody(); } break; }
      case "drawer-toggle": toggleDrawer(); break;
      case "drawer-item": S.drawer.menu = S.drawer.menu === el.dataset.id ? null : el.dataset.id; renderBody(); if (S.drawer.menu) later(() => openEl.querySelector(".an-menu__item")?.focus(), 20); break;
      case "drawer-menu-item": S.drawer.menu = null; renderBody(); break;
      case "reset": reset(); break;
    }
  };
  function toggleDrawer(force) {
    S.drawer.tucked = force ?? !S.drawer.tucked;
    S.drawer.menu = null;
    S.drawer.flash = S.drawer.tucked;
    render();
    if (S.open) sizeNotch(true);
    updateTip();
    later(() => { S.drawer.flash = false; }, 900);
    emit("drawer-toggled", { tucked: S.drawer.tucked });
  }
  const onSubmit = (e) => {
    const form = e.target.closest('[data-act="ask-form"]');
    if (!form) return;
    e.preventDefault();
    if (S.ask.busy) return;
    const v = form.q.value.trim();
    if (v) ask(null, v);
  };
  const onInput = (e) => {
    if (e.target.name === "q") {
      S.ask.draft = e.target.value;
      const send = openEl.querySelector(".an-send");
      send?.classList.toggle("is-empty", !S.ask.draft.trim());
    }
  };
  const onKey = (e) => {
    if (e.key === "Escape") {
      if (S.drawer.menu) { S.drawer.menu = null; renderBody(); openEl.querySelector(".an-drawer__icon")?.focus(); return; }
      if (S.open) { e.stopPropagation(); close("escape"); notchBtn.focus({ preventScroll: true }); }
      return;
    }
    const tab = e.target.closest?.("[data-tab]");
    if (tab && (e.key === "ArrowRight" || e.key === "ArrowLeft" || e.key === "Home" || e.key === "End")) {
      e.preventDefault();
      const i = MODULES.indexOf(S.module);
      const n = e.key === "Home" ? 0 : e.key === "End" ? MODULES.length - 1 : (i + (e.key === "ArrowRight" ? 1 : -1) + MODULES.length) % MODULES.length;
      S.module = MODULES[n];
      switchModule(n >= i ? 1 : -1);
      root.querySelector(`[data-tab="${S.module}"]`)?.focus();
      updateTip();
    }
    const tile = e.target.closest?.(".an-tile[data-shelf]");
    if (tile && (e.key === "Delete" || e.key === "Backspace")) { e.preventDefault(); S.shelf = S.shelf.filter((x) => x !== tile.dataset.shelf); S.shelfSel = S.shelf.at(-1) || null; render(); }
    if (e.target.closest?.('[data-act="hold"]') && (e.key === " " || e.key === "Enter") && !e.repeat) { e.preventDefault(); startHold(); }
  };
  const onKeyUp = (e) => { if (e.target.closest?.('[data-act="hold"]') && (e.key === " " || e.key === "Enter")) endHold(); };

  // Hover: open after a beat, close after leaving (unless pinned).
  const onEnter = (e) => {
    if (e.pointerType !== "mouse" || !mqHover.matches) return;
    cancel(closeTimer);
    if (S.open || drag) return;
    cancel(openTimer);
    openTimer = later(() => open(S.module, "hover"), 120);
  };
  const onLeave = (e) => {
    if (e.pointerType !== "mouse") return;
    cancel(openTimer);
    if (S.open && !S.pinned) scheduleClose();
  };

  const unlisten = [];
  const listen = (target, type, fn, opts) => { target.addEventListener(type, fn, opts); unlisten.push(() => target.removeEventListener(type, fn, opts)); };
  listen(root, "click", onClick);
  listen(root, "submit", onSubmit);
  listen(root, "input", onInput);
  listen(root, "keydown", onKey);
  listen(root, "keyup", onKeyUp);
  listen(root, "pointerdown", onPointerDown);
  listen(root, "pointermove", onPointerMove);
  listen(root, "pointerup", (e) => { endHold(); endDrag(e); });
  listen(root, "pointercancel", (e) => { endHold(); endDrag(e, true); });
  listen(root, "lostpointercapture", (e) => { if (drag && drag.ghost && e.pointerId === drag.pid) endDrag(e, true); });
  listen(root, "dragstart", (e) => e.preventDefault());
  listen(notch, "pointerenter", onEnter);
  listen(notch, "pointerleave", onLeave);
  listen(root, "focusout", () => later(() => { if (S.open && !S.pinned && !root.contains(document.activeElement)) scheduleClose(); }, 0));
  const onMq = () => { updateCue(); root.classList.toggle("dm--reduce", mqReduce.matches); };
  mqHover.addEventListener?.("change", onMq);
  mqReduce.addEventListener?.("change", onMq);
  const ro = new ResizeObserver(() => layout());
  ro.observe(root);

  // Claude asks for permission a moment after the desktop first comes into view.
  let io = null;
  if (autoAgent && "IntersectionObserver" in window) {
    io = new IntersectionObserver((entries) => {
      if (entries.some((x) => x.isIntersecting)) {
        io.disconnect(); io = null;
        later(() => { if (S.agent.phase === "idle") request("push"); }, 2600);
      }
    }, { threshold: 0.4 });
    io.observe(screen);
  }

  function reset() {
    askGen++; // cancel any in-flight Ask reveal loop
    audio.pause();
    audio.removeAttribute("src");
    Object.assign(S, {
      module: "shelf", shelf: initialShelf.slice(), shelfSel: null, landing: null, dropLit: false, finderSel: "proposal", delivered: [],
      drawer: { tucked: false, menu: null, flash: false }, agent: { phase: "idle", req: "push", since: 0, holding: false },
      session: { status: "idle", text: "" }, cal: "idle", mirror: true,
      music: { track: 0, playing: false, t: 0, d: [50, 54, 48], err: false, played: new Set(), all: false },
      ask: { log: [], busy: false, draft: "" }, usage: { claude: 85, codex: 34, wClaude: 41, wCodex: 58, shown: false },
    });
    knockTimers.forEach(cancel);
    if (S.open) close("reset");
    root.classList.remove("has-used");
    termReset();
    renderTerm();
    render();
    emit("reset", {});
  }

  // ------------------------------------------------------------ boot ----
  termReset();
  layout();
  renderTerm();
  render();

  // ------------------------------------------------------------- API ----
  const api = {
    root,
    show(moduleId) {
      const id = ALIASES[moduleId] || moduleId;
      if (id === "drawer") {
        if (!S.drawer.tucked) toggleDrawer(true);
        open(S.module, "api");
        S.drawer.flash = true; renderBody(); later(() => { S.drawer.flash = false; }, 900);
        updateTip();
        emit("module-shown", { module: "drawer" });
        return api;
      }
      if (!MODULES.includes(id)) return api;
      if (id === "agents" && S.agent.phase === "idle") request("push");
      if (S.open && S.module !== id) { const i = MODULES.indexOf(S.module); S.module = id; S.pinned = true; switchModule(MODULES.indexOf(id) >= i ? 1 : -1); updateTip(); }
      else open(id, "api");
      return api;
    },
    open() { open(S.module, "api"); return api; },
    close() { close("api"); return api; },
    reset() { reset(); return api; },
    on(type, fn) {
      const h = (e) => { if (type === "*" || e.detail.type === type) fn(e.detail); };
      root.addEventListener("altillo-demo", h);
      return () => root.removeEventListener("altillo-demo", h);
    },
    get state() { return { open: S.open, module: S.module, shelf: [...S.shelf], delivered: [...S.delivered], drawerTucked: S.drawer.tucked, agent: S.agent.phase, playing: S.music.playing, compact: S.compact }; },
    destroy() {
      destroyed = true;
      timers.forEach((id) => clearTimeout(id));
      timers.clear();
      clearInterval(usageTick);
      clearInterval(agoTick);
      ro.disconnect();
      io?.disconnect();
      unlisten.forEach((off) => off());
      audio.pause();
      audio.removeAttribute("src");
      mqHover.removeEventListener?.("change", onMq);
      mqReduce.removeEventListener?.("change", onMq);
      document.querySelectorAll(".dm-ghost").forEach((g) => g.remove());
      root.replaceChildren();
      root.classList.remove("dm", "dm--compact", "dm--reduce", "is-open", "is-dragging", "has-used");
    },
  };
  return api;
}

export default mountDemo;
