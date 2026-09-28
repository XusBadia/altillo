import { test, expect } from "@playwright/test";
import { LOCALES, gotoPage, waitForDemo, demoState, centre, isWide } from "./helpers.js";

for (const L of LOCALES) {
  test.describe(`${L.code} demo`, () => {
    test("mounts in the page's language, styled by the page's own CSS", async ({ page }) => {
      await gotoPage(page, L.path);
      await waitForDemo(page);
      await expect(page.locator("#demo .dm-screen")).toBeVisible();
      // The page links the kit, so the demo mustn't inject a second copy.
      const injected = await page.locator('link[rel="stylesheet"][href*="/assets/notch-"], link[rel="stylesheet"][href*="/assets/demo-"]').count();
      expect(injected).toBe(0);
      const markers = await page.evaluate(() => {
        const s = getComputedStyle(document.documentElement);
        return [s.getPropertyValue("--an-kit").trim(), s.getPropertyValue("--dm-kit").trim()];
      });
      expect(markers).toEqual(["1", "1"]);
      // Its own copy is localised too.
      await page.evaluate(() => window.altilloDemo.show("usage"));
      await expect(page.locator("#demo .an-tab.is-active")).toContainText(L.tab.usage);
    });

    test("steps or chips switch the module", async ({ page }) => {
      await gotoPage(page, L.path);
      await waitForDemo(page);
      const wide = isWide(page);
      const button = (id) => page.locator(wide ? `.step__btn[data-show="${id}"]` : `.try__chips [data-show="${id}"]`);
      // Wide: park the calendar step mid-screen, then pick its neighbours
      // (already on screen, so clicking doesn't scroll the steps around).
      if (wide) {
        await centre(page, '.step[data-module="calendar"]');
        await expect.poll(async () => (await demoState(page)).module).toBe("calendar");
      }
      for (const id of wide ? ["music", "agents"] : ["calendar", "usage", "mirror"]) {
        if (wide) await expect(button(id)).toBeInViewport();
        await button(id).click();
        await expect.poll(async () => (await demoState(page)).module).toBe(id);
        await expect.poll(async () => (await demoState(page)).open).toBe(true);
        if (wide) {
          await expect(page.locator(`.step[data-module="${id}"]`)).toHaveClass(/is-active/);
          await expect(button(id)).toHaveAttribute("aria-current", "step");
        } else {
          await expect(button(id)).toHaveAttribute("aria-pressed", "true");
        }
        await expect(page.locator(".try__now")).toHaveText((await page.locator(`.step[data-module="${id}"] .step__title`).textContent()).trim());
      }
    });

    test("a file dragged with the mouse lands on the shelf", async ({ page }) => {
      test.skip(page.viewportSize().width < 700, "mouse drag on desktop layouts");
      await gotoPage(page, L.path);
      await waitForDemo(page);
      await page.locator("#demo").scrollIntoViewIfNeeded();
      // Reaching into the demo first stops scrolling from driving it, so
      // nothing reopens the notch behind our back.
      await page.locator("#demo .dm-files").click({ position: { x: 4, y: 4 } });
      if (isWide(page)) await expect(page.locator(".try__paused")).toBeVisible();
      await page.evaluate(() => window.altilloDemo.close());
      await expect.poll(async () => (await demoState(page)).open).toBe(false);
      expect((await demoState(page)).shelf).not.toContain("proposal");

      const file = page.locator('#demo .dm-file[data-file="proposal"]');
      const fb = await file.boundingBox();
      await page.mouse.move(fb.x + fb.width / 2, fb.y + fb.height / 2);
      await page.mouse.down();
      // Travel towards the notch: nearby, it opens on the Shelf. Positions
      // are re-read on every move, since the notch springs as it opens.
      const notchCentre = async () => {
        const nb = await page.locator("#demo .dm-notch").boundingBox();
        return { x: nb.x + nb.width / 2, y: nb.y + nb.height / 2 };
      };
      let c = await notchCentre();
      await page.mouse.move(c.x, c.y + 120, { steps: 12 });
      let wiggle = 0;
      await expect.poll(async () => {
        c = await notchCentre();
        await page.mouse.move(c.x + (wiggle++ % 2), c.y + 110);
        return (await demoState(page)).open;
      }).toBe(true);
      // Over the open panel (the Shelf lights up to take it), then let go.
      await expect.poll(async () => {
        c = await notchCentre();
        await page.mouse.move(c.x + (wiggle++ % 2), c.y, { steps: 3 });
        return page.locator("#demo .an-shelf.an-card--lit").count();
      }).toBeGreaterThan(0);
      await page.mouse.up();
      await expect.poll(async () => (await demoState(page)).shelf).toContain("proposal");
      await expect(page.locator('#demo .an-tile[data-shelf="proposal"]')).toBeVisible();
    });

    test("an emptied, open shelf still takes a file let go just below it", async ({ page }) => {
      test.skip(page.viewportSize().width < 700, "mouse drag on desktop layouts");
      await gotoPage(page, L.path);
      await waitForDemo(page);
      await page.locator("#demo").scrollIntoViewIfNeeded();
      await page.locator("#demo .dm-files").click({ position: { x: 4, y: 4 } });
      await page.evaluate(() => window.altilloDemo.show("shelf"));
      await page.locator('#demo [data-act="empty"]').click();
      await expect.poll(async () => (await demoState(page)).shelf).toEqual([]);

      const fb = await page.locator('#demo .dm-file[data-file="proposal"]').boundingBox();
      await page.mouse.move(fb.x + fb.width / 2, fb.y + fb.height / 2);
      await page.mouse.down();
      // Aim a little under the short, empty panel: it lights up as it's
      // approached, and a lit shelf takes the file.
      const nb = await page.locator("#demo .dm-notch").boundingBox();
      await page.mouse.move(nb.x + nb.width / 2, nb.y + nb.height + 40, { steps: 20 });
      await expect(page.locator("#demo .an-shelf.an-card--lit")).toHaveCount(1);
      await page.mouse.up();
      await expect.poll(async () => (await demoState(page)).shelf).toContain("proposal");
    });
  });
}

