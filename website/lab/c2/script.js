// Altillo — C2 «Desván refinado»: demo scrollytelling, scroll motion, eggs.
import { mountDemo } from "../shared/demo/demo.js";
import { mountEggs } from "../shared/eggs/eggs.js";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const backOut = (t) => { const c = 1.25; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };

const html = document.documentElement;
const mqReduce = matchMedia("(prefers-reduced-motion: reduce)");
const mqWide = matchMedia("(min-width: 1181px)");
let reduced = mqReduce.matches;
html.classList.toggle("motion", !reduced);

/* ======================================================================
   1 · The interactive demo + chapters
   ====================================================================== */
const demoEl = $("#demo");
const demo = mountDemo(demoEl, { locale: "en", autoAgent: false });
window.__demo = demo;

const chapters = $$(".chap");
const IDS = chapters.map((c) => c.dataset.module);
const NAMES = chapters.map((c) => $(".eyebrow", c).textContent.trim());

// Mobile chip row: the same kraft tags, with names.
const chipsEl = $(".chips");
chapters.forEach((c, i) => {
  const b = $(".tag", c).cloneNode(false);
  b.textContent = `${String(i + 1).padStart(2, "0")} · ${NAMES[i]}`;
  chipsEl.append(b);
});

const odoCols = $$(".odo__col");
const nameWrap = $(".stagebox__name");
const nameSpan = $("[data-name]");
let nameTimer = 0;
function tickOdo(n) {
  const s = String(n).padStart(2, "0");
  odoCols.forEach((col, k) => { col.style.transform = `translateY(${-Number(s[k])}em)`; });
}
function swapName(text) {
  if (reduced || nameSpan.textContent === text) { nameSpan.textContent = text; return; }
  clearTimeout(nameTimer);
  nameWrap.classList.add("is-swapping");
  nameTimer = setTimeout(() => { nameSpan.textContent = text; nameWrap.classList.remove("is-swapping"); }, 150);
}

let active = -1;
let quietUntil = 0; // ignore echo `module-shown` events right after we call show()
function callShow(i) {
  if (demoEl.classList.contains("is-dragging")) return;
  quietUntil = performance.now() + 700;
  demo.show(IDS[i]);
}
function setActive(i, { show = true } = {}) {
  if (i < 0) return;
  if (i !== active) {
    active = i;
    chapters.forEach((c, j) => c.classList.toggle("is-active", j === i));
    $$(".tag[data-show]").forEach((t) => t.setAttribute("aria-pressed", String(t.dataset.show === IDS[i])));
    tickOdo(i + 1);
    swapName(NAMES[i]);
    if (!mqWide.matches) {
      const chip = $(`.chips .tag[data-show="${IDS[i]}"]`);
      if (chip) {
        const left = chipsEl.scrollLeft + chip.getBoundingClientRect().left - chipsEl.getBoundingClientRect().left - 20;
        chipsEl.scrollTo({ left, behavior: reduced ? "auto" : "smooth" });
      }
    }
  }
  if (show) callShow(i);
}
setActive(0, { show: false });

// Scrolling a chapter into the middle of the viewport shows its module (desktop).
// While a tag click scrolls to its chapter, chapters passing through the middle
// must not show their modules: hold the lock until we arrive (or scrolling ends).
let lockTarget = -1;
let lockTimer = 0;
function releaseLock() { lockTarget = -1; clearTimeout(lockTimer); }
function lockTo(i) {
  lockTarget = i;
  clearTimeout(lockTimer);
  lockTimer = setTimeout(releaseLock, 3000); // fallback where `scrollend` is missing
  addEventListener("scrollend", releaseLock, { once: true });
}
let centered = 0; // the chapter currently in the middle of the viewport
const chapterIO = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) centered = chapters.indexOf(e.target);
  if (lockTarget >= 0) { if (centered === lockTarget) releaseLock(); return; }
  if (!mqWide.matches || !following) return;
  for (const e of entries) if (e.isIntersecting) setActive(chapters.indexOf(e.target));
}, { rootMargin: "-47% 0px -47% 0px" });
chapters.forEach((c) => chapterIO.observe(c));

