import { test, expect } from "@playwright/test";
import { LOCALES, watch, gotoPage, waitForDemo, waitForEggs, scrollThrough } from "./helpers.js";

for (const L of LOCALES) {
  test.describe(`${L.code} page`, () => {
    test("loads with no console errors and no failed requests", async ({ page }) => {
      const problems = watch(page);
      await gotoPage(page, L.path);
      await page.waitForLoadState("load");
      await waitForDemo(page);
      await waitForEggs(page);
      await scrollThrough(page);
      // The lazy Aurio images have arrived and decoded.
      for (const img of await page.locator(".aurio__img").all()) {
        await expect.poll(() => img.evaluate((i) => i.complete && i.naturalWidth > 0)).toBe(true);
      }
      await page.waitForLoadState("networkidle");
      expect(problems).toEqual([]);
    });

    test("has its language, meta and structured data", async ({ page }) => {
      await gotoPage(page, L.path);
      await expect(page).toHaveTitle(L.title);
      await expect(page.locator("html")).toHaveAttribute("lang", L.code);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", L.canonical);
      await expect(page.locator('link[hreflang="en"]')).toHaveAttribute("href", "https://altillo.app/");
      await expect(page.locator('link[hreflang="es"]')).toHaveAttribute("href", "https://altillo.app/es/");
      await expect(page.locator('link[hreflang="x-default"]')).toHaveAttribute("href", "https://altillo.app/");
      await expect(page.locator('meta[property="og:locale"]')).toHaveAttribute("content", L.ogLocale);
      await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content", L.canonical);
      await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", `https://altillo.app${L.ogImage}`);
      await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute("content", `https://altillo.app${L.ogImage}`);
      const ld = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent());
      expect(ld["@type"]).toBe("SoftwareApplication");
      expect(ld.image).toBe(`https://altillo.app${L.ogImage}`);
      expect(ld.url).toBe(L.canonical);
      expect(ld.downloadUrl).toBe("https://github.com/XusBadia/altillo/releases/latest");
      // The social card and icons exist at the site root.
      for (const p of [L.ogImage, "/favicon.svg", "/altillo-icon.png"]) {
        expect((await page.request.get(p)).status(), p).toBe(200);
      }
    });

    test("the hero notch opens into the Shelf", async ({ page }) => {
      await gotoPage(page, L.path);
      await expect(page.locator("h1")).toHaveText(L.h1);
      // Fully open: the slab is at its natural size and the ears are gone.
      await expect(page.locator(".hero__slab")).toHaveAttribute("style", /transform: none/);
      await expect.poll(() => page.locator(".hero__ears").evaluate((e) => +getComputedStyle(e).opacity)).toBe(0);
      await expect(page.locator(".hero__open .an-tab.is-active")).toHaveText(L.tab.shelf);
      await expect(page.locator(".hero__open .an-tile")).toHaveCount(6);
      await expect(page.locator(".hero__open .an-tile").first()).toBeVisible();
    });

    test("the closed notches speak in words, leaning around the camera", async ({ page }) => {
      await gotoPage(page, L.path);
      for (const sel of [".hero__ears", ".closing__ears"]) {
        const g = await page.locator(sel).evaluate((el) => {
          const cam = el.getBoundingClientRect();
          const [l, r] = [...el.querySelectorAll(":scope > .an-fear")].map((e) => e.getBoundingClientRect());
          return { lw: l.width, rw: r.width, joinsL: Math.abs(l.right - cam.left), joinsR: Math.abs(r.left - cam.right), text: el.textContent.replace(/\s+/g, " ").trim() };
        });
        expect(g.joinsL).toBeLessThan(1);
        expect(g.joinsR).toBeLessThan(1);
        expect(Math.abs(g.lw - g.rw)).toBeGreaterThan(4);
        expect(g.text).toMatch(/[A-Za-z]{4,}/);
      }
    });

    test("navigation links go where they say", async ({ page }) => {
      await gotoPage(page, L.path);
      const links = page.locator(".nav__links a");
      await expect(links.nth(0)).toHaveAttribute("href", "#features");
      await expect(links.nth(0)).toHaveText(L.features);
      await expect(links.nth(1)).toHaveAttribute("href", "https://github.com/XusBadia/altillo");
      await expect(links.nth(2)).toHaveAttribute("href", "#aurio");
      await expect(links.nth(3)).toHaveAttribute("href", "https://github.com/XusBadia/altillo/releases/latest");
      await expect(links.nth(3)).toHaveText(L.download);
      await expect(page.locator(".hero__copy .btn--amber")).toHaveAttribute("href", "https://github.com/XusBadia/altillo/releases/latest");
      await expect(page.locator('#aurio a[href="https://www.aurioapp.com"]')).toHaveCount(2);

      // Footer: privacy in the same language, and the switch to the other one.
      await expect(page.locator(`.footer a[href="${L.privacy}"]`)).toHaveCount(1);
      await expect(page.locator(`.footer a[href="${L.other}"]`)).toHaveCount(1);

      // In-page anchors land on their sections.
      // Wait for the anchor to arrive below the fixed nav. Merely entering
      // the viewport can still mean the smooth scroll is halfway through;
      // starting a second one there races WebKit's first navigation.
      const waitAtAnchor = async (sel) => {
        let previousY = null;
        let stableSince = Date.now();
        await expect.poll(async () => {
          const { top, padding, y } = await page.locator(sel).evaluate((el) => ({
            top: el.getBoundingClientRect().top,
            padding: parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop),
            y: window.scrollY,
          }));
          // Entering the 2 px tolerance isn't enough: WebKit can still have
          // a smooth scroll in flight. Require it to stay put before clicking
          // the next anchor, while preserving the same alignment assertion.
          if (previousY === null || Math.abs(y - previousY) > 0.1) stableSince = Date.now();
          previousY = y;
          return { aligned: Math.abs(top - padding) <= 2, settled: Date.now() - stableSince >= 200 };
        }, { intervals: [100] }).toEqual({ aligned: true, settled: true });
      };
      // Phones keep only Download in the bar.
      if (page.viewportSize().width <= 760) {
        await expect(links.nth(3)).toBeVisible();
        await expect(links.nth(0)).toBeHidden();
        return;
      }
      // Past the hero the sticky nav slides in (it's always on below 940 px).
      await page.evaluate(() => window.scrollTo({ top: 400, behavior: "instant" }));
      await expect(page.locator("#nav")).toHaveClass(/is-visible|is-scrolled/);
      await expect(links.nth(0)).toBeVisible();
      await links.nth(0).click();
      await expect(page).toHaveURL(/#features$/);
      await waitAtAnchor("#features");
      await links.nth(2).click();
      await expect(page).toHaveURL(/#aurio$/);
      await waitAtAnchor("#aurio");
    });

    test("the language switch leads to the other page", async ({ page }) => {
      await gotoPage(page, L.path);
      await page.locator(`.footer a[href="${L.other}"]`).click();
      await expect(page).toHaveURL(new RegExp(`${L.other.replace(/\//g, "\\/")}$`));
      await expect(page.locator("html")).toHaveAttribute("lang", L.code === "en" ? "es" : "en");
    });

    test("reduced motion shows a still page", async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await gotoPage(page, L.path);
      // Open from the first frame, with no opening animation to wait for.
      await expect(page.locator(".hero__slab")).toHaveAttribute("style", /transform: none/);
      await expect(page.locator(".hero__ears")).toHaveCSS("opacity", "0");
      // Every arrival is already in place.
      const pending = await page.locator(".lines, .reveal").evaluateAll((els) => els.filter((e) => !e.classList.contains("is-in")).length);
      expect(pending).toBe(0);
      // Rings and counts sit at their final values without waiting.
      await expect(page.locator(".bento [data-count]").first()).toHaveText("85");
      await waitForDemo(page);
      await expect(page.locator("#demo")).toHaveClass(/dm--reduce/);
    });

    test("prints every figure at its final value", async ({ page }) => {
      await gotoPage(page, L.path);
      await page.emulateMedia({ media: "print" });
      await page.evaluate(() => window.dispatchEvent(new Event("beforeprint")));
      await expect(page.locator(".bento [data-count]").first()).toHaveText("85");
      await expect(page.locator(".try")).toBeHidden();
      await expect(page.locator(".nav")).toBeHidden();
    });
  });
}

