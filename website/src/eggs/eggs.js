/* ==========================================================================
   Altillo — easter eggs engine for the marketing-site prototypes.

   Vanilla ES module, no dependencies, style-agnostic (theme it with the
   --egg-* custom properties documented in README.md).

     import { mountEggs } from "./eggs/eggs.js";
     const eggs = mountEggs({
       locale: "en",
       demoRoot: document.querySelector("#demo"),
       selectors: { logo: ".brand", heroNotch: ".hero .an-notch", footer: "footer" },
     });

   Every egg announces itself as a notch *peek*: a small black pill that
   drops from the top centre of the viewport. Found eggs are remembered in
   localStorage and listed in the secret drawer (press ? or use the keyhole).
   ========================================================================== */

const STORE_KEY = "altillo.eggs.v1";
const DEMO_EVENT = "altillo-demo";
const OUT_EVENT = "altillo-eggs";
const GITHUB = "https://github.com/XusBadia/altillo";
const AURIO_URL = "https://www.aurioapp.com";
const AURIO_IMG = "/media/aurio-mascot-wink.webp";

/* ---------- Small utilities (exported so pages can reuse them) ----------- */

/** Accent- and case-insensitive: "Desván" → "desvan". */
export const normalize = (value) =>
  String(value ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();

const ARROWS = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right" };

/** A KeyboardEvent → a token ("a", "up", …) or null if it should be ignored. */
export function keyToken(event) {
  if (event.metaKey || event.ctrlKey || event.altKey) return null;
  if (ARROWS[event.key]) return ARROWS[event.key];
  if (event.key && event.key.length === 1) return normalize(event.key);
  return null;
}

const isTyping = (target) =>
  !!target?.closest?.("input, textarea, select, [contenteditable=''], [contenteditable='true']");

/** A word ("altillo") or an array of tokens (["up","up",…]) → tokens. */
const toTokens = (sequence) =>
  Array.isArray(sequence) ? sequence.map(normalize) : [...normalize(sequence)];

/**
 * Listen for a key sequence anywhere on the page (ignores form fields and
 * modifier chords). Returns a cleanup function.
 */
export function onKeySequence(sequence, callback, { target = document } = {}) {
  const wanted = toTokens(sequence);
  let buffer = [];
  const handler = (event) => {
    if (isTyping(event.target)) return;
    const token = keyToken(event);
    if (!token) return;
    buffer = [...buffer, token].slice(-wanted.length);
    if (buffer.length === wanted.length && buffer.every((t, i) => t === wanted[i])) {
      buffer = [];
      callback(event);
    }
  };
  target.addEventListener("keydown", handler);
  return () => target.removeEventListener("keydown", handler);
}

/**
 * Call `callback` after `count` clicks on `element`, each within `windowMs`
 * of the previous one. Returns a cleanup function.
 */
export function tapCounter(element, count, callback, { windowMs = 700, event = "click" } = {}) {
  if (!element) return () => {};
  let taps = [];
  const handler = (e) => {
    const now = performance.now();
    taps = taps.filter((t) => now - t < windowMs * count);
    if (taps.length && now - taps[taps.length - 1] > windowMs) taps = [];
    taps.push(now);
    if (taps.length >= count) {
      taps = [];
      callback(e);
    }
  };
  element.addEventListener(event, handler);
  return () => element.removeEventListener(event, handler);
}

const resolve = (value, root = document) => {
  if (!value) return null;
  if (typeof value === "string") return root.querySelector(value);
  return value instanceof Element ? value : null;
};

const esc = (text) =>
  String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const prefersReducedMotion = () =>
  typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ---------- Icons: 24×24, stroke = currentColor --------------------------- */

const svg = (body, extra = "") =>
  `<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"${extra}>${body}</svg>`;

export const ICONS = {
  house: svg('<path d="M12 3.2 20.5 10.4V20.5H3.5V10.4Z"/><rect x="9.6" y="12.2" width="4.8" height="4.8" rx=".6" fill="var(--egg-accent)" stroke="none" class="egg-i-window"/>'),
  knock:
    '<svg viewBox="0 0 256 256" width="24" height="24" fill="currentColor" aria-hidden="true" focusable="false"><path d="M216,64v90.93c0,46.2-36.85,84.55-83,85.06A83.71,83.71,0,0,1,72.6,215.4C50.79,192.33,26.15,136,26.15,136a16,16,0,0,1,6.53-22.23c7.66-4,17.1-.84,21.4,6.62l21,36.44a6.09,6.09,0,0,0,6,3.09l.12,0A8.19,8.19,0,0,0,88,151.74V48a16,16,0,0,1,16.77-16c8.61.4,15.23,7.82,15.23,16.43V112a8,8,0,0,0,8.53,8,8.17,8.17,0,0,0,7.47-8.25V32a16,16,0,0,1,16.77-16c8.61.4,15.23,7.82,15.23,16.43V120a8,8,0,0,0,8.53,8,8.17,8.17,0,0,0,7.47-8.25V64.45c0-8.61,6.62-16,15.23-16.43A16,16,0,0,1,216,64Z"/></svg>',
  bulb: svg('<path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8c.7.6 1.1 1.3 1.1 2.2h5c0-.9.4-1.6 1.1-2.2A6 6 0 0 0 12 3Z" fill="var(--egg-accent)" fill-opacity=".35"/>'),
  plan: svg('<path d="M3.5 5.5 9 3.5l6 2 5.5-2v15l-5.5 2-6-2-5.5 2Z"/><path d="M9 3.5v15M15 5.5v15"/>'),
  creak: svg('<path d="M3 15c2-3 4 3 6 0s4 3 6 0 4 3 6 0"/><path d="M3 9c2-3 4 3 6 0s4 3 6 0 4 3 6 0" opacity=".55"/>'),
  shield: svg('<path d="M12 3 19.5 6v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6Z"/><path d="m8.8 12.2 2.3 2.3 4.3-4.6"/>'),
  vinyl: svg('<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.4" fill="var(--egg-accent)" stroke="none"/><path d="M12 6.2a5.8 5.8 0 0 1 5.8 5.8" opacity=".55"/>'),
  mirror: svg('<ellipse cx="12" cy="10" rx="6" ry="7.5"/><path d="M12 17.5V21M8.5 21h7"/><path d="M9.5 7.5a3 3 0 0 1 2-1.6" opacity=".6"/>'),
  moon: svg('<path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10Z" fill="var(--egg-accent)" fill-opacity=".25"/>'),
  terminal: svg('<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="m7.5 10 3 2.5-3 2.5M12.5 15.5h4"/>'),
  dragon: svg('<path d="M5 18c0-6 3.5-10 8.5-10 2.2 0 4 .9 5.2 2.3L21 9.5l-1 3c.3 3.2-2.7 5.5-6 5.5Z"/><path d="M9 8 7.5 4.5 11 7M14 8l.5-3.5 2 3.8"/><circle cx="16.2" cy="12" r=".9" fill="currentColor" stroke="none"/>'),
  sleep: svg('<path d="M4 8h5l-5 6h5M13 4h4l-4 5h4M15 13h5l-5 6h5"/>'),
  question: svg('<circle cx="12" cy="12" r="9"/><path d="M9.6 9.4a2.5 2.5 0 1 1 3.3 2.4c-.6.2-.9.7-.9 1.3v.6"/><circle cx="12" cy="16.9" r=".6" fill="currentColor"/>'),
  key: svg('<circle cx="8" cy="12" r="4"/><path d="M12 12h9M17.5 12v3M20.5 12v2.5"/>'),
  keyhole: svg('<circle cx="12" cy="9.5" r="3.2"/><path d="M10.6 12.2 9.5 19h5l-1.1-6.8"/>'),
  door: svg('<path d="M6 21V4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21M4 21h16"/><circle cx="14.7" cy="12.5" r=".9" fill="currentColor" stroke="none"/>'),
};

/* ---------- Copy ---------------------------------------------------------- */

const STRINGS = {
  en: {
    drawerTitle: "The secret drawer",
    drawerLabel: "Secret drawer: easter eggs found",
    count: (n, total) => `${n} of ${total} found`,
    keyhole: "Open the secret drawer",
    close: "Close",
    putBack: "Put it back",
    noteFound: "Note found",
    reset: "Forget what I found",
    resetDone: "Forgotten. The house keeps its secrets again.",
    nightOn: "Lights out",
    nightOff: "Lights on",
    unknown: "Not found yet",
    nightToggle: "Night mode",
    hidden: "Someone left the light on…",
    allFound: "Every door opened. You know this attic better than we do.",
    hintLead: "Hint",
  },
  es: {
    drawerTitle: "El cajón secreto",
    drawerLabel: "Cajón secreto: huevos de pascua encontrados",
    count: (n, total) => `${n} de ${total} encontrados`,
    keyhole: "Abrir el cajón secreto",
    close: "Cerrar",
    putBack: "Dejarla donde estaba",
    noteFound: "Nota encontrada",
    reset: "Olvidar lo encontrado",
    resetDone: "Olvidado. La casa vuelve a guardar sus secretos.",
    nightOn: "Apagar la luz",
    nightOff: "Encender la luz",
    unknown: "Aún sin encontrar",
    nightToggle: "Modo noche",
    hidden: "Alguien se dejó la luz encendida…",
    allFound: "Todas las puertas abiertas. Conoces este altillo mejor que nosotros.",
    hintLead: "Pista",
  },
};

/** Built-in catalogue copy: [title, hint, message]. */
const EGG_COPY = {
  en: {
    knock: ["The knock", "The notch has a door. Doors like a knock — three, quick.", "Someone heard the knock."],
    "lights-out": ["Lights out", "Say the name of the house. Just type it.", "Lights out. Mind the stairs."],
    blueprint: ["The blueprint", "Old games had a code for everything. ↑ ↑ ↓ ↓ …", "You found the plans."],
    creak: ["The creak", "Load the shelf until there’s no room left.", "The attic creaks."],
    "good-call": ["Good call", "When an agent wants to wipe everything, say no.", "Good call."],
    "fourth-track": ["Track four", "Play every record on the shelf.", "Bonus track"],
    "still-you": ["Still you", "Mirrors don’t change their minds. Ask five times.", "Still you."],
    "window-light": ["Someone’s home", "The logo is a house. Knock on it five times.", "Someone’s home."],
    "light-on": ["Light left on", "Wander off to another tab. Then come back.", "Welcome back. We kept the light on."],
    "night-owl": ["Night owl", "Drop by after midnight, before five.", "The house looks better while the rest sleeps."],
    console: ["Developer’s entrance", "Builders use the side door: the console.", "Side door’s open. Hi, builder."],
    aurio: ["The neighbour", "The dragon next door answers to its name.", "Aurio waves from next door."],
    yawn: ["The yawn", "Do nothing at all for a minute.", "*yawns* Still up here if you need me."],
    hint: ["Curiosity", "Press ? anywhere.", "Curious? Good. Here’s the drawer."],
  },
  es: {
    knock: ["La llamada", "El notch tiene una puerta. Llama tres veces, rápido.", "Alguien ha oído la llamada."],
    "lights-out": ["Luces fuera", "Di el nombre de la casa. Escríbelo sin más.", "Luces fuera. Cuidado con la escalera."],
    blueprint: ["El plano", "Los juegos de antes tenían un código para todo. ↑ ↑ ↓ ↓ …", "Has encontrado los planos."],
    creak: ["El crujido", "Llena el altillo hasta que no quepa nada.", "El altillo cruje."],
    "good-call": ["Bien visto", "Cuando un agente quiera borrarlo todo, dile que no.", "Bien visto."],
    "fourth-track": ["La cuarta pista", "Escucha todas las canciones de Sonando.", "Pista oculta"],
    "still-you": ["Sigues siendo tú", "Los espejos no cambian de opinión. Pregunta cinco veces.", "Sigues siendo tú."],
    "window-light": ["Hay alguien en casa", "El logo es una casa. Llama cinco veces.", "Hay alguien en casa."],
    "light-on": ["La luz encendida", "Vete a otra pestaña. Luego vuelve.", "Bienvenido. Te dejamos la luz encendida."],
    "night-owl": ["Búho", "Pásate después de medianoche y antes de las cinco.", "La casa se ve mejor cuando duerme el resto."],
    console: ["La entrada de servicio", "Quien construye entra por la puerta lateral: la consola.", "La puerta lateral está abierta. Hola."],
    aurio: ["El vecino", "El dragón de al lado responde a su nombre.", "Aurio saluda desde la casa de al lado."],
    yawn: ["El bostezo", "No hagas nada durante un minuto.", "*bosteza* Sigo aquí arriba si me necesitas."],
    hint: ["Curiosidad", "Pulsa ? en cualquier sitio.", "¿Curiosidad? Bien. Aquí está el cajón."],
  },
};

const HIDDEN_TRACK = { title: "Dust on the Rafters", artist: "The Attic Sessions", number: 4 };

/* ---------- Favicon for the hidden tab ------------------------------------ */

const LIGHT_ON_FAVICON =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="15" fill="#120e0a"/><circle cx="32" cy="38" r="22" fill="#ffb547" opacity=".22"/><path d="M32 10 54 28v26H10V28Z" fill="none" stroke="#f6efe3" stroke-width="5" stroke-linejoin="round"/><rect x="25" y="32" width="14" height="14" rx="2" fill="#ffb547"/></svg>`,
  );

/* ---------- The blueprint (hand-drawn attic floor plan) ------------------- */

function blueprintSVG(english) {
  const L = english
    ? { shelf: "SHELF", usage: "USAGE", agents: "AGENTS", music: "MUSIC", cal: "CALENDAR", stairs: "STAIRS", secret: "not on the tour", title: "ALTILLO · ATTIC LEVEL", sheet: "SHEET 1 OF 1 · SCALE: ROUGHLY", drawn: "drawn by: someone upstairs", camera: "camera (do not knock)" }
    : { shelf: "ALTILLO", usage: "USO", agents: "AGENTES", music: "SONANDO", cal: "AGENDA", stairs: "ESCALERA", secret: "fuera de la visita", title: "ALTILLO · PLANTA ÁTICO", sheet: "HOJA 1 DE 1 · ESCALA: A OJO", drawn: "dibujado por: alguien de arriba", camera: "cámara (no llamar)" };
  return `
<svg class="egg-blueprint" viewBox="0 0 560 380" role="img" aria-label="${esc(english ? "A hand-drawn floor plan of the attic, with one room that is not on the tour" : "Un plano dibujado a mano del altillo, con una habitación fuera de la visita")}">
  <defs>
    <filter id="egg-wobble" x="-5%" y="-5%" width="110%" height="110%">
      <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="7"/>
      <feDisplacementMap in="SourceGraphic" scale="3.2"/>
    </filter>
    <pattern id="egg-grid" width="20" height="20" patternUnits="userSpaceOnUse">
      <path d="M20 0H0V20" fill="none" stroke="currentColor" stroke-opacity=".09" stroke-width="1"/>
    </pattern>
    <pattern id="egg-hatch" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <path d="M0 0V7" stroke="currentColor" stroke-opacity=".35" stroke-width="1.2"/>
    </pattern>
  </defs>
  <rect width="560" height="380" fill="url(#egg-grid)"/>
  <g filter="url(#egg-wobble)" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <!-- the camera: the notch itself, drawn in the ceiling -->
    <path d="M226 26h108v16a8 8 0 0 1-8 8h-92a8 8 0 0 1-8-8Z" stroke-width="2" fill="url(#egg-hatch)"/>
    <!-- outer walls -->
    <path d="M40 50H520V300H40Z" stroke-width="4.5"/>
    <!-- roof slope (dashed: low ceiling) -->
    <path d="M58 68H502M258 282H502" stroke-width="1.3" stroke-dasharray="7 6" opacity=".55"/>
    <!-- interior walls (gaps are doorways) -->
    <path d="M250 50V98M250 136V300" stroke-width="3"/>
    <path d="M400 50V100M400 136V230M400 266V300" stroke-width="3"/>
    <path d="M250 190H256M292 190H520" stroke-width="3"/>
    <!-- door swings -->
    <path d="M250 136a38 38 0 0 1 38-38" stroke-width="1.4" opacity=".7"/>
    <path d="M292 190A36 36 0 0 1 256 226" stroke-width="1.4" opacity=".7"/>
    <path d="M400 266a36 36 0 0 1 36-36" stroke-width="1.4" opacity=".7"/>
    <path d="M400 100A36 36 0 0 0 364 136" stroke-width="1.4" opacity=".7"/>
    <!-- shelf: planks along the wall -->
    <path d="M62 84h166M62 100h166" stroke-width="1.6"/>
    <path d="M78 84v-8h18v8M118 84v-10h14v10M160 84v-6h24v6" stroke-width="1.3"/>
    <!-- usage: a gauge -->
    <path d="M300 128a26 26 0 0 1 52 0" stroke-width="1.6"/><path d="M326 128l12-14" stroke-width="1.6"/>
    <!-- agents: a table and chairs -->
    <rect x="432" y="96" width="56" height="34" rx="4" stroke-width="1.6"/>
    <path d="M440 142h14M466 142h14M440 84h14M466 84h14" stroke-width="1.6"/>
    <!-- music: a record -->
    <circle cx="462" cy="256" r="22" stroke-width="1.6"/><circle cx="462" cy="256" r="4" stroke-width="1.6"/>
    <!-- calendar -->
    <rect x="304" y="238" width="44" height="40" rx="3" stroke-width="1.6"/><path d="M304 250h44M316 232v10M336 232v10" stroke-width="1.6"/>
    <!-- stairs -->
    <path d="M56 214h68M56 228h68M56 242h68M56 256h68M56 270h68M56 284h68" stroke-width="1.4"/>
    <path d="M90 204v84m-7-8 7 9 7-9" stroke-width="1.5"/>
    <!-- dimension line -->
    <path d="M40 330H520M40 322v16M520 322v16" stroke-width="1.2" opacity=".75"/>
    <!-- compass -->
    <path d="M500 346l8-22 8 22-8-6Z" stroke-width="1.4"/>
  </g>
  <!-- the room that is not on the tour: dashed walls, a hidden door, a lamp left on -->
  <g class="egg-bp-secret" fill="none" stroke-linecap="round" stroke-linejoin="round" filter="url(#egg-wobble)">
    <path d="M140 300V272M140 238V190H250" stroke="currentColor" stroke-width="2.4" stroke-dasharray="8 7"/>
    <path d="M140 238a34 34 0 0 1 34 34" stroke="var(--egg-accent)" stroke-width="1.6" stroke-dasharray="4 4"/>
    <circle cx="206" cy="252" r="34" fill="var(--egg-accent)" fill-opacity=".16" stroke="none"/>
    <circle cx="206" cy="252" r="5" fill="var(--egg-accent)" stroke="none"/>
  </g>
  <g class="egg-bp-labels" fill="currentColor" font-family="var(--egg-hand)" text-anchor="middle">
    <text x="145" y="146" font-size="17" transform="rotate(-2 145 146)">${L.shelf}</text>
    <text x="326" y="160" font-size="16">${L.usage}</text>
    <text x="460" y="170" font-size="16" transform="rotate(1.5 460 170)">${L.agents}</text>
    <text x="462" y="220" font-size="15">${L.music}</text>
    <text x="346" y="222" font-size="14" transform="rotate(-1 346 222)">${L.cal}</text>
    <text x="90" y="198" font-size="13">${L.stairs}</text>
    <text x="280" y="20" font-size="11" opacity=".75">${L.camera}</text>
    <text x="280" y="350" font-size="12" opacity=".75">≈ 760 pt</text>
    <text x="508" y="366" font-size="12">N</text>
    <text x="196" y="210" font-size="14" fill="var(--egg-accent)" transform="rotate(-3 196 210)">${L.secret}</text>
    <text x="206" y="240" font-size="20" fill="var(--egg-accent)">?</text>
  </g>
  <g fill="currentColor" font-family="var(--egg-mono)" font-size="9.5" letter-spacing=".08em">
    <text x="40" y="354" opacity=".85">${L.title}</text>
    <text x="40" y="368" opacity=".6">${L.sheet}</text>
    <text x="330" y="368" opacity=".6" font-family="var(--egg-hand)" font-size="12" letter-spacing="0">${L.drawn}</text>
  </g>
</svg>`;
}

/* ==========================================================================
   mountEggs
   ========================================================================== */

export function mountEggs(options = {}) {
  const {
    locale = document.documentElement.lang || "en",
    selectors = {},
    storageKey = STORE_KEY,
    idleMs = 60_000,
    now = () => new Date(),
    console: consoleEgg = true,
    keyhole: keyholeMode = "auto",
    veil = true,
    aurioImage = AURIO_IMG,
    aurioHref = AURIO_URL,
    builtins = true,
  } = options;

  const english = !normalize(locale).startsWith("es");
  const lang = english ? "en" : "es";
  const S = STRINGS[lang];
  const html = document.documentElement;
  const demoRoot = resolve(options.demoRoot);
  const el = Object.fromEntries(Object.entries(selectors).map(([k, v]) => [k, resolve(v)]));
  const reduced = () => prefersReducedMotion();

  const cleanups = [];
  const timers = new Set();
  const eggs = new Map(); // id → egg definition
  const later = (fn, ms) => {
    const id = setTimeout(() => {
      timers.delete(id);
      fn();
    }, ms);
    timers.add(id);
    return id;
  };
  const listen = (target, type, fn, opts) => {
    if (!target) return () => {};
    target.addEventListener(type, fn, opts);
    const off = () => target.removeEventListener(type, fn, opts);
    cleanups.push(off);
    return off;
  };

  /* ---------- Registry (localStorage) ------------------------------------- */

  const load = () => {
    try {
      const data = JSON.parse(localStorage.getItem(storageKey) || "{}");
      return data && typeof data.found === "object" ? data : { found: {} };
    } catch {
      return { found: {} };
    }
  };
  let store = load();
  const save = () => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(store));
    } catch {
      /* private mode: remember for this visit only */
    }
  };
  const isFound = (id) => !!store.found[id];
  const foundCount = () => [...eggs.keys()].filter(isFound).length;
  const emit = (detail) => {
    document.dispatchEvent(new CustomEvent(OUT_EVENT, { detail }));
    demoRoot?.dispatchEvent(new CustomEvent(OUT_EVENT, { detail }));
  };

  /* ---------- DOM layer --------------------------------------------------- */

  const layer = document.createElement("div");
  layer.className = "egg-layer";
  layer.dataset.eggs = "";
  layer.innerHTML = `
    <div class="egg-veil" aria-hidden="true">
      <div class="egg-veil__dim"></div>
      <div class="egg-veil__dark"></div>
      <div class="egg-veil__cone"></div>
    </div>
    <div class="egg-peek-slot"></div>
    <div class="egg-live egg-sr" role="status" aria-live="polite"></div>`;
  document.body.append(layer);
  const veilEl = layer.querySelector(".egg-veil");
  if (!veil) veilEl.hidden = true;
  const peekSlot = layer.querySelector(".egg-peek-slot");
  const live = layer.querySelector(".egg-live");

  /* ---------- Peek (the signature) ---------------------------------------- */

  const queue = [];
  let peeking = null;

  function peek(text, { icon = "house", mood = "", counter = true, duration, id } = {}) {
    queue.push({ text, icon, mood, counter, duration, id });
    // A burst of discoveries shouldn't turn into a minute of peeks: keep the newest few.
    if (queue.length > 3) queue.splice(0, queue.length - 3);
    const current = peeking;
    if (current && !current._hurried) {
      current._hurried = true;
      later(() => current._dismiss?.(), 1400);
    }
    if (!peeking) nextPeek();
  }

  function nextPeek() {
    const item = queue.shift();
    if (!item) {
      peeking = null;
      return;
    }
    const total = eggs.size;
    const count = foundCount();
    const node = document.createElement("button");
    node.type = "button";
    node.className = `egg-peek${item.mood ? ` egg-peek--${item.mood}` : ""}`;
    node.setAttribute("aria-label", `${item.text} — ${S.close}`);
    const iconHTML = ICONS[item.icon] || (String(item.icon).trim().startsWith("<") ? item.icon : ICONS.house);
    node.innerHTML = `
      <span class="egg-peek__icon">${iconHTML}</span>
      <span class="egg-peek__text">${esc(item.text)}</span>
      ${item.counter && total ? `<span class="egg-peek__count" aria-hidden="true">${count}/${total}</span>` : ""}`;
    peekSlot.append(node);
    live.textContent = item.counter && total ? `${item.text} ${S.count(count, total)}.` : item.text;
    peeking = node;
    requestAnimationFrame(() => requestAnimationFrame(() => node.classList.add("is-in")));
    const base = item.duration ?? Math.min(6500, 2800 + item.text.length * 45);
    const ms = queue.length ? Math.min(base, 1900) : base;
    let done = false;
    const out = () => {
      if (done) return;
      done = true;
      node.classList.remove("is-in");
      node.classList.add("is-out");
      later(() => {
        node.remove();
        nextPeek();
      }, reduced() ? 0 : 320);
    };
    node.addEventListener("click", out);
    node._dismiss = out;
    later(out, ms);
  }

  /* ---------- Note (modal, kraft paper taped to the page) ----------------- */

  let note = null;

  function closeNote() {
    if (!note) return;
    const { scrim, returnFocus, onKey } = note;
    note = null;
    document.removeEventListener("keydown", onKey, true);
    scrim.classList.remove("is-in");
    later(() => scrim.remove(), reduced() ? 0 : 220);
    html.classList.remove("egg-has-note");
    returnFocus?.focus?.({ preventScroll: true });
  }

  function openNote({ title, body = "", figure = "", variant = "kraft", eyebrow } = {}) {
    closeNote();
    const activeBeforeClose = document.activeElement;
    const wasInDrawer = !!(drawer && drawer.panel.contains(activeBeforeClose));
    closeDrawer(false);
    const returnFocus = wasInDrawer ? keyholeEl || document.body : activeBeforeClose;
    const scrim = document.createElement("div");
    scrim.className = `egg-scrim egg-scrim--note`;
    const titleId = `egg-note-title-${Math.random().toString(36).slice(2, 8)}`;
    scrim.innerHTML = `
      <div class="egg-note egg-note--${esc(variant)}" role="dialog" aria-modal="true" aria-labelledby="${titleId}">
        <span class="egg-tape egg-tape--l" aria-hidden="true"></span>
        <span class="egg-tape egg-tape--r" aria-hidden="true"></span>
        <p class="egg-note__eyebrow">${esc(eyebrow ?? S.noteFound)}</p>
        <h2 class="egg-note__title" id="${titleId}">${esc(title)}</h2>
        ${figure ? `<div class="egg-note__figure">${figure}</div>` : ""}
        ${body ? `<p class="egg-note__body">${esc(body)}</p>` : ""}
        <div class="egg-note__actions"><button type="button" class="egg-btn egg-note__close">${esc(S.putBack)}</button></div>
      </div>`;
    layer.append(scrim);
    html.classList.add("egg-has-note");
    const onKey = (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        closeNote();
      } else if (event.key === "Tab") {
        const focusables = [...scrim.querySelectorAll("button, a[href]")];
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", onKey, true);
    scrim.addEventListener("click", (event) => {
      if (event.target === scrim || event.target.closest(".egg-note__close")) closeNote();
    });
    note = { scrim, returnFocus, onKey };
    requestAnimationFrame(() => requestAnimationFrame(() => scrim.classList.add("is-in")));
    scrim.querySelector(".egg-note__close").focus({ preventScroll: true });
  }

  /* ---------- Secret drawer ----------------------------------------------- */

  let drawer = null;

  function renderDrawer() {
    const list = [...eggs.values()];
    const count = foundCount();
    const rows = list
      .map((egg) => {
        const found = isFound(egg.id);
        const iconHTML = ICONS[egg.icon] || (String(egg.icon || "").trim().startsWith("<") ? egg.icon : ICONS.house);
        return `
        <li class="egg-drawer__item${found ? " is-found" : ""}">
          <span class="egg-drawer__icon">${found ? iconHTML : ICONS.keyhole}</span>
          <span class="egg-drawer__words">
            <span class="egg-drawer__name">${found ? esc(egg.title) : `<span class="egg-sr">${esc(S.unknown)}. </span><span aria-hidden="true">• • •</span>`}</span>
            <span class="egg-drawer__hint">${found ? esc(egg.hint || egg.message || "") : `<span class="egg-sr">${esc(S.hintLead)}: </span>${esc(egg.hint || "")}`}</span>
          </span>
        </li>`;
      })
      .join("");
    const dots = list.map((egg) => `<i class="${isFound(egg.id) ? "is-lit" : ""}"></i>`).join("");
    return `
      <div class="egg-drawer__handle" aria-hidden="true"></div>
      <header class="egg-drawer__head">
        <h2 class="egg-drawer__title" id="egg-drawer-title">${esc(S.drawerTitle)}</h2>
        <p class="egg-drawer__count"><span class="egg-drawer__dots" aria-hidden="true">${dots}</span>${esc(count === list.length && list.length ? S.allFound : S.count(count, list.length))}</p>
        <button type="button" class="egg-drawer__x" aria-label="${esc(S.close)}">${svg('<path d="M6 6l12 12M18 6 6 18"/>')}</button>
      </header>
      <ul class="egg-drawer__list">${rows}</ul>
      <footer class="egg-drawer__foot">
        <button type="button" class="egg-btn egg-btn--quiet" data-egg-action="night" aria-pressed="${html.classList.contains("is-night")}">${ICONS.moon}<span>${esc(S.nightToggle)}</span></button>
        <button type="button" class="egg-btn egg-btn--quiet" data-egg-action="reset">${esc(S.reset)}</button>
      </footer>`;
  }

  function openDrawer() {
    if (drawer) return;
    closeNote();
    const returnFocus = document.activeElement;
    const scrim = document.createElement("div");
    scrim.className = "egg-scrim egg-scrim--drawer";
    scrim.innerHTML = `<section class="egg-drawer" role="dialog" aria-modal="true" aria-labelledby="egg-drawer-title"></section>`;
    const panel = scrim.firstElementChild;
    panel.innerHTML = renderDrawer();
    layer.append(scrim);
    const onKey = (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        closeDrawer();
      } else if (event.key === "Tab") {
        const focusables = [...panel.querySelectorAll("button")];
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", onKey, true);
    scrim.addEventListener("click", (event) => {
      if (event.target === scrim || event.target.closest(".egg-drawer__x")) return closeDrawer();
      const action = event.target.closest("[data-egg-action]")?.dataset.eggAction;
      if (action === "night") {
        setNight(!html.classList.contains("is-night"));
        refreshDrawer();
      } else if (action === "reset") {
        reset();
        refreshDrawer();
        peek(S.resetDone, { icon: "key", counter: false });
      }
    });
    drawer = { scrim, panel, returnFocus, onKey };
    html.classList.add("egg-has-drawer");
    keyholeEl?.setAttribute("aria-expanded", "true");
    requestAnimationFrame(() => requestAnimationFrame(() => scrim.classList.add("is-in")));
    panel.querySelector(".egg-drawer__x").focus({ preventScroll: true });
  }

  function refreshDrawer() {
    if (!drawer) return;
    const focusedAction = document.activeElement?.dataset?.eggAction;
    drawer.panel.innerHTML = renderDrawer();
    (focusedAction ? drawer.panel.querySelector(`[data-egg-action="${focusedAction}"]`) : drawer.panel.querySelector(".egg-drawer__x"))?.focus({ preventScroll: true });
  }

  function closeDrawer(restoreFocus = true) {
    if (!drawer) return;
    const { scrim, returnFocus, onKey } = drawer;
    drawer = null;
    document.removeEventListener("keydown", onKey, true);
    scrim.classList.remove("is-in");
    later(() => scrim.remove(), reduced() ? 0 : 260);
    html.classList.remove("egg-has-drawer");
    keyholeEl?.setAttribute("aria-expanded", "false");
    if (restoreFocus) returnFocus?.focus?.({ preventScroll: true });
  }

  /* ---------- Keyhole (drawer entry point) -------------------------------- */

  let keyholeEl = null;
  if (keyholeMode !== false) {
    keyholeEl = document.createElement("button");
    keyholeEl.type = "button";
    keyholeEl.className = "egg-keyhole";
    keyholeEl.setAttribute("aria-label", S.keyhole);
    keyholeEl.setAttribute("aria-haspopup", "dialog");
    keyholeEl.setAttribute("aria-expanded", "false");
    keyholeEl.title = S.keyhole;
    keyholeEl.innerHTML = ICONS.keyhole;
    const footer = el.footer;
    if (footer && keyholeMode !== "fixed") {
      keyholeEl.classList.add("egg-keyhole--inline");
      footer.append(keyholeEl);
    } else {
      keyholeEl.classList.add("egg-keyhole--fixed");
      layer.append(keyholeEl);
    }
    listen(keyholeEl, "click", () => (drawer ? closeDrawer() : openDrawer()));
    cleanups.push(() => keyholeEl.remove());
  }

  /* ---------- Night mode -------------------------------------------------- */

  function setNight(on) {
    html.classList.toggle("is-night", !!on);
    emit({ type: "night", on: !!on });
  }

  let lampTimer = null;
  function lamp(ms = 7000) {
    if (!veil) return;
    veilEl.classList.add("is-lamp");
    const move = (event) => {
      veilEl.style.setProperty("--egg-lamp-x", `${event.clientX}px`);
      veilEl.style.setProperty("--egg-lamp-y", `${event.clientY}px`);
    };
    veilEl.style.setProperty("--egg-lamp-x", `${lastPointer.x}px`);
    veilEl.style.setProperty("--egg-lamp-y", `${lastPointer.y}px`);
    const off = listen(window, "pointermove", move, { passive: true });
    clearTimeout(lampTimer);
    lampTimer = later(() => {
      off();
      veilEl.classList.remove("is-lamp");
    }, ms);
  }
  const lastPointer = { x: innerWidth / 2, y: innerHeight * 0.4 };
  listen(window, "pointermove", (e) => ((lastPointer.x = e.clientX), (lastPointer.y = e.clientY)), { passive: true });

  /* ---------- Found ------------------------------------------------------- */

  function found(id, detail = {}) {
    const egg = eggs.get(id);
    if (!egg) return false;
    const first = !isFound(id);
    if (first) {
      store.found[id] = Date.now();
      save();
    }
    html.dataset.lastEgg = id;
    emit({ type: "found", id, first, count: foundCount(), total: eggs.size });
    if (egg.reveal) egg.reveal(ctx, detail, { first });
    else peek(detail.message || egg.message || egg.title, { icon: egg.icon, id });
    if (drawer) refreshDrawer();
    return true;
  }

  function reset() {
    store = { found: {} };
    save();
    emit({ type: "reset" });
  }

  /* ---------- Context handed to eggs -------------------------------------- */

  const ctx = {
    locale: lang,
    english,
    t: (en, es) => (english ? en : es ?? en),
    el,
    demoRoot,
    peek,
    note: openNote,
    openDrawer,
    closeDrawer,
    setNight,
    lamp,
    later,
    listen,
    reduced,
    onKeys: (sequence, fn) => {
      const off = onKeySequence(sequence, fn);
      cleanups.push(off);
      return off;
    },
    onTaps: (element, count, fn, opts) => {
      const off = tapCounter(element, count, fn, opts);
      cleanups.push(off);
      return off;
    },
    onDemo: (type, fn) => {
      if (!demoRoot) return () => {};
      return listen(demoRoot, DEMO_EVENT, (event) => {
        if (event.detail?.type === type) fn(event.detail || {}, event);
      });
    },
    emit,
  };

  /* ---------- register ---------------------------------------------------- */

  /**
   * register({ id, title, hint, message?, icon?, requires?, trigger?(ctx), reveal?(ctx, detail) })
   * `trigger` wires listeners and calls ctx.found() — or the returned `found` —
   * when discovered. It may return a cleanup function. `requires` lists
   * selector keys / "demoRoot" that must exist; if any is missing the egg is
   * silently skipped (and does not count towards the total).
   */
  function register(def) {
    if (!def?.id || eggs.has(def.id)) return false;
    for (const need of def.requires || []) {
      if (need === "demoRoot" ? !demoRoot : !el[need]) return false;
    }
    const egg = { icon: "house", ...def };
    eggs.set(egg.id, egg);
    const eggCtx = { ...ctx, found: (detail) => found(egg.id, detail), self: egg };
    if (typeof egg.trigger === "function") {
      const off = egg.trigger(eggCtx);
      if (typeof off === "function") cleanups.push(off);
    }
    if (drawer) refreshDrawer();
    return true;
  }

  /* ==========================================================================
     Built-in catalogue
     ========================================================================== */

  const C = EGG_COPY[lang];
  const copy = (id) => ({ title: C[id][0], hint: C[id][1], message: C[id][2] });

  if (builtins) {
    // 1. Knock: three quick clicks on the hero notch (or the demo says so).
    if (el.heroNotch || demoRoot) register({
      id: "knock",
      icon: "knock",
      ...copy("knock"),
      trigger: ({ found, onDemo, onTaps }) => {
        if (el.heroNotch) onTaps(el.heroNotch, 3, () => found(), { windowMs: 450 });
        onDemo("notch-knocked", () => found());
      },
      reveal: ({ peek }, _d) => {
        if (el.heroNotch && !reduced()) {
          el.heroNotch.classList.remove("egg-knocked");
          void el.heroNotch.offsetWidth;
          el.heroNotch.classList.add("egg-knocked");
          later(() => el.heroNotch?.classList.remove("egg-knocked"), 700);
        }
        peek(C.knock[2], { icon: "knock" });
      },
    });

    // 2. Lights out: type "altillo" (or "desván").
    register({
      id: "lights-out",
      icon: "bulb",
      ...copy("lights-out"),
      trigger: ({ found, onKeys }) => {
        onKeys("altillo", () => found());
        onKeys("desvan", () => found());
      },
      reveal: ({ peek }) => {
        const on = !html.classList.contains("is-night");
        setNight(on);
        if (on) {
          lamp(7000);
          peek(C["lights-out"][2], { icon: "bulb", mood: "night" });
        } else {
          veilEl.classList.remove("is-lamp");
          peek(S.nightOff, { icon: "bulb", counter: false });
        }
      },
    });

    // 3. The blueprint: Konami code.
    register({
      id: "blueprint",
      icon: "plan",
      ...copy("blueprint"),
      trigger: ({ found, onKeys }) => onKeys(["up", "up", "down", "down", "left", "right", "left", "right", "b", "a"], () => found()),
      reveal: ({ note }) =>
        note({
          variant: "blueprint",
          eyebrow: english ? "Rolled up behind the rafters" : "Enrollado detrás de las vigas",
          title: english ? "The blueprint" : "El plano",
          figure: blueprintSVG(english),
          body: english
            ? "Every room on the tour, plus one that isn’t. There’s nothing to complete in there. Just a lamp someone forgot to switch off."
            : "Todas las habitaciones de la visita y una que no lo está. Ahí dentro no hay nada que completar. Solo una lámpara que alguien olvidó apagar.",
        }),
    });

    // 4–7. Demo events.
    register({
      id: "creak",
      icon: "creak",
      requires: ["demoRoot"],
      ...copy("creak"),
      trigger: ({ found, onDemo }) => onDemo("shelf-full", () => found()),
      reveal: ({ peek }) => {
        if (!reduced()) {
          demoRoot.classList.remove("egg-creaking");
          void demoRoot.offsetWidth;
          demoRoot.classList.add("egg-creaking");
          later(() => demoRoot.classList.remove("egg-creaking"), 900);
        }
        peek(C.creak[2], { icon: "creak" });
      },
    });

    const RM_RF = /\brm\s+(-[a-z]*r[a-z]*f[a-z]*|-[a-z]*f[a-z]*r[a-z]*|-r\s+-f|-f\s+-r|--recursive\s+--force|--force\s+--recursive)\b/i;
    register({
      id: "good-call",
      icon: "shield",
      requires: ["demoRoot"],
      ...copy("good-call"),
      trigger: ({ found, onDemo }) =>
        onDemo("agent-denied", (detail) => {
          const command = [detail.command, detail.cmd, detail.text, detail.request].filter(Boolean).join(" ");
          if (RM_RF.test(command)) found();
        }),
    });

    register({
      id: "fourth-track",
      icon: "vinyl",
      requires: ["demoRoot"],
      ...copy("fourth-track"),
      trigger: ({ found, onDemo }) => onDemo("all-tracks-played", () => found()),
      reveal: ({ peek, emit }) => {
        emit({ type: "hidden-track", ...HIDDEN_TRACK });
        peek(`${C["fourth-track"][2]}: “${HIDDEN_TRACK.title}”`, { icon: "vinyl", duration: 6000 });
      },
    });

    register({
      id: "still-you",
      icon: "mirror",
      requires: ["demoRoot"],
      ...copy("still-you"),
      trigger: ({ found, onDemo }) => {
        let flips = 0;
        onDemo("mirror-flipped", () => {
          flips += 1;
          if (flips >= 5) {
            flips = 0;
            found();
          }
        });
      },
    });

    // 8. Someone's home: five clicks on the logo light the house window.
    register({
      id: "window-light",
      icon: "house",
      requires: ["logo"],
      ...copy("window-light"),
      // A selector list binds every match (e.g. a hero logo and a sticky
      // nav logo, only one of which is visible at a time).
      trigger: ({ found, onTaps }) => {
        const logos = typeof selectors.logo === "string" ? [...document.querySelectorAll(selectors.logo)] : [el.logo];
        logos.forEach((logo) => onTaps(logo, 5, () => found({ logo }), { windowMs: 600 }));
      },
      reveal: ({ peek }, detail) => {
        const logo = detail?.logo || el.logo;
        logo.classList.remove("egg-flicker");
        void logo.offsetWidth;
        logo.classList.add("egg-flicker");
        later(() => logo?.classList.remove("egg-flicker"), 2600);
        peek(C["window-light"][2], { icon: "house" });
      },
    });

    // 9. Tab hidden: title + favicon swap; found on return.
    register({
      id: "light-on",
      icon: "bulb",
      ...copy("light-on"),
      trigger: ({ found, listen }) => {
        let saved = null;
        let away = false;
        const icons = () => [...document.querySelectorAll('link[rel~="icon"]')];
        listen(document, "visibilitychange", () => {
          if (document.hidden) {
            away = true;
            saved = { title: document.title, icons: icons().map((l) => [l, l.getAttribute("href"), l.getAttribute("type")]) };
            document.title = S.hidden;
            let links = icons();
            if (!links.length) {
              const link = document.createElement("link");
              link.rel = "icon";
              link.dataset.eggTemp = "";
              document.head.append(link);
              links = [link];
            }
            links.forEach((l) => {
              l.setAttribute("href", LIGHT_ON_FAVICON);
              l.setAttribute("type", "image/svg+xml");
            });
          } else if (away) {
            away = false;
            restore();
            found();
          }
        });
        const restore = () => {
          if (!saved) return;
          document.title = saved.title;
          saved.icons.forEach(([l, href, type]) => {
            href == null ? l.removeAttribute("href") : l.setAttribute("href", href);
            type == null ? l.removeAttribute("type") : l.setAttribute("type", type);
          });
          document.querySelectorAll("link[data-egg-temp]").forEach((l) => l.remove());
          saved = null;
        };
        return restore;
      },
      reveal: ({ peek }, _detail, { first }) => {
        if (first) peek(C["light-on"][2], { icon: "bulb" });
      },
    });

    // 10. Night owl: visiting between 00:00 and 05:00 local time.
    register({
      id: "night-owl",
      icon: "moon",
      ...copy("night-owl"),
      trigger: ({ found, later }) => {
        const hour = Number(new URLSearchParams(location.search).get("eggs-hour") ?? now().getHours());
        if (hour >= 0 && hour < 5) later(() => found(), 900);
      },
      reveal: ({ peek }) => {
        setNight(true);
        peek(C["night-owl"][2], { icon: "moon", mood: "night", duration: 6000 });
      },
    });

    // 11. Console: a door for developers. Found by calling altillo.knock().
    if (consoleEgg) {
      register({
        id: "console",
        icon: "terminal",
        ...copy("console"),
        trigger: ({ found }) => {
          const door = [
            "   ___________",
            "  /     |     \\",
            " /______|______\\",
            " |   _______   |",
            " |  |       |  |",
            " |  |    o  |  |   " + (english ? "The attic is open." : "El altillo está abierto."),
            " |  |       |  |   " + (english ? "Knock: altillo.knock()" : "Llama: altillo.knock()"),
            " |__|_______|__|   " + GITHUB,
          ].join("\n");
          // A styled greeting. It contains nothing sensitive.
          console.log(
            `%c${door}\n%c${english ? "Built in the open. Pull requests welcome — wipe your feet." : "Hecho a la vista. Se aceptan pull requests — límpiate los pies."}`,
            "color:#ffb547;font:12px/1.35 ui-monospace,SFMono-Regular,Menlo,monospace",
            "color:#9d968d;font:12px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace",
          );
          const previous = window.altillo;
          if (previous === undefined) {
            window.altillo = Object.freeze({
              knock() {
                found();
                return english ? "Come on up." : "Sube.";
              },
              drawer() {
                openDrawer();
                return "🗝";
              },
            });
            return () => {
              if (window.altillo && window.altillo !== previous) delete window.altillo;
            };
          }
        },
      });
    }

    // 12. Aurio: type "aurio" and the dragon next door peeks in.
    register({
      id: "aurio",
      icon: "dragon",
      ...copy("aurio"),
      trigger: ({ found, onKeys }) => onKeys("aurio", () => found()),
      reveal: ({ peek }) => {
        peek(C.aurio[2], { icon: "dragon" });
        if (!aurioImage) return;
        const probe = new Image();
        probe.onload = () => {
          layer.querySelector(".egg-dragon")?.remove();
          const dragon = document.createElement("a");
          dragon.className = "egg-dragon";
          // aurioHref: a URL opens in a new tab; an in-page "#anchor" scrolls there.
          const local = String(aurioHref).startsWith("#");
          dragon.href = aurioHref;
          if (local) {
            dragon.setAttribute("aria-label", english ? "Aurio, our dragon, from our other app — read about it below" : "Aurio, nuestro dragón, de nuestra otra app — más abajo");
            dragon.addEventListener("click", () => {
              dragon.classList.remove("is-in");
              later(() => dragon.remove(), 700);
            });
          } else {
            dragon.target = "_blank";
            dragon.rel = "noopener";
            dragon.setAttribute("aria-label", english ? "Aurio, our dragon, from our other app — visit aurioapp.com" : "Aurio, nuestro dragón, de nuestra otra app — visita aurioapp.com");
          }
          dragon.innerHTML = `<img src="${esc(aurioImage)}" alt="" width="200" height="200" decoding="async"><span class="egg-dragon__bubble">${esc(english ? "Psst. I live next door." : "Psst. Vivo al lado.")}</span>`;
          layer.append(dragon);
          requestAnimationFrame(() => requestAnimationFrame(() => dragon.classList.add("is-in")));
          later(() => {
            dragon.classList.remove("is-in");
            later(() => dragon.remove(), 700);
          }, 5200);
        };
        probe.src = aurioImage;
      },
    });

    // 13. Yawn: 60 s of nothing.
    register({
      id: "yawn",
      icon: "sleep",
      ...copy("yawn"),
      trigger: ({ found, listen }) => {
        let timer = null;
        let fired = false;
        const arm = () => {
          if (fired) return;
          clearTimeout(timer);
          timer = setTimeout(() => {
            if (document.hidden || note || drawer) return arm();
            fired = true;
            found();
          }, idleMs);
        };
        for (const type of ["pointermove", "pointerdown", "keydown", "scroll", "wheel", "touchstart"]) {
          listen(window, type, arm, { passive: true });
        }
        arm();
        return () => clearTimeout(timer);
      },
      reveal: ({ peek }) => peek(C.yawn[2], { icon: "sleep", mood: "yawn", duration: 5200 }),
    });

    // 14. Curiosity: the ? key opens the drawer.
    register({
      id: "hint",
      icon: "question",
      ...copy("hint"),
      trigger: ({ found, listen }) =>
        listen(document, "keydown", (event) => {
          if (event.key !== "?" || isTyping(event.target) || event.metaKey || event.ctrlKey) return;
          if (note) return;
          event.preventDefault();
          if (drawer) return closeDrawer();
          found();
        }),
      reveal: ({ openDrawer }, _d, { first }) => {
        openDrawer();
        if (first) peek(C.hint[2], { icon: "question" });
      },
    });
  }

  // Custom eggs passed at mount time.
  for (const def of options.eggs || []) register(def);

  return {
    register,
    /** Discover an egg programmatically (tests, custom triggers). */
    trigger: (id, detail) => found(id, detail),
    peek,
    note: openNote,
    closeNote,
    openDrawer,
    closeDrawer,
    setNight,
    lamp,
    reset,
    get total() {
      return eggs.size;
    },
    get count() {
      return foundCount();
    },
    list: () => [...eggs.values()].map(({ id, title, hint }) => ({ id, title, hint, found: isFound(id) })),
    destroy() {
      cleanups.splice(0).forEach((fn) => fn());
      timers.forEach(clearTimeout);
      timers.clear();
      closeNote();
      closeDrawer(false);
      html.classList.remove("is-night", "egg-has-note", "egg-has-drawer");
      delete html.dataset.lastEgg;
      layer.remove();
    },
  };
}

export default mountEggs;
