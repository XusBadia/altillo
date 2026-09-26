import { test, expect } from '@playwright/test';

async function ready(page, path = '/') {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(path);
  const step = page.locator('.story-step[data-chapter="shelf"]');
  await step.evaluate((el) => {
    const rect = el.getBoundingClientRect();
    scrollTo({ top: scrollY + rect.top + rect.height / 2 - innerHeight * (innerWidth < 1000 ? .72 : .5), behavior: 'instant' });
  });
  await expect(step).toHaveClass(/is-active/);
  await page.getByRole('button', { name: path.startsWith('/en') ? 'Reset demo' : 'Reiniciar demo' }).click();
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'idle');
}

async function hoverNotch(page) {
  await page.locator('.ad-camera').hover();
  await page.clock.fastForward(150);
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'shelf');
}

test('hover teaches opening, grants an exit grace period and closes without a click', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Touch has no hover interaction');
  await ready(page);
  await expect(page.getByRole('button', { name: 'Abrir Altillo', exact: true })).toContainText('Acerca el cursor aquí');
  await page.clock.install();
  await hoverNotch(page);
  await expect(page.getByRole('button', { name: 'Abrir estante', exact: true })).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator('.ad-notch-cue')).toBeHidden();
  await page.mouse.move(0, 0);
  await page.clock.fastForward(100);
  await expect(page.locator('.ad-notch-panel')).toBeVisible();
  await page.locator('.ad-camera').hover();
  await page.clock.fastForward(250);
  await expect(page.locator('.ad-notch-panel')).toBeVisible();
  await page.mouse.move(0, 0);
  await page.clock.fastForward(250);
  await expect(page.locator('.ad-notch-panel')).toBeHidden();
});

test('click pins a hover-open shelf and hover never replaces selected usage', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Touch has no hover interaction');
  await ready(page);
  await page.clock.install();
  await hoverNotch(page);
  await page.getByRole('button', { name: 'Abrir estante', exact: true }).click();
  await page.mouse.move(0, 0);
  await page.getByRole('button', { name: 'Reiniciar demo' }).focus();
  await page.clock.fastForward(300);
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'shelf');
  await page.getByRole('button', { name: 'Ver consumo de Claude y Codex' }).click();
  await page.mouse.move(0, 0);
  await page.locator('.ad-camera').hover();
  await page.clock.fastForward(300);
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'usage');
  await expect(page.getByRole('img', { name: 'Claude: 85% consumido' })).toBeVisible();
});

test('keyboard focus protects an open hover panel until focus leaves', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Touch has no hover interaction');
  await ready(page);
  await page.clock.install();
  await hoverNotch(page);
  await page.getByRole('button', { name: 'Cerrar Altillo' }).focus();
  await page.mouse.move(0, 0);
  await page.clock.fastForward(300);
  await expect(page.getByRole('button', { name: 'Cerrar Altillo' })).toBeFocused();
  await expect(page.locator('.ad-notch-panel')).toBeVisible();
  await page.getByRole('button', { name: 'Reiniciar demo' }).focus();
  await page.clock.fastForward(300);
  await expect(page.locator('.ad-notch-panel')).toBeHidden();
});

test('touch enters without opening and the visible cue opens on tap', async ({ page, isMobile }) => {
  test.skip(!isMobile, 'Tests the touch-specific cue and pointer');
  await ready(page, '/en/');
  await expect(page.getByRole('button', { name: 'Open Altillo', exact: true })).toContainText('Tap to open');
  await page.clock.install();
  await page.locator('.ad-notch').dispatchEvent('pointerenter', { pointerType: 'touch', isPrimary: true });
  await page.clock.fastForward(400);
  await expect(page.locator('.ad-notch-panel')).toBeHidden();
  await page.getByRole('button', { name: 'Open Altillo', exact: true }).tap();
  await expect(page.getByRole('button', { name: 'Open shelf', exact: true })).toHaveAttribute('aria-expanded', 'true');
});

test('English demo translates actions, outcomes and accessibility names throughout a full task', async ({ page }) => {
  await ready(page, '/en/');
  const demo = page.locator('#interactive-demo');
  await expect(demo.getByRole('button', { name: 'Ideas.pdf, sample document', exact: true })).toBeVisible();
  await demo.getByRole('button', { name: 'Add to shelf', exact: true }).click();
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf added to the shelf.');
  await expect(demo.getByRole('button', { name: 'Ideas.pdf, on the shelf', exact: true })).toBeVisible();
  await demo.getByRole('button', { name: /^Move to Deliveries/ }).click();
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf moved to Deliveries.');
  await expect(demo.getByRole('button', { name: 'Move the shelf file to Deliveries', exact: true })).toContainText('1 file received');
  await demo.getByRole('button', { name: 'Close Altillo' }).click();
  await demo.getByRole('button', { name: 'View Claude and Codex usage' }).click();
  await expect(demo.getByRole('img', { name: 'Claude: 85% used' })).toBeVisible();
  await expect(demo.getByRole('meter', { name: 'Codex weekly usage' })).toHaveAttribute('aria-valuenow', '58');
  await demo.getByRole('button', { name: 'Close Altillo' }).click();
  await demo.getByRole('button', { name: /Request permission to continue/ }).click();
  await expect(demo.getByText('Sample request · you decide; Altillo never auto-approves')).toBeVisible();
  await demo.getByRole('button', { name: 'Allow', exact: true }).click();
  await expect(demo.getByRole('status')).toHaveText('Permission granted in the demo.');
  await expect(demo.locator('.ad-terminal-result')).toContainText('Changes published in the demo.');
  await demo.getByRole('button', { name: 'Another request', exact: true }).click();
  await demo.getByRole('button', { name: 'Deny', exact: true }).click();
  await expect(demo.getByRole('status')).toHaveText('Action denied in the demo.');
  await demo.getByRole('button', { name: 'Reset demo' }).click();
  await expect(demo.getByRole('status')).toHaveText('Demo reset.');
  await expect(demo.locator('.ad-destination')).toContainText('Empty folder');
  await expect(demo.locator('.ad-notch-panel')).toBeHidden();
  await expect(demo.getByRole('button', { name: 'Add to shelf', exact: true })).toBeEnabled();
  await expect(demo).not.toContainText(/Subir al estante|Pedir permiso|Reiniciar|Carpeta vacía/);
});

for (const width of [390, 1280]) {
  test(`English and Spanish switch links stay within the viewport at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/en/');
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.getByRole('link', { name: 'English', exact: true })).toHaveAttribute('aria-current', 'page');
    await expect(page.locator('.hero-function')).toContainText('files');
    await expect(page.locator('main')).not.toContainText(/Deja archivos|Todavía no|Nos ayudas/);
    for (const label of ['English', 'Español']) {
      const link = page.getByRole('link', { name: label, exact: true });
      await expect(link).toBeVisible();
      const rect = await link.boundingBox();
      expect(rect.x).toBeGreaterThanOrEqual(0);
      expect(rect.x + rect.width).toBeLessThanOrEqual(width);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.getByRole('link', { name: 'Español', exact: true }).click();
    await expect(page.locator('html')).toHaveAttribute('lang', 'es');
    await expect(page.getByRole('link', { name: 'Español', exact: true })).toHaveAttribute('aria-current', 'page');
    await expect(page.locator('.hero-function')).toContainText('Deja archivos');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.getByRole('link', { name: 'English', exact: true }).click();
    await expect(page).toHaveURL(/\/en\/$/);
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  });
}
