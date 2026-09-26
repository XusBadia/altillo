import { test, expect } from '@playwright/test';

const chapterFor = { calendar: 'day', music: 'day', mirror: 'day', usage: 'ai', agents: 'ai' };

async function choose(page, module) {
  const step = page.locator(`.story-step[data-chapter="${chapterFor[module]}"]`);
  await step.evaluate(el => {
    const rect = el.getBoundingClientRect();
    window.scrollTo({
      top: scrollY + rect.top + rect.height / 2 - innerHeight * (innerWidth < 1000 ? .72 : .5),
      behavior: 'instant',
    });
  });
  await expect(step).toHaveClass(/is-active/);
  await step.locator(`[data-module="${module}"]`).click();
  await expect(page.locator('.ad-notch')).toHaveAttribute('data-view', module);
}

async function checkInlineIcons(page) {
  // A fresh context with the old sprite unavailable catches a blank first paint.
  await page.route('**/icons.svg*', route => route.abort());
  await page.goto('/');
  await expect(page.locator('svg use')).toHaveCount(0);
  for (const module of Object.keys(chapterFor)) {
    await choose(page, module);
    const panel = page.locator('.ad-notch-panel');
    await expect(panel.locator('[data-action="close"] svg path')).not.toHaveCount(0);
    await expect(panel.locator('svg use')).toHaveCount(0);
    const graphics = await panel.locator('svg:visible').evaluateAll(elements => elements.map(svg => {
      const bounds = svg.getBBox();
      return {
        paths: svg.querySelectorAll('path').length,
        painted: bounds.width > 0 && bounds.height > 0,
      };
    }));
    expect(graphics.length).toBeGreaterThan(1);
    for (const graphic of graphics) {
      expect(graphic.paths).toBeGreaterThan(0);
      expect(graphic.painted).toBe(true);
    }
  }
}

async function checkStablePlaybackIcon(page) {
  // This test owns SVG stability, not the scroll film. Avoid a late WebKit
  // layout shift handing the demo back to another chapter during playback.
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await choose(page, 'music');
  const button = page.locator('[data-action="music-play"]');
  const audio = page.locator('audio.ad-demo-audio');
  await expect(button).toHaveAttribute('aria-pressed', 'false');
  const playShape = await button.locator('svg').innerHTML();
  await button.click();
  await expect(button).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => audio.evaluate(el => el.currentTime)).toBeGreaterThan(.25);
  expect(await button.locator('svg').innerHTML()).not.toBe(playShape);
  await button.evaluate(el => {
    window.pauseIconNode = el.querySelector('svg');
    window.pauseIconMutations = 0;
    window.pauseIconObserver = new MutationObserver(records => {
      window.pauseIconMutations += records.filter(record => record.type === 'childList').length;
    });
    window.pauseIconObserver.observe(el, { childList: true, subtree: true });
    window.audioTickCount = 0;
    document.querySelector('audio').addEventListener('timeupdate', () => { window.audioTickCount += 1; });
  });
  // Wait for real media timeupdates, not synthetic events or a fixed sleep.
  await expect.poll(() => page.evaluate(() => window.audioTickCount)).toBeGreaterThanOrEqual(4);
  expect(await button.evaluate(el => el.querySelector('svg') === window.pauseIconNode)).toBe(true);
  expect(await page.evaluate(() => window.pauseIconMutations)).toBe(0);
  await page.evaluate(() => window.pauseIconObserver.disconnect());
  await button.click();
  await expect(button).toHaveAttribute('aria-pressed', 'false');
  expect(await audio.evaluate(el => el.paused)).toBe(true);
  expect(await button.locator('svg').innerHTML()).toBe(playShape);
}

test('all demo icons paint without fetching the external sprite', async ({ page }) => {
  await checkInlineIcons(page);
});

test('the pause SVG stays mounted while audio time advances', async ({ page }) => {
  await checkStablePlaybackIcon(page);
});

test.describe('touch Safari', () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3 });
  test('inline icons and pause remain stable on a touch viewport', async ({ page, browserName }) => {
    test.skip(browserName !== 'webkit', 'The other projects already cover Chromium desktop and mobile.');
    await checkInlineIcons(page);
    await checkStablePlaybackIcon(page);
  });
});