test.describe("scroll-driven demo (wide screens)", () => {
  test.beforeEach(({ page }) => test.skip(!isWide(page), "steps only show from 1300 px"));

  for (const L of LOCALES) {
    test(`${L.code}: scrolling drives the demo; reaching in pauses it until Resume`, async ({ page }) => {
      await gotoPage(page, L.path);
      await waitForDemo(page);

      await centre(page, '.step[data-module="calendar"]');
      await expect.poll(async () => (await demoState(page)).module).toBe("calendar");
      await expect(page.locator('.step[data-module="calendar"]')).toHaveClass(/is-active/);

      // Reaching into the demo takes the wheel.
      const pill = page.locator(".try__paused");
      await expect(pill).toBeHidden();
      await page.locator("#demo .dm-files").click({ position: { x: 4, y: 4 } });
      await expect(pill).toBeVisible();

      // Scrolling on no longer changes the module…
      await centre(page, '.step[data-module="mirror"]');
      await page.waitForFunction(() => {
        const el = document.querySelector('.step[data-module="mirror"]').getBoundingClientRect();
        return el.top < innerHeight / 2 && el.bottom > innerHeight / 2;
      });
      await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
      expect((await demoState(page)).module).toBe("calendar");

      // …until Resume hands it back, catching up with the step on the
      // centre line.
      // (Dispatched, so the click itself can't scroll the page.)
      const resume = page.getByRole("button", { name: L.resume });
      await expect(resume).toBeVisible();
      await resume.dispatchEvent("click");
      await expect(pill).toBeHidden();
      const centred = () => page.evaluate(() => [...document.querySelectorAll(".step")].find((el) => {
        const r = el.getBoundingClientRect();
        return r.top <= innerHeight / 2 && r.bottom >= innerHeight / 2;
      })?.dataset.module);
      await expect.poll(async () => (await demoState(page)).module === (await centred())).toBe(true);
      expect((await demoState(page)).module).not.toBe("calendar");
    });
  }
});
