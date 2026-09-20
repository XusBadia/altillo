import { readFile, writeFile } from "node:fs/promises";

// Ship just the icons used by this site, keeping static links usable without JS.
const icons = [
  "arrow-up-right", "arrow-down-right", "arrow-down", "arrow-up",
  "house", "folder", "chevron-left", "layout-grid", "check", "x",
  "rotate-ccw", "search", "clock", "monitor", "download", "laptop",
  "compass", "terminal", "trash-2", "wifi", "battery-medium", "command",
  "asterisk", "corner-down-right", "corner-down-left",
];
const root = new URL("../", import.meta.url);
const license = await readFile(new URL("node_modules/lucide-static/LICENSE", root), "utf8");
const symbols = await Promise.all(icons.map(async (name) => {
  const svg = await readFile(new URL(`node_modules/lucide-static/icons/${name}.svg`, root), "utf8");
  const body = svg.match(/<svg[\s\S]*?>([\s\S]*?)<\/svg>/)?.[1]?.trim();
  if (!body) throw new Error(`Invalid Lucide icon: ${name}`);
  return `  <symbol id="${name}" viewBox="0 0 24 24">${body}</symbol>`;
}));
await writeFile(new URL("public/icons.svg", root), `<!-- Generated from lucide-static. See /lucide-LICENSE.txt. -->\n<svg xmlns="http://www.w3.org/2000/svg">\n${symbols.join("\n")}\n</svg>\n`);
await writeFile(new URL("public/lucide-LICENSE.txt", root), license);
