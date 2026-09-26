import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";

export default defineConfig({
  build: {
    rolldownOptions: {
      input: {
        en: fileURLToPath(new URL("./index.html", import.meta.url)),
        es: fileURLToPath(new URL("./es/index.html", import.meta.url)),
      },
    },
  },
});