// Scroll never overrides the visitor: once they touch the demo, following pauses
// until they pick a chapter tag, press Resume, or leave the section and come back.
let following = true;
const followEl = $(".follow");
function setFollowing(on, { resync = false } = {}) {
  if (following === on) return;
  following = on;
  followEl.hidden = on;
  if (on && resync && mqWide.matches) setActive(centered);
}
const ACTION_KEYS = new Set(["Enter", " ", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "Delete", "Backspace"]);
const CONTROL = "button, a[href], input, textarea, select, [role='tab'], [role='button'], [tabindex]:not([tabindex='-1'])";
const pause = () => { if (mqWide.matches) setFollowing(false); };
demoEl.addEventListener("pointerdown", (e) => { if (e.isTrusted) pause(); }, true);
demoEl.addEventListener("keydown", (e) => {
  // Tab passing through (or any other key) does not count as playing with the demo.
  if (e.isTrusted && ACTION_KEYS.has(e.key) && e.target.closest?.(CONTROL) && demoEl.contains(e.target)) pause();
}, true);
$(".follow button").addEventListener("click", () => setFollowing(true, { resync: true }));
let leftTry = false;
new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) leftTry = true;
    else if (leftTry) { leftTry = false; setFollowing(true); }
  }
}).observe($(".try__grid"));

// Narrow screens: open the current module when the demo comes into view.
let greeted = false;
new IntersectionObserver((entries, obs) => {
  if (mqWide.matches || greeted || !entries.some((e) => e.isIntersecting)) return;
  greeted = true; obs.disconnect();
  if (!demo.state.open) setTimeout(() => callShow(active), 400);
}, { threshold: 0.55 }).observe(demoEl);

// Tags are buttons: jump to that module (and on desktop bring its words to the middle).
document.addEventListener("click", (e) => {
  const tag = e.target.closest(".tag[data-show]");
  if (!tag) return;
  const i = IDS.indexOf(tag.dataset.show);
  setFollowing(true);
  setActive(i);
  if (mqWide.matches && tag.closest(".chap")) {
    if (centered !== i) lockTo(i);
    chapters[i].scrollIntoView({ block: "center", behavior: reduced ? "auto" : "smooth" });
  }
});

// Free play inside the demo keeps the chapter marker honest.
demo.on("module-shown", (d) => {
  const i = IDS.indexOf(d.module);
  if (i < 0 || i === active) return;
  if (performance.now() < quietUntil && d.module !== IDS[active]) return;
  setActive(i, { show: false });
});

/* ======================================================================
   2 · Tags swing in on their twine
   ====================================================================== */
const tagIO = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    const t = e.target;
    tagIO.unobserve(t);
    if (reduced) { t.classList.add("is-hung"); continue; }
    const inChips = t.parentElement === chipsEl;
    t.style.animationDelay = inChips ? `${[...chipsEl.children].indexOf(t) * 70}ms` : "0ms";
    t.classList.add("is-hung", "is-swinging");
    t.addEventListener("animationend", () => { t.classList.remove("is-swinging"); t.style.animationDelay = ""; }, { once: true });
  }
}, { rootMargin: "0px 0px -12% 0px" });
$$(".tag").forEach((t) => tagIO.observe(t));

// Fade + rise for the quieter blocks.
const revealIO = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); revealIO.unobserve(e.target); }
}, { rootMargin: "0px 0px -12% 0px", threshold: 0.08 });
$$("[data-reveal]").forEach((el) => revealIO.observe(el));

/* ======================================================================
   3 · Scroll-driven scene: hero opens, the file drifts up, the lamp
       warms with depth, illustrations drift, and the lights go out.
   ====================================================================== */
