import { test, expect } from '@playwright/test';

const chapters = {
  shelf: 'shelf', drawer: 'shelf', calendar: 'day', music: 'day', mirror: 'day', usage: 'ai', agents: 'ai',
};

async function choose(page, module) {
  const step = page.locator(`.story-step[data-chapter="${chapters[module]}"]`);
  await step.evaluate((el) => {
    const r = el.getBoundingClientRect();
    window.scrollTo({ top: scrollY + r.top + r.height / 2 - innerHeight * (innerWidth < 1000 ? 0.72 : 0.5), behavior: 'instant' });
  });
  await expect(step).toHaveClass(/is-active/);
  await step.locator(`[data-module="${module}"]`).click();
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', module);
  return page.locator('#interactive-demo');
}

test('all seven modules are reachable within three chapters without tabs', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.story-step')).toHaveCount(3);
  await expect(page.locator('.story-step [data-module]')).toHaveCount(7);
  await expect(page.getByRole('tab')).toHaveCount(0);
  for (const module of Object.keys(chapters)) {
    const demo = await choose(page, module);
    await expect(demo.locator('.ad-notch-panel')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
});

test('calendar joins remain a clearly labelled simulation', async ({ page, context }) => {
  await page.goto('/');
  const demo = await choose(page, 'calendar');
  const pagesBefore = context.pages().length;
  await demo.locator('[data-action="join"][data-event="0"]').click();
  await expect(demo.locator('.ad-meeting-status')).toContainText('Enlace preparado · videollamada simulada');
  expect(context.pages()).toHaveLength(pagesBefore);
  await expect(page).toHaveURL(/\/$/);
});

test('music responds to playback and next while preserving its state', async ({ page }) => {
  await page.goto('/');
  const demo = await choose(page, 'music');
  await expect(demo.locator('.ad-track-title')).toHaveText('A walk in the pines');
  await demo.getByRole('button', { name: 'Reproducir', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Pausar', exact: true })).toBeVisible();
  await demo.getByRole('button', { name: 'Siguiente canción', exact: true }).click();
  await expect(demo.locator('.ad-track-title')).toHaveText('After the rain');
  await choose(page, 'calendar');
  await choose(page, 'music');
  await expect(demo.locator('.ad-track-title')).toHaveText('After the rain');
  await demo.getByRole('button', { name: 'Pausar', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Reproducir', exact: true })).toBeVisible();
});

test('mirror flips its sample without requesting camera access', async ({ page }) => {
  await page.addInitScript(() => {
    window.cameraRequests = 0;
    if (navigator.mediaDevices) {
      navigator.mediaDevices.getUserMedia = async () => {
        window.cameraRequests += 1;
        throw new Error('The website demo must not request camera access');
      };
    }
  });
  await page.goto('/');
  const demo = await choose(page, 'mirror');
  await expect(demo.getByText('Vista de ejemplo · cámara apagada', { exact: true })).toBeVisible();
  await expect(demo.locator('[data-action="mirror-flip"]')).toHaveAttribute('aria-pressed', 'true');
  await demo.locator('[data-action="mirror-flip"]').click();
  await expect(demo.locator('[data-action="mirror-flip"]')).toHaveAttribute('aria-pressed', 'false');
  await expect(demo.locator('.ad-mirror-art')).toHaveAttribute('data-flipped', 'false');
  expect(await page.evaluate(() => window.cameraRequests)).toBe(0);
});

test('drawer reveals its group and opens an example menu', async ({ page }) => {
  await page.goto('/');
  const demo = await choose(page, 'drawer');
  await expect(demo.locator('.ad-drawer-icons')).toBeHidden();
  await demo.locator('[data-action="drawer-toggle"]').click();
  await expect(demo.locator('.ad-drawer-icons')).toBeVisible();
  await expect(demo.locator('[data-action="drawer-toggle"]')).toHaveAttribute('aria-expanded', 'true');
  await demo.locator('[data-action="drawer-menu"]').click();
  await expect(demo.locator('.ad-drawer-menu')).toContainText('Actualizado ahora');
  await demo.locator('[data-action="drawer-toggle"]').click();
  await expect(demo.locator('.ad-drawer-icons')).toBeHidden();
  await expect(demo.locator('.ad-drawer-menu')).toBeHidden();
});

test('reset clears the state of every daily module', async ({ page }) => {
  await page.goto('/');
  const demo = await choose(page, 'drawer');
  await demo.locator('[data-action="drawer-toggle"]').click();
  await choose(page, 'calendar');
  await demo.locator('[data-action="join"][data-event="0"]').click();
  await choose(page, 'music');
  await demo.locator('[data-action="music-play"]').click();
  await demo.locator('[data-action="music-next"]').click();
  await choose(page, 'mirror');
  await demo.locator('[data-action="mirror-flip"]').click();
  await demo.getByRole('button', { name: 'Reiniciar demo', exact: true }).click();
  await choose(page, 'drawer');
  await expect(demo.locator('.ad-drawer-icons')).toBeHidden();
  await choose(page, 'calendar');
  await expect(demo.locator('.ad-meeting-status')).toHaveCount(0);
  await choose(page, 'music');
  await expect(demo.locator('.ad-track-title')).toHaveText('A walk in the pines');
  await expect(demo.getByRole('button', { name: 'Reproducir', exact: true })).toBeVisible();
  await choose(page, 'mirror');
  await expect(demo.locator('[data-action="mirror-flip"]')).toHaveAttribute('aria-pressed', 'true');
});

test('English daily modules translate actions and simulation notices', async ({ page }) => {
  await page.goto('/en/');
  const demo = await choose(page, 'calendar');
  await demo.locator('[data-action="join"][data-event="0"]').click();
  await expect(demo.locator('.ad-meeting-status')).toContainText('Link ready · simulated video call');
  await choose(page, 'music');
  await demo.getByRole('button', { name: 'Play', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Pause', exact: true })).toBeVisible();
  await expect(demo.getByRole('button', { name: 'Next track', exact: true })).toBeVisible();
  await choose(page, 'mirror');
  await expect(demo.getByText('Sample view · camera off', { exact: true })).toBeVisible();
  await choose(page, 'drawer');
  await demo.locator('[data-action="drawer-toggle"]').click();
  await demo.locator('[data-action="drawer-menu"]').click();
  await expect(demo.locator('.ad-drawer-menu')).not.toContainText('Actualizado ahora');
});