test.describe("fallbacks", () => {
  test("without its script the page is still readable", async ({ browser }) => {
    const ctx = await browser.newContext({ javaScriptEnabled: false });
    const page = await ctx.newPage();
    await page.goto("/");
    await expect(page.locator("h1")).toBeVisible();
    await expect(page.locator(".bento .cell").first()).toBeVisible();
    await expect(page.locator("#aurio h3")).toBeVisible();
    await ctx.close();
  });

  test("if the demo can't load, Features lands on the bento", async ({ page }) => {
    await page.route(/\/assets\/demo-[^/]+\.js$/, (r) => r.abort());
    await page.goto("/?eggs-hour=12");
    await expect(page.locator(".try")).toBeHidden();
    await expect(page.locator(".bento-wrap")).toHaveAttribute("id", "features");
    await expect(page.locator(".hero__slab")).toHaveAttribute("style", /transform: none/);
  });
});

test.describe("phone layout", () => {
  test.beforeEach(({ page }, info) => test.skip(page.viewportSize().width > 500, "phones only"));

  for (const L of LOCALES) {
    test(`${L.code}: fits 390 px, with chips instead of steps`, async ({ page }) => {
      await gotoPage(page, L.path);
      await waitForDemo(page);
      await scrollThrough(page);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(overflow).toBeLessThanOrEqual(0);
      await expect(page.locator(".try__chips")).toBeVisible();
      await expect(page.locator(".try__steps")).toBeHidden();
      // Phones are greeted with the Shelf open, and its chip marked.
      await expect(page.locator('.try__chips [data-show="shelf"]')).toHaveAttribute("aria-pressed", "true");
      await expect.poll(() => page.evaluate(() => window.altilloDemo.state.open)).toBe(true);
      // The nav is always there on phones.
      await expect(page.locator(".nav")).toBeVisible();
    });
  }
});