const H = {
  notch: $(".hero__notch"),
  ears: $(".hero__ears"),
  parts: $$(".hero__notch > .an-band, .hero__notch > .an-body"),
  file: $(".hero__file"),
  thing: $(".hero__file-thing"),
  name: $(".hero__file-name"),
  slot: $(".hero__slot"),
  shelf: $(".hero__shelf"),
  counts: $$(".hero__count"),
};
const L = { warm: $(".lamp__warm"), edge: $(".lamp__edge"), dusk: $(".lamp__dusk") };
const foot = $(".foot");
const footGlow = $(".foot__glow");
const parallax = $$("[data-parallax]").map((el) => ({
  el,
  f: Number(el.dataset.parallax),
  target: el.classList.contains("plate") ? $("img", el) : el,
  max: el.classList.contains("plate") ? 20 : 60,
}));

let sx0 = 0.44, sy0 = 0.16, fdx = 0, fdy = -200;
let docH = 1, vh = innerHeight, footTop = 1, footH = 1;
let autoP = 0, landed = false;

function measure() {
  vh = innerHeight;
  docH = document.documentElement.scrollHeight;
  footTop = foot.getBoundingClientRect().top + scrollY;
  footH = foot.offsetHeight;
  // Hero: closed (ears) vs open panel, and the path from the desktop file to its slot.
  const prevN = H.notch.style.transform, prevF = H.file.style.transform, prevT = H.thing.style.transform;
  H.notch.style.transform = "translateX(-50%)";
  H.file.style.transform = "none";
  H.thing.style.transform = "none";
  sx0 = H.ears.offsetWidth / H.notch.offsetWidth;
  sy0 = H.ears.offsetHeight / H.notch.offsetHeight;
  const fThumb = $(".an-thumb", H.file);
  const a = fThumb.getBoundingClientRect();
  const b = $(".an-thumb", H.slot).getBoundingClientRect();
  const k = a.width / fThumb.offsetWidth || 1; // CSS zoom between layout and screen px
  fdx = (b.left + b.width / 2 - (a.left + a.width / 2)) / k;
  fdy = (b.top + b.height / 2 - (a.top + a.height / 2)) / k;
  H.notch.style.transform = prevN; H.file.style.transform = prevF; H.thing.style.transform = prevT;
}

function setLanded(on) {
  if (on === landed) return;
  landed = on;
  H.slot.classList.toggle("is-landed", on);
  H.counts.forEach((c) => { c.textContent = on ? "6" : "5"; });
}

function frame() {
  ticking = false;
  const y = scrollY;

  // Hero — the panel opens over the first ~140 px (or by itself if you wait).
  const p = reduced ? 1 : Math.max(autoP, easeOut(clamp(y / 140)));
  H.notch.style.transform = `translateX(-50%) scale(${lerp(sx0, 1, p)}, ${lerp(sy0, 1, Math.min(p, 1.02))})`;
  H.ears.style.opacity = clamp(1 - p * 3);
  const c = clamp((p - 0.55) / 0.4);
  H.parts.forEach((el) => { el.style.opacity = c; });

  // The file is dragged from the desktop up onto the shelf.
  const d = reduced ? 1 : clamp((y - 24) / Math.min(300, vh * 0.36));
  const e = easeInOut(d);
  const lift = Math.sin(Math.PI * e);
  H.file.style.transform = `translate(${fdx * e + lift * 28}px, ${fdy * e - lift * 18}px) scale(${1 + 0.07 * lift})`;
  H.thing.style.transform = `rotate(${lerp(-7, 0.6, e)}deg)`;
  H.name.style.opacity = clamp(1 - d * 3.5);
  H.file.style.opacity = d >= 0.995 ? 0 : 1;
  H.shelf.classList.toggle("is-lit", d > 0.55 && d < 0.995 && p > 0.9);
  setLanded(d >= 0.995);

  // The lamp: warmer and brighter the deeper you read…
  const g = clamp(y / Math.max(1, docH - vh));
  const q = clamp((y + vh - footTop - 40) / (footH * 0.85)); // …then it dims into the footer.
  L.warm.style.opacity = clamp(g * 1.8) * (1 - q);
  L.edge.style.opacity = lerp(1, 0.5, clamp(g * 1.6)) + q * 0.5;
  const night = html.classList.contains("is-night");
  L.dusk.style.opacity = q * (night ? 0.4 : 0.92);
  footGlow.style.opacity = 1 - q * 0.85;
  foot.classList.toggle("is-out", q > 0.9);

  // Gentle parallax on the illustrations.
  if (!reduced) {
    for (const it of parallax) {
      const r = it.el.getBoundingClientRect();
      if (r.bottom < -200 || r.top > vh + 200) continue;
      const off = clamp((r.top + r.height / 2 - vh / 2) * it.f, -it.max, it.max);
      it.target.style.translate = `0 ${off.toFixed(1)}px`;
    }
  }
}

