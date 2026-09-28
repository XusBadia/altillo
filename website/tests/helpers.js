import { expect } from "@playwright/test";

// Copy each page must carry, so the same tests cover both languages.
export const LOCALES = [
  {
    code: "en",
    path: "/",
    other: "/es/",
    canonical: "https://altillo.app/",
    ogLocale: "en_GB",
    title: "Altillo — Your notch, put to work.",
    h1: /Your notch,\s*put to\s*work\./,
    features: "Features",
    download: "Download",
    privacy: "/privacy/",
    modules: { shelf: "Shelf", usage: "AI usage", calendar: "Calendar", mirror: "Mirror", music: "Now playing" },
    tab: { shelf: "Shelf", usage: "Usage" },
    resume: "Resume",
    drawerTitle: /./,
  },
  {
    code: "es",
    path: "/es/",
    other: "/",
    canonical: "https://altillo.app/es/",
    ogLocale: "es_ES",
    title: "Altillo — Tu notch, a trabajar.",
    h1: /Tu notch,\s*a\s*trabajar\./,
    features: "Funciones",
    download: "Descargar",
    privacy: "/es/privacidad/",
    modules: { shelf: "Altillo", usage: "Uso de IA", calendar: "Agenda", mirror: "Espejo", music: "Sonando" },
    tab: { shelf: "Altillo", usage: "Uso" },
    resume: "Reanudar",
    drawerTitle: /./,
  },
];

// Pin the eggs' clock to midday: a run between 00:00 and 05:00 would
// otherwise switch the page to night mode on load (the night-owl egg).
export const url = (path, extra = "") => `${path}?eggs-hour=12${extra}`;

// Records console errors, uncaught exceptions and any failed or 4xx/5xx
// request from our own origin.
export function watch(page) {
  const problems = [];
  page.on("console", (m) => { if (m.type() === "error") problems.push(`console: ${m.text()}`); });
  page.on("pageerror", (e) => problems.push(`pageerror: ${e.message}`));
  page.on("requestfailed", (r) => {
    const f = r.failure()?.errorText || "";
    // Media elements may cancel their own range requests; that's not a 404.
    if (/abort|cancel/i.test(f) && r.resourceType() === "media") return;
    problems.push(`requestfailed: ${r.url()} ${f}`);
  });
  page.on("response", (r) => {
    if (r.status() >= 400 && r.url().startsWith("http://127.0.0.1")) problems.push(`${r.status()}: ${r.url()}`);
  });
  return problems;
}

export const isWide = (page) => page.viewportSize().width >= 1300;

export async function gotoPage(page, path, extra = "") {
  await page.goto(url(path, extra));
  await page.waitForFunction(() => window.__altillo === true);
}

export async function waitForDemo(page) {
  await page.waitForFunction(() => !!window.altilloDemo);
  await expect(page.locator("#demo .dm-notch")).toBeAttached();
}

export async function waitForEggs(page) {
  await page.waitForFunction(() => !!window.altilloEggs, null, { timeout: 15_000 });
}

export const demoState = (page) => page.evaluate(() => ({ ...window.altilloDemo.state, shelf: [...window.altilloDemo.state.shelf] }));

// Scroll so that an element's centre sits on the viewport's centre line
// (instant, not the page's smooth scroll).
export async function centre(page, selector) {
  await page.evaluate((s) => {
    const el = document.querySelector(s);
    const r = el.getBoundingClientRect();
    window.scrollTo({ top: window.scrollY + r.top + r.height / 2 - innerHeight / 2, behavior: "instant" });
  }, selector);
}

// Scroll to the bottom of the page in steps, so lazy images, observers and
// arrivals all get their turn.
export async function scrollThrough(page) {
  await page.evaluate(async () => {
    const step = Math.round(innerHeight * 0.8);
    for (let y = 0; y < document.documentElement.scrollHeight; y += step) {
      window.scrollTo({ top: y, behavior: "instant" });
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    }
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "instant" });
  });
}
