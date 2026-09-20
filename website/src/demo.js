import "./demo.css";
import { createDemoCopy } from "./demo-copy.js";

const paths = {
  shelf: '<path d="m3 10 9-7 9 7v10H3Z"/><path d="M8 20v-8h8v8"/>',
  folder: '<path d="M3 6h7l2 3h9v11H3Z"/>',
  chevron: '<path d="m14 5-7 7 7 7"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  reset: '<path d="M3 10a9 9 0 1 1 1 8M3 4v6h6"/>',
  up: '<path d="M12 20V4m-6 6 6-6 6 6"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
};
const svg = (name) =>
  `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.folder}</svg>`;
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
  if (!element) return { setChapter() {}, reset() {} };
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
  };
  let drag = null;
  let suppressClick = false;
  let returnFocus = null;
  element.innerHTML = `
    <div class="ad-desktop" aria-label="Escritorio Mac de demostración">
      <div class="ad-wallpaper" aria-hidden="true"></div>
      <div class="ad-menubar" aria-hidden="true"><div><span class="ad-apple">●</span><b>Finder</b><span>Archivo</span><span>Edición</span><span>Visualización</span></div><div><span>⌁</span><span>◧</span><span>Mar 10:24</span></div></div>
      <div class="ad-notch" data-open="false">
        <div class="ad-notch-bar"><button type="button" data-action="usage" class="ad-usage-trigger" aria-label="Ver consumo de Claude y Codex" aria-expanded="false"><span class="ad-tiny-ring"></span><span>85</span></button><span class="ad-camera" aria-hidden="true"></span><button type="button" data-action="shelf" class="ad-shelf-trigger" aria-label="Abrir estante" aria-expanded="false">${svg("shelf")}<span>0</span></button></div>
        <div class="ad-notch-panel" hidden></div>
      </div>
      <button type="button" class="ad-notch-cue" data-action="shelf" aria-label="Abrir Altillo"><span aria-hidden="true">↑</span><span class="ad-cue-label">${canHover.matches ? "Acerca el cursor aquí" : "Toca para abrir"}</span></button>
      <section class="ad-finder ad-window" aria-label="Finder: documentos de ejemplo">
        <div class="ad-finder-sidebar"><div class="ad-sidebar-traffic">${traffic}</div><small>Favoritos</small><span>◷ &nbsp; Recientes</span><span>▣ &nbsp; Escritorio</span><span class="is-current">${svg("folder")} Documentos</span><span>↓ &nbsp; Descargas</span><small>Ubicaciones</small><span>▱ &nbsp; Mi Mac</span></div>
        <div class="ad-finder-main"><div class="ad-window-title"><span class="ad-mobile-traffic">${traffic}</span><span class="ad-finder-arrows" aria-hidden="true">${svg("chevron")}${svg("chevron")}</span><strong>Documentos</strong><span class="ad-finder-tools" aria-hidden="true">${svg("grid")}${svg("search")}</span></div><div class="ad-finder-files"></div><div class="ad-finder-bottom"><span class="ad-selection-meta"></span><button type="button" data-action="add">${svg("up")} Subir al estante</button></div></div>
      </section>
      <section class="ad-terminal ad-window" aria-label="Terminal de ejemplo"><div class="ad-terminal-title">${traffic}<span>mi-web — claude</span><span aria-hidden="true">⌘</span></div><div class="ad-terminal-body"><p><span class="ad-terminal-star">✳</span><b>Claude Code</b><span class="ad-terminal-version">v2.1</span></p><p class="ad-terminal-path">~/proyectos/mi-web</p><p class="ad-terminal-line"><span>❯</span> Publica los cambios de la web</p><div class="ad-terminal-result"></div><button type="button" data-action="agent"><span>↳</span> Pedir permiso para continuar <span class="ad-terminal-enter">↵</span></button></div></section>
      <button type="button" class="ad-destination" data-action="deliver" aria-label="Llevar el archivo del estante a Entregas"><span class="ad-folder-art" aria-hidden="true"></span><span>Entregas</span><small>Carpeta vacía</small></button>
      <div class="ad-dock" aria-hidden="true"><span class="ad-dock-finder"><i>⌣</i></span><span class="ad-dock-safari">◈</span><span class="ad-dock-notes"><i></i></span><span class="ad-dock-terminal">&gt;_</span><span class="ad-dock-divider"></span><span class="ad-dock-folder">${svg("folder")}</span><span class="ad-dock-trash">▤</span></div>
      <div class="ad-screen-label">DEMO · DATOS DE EJEMPLO</div>
    </div>
    <div class="ad-demo-caption"><p class="ad-instruction"></p><button type="button" data-action="reset" aria-label="Reiniciar demo">${svg("reset")}<span>Reiniciar</span></button></div>
    <p class="ad-sr" role="status" aria-live="polite" aria-atomic="true"></p>
  `;
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
  document.addEventListener("pointerdown", (event) => {
    if (state.open && !notch.contains(event.target) && !cue.contains(event.target)) close();
  });
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
    return `<button type="button" class="ad-file ${source === "finder" && state.selected === doc.id ? "is-selected" : ""}" data-doc="${doc.id}" data-source="${source}" aria-label="${doc.name}${source === "shelf" ? ", en el estante" : ", documento de ejemplo"}" aria-pressed="${source === "finder" && state.selected === doc.id}">${art(doc)}<span class="ad-filename">${doc.name}</span>${source === "finder" && state.shelf.includes(doc.id) ? '<span class="ad-file-shelved" aria-label="En el estante">↗</span>' : ""}</button>`;
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
        ? '<span>↳</span> Ver solicitud en Altillo <span class="ad-terminal-enter">↵</span>'
        : state.agent === "idle"
          ? '<span>↳</span> Pedir permiso para continuar <span class="ad-terminal-enter">↵</span>'
          : '<span>↳</span> Probar otra solicitud <span class="ad-terminal-enter">↵</span>';
    localize(element.querySelector('.ad-terminal'));
  }
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
      content = `<div class="ad-shelf-wood" data-dropzone="shelf">${state.shelf.length ? state.shelf.map((id) => `<div class="ad-shelf-tile">${fileButton(getDoc(id), "shelf")}<button type="button" class="ad-remove" data-remove="${id}" aria-label="Retirar ${getDoc(id).name}">${svg("close")}</button></div>`).join("") : `<div class="ad-empty-shelf">${svg("shelf")}<span>Deja aquí lo que vas a usar después.</span><small>Arrastra un archivo desde Documentos</small></div>`}<div class="ad-plank" aria-hidden="true"></div></div><div class="ad-panel-footer"><span>${state.shelf.length ? "Arrástralo a Entregas cuando lo necesites." : "Tus archivos, a un gesto de distancia."}</span>${state.shelf.length ? '<button type="button" data-action="deliver">Llevar a Entregas ↗</button>' : ""}</div>`;
    } else if (state.open === "usage") {
      content = `<div class="ad-usage-cards">${[
        {
          name: "Claude",
          mark: "✳",
          value: 85,
          weekly: 41,
          reset: "1 h 11 min",
          plan: "Max 20×",
          note: "9 puntos por delante del ritmo",
        },
        {
          name: "Codex",
          mark: "&gt;_",
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
      content = `<div class="ad-agent-request ${resolved ? "is-resolved" : ""}"><div class="ad-agent-heading"><i class="ad-provider">✳</i><strong>${resolved ? (state.agent === "allowed" ? "Permiso concedido" : "Acción denegada") : "Claude quiere hacer algo en mi-web"}</strong><small>ahora</small></div><div class="ad-agent-command"><span>Bash</span><code>git push origin feat/nueva-web</code></div><div class="ad-agent-controls"><span>${resolved ? (state.agent === "allowed" ? "El agente puede continuar." : "El comando no se ejecutará.") : "Publicar los cambios en el repositorio"}</span>${resolved ? '<button type="button" data-action="agent">Otra solicitud</button>' : '<button type="button" data-action="deny">Denegar</button><button type="button" data-action="allow">Permitir</button>'}</div></div><div class="ad-agent-task"><i class="ad-provider ad-provider-codex">&gt;_</i><strong>api</strong><span>Ejecutando tests · 42 de 118</span><small>••• Trabajando</small></div><div class="ad-panel-footer"><span>Solicitud simulada · función en desarrollo</span></div>`;
    }
    panel.innerHTML = `<div class="ad-panel-heading"><strong>${state.open === "shelf" ? `${svg("shelf")} Altillo` : state.open === "usage" ? "Tu consumo" : "Agentes"}</strong><button type="button" data-action="close" aria-label="Cerrar Altillo">${svg("close")}</button></div>${content}`;
    localize(panel);
    updateInstruction();
  }
  function updateInstruction() {
    const message =
      state.open === "usage"
        ? "Claude y Codex, de un vistazo. Pulsa fuera para seguir."
        : state.open === "agents"
          ? "Decide aquí. El agente recibe tu respuesta sin cambiar de ventana."
          : state.shelf.length
            ? "Ahora llévalo a la carpeta Entregas. O déjalo arriba para luego."
            : "Arrastra un documento al notch. También puedes seleccionarlo y pulsar «Subir al estante».";
    element.querySelector(".ad-instruction").textContent = t(!state.open && !state.shelf.length ? (canHover.matches ? "Acerca el cursor al notch para abrir Altillo. Después, arrastra un documento." : "Toca arriba para abrir Altillo. Después, selecciona un documento y súbelo al estante.") : message);
  }
  function open(view, focus = false) {
    returnFocus =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    state.open = view;
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
    cancelDrag();
    close();
    Object.assign(state, {
      open: null,
      shelf: [],
      delivered: [],
      selected: "ideas",
      agent: "idle",
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
    setChapter(chapter) {
      if (!["shelf", "usage", "agents"].includes(chapter) || drag) return;
      pinned = false; hoverOpened = false;
      clearTimeout(hoverOpenTimer); clearTimeout(hoverCloseTimer);
      if (chapter === "agents" && state.agent === "idle") {
        state.agent = "waiting";
        renderTerminal();
      }
      if (chapter === "shelf" && !state.shelf.length) close();
      else open(chapter);
    },
    reset,
  };
}
