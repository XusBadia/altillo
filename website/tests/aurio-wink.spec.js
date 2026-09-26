import { test, expect } from '@playwright/test';

test('Aurio holds the app wink while hovered and returns on leave', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Touch devices do not have hover.');
  await page.goto('/es/');
  const aurio = page.locator('.aurio-sign');
  await aurio.hover();
  await expect(aurio.locator('.aurio-mascot-wink')).toHaveCSS('opacity', '1');
  await expect(aurio.locator('.aurio-mascot-base')).toHaveCSS('opacity', '0');
  await page.mouse.move(0, 0);
  await expect(aurio.locator('.aurio-mascot-wink')).toHaveCSS('opacity', '0');
  await expect(aurio.locator('.aurio-mascot-base')).toHaveCSS('opacity', '1');
});

test('Aurio responds to keyboard focus with reduced motion', async ({ page, browserName }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/es/');
  const aurio = page.locator('.aurio-sign');
  // Start immediately before the mascot, then reach it through native tab order.
  await page.getByRole('link', { name: 'Conocer Aurio', exact: true }).focus();
  // Safari's default keyboard navigation uses Option+Tab to include links.
  const nextLink = browserName === 'webkit' ? 'Alt+Tab' : 'Tab';
  await page.keyboard.press(nextLink);
  await expect(aurio).toBeFocused();
  await expect(aurio.locator('.aurio-mascot-wink')).toHaveCSS('opacity', '1');
  await expect(aurio.locator('.aurio-mascot-wink')).toHaveCSS('transition-duration', '0s');
  await page.keyboard.press(nextLink);
  await expect(aurio.locator('.aurio-mascot-wink')).toHaveCSS('opacity', '0');
});
