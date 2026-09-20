import "./style.css";
import { mountDemo } from "./demo.js";
import { mountMotion } from "./motion.js";
import { mountHeroFilm } from "./hero-film.js";
import { mountEasterEggs } from "./easter-eggs.js";

const demoElement = document.querySelector("#interactive-demo");
const demo = mountDemo(demoElement, {
  locale: document.documentElement.lang,
});
const motion = mountMotion({ demo });
const heroFilm = mountHeroFilm();
const easterEggs = mountEasterEggs({
  demoElement,
  locale: document.documentElement.lang,
});
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
  easterEggs.destroy?.();
});

// Keep the current section when changing language with a normal page navigation.
for (const link of document.querySelectorAll(".language-switch a")) {
  link.addEventListener("click", () => {
    const destination = new URL(link.href);
    destination.hash = window.location.hash;
    link.href = destination.href;
  });
}
