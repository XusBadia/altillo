// Altillo — B2. The hero notch opening with scroll, the live demo with
// scrollytelling, scroll-linked motion (transform/opacity, one rAF loop),
// and the easter eggs.

// Tells the head's safety net that the page script is running.
window.__altillo = true;

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const mqNarrowNav = matchMedia("(max-width: 940px)");
const mqSteps = matchMedia("(min-width: 1300px)");

const hero = $("#hero");
const pin = $(".hero__pin");
const nav = $("#nav");
const H = {
  slab: $(".hero__slab"),
  open: $(".hero__open"),
  parts: $$(".hero__open > *"),
  ears: $(".hero__ears"),
  copy: $(".hero__copy"),
  glow: $(".hero__glow"),
  notch: $(".hero__notch"),
};

/* ==========================================================================
   Geometry, cached on resize (transforms never feed back into layout).
   ========================================================================== */
let vh = innerHeight;
let sx0 = 0.44, sy0 = 0.155, dy = 180; // pill/panel ratios; panel − pill height
let docH = 0;
const rises = $$("[data-rise]").map((el) => ({ el, top: 0, h: 0 }));
const closing = { ears: $(".closing__ears"), closed: $(".closing__closed"), glow: $(".closing__glow"), house: $(".closing__ears .an-house") };

const docTop = (el) => { let y = 0; for (let n = el; n; n = n.offsetParent) y += n.offsetTop; return y; };

function measure() {
  vh = innerHeight;
  const o = H.open.getBoundingClientRect();
  const e = H.ears.getBoundingClientRect();
  if (o.width && o.height) {
    sx0 = e.width / o.width;
    sy0 = e.height / o.height;
    dy = o.height - e.height;
  }
  for (const r of rises) { r.top = docTop(r.el); r.h = r.el.offsetHeight; }
  docH = document.documentElement.scrollHeight;
}

/* ==========================================================================
   Hero: on load the closed notch springs open into the Shelf (~0.8 s, a
   small overshoot like the app's spring), and the halo fades in. Scrolling
   only adds depth: a brighter, wider halo and a touch of parallax.
   ========================================================================== */
const OPEN_DELAY = 420, OPEN_MS = 720;
let t0 = Infinity;     // when the opening starts
let v = reduce ? 1 : 0;
const backOut = (t) => { const c1 = 0.55, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); };

function paintHero(v, y) {
  const ex = backOut(clamp(v / 0.78));
  const ey = backOut(clamp((v - 0.06) / 0.94));
  H.slab.style.transform = v >= 1 ? "none" : `scale(${lerp(sx0, 1, ex).toFixed(4)}, ${lerp(sy0, 1, ey).toFixed(4)})`;
  H.ears.style.opacity = (1 - clamp(v / 0.18)).toFixed(3);
  const c = easeOut(clamp((v - 0.3) / 0.6));
  for (const el of H.parts) {
    el.style.opacity = c.toFixed(3);
    el.style.transform = c >= 1 ? "none" : `translateY(${(-(1 - c) * 8).toFixed(2)}px) scale(${(0.965 + 0.035 * c).toFixed(4)})`;
  }
  const s = reduce ? 0 : clamp(y / (vh * 0.9));
  const e = easeOut(clamp(v));
  H.glow.style.opacity = ((0.15 + 0.7 * e) * (1 + 0.22 * s)).toFixed(3);
  H.glow.style.transform = `translateY(${(-(1 - e) * dy * 0.8).toFixed(1)}px) scale(${((0.72 + 0.28 * e) * (1 + 0.14 * s)).toFixed(4)}, ${((0.55 + 0.45 * e) * (1 + 0.1 * s)).toFixed(4)})`;
  H.copy.style.transform = s > 0 ? `translateY(${(Math.min(y, vh) * 0.08).toFixed(1)}px)` : "none";
}

/* ==========================================================================
   The frame loop: runs only while something is moving.
   ========================================================================== */
let raf = 0;
const kick = () => { if (!raf) raf = requestAnimationFrame(frame); };