let ticking = false;
const request = () => { if (!ticking) { ticking = true; requestAnimationFrame(frame); } };
addEventListener("scroll", request, { passive: true });
addEventListener("resize", () => { measure(); request(); });
new ResizeObserver(() => { measure(); request(); }).observe(document.body);
measure();
frame();

// If nobody scrolls, the notch opens by itself after a beat.
if (!reduced) {
  setTimeout(() => {
    if (scrollY > 40) { autoP = 1; return; }
    const t0 = performance.now(), dur = 620;
    const step = (now) => {
      const t = clamp((now - t0) / dur);
      autoP = backOut(t);
      frame();
      if (t < 1) requestAnimationFrame(step); else autoP = 1;
    };
    requestAnimationFrame(step);
  }, 1100);
}

mqReduce.addEventListener?.("change", () => { reduced = mqReduce.matches; html.classList.toggle("motion", !reduced); measure(); request(); });

/* ======================================================================
   4 · Easter eggs (shared engine) + two that only live in this attic
   ====================================================================== */
const eggs = mountEggs({
  locale: "en",
  demoRoot: demoEl,
  selectors: { logo: ".nav .brand", heroNotch: ".hero__hang", footer: ".foot__in" },
});
window.__eggs = eggs;

// The polaroid: peel the tape and it turns over — there’s a note on the back.
const pol = $(".polaroid");
const tape = $(".polaroid__tape");
let polTimer = 0;
function turnPolaroid() {
  clearTimeout(polTimer);
  const flipped = pol.classList.contains("is-flipped");
  if (!flipped) {
    pol.classList.add("is-peeled");
    polTimer = setTimeout(() => pol.classList.add("is-flipped"), reduced ? 0 : 280);
    tape.setAttribute("aria-label", "Stick the photo back");
  } else {
    pol.classList.remove("is-flipped");
    polTimer = setTimeout(() => pol.classList.remove("is-peeled"), reduced ? 0 : 650);
    tape.setAttribute("aria-label", "Peel the tape");
  }
  $(".polaroid__back").setAttribute("aria-hidden", String(flipped));
}
tape.addEventListener("click", turnPolaroid);
$(".polaroid__back").addEventListener("click", () => pol.classList.contains("is-flipped") && turnPolaroid());
eggs.register({
  id: "turned-over",
  icon: "door",
  title: "The back of the photo",
  hint: "Tape comes off, if you ask nicely.",
  message: "Some notes are only for the curious.",
  trigger: ({ found, listen }) => listen(tape, "click", () => { if (pol.classList.contains("is-peeled")) found(); }),
});

// The pull cord: the lamp goes out at the bottom of the page — pull it.
const cord = $(".cord");
let cordFound = false;
cord.addEventListener("click", () => {
  cord.classList.remove("is-pulled");
  void cord.offsetWidth;
  cord.classList.add("is-pulled");
  const on = !html.classList.contains("is-night");
  eggs.setNight(on);
  request();
});
document.addEventListener("altillo-eggs", (e) => { if (e.detail?.type === "night") request(); });
eggs.register({
  id: "pull-cord",
  icon: "bulb",
  title: "The pull cord",
  hint: "Every attic has a light you can pull.",
  message: "Click. Someone’s still up.",
  trigger: ({ found, listen }) => listen(cord, "click", () => { if (!cordFound) { cordFound = true; found(); } }),
});
