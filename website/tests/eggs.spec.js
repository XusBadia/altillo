import { test, expect } from "@playwright/test";
import { LOCALES, gotoPage, waitForEggs } from "./helpers.js";

for (const L of LOCALES) {
  test.describe(`${L.code} easter eggs`, () => {
    test.beforeEach(async ({ page }) => {
      await gotoPage(page, L.path);
      await waitForEggs(page);
    });

    test("knocking three times on the hero notch", async ({ page }) => {
      await page.locator(".hero__notch").click({ clickCount: 3 });
      await expect(page.locator("html")).toHaveAttribute("data-last-egg", "knock");
      await expect(page.locator(".egg-peek").first()).toBeVisible();
    });

    test("typing “altillo” turns the lights off, and on again", async ({ page }) => {
      await page.locator("body").click({ position: { x: 5, y: 5 } });
      await expect(page.locator("html")).not.toHaveClass(/is-night/);
      await page.keyboard.type("altillo");
      await expect(page.locator("html")).toHaveClass(/is-night/);
      await expect(page.locator("html")).toHaveAttribute("data-last-egg", "lights-out");
      await page.keyboard.type("altillo");
      await expect(page.locator("html")).not.toHaveClass(/is-night/);
    });

    test("“?” opens the secret drawer in the page's language; Escape closes it", async ({ page }) => {
      await page.keyboard.press("?");
      const drawer = page.locator(".egg-drawer");
      await expect(drawer).toBeVisible();
      await expect(page.locator("html")).toHaveClass(/egg-has-drawer/);
      // Our own two eggs are listed alongside the engine's.
      const rows = page.locator(".egg-drawer__item");
      expect(await rows.count()).toBeGreaterThan(8);
      const hints = (await page.locator(".egg-drawer__hint").allTextContents()).join(" ");
      expect(hints).toContain(L.code === "es" ? "Quédate cerca de la luz." : "Linger by the light.");
      await page.keyboard.press("Escape");
      await expect(drawer).toBeHidden();
      await expect(page.locator("html")).not.toHaveClass(/egg-has-drawer/);
    });
  });
}
