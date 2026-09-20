import { readFile, writeFile } from "node:fs/promises";

// Ship just the icons used by this site, keeping static links usable without JS.
// Keep the site's semantic IDs stable while selecting Phosphor's regular weight.
const icons = {
  "arrow-up-right": "arrow-up-right", "arrow-down-right": "arrow-down-right",
  "arrow-down": "arrow-down", "arrow-up": "arrow-up", house: "house",
  folder: "folder", "chevron-left": "caret-left", "layout-grid": "squares-four",
  check: "check", x: "x", "rotate-ccw": "arrow-counter-clockwise",
  search: "magnifying-glass", clock: "clock", monitor: "monitor",
  download: "download-simple", laptop: "laptop", compass: "compass",
  terminal: "terminal", "trash-2": "trash", wifi: "wifi-high",
  "battery-medium": "battery-medium", command: "command", asterisk: "asterisk",
  "corner-down-right": "arrow-elbow-down-right", "corner-down-left": "arrow-elbow-down-left",
  calendar: "calendar-blank", "music-note": "music-notes", play: "play", pause: "pause",
  "skip-back": "skip-back", "skip-forward": "skip-forward", camera: "camera",
  flip: "flip-horizontal", archive: "archive", eye: "eye", "eye-off": "eye-slash",
  settings: "gear", video: "video-camera", person: "user", bell: "bell", cloud: "cloud",
  bluetooth: "bluetooth", "dots-three": "dots-three", "speaker-high": "speaker-high",
};
const root = new URL("../", import.meta.url);
const license = await readFile(new URL("node_modules/@phosphor-icons/core/LICENSE", root), "utf8");
const symbols = await Promise.all(Object.entries(icons).map(async ([id, name]) => {
  const svg = await readFile(new URL(`node_modules/@phosphor-icons/core/assets/regular/${name}.svg`, root), "utf8");
  const body = svg.match(/<svg[\s\S]*?>([\s\S]*?)<\/svg>/)?.[1]?.trim();
  if (!body || !svg.includes('viewBox="0 0 256 256"')) throw new Error(`Invalid Phosphor icon: ${name}`);
  // Phosphor outlines are filled paths. Explicit paint overrides legacy SVG
  // attributes on the host, and 24/256 preserves the site's 24px icon coordinate system.
  return `  <symbol id="${id}" viewBox="0 0 24 24"><g transform="scale(0.09375)" fill="currentColor" stroke="none">${body}</g></symbol>`;
}));
await writeFile(new URL("public/icons.svg", root), `<!-- Generated from @phosphor-icons/core (regular). See /phosphor-LICENSE.txt. -->\n<svg xmlns="http://www.w3.org/2000/svg">\n${symbols.join("\n")}\n</svg>\n`);
await writeFile(new URL("public/phosphor-LICENSE.txt", root), license.replace(/\r\n/g, "\n"));
