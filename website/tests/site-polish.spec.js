import { test, expect } from '@playwright/test';

for (const route of ['/', '/es/']) {
  test(`download stays readable and navigation fits narrow screens ${route}`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto(route);
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      const download = page.locator('.nav-download');
      await expect(download).toBeVisible();
      const metrics = await download.evaluate(el => {
        const css = getComputedStyle(el);
        const channel = value => { const s = value / 255; return s <= .04045 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4; };
        const light = value => value.match(/[\d.]+/g).slice(0, 3).map(Number).map(channel).reduce((v, c, i) => v + c * [.2126, .7152, .0722][i], 0);
        const a = light(css.color), b = light(css.backgroundColor);
        return { contrast: (Math.max(a, b) + .05) / (Math.min(a, b) + .05), padding: parseFloat(css.paddingLeft) };
      });
      expect(metrics.contrast).toBeGreaterThanOrEqual(4.5);
      expect(metrics.padding).toBeGreaterThanOrEqual(12);
      const visible = await page.locator('.site-header a').evaluateAll(links => links.filter(el => el.getBoundingClientRect().width).map(el => ({ left: el.getBoundingClientRect().left, right: el.getBoundingClientRect().right })));
      for (const box of visible) { expect(box.left).toBeGreaterThanOrEqual(0); expect(box.right).toBeLessThanOrEqual(width); }
    }
    await expect(page.locator('.hero-download')).toHaveAttribute('href', 'https://github.com/XusBadia/altillo/releases/latest');
  });
}
