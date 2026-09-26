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

async function clickCurrentPanelControl(demo, selector) {
  const panel = demo.locator('.ad-notch-panel');
  await expect(panel.locator(selector)).toBeVisible();
  await panel.evaluate((currentPanel, currentSelector) => {
    const control = currentPanel.querySelector(currentSelector);
    if (!(control instanceof HTMLElement)) throw new Error(`Missing panel control: ${currentSelector}`);
    control.click();
  }, selector);
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
  await expect(demo.locator('.ad-track-title')).toHaveText('Azotea');
  await demo.getByRole('button', { name: 'Reproducir', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Pausar', exact: true })).toBeVisible();
  // A short sample can end while WebKit is preparing the click, replacing the controls. Dispatch through the
  // stable panel so querying and clicking the current button remain one synchronous operation.
  await clickCurrentPanelControl(demo, '[data-action="music-next"]');
  await expect(demo.locator('.ad-track-title')).toHaveText('Luz de tarde');
  await choose(page, 'calendar');
  await choose(page, 'music');
  await expect(demo.locator('.ad-track-title')).toHaveText('Luz de tarde');
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
  await clickCurrentPanelControl(demo, '[data-action="mirror-flip"]');
  await expect(demo.locator('[data-action="mirror-flip"]')).toHaveAttribute('aria-pressed', 'false');
  await expect(demo.locator('.ad-mirror-art')).toHaveAttribute('data-flipped', 'false');
  await clickCurrentPanelControl(demo, '[data-action="mirror-flip"]');
  await clickCurrentPanelControl(demo, '[data-action="mirror-flip"]');
  await expect(demo.locator('.ad-mirror-art')).toHaveClass(/is-haunted/);
  await expect(demo.locator('.ad-mirror-presence')).toHaveCount(1);
  await expect(demo.locator('.ad-mirror-presence')).toHaveCSS('animation-name', 'ad-presence-arrive');
  await demo.getByRole('button', { name: 'Reiniciar demo', exact: true }).click();
  await expect(demo.locator('.ad-mirror-presence')).toHaveCount(0);
  await expect(page.locator('body')).not.toHaveClass(/egg-demo-mirror-guest/);
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

test('secret module gestures reveal object-specific visual changes', async ({ page }) => {
  await page.goto('/');
  const demo = await choose(page, 'drawer');
  for (let index = 0; index < 3; index += 1) await demo.locator('[data-action="drawer-toggle"]').click();
  await expect(demo.locator('.ad-drawer-surface')).toHaveClass(/is-secret/);
  await expect(demo.locator('.ad-drawer-staircase i')).toHaveCount(7);

  await choose(page, 'calendar');
  await demo.locator('[data-action="join"][data-event="0"]').click();
  await demo.locator('[data-action="join"][data-event="1"]').click();
  await expect(demo.locator('.ad-calendar-surface')).toHaveClass(/is-secret/);
  await expect(demo.locator('.ad-calendar-convergence')).toContainText('La misma sala');

  await choose(page, 'music');
  for (let index = 0; index < 3; index += 1) await demo.locator('[data-action="music-next"]').click();
  await expect(demo.locator('.ad-music-surface')).toHaveClass(/is-secret/);
  await expect(demo.locator('.ad-album-hidden')).toContainText(/PISTA\s*04/);

  await choose(page, 'usage');
  const usage = demo.locator('[data-action="usage"]');
  await usage.click();
  await usage.click();
  await usage.click();
  await expect(demo.locator('.ad-usage-cards')).toHaveClass(/is-secret/);
  await expect(demo.locator('.ad-impossible-value')).toHaveCount(2);

  await choose(page, 'agents');
  await clickCurrentPanelControl(demo, '[data-action="deny"]');
  await clickCurrentPanelControl(demo, '.ad-agent-request [data-action="agent"]');
  await clickCurrentPanelControl(demo, '[data-action="allow"]');
  await expect(demo.locator('.ad-agent-request')).toHaveClass(/is-remembering/);
  await expect(demo.locator('.ad-agent-memory')).toContainText('LA CASA RECUERDA');
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
  await expect(demo.locator('.ad-track-title')).toHaveText('Azotea');
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