function frame() {
  raf = 0;
  const y = scrollY;

  // Hero
  if (y < vh * 1.4 || v < 1) {
    if (!reduce) v = clamp((performance.now() - t0) / OPEN_MS);
    paintHero(v, y);
    if (v < 1 && t0 !== Infinity) kick();
  }

  // Nav
  if (mqNarrowNav.matches) nav.classList.toggle("is-scrolled", y > 8);
  else nav.classList.toggle("is-visible", y > 160);

  if (!reduce) {
    // Big panels rise and settle: 32 px and 0.97 → in place.
    for (const r of rises) {
      const t = easeOut(clamp((y + vh - r.top) / (vh * 0.5)));
      if (r.t === t) continue;
      r.t = t;
      r.el.style.willChange = t > 0 && t < 1 ? "transform, opacity" : "";
      r.el.style.transform = t >= 1 ? "none" : `translateY(${((1 - t) * 32).toFixed(1)}px) scale(${(0.97 + 0.03 * t).toFixed(4)})`;
      r.el.style.opacity = t >= 1 ? "" : (0.6 + 0.4 * t).toFixed(3);
    }

    // Lights off as you reach the footer.
    const q = easeInOut(clamp(1 - (docH - (y + vh)) / 280));
    if (closing.q !== q) {
      closing.q = q;
      closing.ears.style.opacity = (1 - q).toFixed(3);
      closing.closed.style.opacity = q.toFixed(3);
      closing.glow.style.opacity = (1 - 0.88 * q).toFixed(3);
      closing.glow.style.transform = `scale(${(1 - 0.22 * q).toFixed(4)})`;
      if (closing.house) closing.house.style.setProperty("--an-lit", (1 - q).toFixed(3));
    }
  }
}

measure();
paintHero(v, scrollY);
addEventListener("scroll", kick, { passive: true });
let onResizeMore = () => {};
addEventListener("resize", () => { measure(); bentoCols(); onResizeMore(); kick(); });
new ResizeObserver(() => { measure(); kick(); }).observe(document.body);

const ready = () => {
  measure();
  requestAnimationFrame(() => hero.classList.add("is-loaded"));
  // The headline's blur only needs its own layer while it sharpens.
  setTimeout(() => hero.classList.add("is-settled"), reduce ? 0 : 1500);
  if (!reduce) setTimeout(() => { t0 = performance.now(); kick(); }, OPEN_DELAY);
  kick();
};
// Don't wait for every image and audio file: start as soon as we run
// (module scripts run after parsing), and re-measure once all has loaded.
ready();
addEventListener("load", () => { measure(); kick(); }, { once: true });

/* ==========================================================================
   Arrivals: headline lines, reveals, staggers, rings that fill.
   ========================================================================== */
// Short groups (principles) arrive together in a stagger; the tall bento
// arrives cell by cell, staggered only across each row.
const stagger = $$("[data-stagger]");
stagger.forEach((g) => [...g.children].forEach((c, i) => c.style.setProperty("--i", i)));
const bentoCells = $$(".bento > .cell:not([data-rise])");
const bentoCols = () => {
  const b = $(".bento");
  for (const c of bentoCells) c.style.setProperty("--i", Math.round((c.offsetLeft / b.clientWidth) * 3));
};
bentoCols();

