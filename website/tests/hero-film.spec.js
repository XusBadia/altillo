import { test, expect } from "@playwright/test";

async function scrollThroughHero(page, progress) {
  await page.locator(".hero").evaluate((hero, value) => {
    const stage = hero.querySelector(".hero-stage");
    const top = scrollY + hero.getBoundingClientRect().top;
    const travel = hero.getBoundingClientRect().height - stage.getBoundingClientRect().height;
    scrollTo({ top: top + travel * value, behavior: "instant" });
  }, progress);
}

async function imageSignature(canvas) {
  return canvas.evaluate((element) => {
    const context = element.getContext("2d");
    const pixels = [];
    for (const y of [0.2, 0.4, 0.6, 0.8]) {
      for (const x of [0.2, 0.4, 0.6, 0.8]) {
        pixels.push(...context.getImageData(Math.floor(element.width * x), Math.floor(element.height * y), 1, 1).data);
      }
    }
    return pixels;
  });
}

test("the actual film advances with scrolling, introduces the next section and reverses", async ({ page, request }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  const response = await request.get("/media/hero-sequence/manifest.json");
  expect(response.ok()).toBe(true);
  const manifest = await response.json();
  expect(manifest.count).toBeGreaterThan(1);
  await page.goto("/");

  const hero = page.locator(".hero");
  const canvas = page.locator(".hero-canvas");
  const intro = page.locator(".intro");
  await expect(hero).toHaveClass(/has-film/);
  await expect(canvas).toBeVisible();
  await expect(canvas).toHaveAttribute("data-frame", "0");
  await expect.poll(() => canvas.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return Math.abs(element.width / element.height - bounds.width / bounds.height);
  })).toBeLessThan(0.005);
  const openingImage = await imageSignature(canvas);
  expect(openingImage.some((value, index) => index % 4 !== 3 && value > 15)).toBe(true);
  await expect(intro).toHaveCSS("opacity", "0");

  await scrollThroughHero(page, 0.4);
  await expect.poll(async () => Number(await canvas.getAttribute("data-frame"))).toBeGreaterThan(manifest.count * 0.3);
  expect(Number(await canvas.getAttribute("data-frame"))).toBeLessThan(manifest.count * 0.75);
  expect(await imageSignature(canvas)).not.toEqual(openingImage);

  await scrollThroughHero(page, 0.94);
  await expect(canvas).toHaveAttribute("data-frame", String(manifest.count - 1));
  await expect(intro).toHaveCSS("opacity", "1");
  await expect(intro.getByRole("heading")).toBeInViewport();
  await expect(intro.getByRole("link", { name: "Pruébalo aquí" })).toBeEnabled();
  expect(await intro.evaluate((element) => element.inert)).toBe(false);
  expect(await imageSignature(canvas)).not.toEqual(openingImage);

  await scrollThroughHero(page, 0);
  await expect(canvas).toHaveAttribute("data-frame", "0");
  await expect(intro).toHaveCSS("opacity", "0");
  expect(await imageSignature(canvas)).toEqual(openingImage);
  await expect(page.locator(".hero-copy")).toHaveCSS("opacity", "1");
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test("reduced motion keeps a static hero without requesting film assets", async ({ page }) => {
  const filmRequests = [];
  page.on("request", (request) => {
    if (request.url().includes("/media/hero-sequence/")) filmRequests.push(request.url());
  });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.locator(".hero-canvas")).toBeAttached();
  await expect(page.locator(".hero-canvas")).toBeHidden();
  await expect(page.locator(".hero")).not.toHaveClass(/has-film/);
  await expect(page.locator(".hero-media")).toBeVisible();
  await page.locator(".intro").scrollIntoViewIfNeeded();
  await expect(page.locator(".intro").getByRole("heading")).toBeInViewport();
  expect(await page.locator(".intro").evaluate((element) => !element.closest(".hero"))).toBe(true);
  await page.getByRole("heading", { name: "Un Mac. Tu turno." }).scrollIntoViewIfNeeded();
  await expect(page.getByRole("heading", { name: "Un Mac. Tu turno." })).toBeInViewport();
  expect(filmRequests).toEqual([]);
});

test("a missing film leaves the poster and the following content usable", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.route("**/media/hero-sequence/manifest.json", (route) => route.fulfill({ status: 404, body: "Not found" }));
  const missingManifest = page.waitForResponse("**/media/hero-sequence/manifest.json");
  await page.goto("/");
  expect((await missingManifest).status()).toBe(404);
  await expect(page.locator(".hero")).not.toHaveClass(/has-film/);
  await expect(page.locator(".hero-canvas")).toBeHidden();
  await expect(page.locator(".hero-media")).toBeVisible();
  await page.locator(".intro").scrollIntoViewIfNeeded();
  await expect(page.locator(".intro").getByRole("heading")).toBeInViewport();
  await expect(page.locator(".intro")).toHaveCSS("opacity", "1");
  await page.locator(".intro").getByRole("link", { name: "Pruébalo aquí" }).click();
  await expect(page).toHaveURL(/#experience$/);
  await expect(page.getByRole("heading", { name: "Un Mac. Tu turno." })).toBeInViewport();
  expect(errors).toEqual([]);
});

test("delayed frames never reverse a forward swipe and are reused on the way back", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  const requests = new Map();
  await page.route("**/hero-sequence/frame-*.webp", async (route) => {
    const url = route.request().url();
    requests.set(url, (requests.get(url) || 0) + 1);
    // Out-of-order arrivals reproduce a variable mobile connection.
    const index = Number(url.match(/frame-(\d+)/)[1]);
    await new Promise((resolve) => setTimeout(resolve, index % 5 === 0 ? 65 : 15));
    await route.continue();
  });
  await page.goto("/");
  const canvas = page.locator(".hero-canvas");
  await expect(canvas).toHaveAttribute("data-frame", "0");
  const seen = await page.evaluate(() => new Promise((resolve) => {
    const canvas = document.querySelector(".hero-canvas");
    const hero = document.querySelector(".hero");
    const travel = hero.offsetHeight - hero.querySelector(".hero-stage").offsetHeight;
    const start = performance.now();
    const seen = [];
    function step(now) {
      const progress = Math.min(1, (now - start) / 1400);
      scrollTo({ top: travel * progress * 0.7, behavior: "instant" });
      seen.push(Number(canvas.dataset.frame));
      if (progress < 1) requestAnimationFrame(step);
      else resolve(seen);
    }
    requestAnimationFrame(step);
  }));
  expect(seen.at(-1)).toBeGreaterThan(120);
  expect(seen.every((value, index) => index === 0 || value >= seen[index - 1])).toBe(true);
  await scrollThroughHero(page, 0.94);
  await expect(canvas).toHaveAttribute("data-frame", "239");
  await scrollThroughHero(page, 0);
  await expect(canvas).toHaveAttribute("data-frame", "0");
  expect(Math.max(...requests.values())).toBe(1);
});
