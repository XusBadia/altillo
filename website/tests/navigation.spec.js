import { test, expect } from '@playwright/test';

for (const route of ['/', '/en/']) {
  test(`navigation stays available outside the demo ${route}`, async ({ page }) => {
    await page.goto(route);
    const header = page.locator('.site-header');
    await expect(header).toBeVisible();
    expect(await header.evaluate(el => getComputedStyle(el).position)).toBe('fixed');
    await page.locator('#experience').evaluate(el => window.scrollTo({ top: scrollY + el.getBoundingClientRect().top, behavior: 'instant' }));
    await expect(header).toHaveClass(/is-demo-hidden/);
    await expect(header).toHaveJSProperty('inert', true);
    await page.locator('#proyecto').evaluate(el => window.scrollTo({ top: scrollY + el.getBoundingClientRect().top, behavior: 'instant' }));
    await expect(header).not.toHaveClass(/is-demo-hidden/);
    await expect(header).toBeVisible();
    await expect(header).toHaveJSProperty('inert', false);
    const destination = route === '/' ? '/en/' : '/';
    await header.locator(`.language-link[href="${destination}"]`).click();
    await expect(page).toHaveURL(new RegExp(destination === '/' ? '/$' : '/en/$'));
  });
}

test('provider logos use brand SVG paths instead of interface symbols', async ({ page }) => {
  await page.goto('/');
  await page.locator('[data-module="usage"]').click();
  const logos = page.locator('.ad-usage-card .ad-brand-logo');
  await expect(logos).toHaveCount(2);
  for (const logo of await logos.all()) {
    expect(await logo.locator('path').count()).toBeGreaterThan(0);
    const box = await logo.boundingBox();
    expect(box.width).toBeGreaterThanOrEqual(16);
    expect(Math.abs(box.width - box.height)).toBeLessThan(1);
  }
});
