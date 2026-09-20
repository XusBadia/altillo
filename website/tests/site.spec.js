import { test, expect } from '@playwright/test';

async function chapter(page, name) {
  const step = page.locator(`.story-step[data-chapter="${name}"]`);
  await step.evaluate((el) => {
    const r = el.getBoundingClientRect();
    window.scrollTo({ top: scrollY + r.top + r.height / 2 - innerHeight * (innerWidth < 1000 ? 0.72 : 0.5), behavior: 'instant' });
  });
  await expect(step).toHaveClass(/is-active/);
}

test('explains the product, labels development and links to Aurio without overflow', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toContainText(/Tu Mac ya tenía\s*un altillo/);
  await expect(page.locator('.hero-function')).toContainText('Deja archivos en el notch');
  await expect(page.locator('#proyecto')).toContainText('Todavía no hay una versión pública para descargar');
  await expect(page.getByRole('link', { name: 'Conocer Aurio', exact: true })).toHaveAttribute('href', 'https://www.aurioapp.com');
  await expect(page.getByRole('tab')).toHaveCount(0);
  await expect(page.locator('.story-step')).toHaveCount(3);
  for (const [name, view] of [['shelf', 'idle'], ['day', 'calendar'], ['ai', 'usage']]) {
    await chapter(page, name);
    await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', view);
    if (name === 'ai') await expect(page.locator(`.story-step[data-chapter="${name}"]`)).toContainText('EN DESARROLLO');
    else await expect(page.locator(`.story-step[data-chapter="${name}"]`)).not.toContainText('EN DESARROLLO');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  expect(errors).toEqual([]);
});

test('double-clicking the Aurio mascot follows its external link', async ({ page }) => {
  await page.route('https://www.aurioapp.com/**', (route) => route.abort());
  await page.goto('/');
  const aurioRequest = page.waitForRequest((request) => request.url().startsWith('https://www.aurioapp.com'));
  await page.locator('.aurio-sign').dblclick();
  expect((await aurioRequest).url()).toBe('https://www.aurioapp.com/');
});

test('three taps on the support label make Aurio wink without following the link', async ({ page }) => {
  await page.goto('/');
  const trigger = page.locator('.support-top .eyebrow');
  const aurio = page.locator('.aurio-sign');
  const urlBefore = page.url();
  await trigger.click();
  await trigger.click();
  await trigger.click();
  await expect(page.locator('body')).toHaveClass(/egg-aurio/);
  await expect(aurio).toHaveClass(/is-winking/);
  await expect(page).toHaveURL(urlBefore);
});

test('scroll chapters preserve manual choice until the next chapter', async ({ page }) => {
  await page.goto('/');
  await chapter(page, 'shelf');
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'idle');
  await page.locator('.story-step [data-module="drawer"]').click();
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'drawer');
  await page.evaluate(() => window.scrollBy({ top: 12, behavior: 'instant' }));
  await expect(page.locator('.story-step[data-chapter="shelf"]')).toHaveClass(/is-active/);
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'drawer');
  await chapter(page, 'ai');
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'usage');
  await expect(page.locator('.chapter-current')).toHaveText('03');
  await chapter(page, 'day');
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'calendar');
  await expect(page.locator('.chapter-current')).toHaveText('02');
});

test('reduced motion disables parallax while chapters remain usable', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await chapter(page, 'day');
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'calendar');
  await expect(page.locator('.hero-media')).toHaveCSS('transform', 'none');
  await expect(page.locator('.hero-copy')).toHaveCSS('transform', 'none');
  await expect(page.locator('html')).toHaveCSS('scroll-behavior', 'auto');
  await expect(page.locator('.intro h2')).toHaveCSS('opacity', '1');
});

test('page remains readable without JavaScript', async ({ browser, baseURL }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(baseURL);
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await expect(page.locator('.intro h2')).toBeVisible();
  await expect(page.locator('noscript p')).toBeVisible();
  await expect(page.locator('noscript p')).toContainText('Activa JavaScript');
  await expect(page.getByRole('link', { name: 'Conocer Aurio', exact: true })).toBeVisible();
  await context.close();
});