const fills = $$("[data-fill]");
if (!reduce) {
  for (const f of fills) {
    $$(".an-ring__arc[data-to]", f).forEach((a) => a.setAttribute("stroke-dasharray", "0 100"));
    $$(".an-bar[data-v]", f).forEach((b) => b.style.setProperty("--v", 0));
    $$("[data-count]", f).forEach((n) => (n.textContent = "0"));
  }
}
function fill(f) {
  $$(".an-ring__arc[data-to]", f).forEach((a) => a.setAttribute("stroke-dasharray", `${a.dataset.to} 100`));
  $$(".an-bar[data-v]", f).forEach((b) => b.style.setProperty("--v", b.dataset.v));
  $$("[data-count]", f).forEach((n) => {
    const to = +n.dataset.count;
    const t0 = performance.now();
    const step = (now) => {
      const t = clamp((now - t0) / 1400);
      n.textContent = Math.round(to * (1 - Math.pow(1 - t, 3)));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}

// Printing: every ring and number at its final value, no animation.
addEventListener("beforeprint", () => {
  for (const f of fills) {
    $$(".an-ring__arc[data-to]", f).forEach((a) => a.setAttribute("stroke-dasharray", `${a.dataset.to} 100`));
    $$(".an-bar[data-v]", f).forEach((b) => b.style.setProperty("--v", b.dataset.v));
    $$("[data-count]", f).forEach((n) => (n.textContent = n.dataset.count));
  }
});

const arrivals = [...$$(".lines"), ...$$(".reveal"), ...stagger.filter((g) => !g.classList.contains("bento")), ...bentoCells, ...fills];
if (reduce || !("IntersectionObserver" in window)) {
  arrivals.forEach((el) => el.classList.add("is-in"));
  fills.forEach(fill);
} else {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("is-in");
      if (e.target.hasAttribute("data-fill")) fill(e.target);
      io.unobserve(e.target);
    }
  }, { rootMargin: "0px 0px -12% 0px", threshold: 0.15 });
  arrivals.forEach((el) => io.observe(el));
}

/* ==========================================================================
   Try it: the live demo, driven by the steps (desktop) or chips (narrow).
   ========================================================================== */
const demoEl = $("#demo");
const steps = $$(".step");
const chips = $$(".try__chips [data-show]");
const now = $(".try__now");
const titles = Object.fromEntries(steps.map((s) => [s.dataset.module, $(".step__title", s).textContent.trim()]));
const norm = (m) => (m === "nowplaying" || m === "now-playing" ? "music" : m);

