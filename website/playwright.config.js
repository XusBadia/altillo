import { defineConfig, devices } from "@playwright/test";

// The suite runs against the production build (`vite build` + `vite preview`),
// so hashed assets, the demo's lazy chunks and every public file are exactly
// what Vercel serves.
const desktop = { viewport: { width: 1440, height: 900 } };

export default defineConfig({
  testDir: "./tests",
  fullyParallel: !process.env.CI,
  workers: process.env.CI ? 1 : undefined,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["line"], ["html", { open: "never" }]] : "list",
  use: { baseURL: "http://127.0.0.1:4174" },
  webServer: {
    command: "npx vite build && npx vite preview --host 127.0.0.1 --port 4174 --strictPort",
    url: "http://127.0.0.1:4174",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], ...desktop } },
    { name: "safari", use: { ...devices["Desktop Safari"], ...desktop } },
    { name: "mobile", use: { ...devices["iPhone 13"], defaultBrowserType: "chromium" } },
    { name: "mobile-safari", use: { ...devices["iPhone 13"] } },
  ],
});
