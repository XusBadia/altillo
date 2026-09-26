import { test, expect } from '@playwright/test';

async function music(page, path = '/') {
  // Audio assertions do not exercise scroll motion. Keeping that separate avoids
  // WebKit changing chapters when a late hero frame shifts the page during playback.
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(path);
  const step = page.locator('.story-step[data-chapter="day"]');
  await step.evaluate(el => {
    const r = el.getBoundingClientRect();
    scrollTo({ top: scrollY + r.top + r.height / 2 - innerHeight * (innerWidth < 1000 ? .72 : .5), behavior: 'instant' });
  });
  await expect(step).toHaveClass(/is-active/);
  await page.locator('[data-module="music"]').click();
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', 'music');
  return page.locator('audio.ad-demo-audio');
}

test('three real tracks decode, play, pause and follow the audio clock', async ({ page }) => {
  const audio = await music(page);
  expect(await audio.evaluate(el => el.paused)).toBe(true);
  for (const title of ['Azotea', 'Luz de tarde', 'Último tranvía']) {
    await expect(page.locator('.ad-track-title')).toHaveText(title);
    await page.locator('[data-action="music-play"]').click();
    await expect.poll(() => audio.evaluate(el => el.currentTime)).toBeGreaterThan(.25);
    expect(await audio.evaluate(el => el.duration)).toBeGreaterThan(30);
    expect(await audio.evaluate(el => el.error)).toBeNull();
    await expect(page.locator('[data-action="music-play"]')).toHaveAttribute('aria-pressed', 'true');
    await expect.poll(() => page.locator('.ad-track-progress').getAttribute('aria-valuenow')).not.toBe('0');
    await page.locator('[data-action="music-play"]').click();
    expect(await audio.evaluate(el => el.paused)).toBe(true);
    await page.locator('[data-action="music-next"]').click();
  }
  await expect(page.locator('.ad-track-title')).toHaveText('Azotea');
  await page.locator('[data-action="music-previous"]').click();
  await expect(page.locator('.ad-track-title')).toHaveText('Último tranvía');
  await page.locator('[data-action="music-play"]').click();
  await expect.poll(() => audio.evaluate(el => el.paused)).toBe(false);
  await page.locator('[data-action="reset"]').click();
  expect(await audio.evaluate(el => el.paused && !el.getAttribute('src'))).toBe(true);
});

test('calendar and mirror switch on the first pointer click', async ({ page }) => {
  await music(page);
  for (const module of ['calendar', 'mirror', 'calendar', 'mirror']) {
    await page.locator(`[data-module="${module}"]`).click();
    await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', module);
    await expect(page.locator('.ad-notch-panel')).toBeVisible();
  }
});

test('audio errors are visible and retryable in English', async ({ page }) => {
  await page.route('**/media/music/**', route => route.abort());
  await music(page, '/en/');
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await expect(page.locator('.ad-panel-footer')).toContainText('Playback failed. Press play to try again.');
  await expect(page.getByRole('button', { name: 'Play', exact: true })).toBeVisible();
  await page.unroute('**/media/music/**');
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await expect.poll(() => page.locator('audio').evaluate(el => el.currentTime)).toBeGreaterThan(.25);
  await expect(page.locator('.ad-panel-footer')).toContainText('Three original tracks · real audio');
});

test('the next track starts when the current recording ends', async ({ page }) => {
  const audio = await music(page);
  await page.locator('[data-action="music-play"]').click();
  await expect.poll(() => audio.evaluate(el => el.currentTime)).toBeGreaterThan(.25);
  await audio.evaluate(el => { el.currentTime = el.duration - .15; });
  await expect(page.locator('.ad-track-title')).toHaveText('Luz de tarde');
  await expect.poll(() => audio.evaluate(el => el.currentTime)).toBeGreaterThan(.25);
  expect(await audio.evaluate(el => el.paused)).toBe(false);
});
