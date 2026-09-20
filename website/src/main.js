import "./style.css";
import { mountDemo } from "./demo.js";
import { mountMotion } from "./motion.js";
import { mountHeroFilm } from "./hero-film.js";

const demo = mountDemo(document.querySelector("#interactive-demo"), {
  locale: document.documentElement.lang,
});
const motion = mountMotion({ demo });
const heroFilm = mountHeroFilm();
const moduleButtons = [...document.querySelectorAll("[data-module]")];
function selectModule(event) {
  demo.setModule(event.currentTarget.dataset.module);
}
moduleButtons.forEach((button) => button.addEventListener("click", selectModule));
if (import.meta.hot) import.meta.hot.dispose(() => {
  moduleButtons.forEach((button) => button.removeEventListener("click", selectModule));
  heroFilm.destroy();
  motion.destroy();
  demo.destroy?.();
});

// Keep the current section when changing language with a normal page navigation.
for (const link of document.querySelectorAll(".language-switch a")) {
  link.addEventListener("click", () => {
    const destination = new URL(link.href);
    destination.hash = window.location.hash;
    link.href = destination.href;
  });
}
