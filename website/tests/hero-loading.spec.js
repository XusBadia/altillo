import { test, expect } from "@playwright/test";

async function openingLayout(page) {
  return page.evaluate(() => Object.fromEntries(
    [".hero-stage", ".hero-copy", ".hero-bottom", ".image-caption"].map((selector) => {
      const { x, y, width, height } = document.querySelector(selector).getBoundingClientRect();
      return [selector, [x, y, width, height]];
    }),
  ));
}

async function screenshotDifference(page, before, after) {
  return page.evaluate(async ([first, second]) => {
    const images = await Promise.all([first, second].map(async (source) => {
      const image = new Image();
      image.src = `data:image/png;base64,${source}`;
      await image.decode();
      return image;
    }));
    if (images[0].width !== images[1].width || images[0].height !== images[1].height) return Infinity;
    const canvas = document.createElement("canvas");
    canvas.width = images[0].width;
    canvas.height = images[0].height;
    const context = canvas.getContext("2d");
    const pixels = images.map((image) => {
      context.drawImage(image, 0, 0);
      return context.getImageData(0, 0, canvas.width, canvas.height).data;
    });
    let difference = 0;
    for (let index = 0; index < pixels[0].length; index++) {
      if (index % 4 !== 3) difference += Math.abs(pixels[0][index] - pixels[1][index]);
    }
    return difference / (canvas.width * canvas.height * 3);
  }, [before.toString("base64"), after.toString("base64")]);
}

for (const path of ["/", "/en/"]) {
  test(`the opening image and layout stay stable when the film starts: ${path}`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    let releaseManifest;
    const manifestGate = new Promise((resolve) => { releaseManifest = resolve; });
    await page.route("**/hero-sequence/manifest.json", async (route) => {
      await manifestGate;
      await route.continue();
    });
    await page.goto(path, { waitUntil: "domcontentloaded" });
    const poster = page.locator(".hero-media");
    await expect(poster).toHaveAttribute("src", "/media/hero-sequence/frame-000.webp");
    await expect.poll(() => poster.evaluate((image) => image.complete && image.naturalWidth > 0)).toBe(true);
    await expect(page.locator(".hero")).not.toHaveClass(/has-film/);
    await page.evaluate(() => document.fonts.ready);
    const beforeLayout = await openingLayout(page);
    const before = await page.locator(".hero-stage").screenshot();

    releaseManifest();
    await expect(page.locator(".hero")).toHaveClass(/has-film/);
    await expect(page.locator(".hero-canvas")).toHaveAttribute("data-frame", "0");
    await expect(page.locator(".hero-canvas")).toBeVisible();
    const after = await page.locator(".hero-stage").screenshot();
    expect(await openingLayout(page)).toEqual(beforeLayout);
    // The poster and canvas can use slightly different image interpolation.
    // A different Mac image, crop, shade or background produces a large change.
    expect(await screenshotDifference(page, before, after)).toBeLessThan(1.5);
  });
}

test("late opening frame never exposes a later frame or an empty canvas", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.addInitScript(() => {
    window.heroOpeningPaints = [];
    function sample() {
      const canvas = document.querySelector(".hero-canvas");
      if (canvas && canvas.getBoundingClientRect().width > 0 && !canvas.hidden) {
        const context = canvas.getContext("2d");
        let brightness = 0;
        for (const x of [0.25, 0.5, 0.75]) {
          for (const y of [0.25, 0.5, 0.75]) {
            const pixel = context.getImageData(Math.floor(canvas.width * x), Math.floor(canvas.height * y), 1, 1).data;
            brightness += pixel[0] + pixel[1] + pixel[2];
          }
        }
        window.heroOpeningPaints.push({ frame: canvas.dataset.frame, brightness });
      }
      requestAnimationFrame(sample);
    }
    requestAnimationFrame(sample);
  });
  let releaseOpening;
  const openingGate = new Promise((resolve) => { releaseOpening = resolve; });
  await page.route("**/hero-sequence/frame-000.webp", async (route) => {
    // The HTML poster loads normally; only the sequence's opening fetch stalls.
    if (route.request().resourceType() === "fetch") await openingGate;
    await route.continue();
  });
  const laterFrame = page.waitForResponse("**/hero-sequence/frame-001.webp");
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await laterFrame;
  await expect(page.locator(".hero")).not.toHaveClass(/has-film/);
  await expect(page.locator(".hero-media")).toBeVisible();
  await expect(page.locator(".hero-canvas")).toBeHidden();
  releaseOpening();
  await expect(page.locator(".hero")).toHaveClass(/has-film/);
  await expect.poll(() => page.evaluate(() => window.heroOpeningPaints.length)).toBeGreaterThan(5);
  const paints = await page.evaluate(() => window.heroOpeningPaints);
  expect(paints.every(({ frame, brightness }) => frame === "0" && brightness > 0)).toBe(true);
});
