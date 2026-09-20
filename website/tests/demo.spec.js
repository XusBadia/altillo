import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.locator('.story-step[data-chapter="shelf"]').evaluate((el) => {
    const r = el.getBoundingClientRect();
    window.scrollTo({ top: scrollY + r.top + r.height / 2 - innerHeight * (innerWidth < 1000 ? 0.72 : 0.5), behavior: 'instant' });
  });
  await expect(page.locator('.story-step[data-chapter="shelf"]')).toHaveClass(/is-active/);
  await page.getByRole('button', { name: 'Reiniciar demo' }).click();
});

test('adds, delivers and removes a document while keeping its original', async ({ page }) => {
  const demo = page.locator('#interactive-demo');
  await demo.getByRole('button', { name: 'Subir al estante' }).click();
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf añadido al estante.');
  await expect(demo.getByRole('button', { name: 'En el estante', exact: true })).toBeDisabled();
  await demo.getByRole('button', { name: /^Llevar a Entregas/ }).click();
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf llevado a Entregas.');
  await expect(demo.locator('.ad-destination')).toContainText('1 archivo recibido');
  await expect(demo.getByRole('button', { name: 'Ideas.pdf, documento de ejemplo', exact: true })).toBeVisible();
  await demo.getByRole('button', { name: 'Subir al estante' }).click();
  await demo.getByRole('button', { name: 'Retirar Ideas.pdf', exact: true }).click();
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf retirado del estante.');
  await expect(demo.getByRole('button', { name: 'Subir al estante' })).toBeEnabled();
});

test('selects another file with a pointer before adding it', async ({ page }) => {
  const demo = page.locator('#interactive-demo');
  await demo.getByRole('button', { name: 'Escapada.jpg, documento de ejemplo', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Escapada.jpg, documento de ejemplo', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(demo.getByRole('button', { name: 'Ideas.pdf, documento de ejemplo', exact: true })).toHaveAttribute('aria-pressed', 'false');
  await demo.getByRole('button', { name: 'Subir al estante' }).click();
  await expect(demo.getByRole('status')).toHaveText('Escapada.jpg añadido al estante.');
  await expect(demo.getByRole('button', { name: 'Retirar Escapada.jpg', exact: true })).toBeVisible();
});

test('shows both usage providers and closes the panel with Escape', async ({ page }) => {
  const demo = page.locator('#interactive-demo');
  const trigger = demo.getByRole('button', { name: 'Ver consumo de Claude y Codex' });
  await trigger.click();
  await expect(trigger).toHaveAttribute('aria-expanded', 'true');
  await expect(demo.getByRole('img', { name: 'Claude: 85% consumido' })).toBeVisible();
  await expect(demo.getByRole('img', { name: 'Codex: 34% consumido' })).toBeVisible();
  await expect(demo.getByRole('meter', { name: 'Consumo semanal de Claude' })).toHaveAttribute('aria-valuenow', '41');
  await expect(demo.getByRole('meter', { name: 'Consumo semanal de Codex' })).toHaveAttribute('aria-valuenow', '58');
  await expect(demo.getByText('Consumo de ejemplo · función en desarrollo')).toBeVisible();
  await trigger.press('Escape');
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');
  await expect(demo.locator('.ad-notch-panel')).toBeHidden();
  await expect(trigger).toBeFocused();
});

test('allows and denies simulated requests and resets desktop state', async ({ page }) => {
  const demo = page.locator('#interactive-demo');
  await demo.getByRole('button', { name: 'Subir al estante' }).click();
  await demo.getByRole('button', { name: 'Cerrar Altillo' }).click();
  await demo.getByRole('button', { name: /Pedir permiso para continuar/ }).click();
  await expect(demo.getByText('Solicitud simulada · función en desarrollo')).toBeVisible();
  await demo.getByRole('button', { name: 'Permitir', exact: true }).click();
  await expect(demo.getByText('El agente puede continuar.')).toBeVisible();
  await expect(demo.locator('.ad-terminal-result')).toContainText('Cambios publicados en la demo');
  await demo.getByRole('button', { name: 'Otra solicitud', exact: true }).click();
  await demo.getByRole('button', { name: 'Denegar', exact: true }).click();
  await expect(demo.getByText('El comando no se ejecutará.')).toBeVisible();
  await expect(demo.locator('.ad-terminal-result')).toContainText('No se ha publicado nada');
  await demo.getByRole('button', { name: 'Reiniciar demo' }).click();
  await expect(demo.getByRole('status')).toHaveText('Demo reiniciada.');
  await expect(demo.locator('.ad-notch-panel')).toBeHidden();
  await expect(demo.getByRole('button', { name: 'Subir al estante' })).toBeEnabled();
  await expect(demo.locator('.ad-destination')).toContainText('Carpeta vacía');
  await expect(demo.getByRole('button', { name: /Pedir permiso para continuar/ })).toBeVisible();
});

async function center(locator) {
  const box = await locator.boundingBox();
  expect(box).not.toBeNull();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function mouseDrag(page, source, target) {
  const start = await center(source);
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 8, start.y - 8);
  await expect(page.locator('.ad-drag-ghost')).toBeVisible();
  const end = await center(target);
  await page.mouse.move(end.x, end.y, { steps: 12 });
  await page.mouse.up();
}

test('drags a file to the notch and then to Entregas with a mouse', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Native touch is covered by the mobile test.');
  const demo = page.locator('#interactive-demo');
  await mouseDrag(page, demo.getByRole('button', { name: 'Ideas.pdf, documento de ejemplo', exact: true }), demo.locator('.ad-notch'));
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf añadido al estante.');
  await mouseDrag(page, demo.getByRole('button', { name: 'Ideas.pdf, en el estante', exact: true }), demo.locator('.ad-destination'));
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf llevado a Entregas.');
  await expect(demo.locator('.ad-destination')).toContainText('1 archivo recibido');
  await expect(page.locator('.ad-drag-ghost')).toHaveCount(0);
});

test('drags into the notch with native touch', async ({ page, context, isMobile }) => {
  test.skip(!isMobile, 'Native touch runs in the mobile Chromium project.');
  const session = await context.newCDPSession(page);
  const demo = page.locator('#interactive-demo');
  const start = await center(demo.getByRole('button', { name: 'Ideas.pdf, documento de ejemplo', exact: true }));
  const point = (x, y) => [{ x, y, id: 1, radiusX: 4, radiusY: 4, force: 1 }];
  await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: point(start.x, start.y) });
  await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: point(start.x + 10, start.y - 10) });
  await expect(page.locator('.ad-drag-ghost')).toBeVisible();
  const end = await center(demo.locator('.ad-notch'));
  for (let n = 1; n <= 10; n++) await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: point(start.x + (end.x - start.x) * n / 10, start.y + (end.y - start.y) * n / 10) });
  await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await expect(demo.getByRole('status')).toHaveText('Ideas.pdf añadido al estante.');
  await expect(demo.getByRole('button', { name: 'Retirar Ideas.pdf', exact: true })).toBeVisible();
  await expect(page.locator('.ad-drag-ghost')).toHaveCount(0);
  await session.detach();
});
