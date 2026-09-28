import { test, expect } from "@playwright/test";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { watch } from "./helpers.js";

const dist = fileURLToPath(new URL("../dist/", import.meta.url));

test.describe("privacy pages", () => {
  for (const [path, lang, h1, back] of [
    ["/privacy/", "en", "Your things stay on your Mac.", "/"],
    ["/es/privacidad/", "es", null, "/es/"],
  ]) {
    test(`${path} loads cleanly`, async ({ page }) => {
      const problems = watch(page);
      const res = await page.goto(path);
      expect(res.status()).toBe(200);
      await expect(page.locator("html")).toHaveAttribute("lang", lang);
      if (h1) await expect(page.locator("h1")).toHaveText(h1);
      else await expect(page.locator("h1")).toBeVisible();
      // Styled by the processed privacy.css.
      expect(await page.locator('link[rel="stylesheet"]').getAttribute("href")).toMatch(/^\/assets\/privacy-[\w-]+\.css$/);
      await expect(page.locator(`footer a[href="${back}"]`)).toHaveCount(1);
      await page.waitForLoadState("networkidle");
      expect(problems).toEqual([]);
    });
  }
});

test.describe("build output", () => {
  test.beforeEach(({ page }, info) => test.skip(info.project.name !== "desktop", "checks files once"));

  test("every local URL in the built HTML and CSS resolves", async ({ request }) => {
    const files = [];
    const walk = (dir) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const p = join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (/\.(html|css)$/.test(e.name)) files.push(p);
      }
    };
    walk(dist);
    expect(files.length).toBeGreaterThan(4);
    const urls = new Set();
    for (const f of files) {
      const text = readFileSync(f, "utf8");
      for (const m of text.matchAll(/(?:src|href)="(\/[^"#?]*)"/g)) urls.add(m[1]);
      for (const m of text.matchAll(/url\((\/[^)"']+)\)/g)) urls.add(m[1]);
    }
    // Music the demo plays and the image the Aurio egg shows.
    for (const u of ["/media/music/azotea.mp3", "/media/music/luz-de-tarde.mp3", "/media/music/ultimo-tranvia.mp3", "/media/aurio-mascot-wink.webp", "/og.png", "/og-es.png"]) urls.add(u);
    expect([...urls].some((u) => /^\/assets\/wood-[\w-]+\.webp$/.test(u))).toBe(true);
    const bad = [];
    for (const u of urls) {
      const r = await request.get(u);
      if (r.status() !== 200) bad.push(`${r.status()} ${u}`);
    }
    expect(bad).toEqual([]);
  });

  test("no source paths leak into the build", async () => {
    for (const f of ["index.html", "es/index.html", "privacy/index.html", "es/privacidad/index.html"]) {
      expect(existsSync(join(dist, f)), f).toBe(true);
      const html = readFileSync(join(dist, f), "utf8");
      expect(html, f).not.toMatch(/(?:src|href)="\/src\//);
      expect(html, f).not.toMatch(/\.\.\/shared\//);
    }
  });

  test("the demo still injects its styles on a page that lacks them", async ({ page }) => {
    const problems = watch(page);
    await page.goto("/?eggs-hour=12");
    await page.waitForFunction(() => !!window.altilloDemo);
    const demoChunk = await page.evaluate(() => performance.getEntriesByType("resource").map((e) => e.name).find((n) => /\/assets\/demo-[\w-]+\.js$/.test(n)));
    expect(demoChunk).toBeTruthy();
    // Strip every stylesheet (and so the --an-kit / --dm-kit markers), then
    // mount a fresh demo: it must bring its own, fully resolved, CSS.
    const result = await page.evaluate(async (src) => {
      document.querySelectorAll('link[rel="stylesheet"], style').forEach((n) => n.remove());
      const { mountDemo } = await import(src);
      const el = document.createElement("div");
      document.body.append(el);
      mountDemo(el, { locale: "es" });
      const links = [...document.querySelectorAll('link[rel="stylesheet"]')];
      await Promise.all(links.map((l) => (l.sheet ? null : new Promise((r) => { l.onload = r; l.onerror = r; }))));
      const s = getComputedStyle(document.documentElement);
      return { hrefs: links.map((l) => new URL(l.href).pathname), an: s.getPropertyValue("--an-kit").trim(), dm: s.getPropertyValue("--dm-kit").trim() };
    }, demoChunk);
    expect(result.hrefs).toHaveLength(2);
    expect(result.hrefs[0]).toMatch(/^\/assets\/notch-[\w-]+\.css$/);
    expect(result.hrefs[1]).toMatch(/^\/assets\/demo-[\w-]+\.css$/);
    expect([result.an, result.dm]).toEqual(["1", "1"]);
    // The injected kit's wood texture resolves too.
    const css = await (await page.request.get(result.hrefs[0])).text();
    const wood = css.match(/url\((\/assets\/wood-[\w-]+\.webp)\)/)?.[1];
    expect(wood).toBeTruthy();
    expect((await page.request.get(wood)).status()).toBe(200);
    expect(problems).toEqual([]);
  });
});