// The demo loads on its own, after the hero is already moving: the hero
// never waits for it, and if it can't load, the section bows out.
async function mountTry() {
  let mountDemo;
  try {
    ({ mountDemo } = await import("../shared/demo/demo.js"));
  } catch (err) {
    const tryEl = $(".try");
    tryEl?.setAttribute("hidden", "");
    // "Features" links then land on the bento instead.
    tryEl?.removeAttribute("id");
    $(".bento-wrap")?.setAttribute("id", "features");
    console.warn("Altillo demo unavailable", err);
    return false;
  }
  const demo = mountDemo(demoEl, { locale: "en", autoAgent: false, initialShelf: ["shot", "notes", "link"] });
  window.altilloDemo = demo;
  let active = null;

  let viaScroll = false;
  function setActive(id) {
    id = norm(id);
    if (!titles[id] || id === active) return;
    active = id;
    steps.forEach((s) => {
    const on = s.dataset.module === id;
    s.classList.toggle("is-active", on);
    const b = $(".step__btn", s);
    if (on) b.setAttribute("aria-current", "step"); else b.removeAttribute("aria-current");
  });
    chips.forEach((c) => {
      const on = c.dataset.show === id;
      c.setAttribute("aria-pressed", String(on));
      if (on && !mqSteps.matches && c.parentElement.scrollWidth > c.parentElement.clientWidth) {
        c.parentElement.scrollTo({ left: c.offsetLeft - (c.parentElement.clientWidth - c.offsetWidth) / 2, behavior: reduce ? "auto" : "smooth" });
      }
    });
    if (now) {
      // Announce what the reader chose (a click, a chip, phones), not every
      // step that scrolling carries past on desktop.
      now.setAttribute("aria-live", viaScroll ? "off" : "polite");
      now.textContent = titles[id];
    }
  }
  chips.forEach((c) => c.setAttribute("aria-pressed", "false"));

  // Show a module. The Drawer is about the menu bar, so after the notch has
  // shown the tucked strip it closes again, leaving the menu bar in focus.
  let drawerTimer = 0;
  let weTucked = false;
  function showModule(id) {
    clearTimeout(drawerTimer);
    // Leaving the Drawer step: bring the menu bar icons back (the demo's own
    // tray toggle), so later features don't carry the Drawer strip.
    if (id !== "drawer" && weTucked && demo.state.drawerTucked) {
      demoEl.querySelector('.dm-tray__toggle[aria-pressed="true"]')?.click();
    }
    if (id !== "drawer") weTucked = false;
    else if (!demo.state.drawerTucked) weTucked = true;
    demo.show(id);
    if (id === "drawer") {
      drawerTimer = setTimeout(() => {
        if (active === "drawer" && !paused && demo.state.drawerTucked) demo.close();
      }, 1700);
    }
  }

  // The user always wins: once they reach into the demo, scrolling stops
  // driving it until they pick a step, press Resume, or leave and come back.
  const pill = $(".try__paused");
  let paused = false;
  let centered = null;
  function setPaused(on) {
    paused = on;
    if (pill) pill.hidden = !on;
  }
  // The caption under the frame (its hint and Reset) isn't reaching in.
  const takeWheel = (e) => { if (e.target.closest?.(".dm-caption")) return; if (mqSteps.matches) { setPaused(true); clearTimeout(drawerTimer); } };
  demoEl.addEventListener("pointerdown", takeWheel, true);
  // Action keys only: moving focus with Tab (or pressing modifiers) isn't taking over.
  const PASSIVE_KEYS = new Set(["Tab", "Shift", "Control", "Alt", "Meta", "CapsLock"]);
  demoEl.addEventListener("keydown", (e) => { if (!PASSIVE_KEYS.has(e.key)) takeWheel(e); }, true);
  $(".try__resume")?.addEventListener("click", () => {
    setPaused(false);
    const id = centered || active;
    if (id) { setActive(id); showModule(id); }
  });

  // Any step or chip is also a button.
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-show]");
    if (!b) return;
    setPaused(false);
    setActive(b.dataset.show);
    showModule(b.dataset.show);
  });
  // Playing inside the demo keeps the steps and chips in sync.
  demo.on("module-shown", (d) => setActive(d.module));

  if ("IntersectionObserver" in window) {
    // Desktop scrollytelling: the step crossing the middle of the screen wins.
    const sio = new IntersectionObserver((entries) => {
      if (!mqSteps.matches) return;
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        centered = e.target.dataset.module;
        if (!paused && centered !== active) { viaScroll = true; setActive(centered); viaScroll = false; showModule(centered); }
      }
    }, { rootMargin: "-50% 0px -50% 0px", threshold: 0 });
    steps.forEach((s) => sio.observe(s));
    // Leaving the section hands the wheel back to scrolling.
    new IntersectionObserver((entries) => {
      for (const e of entries) if (!e.isIntersecting) setPaused(false);
    }).observe($(".try"));
  }

  // Chips and phones: don't greet them with a closed notch. Show the Shelf,
  // and mark its chip, as soon as the demo is up.
  if (!mqSteps.matches) { setActive("shelf"); showModule("shelf"); }

  // The chip row fades on the side that has more to scroll to.
  const chipRow = $(".try__chips");
  const chipEdges = () => {
    const max = chipRow.scrollWidth - chipRow.clientWidth;
    chipRow.classList.toggle("is-start", chipRow.scrollLeft < 4);
    chipRow.classList.toggle("is-end", max > 0 && chipRow.scrollLeft > max - 4);
  };
  chipRow.addEventListener("scroll", chipEdges, { passive: true });
  onResizeMore = chipEdges;
  chipEdges();

  // Center the sticky demo on its real height.
  new ResizeObserver(() => $(".try__grid").style.setProperty("--demo-h", `${demoEl.offsetHeight}px`)).observe(demoEl);
  measure();
  kick();
  return true;
}
const tryReady = mountTry();

/* ==========================================================================
   Easter eggs: the shared engine, plus two of B's own.
   ========================================================================== */
