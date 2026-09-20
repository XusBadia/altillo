import "./style.css";
import { mountDemo } from "./demo.js";
import { mountMotion } from "./motion.js";

const demo = mountDemo(document.querySelector("#interactive-demo"), {
  locale: document.documentElement.lang,
});
const motion = mountMotion({ demo });
if (import.meta.hot) import.meta.hot.dispose(() => motion.destroy());

// Keep the current section when changing language with a normal page navigation.
for (const link of document.querySelectorAll(".language-switch a")) {
  link.addEventListener("click", () => {
    const destination = new URL(link.href);
    destination.hash = window.location.hash;
    link.href = destination.href;
  });
}
