import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";

export default defineConfig({
  build: {
    rolldownOptions: {
      input: {
        en: fileURLToPath(new URL("./index.html", import.meta.url)),
        es: fileURLToPath(new URL("./es/index.html", import.meta.url)),
        privacy: fileURLToPath(new URL("./privacy/index.html", import.meta.url)),
        privacidad: fileURLToPath(new URL("./es/privacidad/index.html", import.meta.url)),
      },
    },
  },
});