// The hero doesn't need them: load the engine once everything else has.
async function loadEggs() {
  const [{ mountEggs }, demoOk] = await Promise.all([import("../shared/eggs/eggs.js"), tryReady]);
  const eggs = mountEggs({
    locale: "en",
    // Demo eggs only when there's a demo to find them in.
    demoRoot: demoOk ? demoEl : null,
    selectors: {
      logo: ".nav .brand, .hero__bar .brand",
      heroNotch: ".hero__notch",
      footer: ".footer__inner nav",
    },
    // The dragon egg points to our own Aurio card, not away from the page.
    aurioHref: "#aurio",
  });
  window.altilloEggs = eggs;

  // 1. The moth: linger by the light and one finds it.
  const MOTH = `<svg viewBox="0 0 22 18" fill="currentColor" aria-hidden="true"><path d="M11 5c.6 0 1 .5 1 1.2v7.6c0 .7-.4 1.2-1 1.2s-1-.5-1-1.2V6.2C10 5.5 10.4 5 11 5Z"/><path d="M10 7.5C7.8 3.6 3.6 1.4 1.2 2.4-.6 3.2.9 8.2 4.6 9.4 2.5 10.6 2 13.6 3.6 14.4c1.9 1 4.8-1.5 6.4-4.6Z" opacity=".9"/><path d="M12 7.5c2.2-3.9 6.4-6.1 8.8-5.1 1.8.8.3 5.8-3.4 7 2.1 1.2 2.6 4.2 1 5-1.9 1-4.8-1.5-6.4-4.6Z" opacity=".9"/><path d="M10.6 5.2 9 2.4M11.4 5.2 13 2.4" stroke="currentColor" stroke-width=".7" fill="none"/></svg>`;
  let mothBusy = false;
  eggs.register({
    id: "moth",
    icon: "bulb",
    title: "Moth",
    hint: "Linger by the light.",
    message: "A moth found the light.",
    requires: ["heroNotch"],
    trigger: ({ found, listen }) => {
      let timer = 0;
      const stop = () => { clearTimeout(timer); timer = 0; };
      const near = (x, y) => {
        const r = H.notch.getBoundingClientRect();
        return Math.hypot(x - (r.left + r.width / 2), y - r.bottom) < Math.max(200, r.width * 0.42);
      };
      listen(pin, "pointermove", (e) => {
        if (e.pointerType !== "mouse") return;
        if (v > 0.6 && near(e.clientX, e.clientY)) { if (!timer) timer = setTimeout(() => { timer = 0; found(); }, 3200); }
        else stop();
      });
      listen(pin, "pointerleave", stop);
      // Touch: a long press on the light.
      listen(H.notch, "pointerdown", (e) => { if (e.pointerType !== "mouse") { stop(); timer = setTimeout(() => { timer = 0; found(); }, 1100); } });
      listen(H.notch, "pointerup", stop);
      listen(H.notch, "pointercancel", stop);
      return stop;
    },
    reveal: ({ peek }) => {
      peek("A moth found the light.", { icon: "bulb" });
      if (reduce || mothBusy) return;
      mothBusy = true;
      const r = H.notch.getBoundingClientRect();
      const pr = pin.getBoundingClientRect();
      const m = document.createElement("div");
      m.className = "moth";
      m.style.setProperty("--moth-y", `${r.bottom - pr.top + 90}px`);
      m.innerHTML = `<div class="moth__orbit"><div class="moth__body">${MOTH}</div></div>`;
      pin.append(m);
      setTimeout(() => { m.remove(); mothBusy = false; }, 5400);
    },
  });

  // 2. The grand tour: open every room of the demo by your own hand.
  if (demoOk) eggs.register({
    id: "grand-tour",
    icon: "house",
    title: "Grand tour",
    hint: "Open every room in the demo yourself.",
    message: "Every room seen. Make yourself at home.",
    requires: ["demoRoot"],
    trigger: ({ found, listen, onDemo }) => {
      let last = 0;
      const seen = new Set();
      const mark = () => (last = performance.now());
      listen(document, "pointerdown", mark, true);
      listen(document, "keydown", mark, true);
      onDemo("module-shown", (d) => {
        if (performance.now() - last > 1500) return;
        seen.add(norm(d.module));
        if (Object.keys(titles).every((id) => seen.has(id))) { seen.clear(); found(); }
      });
    },
  });
}
const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 200));
if (document.readyState === "complete") idle(loadEggs);
else addEventListener("load", () => idle(loadEggs), { once: true });
