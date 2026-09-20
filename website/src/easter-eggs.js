const normalizeKey = (value) =>
  String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();

const copy = (locale) => {
  const english = String(locale).toLowerCase().startsWith("en");
  return {
    english,
    message(es, en = es) {
      return english ? en : es;
    },
  };
};

/** A quiet layer of discoverable details. It never gates the main experience. */
export function mountEasterEggs({ demoElement, locale = document.documentElement.lang } = {}) {
  const { english, message } = copy(locale);
  const hero = document.querySelector(".hero");
  const heroStage = hero?.querySelector(".hero-stage");
  const attic = document.querySelector(".attic-scene");
  const caption = document.querySelector(".hero .image-caption");
  const favicon = document.querySelector('link[rel~="icon"]');
  const originalTitle = document.title;
  const originalFavicon = favicon?.getAttribute("href");
  const cleanups = [];
  let titleTimer;
  let toastTimer;
  let overlay;
  let keyBuffer = "";
  let doorTaps = [];
  let logoTaps = [];
  let aurioTaps = [];

  if (!heroStage && !attic) return { destroy() {} };

  const schedule = (callback, delay) => {
    const timer = window.setTimeout(callback, delay);
    cleanups.push(() => window.clearTimeout(timer));
    return timer;
  };

  function setFavicon(mood = "door") {
    if (!favicon) return;
    const color = mood === "night" ? "#a783c8" : "#f0b878";
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="16" fill="#201914"/><path d="M19 54V24c0-5 4-9 9-9h17v39H19Z" fill="#9b6d48"/><path d="M31 34h6v6h-6z" fill="${color}"/><path d="M19 54h26" stroke="#e7c59a" stroke-width="3" stroke-linecap="round"/></svg>`;
    favicon.href = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  }

  function announce(text, { mood = "door", sticky = false } = {}) {
    let toast = document.querySelector(".egg-toast");
    if (!toast) {
      toast = document.createElement("div");
      toast.className = "egg-toast";
      toast.setAttribute("role", "status");
      toast.setAttribute("aria-live", "polite");
      document.body.append(toast);
    }
    toast.textContent = text;
    toast.classList.remove("is-visible");
    requestAnimationFrame(() => toast.classList.add("is-visible"));
    window.clearTimeout(toastTimer);
    if (!sticky) toastTimer = window.setTimeout(() => toast.classList.remove("is-visible"), 4200);
    document.documentElement.dataset.eggMood = mood;
    window.clearTimeout(titleTimer);
    document.title = `${english ? "Altillo" : "Altillo"} · ${text}`;
    setFavicon(mood);
    titleTimer = window.setTimeout(() => {
      document.title = originalTitle;
      document.documentElement.dataset.eggMood = "";
      if (favicon && originalFavicon) favicon.href = originalFavicon;
    }, sticky ? 12000 : 3600);
  }

  function closeOverlay() {
    if (!overlay) return;
    overlay.remove();
    overlay = null;
    document.body.classList.remove("has-egg-overlay");
  }

  function openOverlay({ title, body, variant = "note", label = message("Cerrar", "Close") }) {
    closeOverlay();
    overlay = document.createElement("div");
    overlay.className = `egg-overlay egg-overlay-${variant}`;
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");
    overlay.setAttribute("aria-labelledby", "egg-overlay-title");
    overlay.innerHTML = `
      <div class="egg-overlay-card">
        <button class="egg-overlay-close" type="button" aria-label="${label}">×</button>
        <span class="egg-overlay-mark" aria-hidden="true">⌂</span>
        <p class="eyebrow">${message("NOTA ENCONTRADA", "NOTE FOUND")}</p>
        <h2 id="egg-overlay-title">${title}</h2>
        <p>${body}</p>
      </div>`;
    document.body.append(overlay);
    document.body.classList.add("has-egg-overlay");
    overlay.addEventListener("click", (event) => {
      if (event.target === overlay || event.target.closest(".egg-overlay-close")) closeOverlay();
    });
    overlay.querySelector(".egg-overlay-close")?.focus();
  }

  function reveal(id, text, options = {}) {
    if (id.startsWith("demo-")) {
      for (const className of [...document.body.classList]) {
        if (className.startsWith("egg-demo-")) document.body.classList.remove(className);
      }
    }
    announce(text, options);
    document.body.dataset.lastEgg = id;
    document.body.classList.add(`egg-${id}`);
    schedule(() => document.body.classList.remove(`egg-${id}`), options.sticky ? 12000 : 5000);
  }

  function hotspot(parent, className, label, handler) {
    if (!parent) return;
    parent.classList.add("has-egg-hotspots");
    const button = document.createElement("button");
    button.type = "button";
    button.className = `egg-hotspot ${className}`;
    button.setAttribute("aria-label", label);
    button.addEventListener("click", handler);
    parent.append(button);
    cleanups.push(() => button.remove());
    return button;
  }

  hotspot(
    heroStage,
    "egg-door-hotspot",
    message("Llamar a la puerta", "Knock on the door"),
    () => {
      const now = performance.now();
      doorTaps = doorTaps.filter((time) => now - time < 900);
      doorTaps.push(now);
      if (doorTaps.length >= 3) {
        doorTaps = [];
        reveal("door", message("Alguien ha oído la llamada.", "Someone heard the knock."));
      }
    },
  );

  if (caption) {
    const captionHandler = (event) => {
      if (event.detail !== 2) return;
      openOverlay({
        title: message("La nota del director", "The director's note"),
        body: message(
          "La puerta nunca fue solo una puerta. Era una forma de mirar el hueco que ya estaba ahí.",
          "The door was never just a door. It was a way of looking at the space that was already there.",
        ),
      });
    };
    caption.addEventListener("click", captionHandler);
    cleanups.push(() => caption.removeEventListener("click", captionHandler));
  }

  for (const brand of document.querySelectorAll(".brand")) {
    const brandHandler = (event) => {
      const now = performance.now();
      logoTaps = logoTaps.filter((time) => now - time < 1000);
      logoTaps.push(now);
      if (logoTaps.length < 5) return;
      logoTaps = [];
      event.preventDefault();
      document.body.classList.toggle("egg-night");
      const night = document.body.classList.contains("egg-night");
      reveal(
        "night",
        message(night ? "La casa se ve mejor cuando duerme el resto." : "La luz vuelve a la escalera.", night ? "The house looks better while the rest sleeps." : "The light returns to the stairs."),
        { mood: night ? "night" : "door", sticky: true },
      );
    };
    brand.addEventListener("click", brandHandler);
    cleanups.push(() => brand.removeEventListener("click", brandHandler));
  }

  hotspot(
    attic,
    "egg-attic-lamp",
    message("Mirar junto a la lámpara", "Look beside the lamp"),
    () => reveal("lamp", message("La lámpara lleva encendida más tiempo del que parece.", "The lamp has been on longer than it looks."), { mood: "night" }),
  );
  hotspot(
    attic,
    "egg-attic-paper",
    message("Leer el papel del estante", "Read the paper on the shelf"),
    () => openOverlay({
      title: message("Todavía no", "Not yet"),
      body: message("Hay cosas que conviene dejar arriba un poco más.", "Some things are better left upstairs a little longer."),
      variant: "paper",
    }),
  );
  hotspot(
    attic,
    "egg-attic-chest",
    message("Abrir el baúl", "Open the chest"),
    () => reveal("chest", message("Aurio dejó algo aquí. No parece suyo.", "Aurio left something here. It does not look like his."), { mood: "night" }),
  );

  const aurio = document.querySelector(".aurio-sign");
  const aurioTrigger = document.querySelector(".support-top .eyebrow");
  function revealAurio() {
    if (!aurio) return;
    reveal("aurio", message("El dragón también conoce la puerta.", "The dragon knows the door too."), { mood: "night" });
    aurio.classList.add("is-winking");
    schedule(() => aurio.classList.remove("is-winking"), 1500);
  }
  if (aurio && aurioTrigger) {
    aurioTrigger.classList.add("egg-aurio-trigger");
    const aurioTriggerHandler = () => {
      const now = performance.now();
      aurioTaps = aurioTaps.filter((time) => now - time < 1100);
      aurioTaps.push(now);
      if (aurioTaps.length < 3) return;
      aurioTaps = [];
      revealAurio();
    };
    aurioTrigger.addEventListener("click", aurioTriggerHandler);
    cleanups.push(() => {
      aurioTrigger.removeEventListener("click", aurioTriggerHandler);
      aurioTrigger.classList.remove("egg-aurio-trigger");
    });
  }

  function toggleNight() {
    document.body.classList.toggle("egg-night");
    const night = document.body.classList.contains("egg-night");
    reveal("night", message(night ? "La casa se ve mejor cuando duerme el resto." : "La luz vuelve a la escalera.", night ? "The house looks better while the rest sleeps." : "The light returns to the stairs."), { mood: night ? "night" : "door", sticky: true });
  }

  function processSequence(sequence) {
    const value = normalizeKey(sequence);
    if (value.endsWith("ALTILLO") || value.endsWith("ATTIC")) {
      openOverlay({
        title: message("El plano no termina aquí", "The blueprint does not end here"),
        body: message("Has encontrado la habitación que no aparece en la visita. No hay nada que completar. Solo una puerta más.", "You found the room that is not part of the tour. There is nothing to complete. Just one more door."),
      });
      return true;
    }
    if (value.endsWith("PUERTA") || value.endsWith("DOOR")) {
      reveal("key", message("La llave estaba en tu bolsillo.", "The key was in your pocket."), { mood: "door" });
      return true;
    }
    if (value.endsWith("DESVAN") || value.endsWith("NIGHT")) {
      toggleNight();
      return true;
    }
    if (value.endsWith("AURIO")) {
      revealAurio();
      return true;
    }
    return false;
  }

  const keyHandler = (event) => {
    if (event.target.closest?.("input, textarea, select, [contenteditable='true']")) return;
    if (event.key === "Escape") {
      closeOverlay();
      return;
    }
    if (event.key === "d" || event.key === "D") {
      toggleNight();
      return;
    }
    if (event.key === "?") {
      openOverlay({
        title: message("Hay algo arriba", "There is something upstairs"),
        body: message("Prueba con la puerta, el nombre del proyecto o una visita nocturna.", "Try the door, the project name or a visit at night."),
      });
      return;
    }
    if (event.key.length !== 1 || event.metaKey || event.ctrlKey) return;
    keyBuffer = `${keyBuffer}${normalizeKey(event.key)}`.slice(-24);
    processSequence(keyBuffer);
  };
  document.addEventListener("keydown", keyHandler);
  cleanups.push(() => document.removeEventListener("keydown", keyHandler));

  const demoEggHandler = (event) => {
    const detail = event.detail || {};
    if (!detail.message) return;
    reveal(`demo-${detail.id || "secret"}`, detail.message, { mood: detail.mood || "door" });
  };
  const demoResetHandler = () => {
    for (const className of [...document.body.classList]) {
      if (className.startsWith("egg-demo-")) document.body.classList.remove(className);
    }
    if (document.body.dataset.lastEgg?.startsWith("demo-")) delete document.body.dataset.lastEgg;
  };
  demoElement?.addEventListener("demo:egg", demoEggHandler);
  cleanups.push(() => demoElement?.removeEventListener("demo:egg", demoEggHandler));
  demoElement?.addEventListener("demo:reset", demoResetHandler);
  cleanups.push(() => demoElement?.removeEventListener("demo:reset", demoResetHandler));

  // A small reward for inspecting the page. It contains no sensitive information.
  console.info(`%c${english ? "The attic is open." : "El altillo está abierto."} %c${english ? "Try the door." : "Prueba la puerta."}`, "color:#f0b878;font-weight:600", "color:#9d968d");

  return {
    destroy() {
      cleanups.splice(0).forEach((cleanup) => cleanup());
      closeOverlay();
      document.body.classList.remove("egg-night", "has-egg-overlay");
      document.querySelector(".egg-toast")?.remove();
      window.clearTimeout(titleTimer);
      window.clearTimeout(toastTimer);
      document.title = originalTitle;
      if (favicon && originalFavicon) favicon.href = originalFavicon;
    },
  };
}
