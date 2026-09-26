import { readFile } from 'node:fs/promises';
import { test, expect } from '@playwright/test';

const repoRoot = new URL('../../', import.meta.url);

for (const policy of [
  {
    route: '/privacy/',
    canonical: 'https://altillo.app/privacy/',
    heading: 'Your things stay on your Mac.',
    provider: 'AI usage checks',
    web: 'Ask and web lookups',
    alternateLanguage: 'es',
    other: 'Updates, links and diagnostics',
    alternate: 'https://altillo.app/es/privacidad/',
  },
  {
    route: '/es/privacidad/',
    canonical: 'https://altillo.app/es/privacidad/',
    heading: 'Tus cosas se quedan en tu Mac.',
    provider: 'Consultas de consumo de IA',
    web: 'Pregunta y consultas web',
    other: 'Actualizaciones, enlaces y diagnósticos',
    alternate: 'https://altillo.app/privacy/',
    alternateLanguage: 'en',
  },
]) {
  test(`publishes a complete privacy policy at ${policy.route}`, async ({ page }) => {
    await page.goto(policy.route);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(policy.heading);
    await expect(page.getByRole('heading', { name: policy.provider })).toBeVisible();
    await expect(page.getByRole('heading', { name: policy.web })).toBeVisible();
    await expect(page.getByRole('heading', { name: policy.other })).toBeVisible();
    await expect(page.locator('tbody tr')).toHaveCount(10);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', policy.canonical);
    await expect(page.locator(`link[rel="alternate"][hreflang="${policy.alternateLanguage}"]`)).toHaveAttribute('href', policy.alternate);
    await expect(page.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute('href', 'https://altillo.app/privacy/');
  });
}

test('home pages link to the matching privacy policy and state the Drawer limit', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'Privacy', exact: true })).toHaveAttribute('href', '/privacy/');
  await expect(page.locator('#proyecto')).toContainText('On macOS 27');
  await expect(page.locator('#proyecto')).toContainText('remain visible in the menu bar');

  await page.goto('/es/');
  await expect(page.getByRole('link', { name: 'Privacidad', exact: true })).toHaveAttribute('href', '/es/privacidad/');
  await expect(page.locator('#proyecto')).toContainText('En macOS 27');
  await expect(page.locator('#proyecto')).toContainText('siguen visibles también en la barra');
});

test('public source claims cannot regress to local-only provider credentials', async () => {
  const paths = [
    'README.md',
    'Apps/macOS/Settings/SettingsModulesPane.swift',
    'Apps/macOS/Onboarding/OnboardingAIToolsPage.swift',
    'Apps/macOS/Resources/Localizable.xcstrings',
    'website/index.html',
    'website/es/index.html',
  ];
  const contents = await Promise.all(paths.map((path) => readFile(new URL(path, repoRoot), 'utf8')));
  const publicCopy = contents.join('\n');
  const forbidden = [
    ['numbers never', 'leave this Mac'],
    ['compatible with', 'OpenUsage'],
    ['your credentials never', 'leave your Mac'],
  ];
  for (const parts of forbidden) {
    expect(publicCopy.toLowerCase()).not.toContain(parts.join(' ').toLowerCase());
  }
});
