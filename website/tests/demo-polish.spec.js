import { test, expect } from '@playwright/test';

test('file markers and Finder face stay inside their bounds', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/es/');
  const chapter = page.locator('.story-step[data-chapter="shelf"]');
  await chapter.evaluate(el => {
    const rect = el.getBoundingClientRect();
    window.scrollTo({ top: scrollY + rect.top + rect.height / 2 - innerHeight * (innerWidth < 1000 ? .72 : .5), behavior: 'instant' });
  });
  await expect(chapter).toHaveClass(/is-active/);
  await page.getByRole('button', { name: 'Reiniciar demo' }).click();
  await page.getByRole('button', { name: 'Subir al estante', exact: true }).click();

  for (const [outer, inner] of [
    ['.ad-file-shelved', '.ad-file-shelved svg'],
    ['.ad-dock-finder', '.ad-dock-finder i'],
  ]) {
    const frame = await page.locator(outer).boundingBox();
    const content = await page.locator(inner).boundingBox();
    expect(content.x).toBeGreaterThan(frame.x);
    expect(content.y).toBeGreaterThan(frame.y);
    expect(content.x + content.width).toBeLessThan(frame.x + frame.width);
    expect(content.y + content.height).toBeLessThan(frame.y + frame.height);
  }

  await page.getByRole('button', { name: 'Ver consumo de Claude y Codex' }).click();
  const panel = await page.locator('.ad-notch-panel').boundingBox();
  for (const card of await page.locator('.ad-usage-card').all()) {
    const bounds = await card.boundingBox();
    expect(bounds.x).toBeGreaterThanOrEqual(panel.x);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(panel.x + panel.width);
    expect(await card.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
  }
});
