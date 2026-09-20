import "./hero-film.css";
import { mountHeroSequence } from "./hero-sequence.js";

const clamp = (value) => Math.max(0, Math.min(1, value));
const ramp = (value, start, end) => clamp((value - start) / (end - start));

/** A cinematic sequence. Scrolling selects frames, in either direction. */
export function mountHeroFilm() {
  const hero = document.querySelector(".hero");
  const stage = hero?.querySelector(".hero-stage");
  const poster = hero?.querySelector(".hero-media");
  const intro = document.querySelector(".intro");
  if (!hero || !stage || !poster || !intro) return { destroy() {} };

  const copy = hero.querySelector(".hero-copy");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const anchor = document.createComment("Intro position without the film");
  intro.before(anchor);
  const canvas = document.createElement("canvas");
  canvas.className = "hero-canvas";
  canvas.setAttribute("aria-hidden", "true");
  canvas.hidden = true;
  poster.after(canvas);

  const track = document.createElement("div");
  track.className = "hero-film-track";
  track.setAttribute("aria-hidden", "true");
  track.innerHTML = '<span></span>';
  stage.append(track);
  let ready = false;
  let active = false;
  let frame = 0;
  let disposed = false;
  let sequence;

  function update() {
    frame = 0;
    if (!active || disposed) return;
    const bounds = hero.getBoundingClientRect();
    const travel = Math.max(1, bounds.height - stage.offsetHeight);
    const progress = clamp(-bounds.top / travel);
    // Leave the final room on screen while the explanation arrives over it.
    sequence?.setProgress(ramp(progress, 0.015, 0.78));
    const introProgress = ramp(progress, 0.72, 0.88);
    hero.style.setProperty("--film-copy", String(1 - ramp(progress, 0.015, 0.15)));
    hero.style.setProperty("--film-intro", String(introProgress));
    hero.style.setProperty("--film-intro-y", `${(1 - introProgress) * 32}px`);
    hero.style.setProperty("--film-shade", String(ramp(progress, 0.65, 0.9)));
    hero.style.setProperty("--film-opening", String(1 - ramp(progress, 0.05, 0.24)));
    track.firstElementChild.style.transform = `scaleX(${progress})`;
    copy.inert = progress > 0.17;
    intro.inert = introProgress < 0.7;
  }

  function schedule() {
    if (!frame && !disposed) frame = requestAnimationFrame(update);
  }

  function syncMode() {
    const enabled = ready && !reducedMotion.matches && !navigator.connection?.saveData;
    if (enabled === active) return;
    // A slow connection must not move the demo after someone has jumped to it.
    const followingSection = document.querySelector("#experience");
    const preservePosition = hero.getBoundingClientRect().bottom <= 0;
    const previousTop = followingSection?.getBoundingClientRect().top;
    active = enabled;
    hero.classList.toggle("has-film", enabled);
    if (enabled) {
      stage.append(intro);
      // Its reveal is linked to the film, not to IntersectionObserver.
      intro.querySelectorAll(".motion-reveal").forEach((el) => el.classList.remove("motion-reveal"));
      schedule();
    } else {
      anchor.after(intro);
      copy.inert = false;
      intro.inert = false;
    }
    if (preservePosition && followingSection) {
      window.scrollBy({
        top: followingSection.getBoundingClientRect().top - previousTop,
        behavior: "instant",
      });
    }
    sequence?.resize();
  }

  sequence = mountHeroSequence({
    canvas, poster, reducedMotion,
    onReady() {
      ready = true;
      syncMode();
    },
  });
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  reducedMotion.addEventListener("change", syncMode);
  navigator.connection?.addEventListener("change", syncMode);

  return {
    destroy() {
      disposed = true;
      if (frame) cancelAnimationFrame(frame);
      sequence.destroy();
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      reducedMotion.removeEventListener("change", syncMode);
      navigator.connection?.removeEventListener("change", syncMode);
      anchor.after(intro);
      anchor.remove();
      canvas.remove();
      track.remove();
      hero.classList.remove("has-film");
      for (const property of ["--film-copy", "--film-intro", "--film-intro-y", "--film-shade", "--film-opening"])
        hero.style.removeProperty(property);
      copy.inert = false;
      intro.inert = false;
    },
  };
}
