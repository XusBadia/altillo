import "./motion.css";

const clamp = (value) => Math.min(1, Math.max(0, value));
const chapters = new Set(["shelf", "usage", "agents"]);

/** Scroll enhances the page; native scrolling and the demo remain independent. */
export function mountMotion({ demo } = {}) {
  const hero = document.querySelector(".hero");
  const media = hero?.querySelector(".hero-media");
  const copy = hero?.querySelector(".hero-copy");
  const experience = document.querySelector("#experience");
  const steps = [
    ...document.querySelectorAll(".story-step[data-chapter]"),
  ].filter((step) => chapters.has(step.dataset.chapter));
  const demoElement = document.querySelector("#interactive-demo");
  const progressElements = [...document.querySelectorAll(".chapter-progress")];
  const currentElements = [...document.querySelectorAll(".chapter-current")];
  const revealElements = [...document.querySelectorAll("[data-reveal]")];
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const originalTransforms = new Map(
    [media, copy]
      .filter(Boolean)
      .map((element) => [element, element.style.transform]),
  );

  let frame = 0;
  let destroyed = false;
  let lastChapter = null;
  let manualChapter = null;
  let pointerHeld = false;
  let observer;

  function measureSteps() {
    const sticky = document.querySelector(".demo-sticky");
    const stickyBottom =
      sticky && window.innerWidth < 1000
        ? Math.min(
            window.innerHeight * 0.6,
            Math.max(0, sticky.getBoundingClientRect().bottom),
          )
        : 0;
    const center = stickyBottom
      ? stickyBottom + (window.innerHeight - stickyBottom) * 0.45
      : window.innerHeight / 2;
    const bounds = steps.map((step) => step.getBoundingClientRect());
    let closest = -1;
    let distance = Infinity;
    bounds.forEach((rect, index) => {
      const nextDistance = Math.abs(rect.top + rect.height / 2 - center);
      if (nextDistance < distance) {
        closest = index;
        distance = nextDistance;
      }
    });
    return { bounds, closest, center };
  }

  function update() {
    frame = 0;
    if (destroyed) return;

    // Finish geometry reads before changing styles or the demo's DOM.
    const heroRect = hero?.getBoundingClientRect();
    const experienceRect = experience?.getBoundingClientRect();
    const { bounds, closest, center } = measureSteps();
    const heroProgress = heroRect
      ? clamp(-heroRect.top / Math.max(heroRect.height, 1))
      : 0;

    if (reducedMotion.matches) {
      originalTransforms.forEach((transform, element) => {
        element.style.transform = transform;
      });
    } else {
      if (media)
        media.style.transform = `translateY(${(heroProgress * 80).toFixed(2)}px) scale(${(1 + heroProgress * 0.08).toFixed(4)})`;
      if (copy)
        copy.style.transform = `translateY(${(heroProgress * 20).toFixed(2)}px)`;
    }

    if (closest < 0) return;
    const chapter = steps[closest].dataset.chapter;
    const firstCenter = bounds[0].top + bounds[0].height / 2;
    const lastCenter = bounds.at(-1).top + bounds.at(-1).height / 2;
    const progress = clamp(
      (center - firstCenter) / Math.max(lastCenter - firstCenter, 1),
    );

    progressElements.forEach((element) => {
      // Visually changes width without triggering layout on every frame.
      element.style.transform = `scaleX(${progress.toFixed(4)})`;
    });
    currentElements.forEach((element) => {
      const label = String(closest + 1).padStart(2, "0");
      if (element.textContent !== label) element.textContent = label;
    });
    steps.forEach((step, index) =>
      step.classList.toggle("is-active", index === closest),
    );

    // Manual demo choices survive incidental scrolls and resizes. Scroll takes
    // over only when the reader reaches another story chapter.
    if (pointerHeld || manualChapter === chapter) return;
    if (
      experienceRect &&
      (experienceRect.top >= window.innerHeight || experienceRect.bottom <= 0)
    )
      return;
    if (manualChapter !== null) {
      manualChapter = null;
      lastChapter = null;
    }
    if (chapter !== lastChapter) {
      demo?.setChapter?.(chapter);
      lastChapter = chapter;
    }
  }

  function schedule() {
    if (!frame && !destroyed) frame = window.requestAnimationFrame(update);
  }

  function preserveInteraction(event) {
    if (
      event.type === "keydown" &&
      !["Enter", " ", "ArrowLeft", "ArrowRight", "Home", "End"].includes(
        event.key,
      )
    )
      return;
    const { closest } = measureSteps();
    manualChapter = closest >= 0 ? steps[closest].dataset.chapter : lastChapter;
    if (event.type === "pointerdown") pointerHeld = true;
  }

  function releasePointer() {
    if (!pointerHeld) return;
    pointerHeld = false;
    schedule();
  }

  function motionPreferenceChanged() {
    if (reducedMotion.matches) {
      revealElements.forEach((element) =>
        element.classList.remove("motion-reveal"),
      );
    }
    schedule();
  }

  if ("IntersectionObserver" in window) {
    observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          if (!reducedMotion.matches)
            entry.target.classList.add("motion-reveal");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.08 },
    );
    revealElements.forEach((element) => observer.observe(element));
  }

  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  window.addEventListener("pointerup", releasePointer);
  window.addEventListener("pointercancel", releasePointer);
  window.addEventListener("blur", releasePointer);
  demoElement?.addEventListener("pointerdown", preserveInteraction, {
    passive: true,
  });
  demoElement?.addEventListener("keydown", preserveInteraction);
  demoElement?.addEventListener("demo:interaction", preserveInteraction);
  reducedMotion.addEventListener("change", motionPreferenceChanged);
  schedule();

  return {
    destroy() {
      if (destroyed) return;
      destroyed = true;
      if (frame) window.cancelAnimationFrame(frame);
      observer?.disconnect();
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      window.removeEventListener("pointerup", releasePointer);
      window.removeEventListener("pointercancel", releasePointer);
      window.removeEventListener("blur", releasePointer);
      demoElement?.removeEventListener("pointerdown", preserveInteraction);
      demoElement?.removeEventListener("keydown", preserveInteraction);
      demoElement?.removeEventListener("demo:interaction", preserveInteraction);
      reducedMotion.removeEventListener("change", motionPreferenceChanged);
      originalTransforms.forEach((transform, element) => {
        element.style.transform = transform;
      });
      revealElements.forEach((element) =>
        element.classList.remove("motion-reveal"),
      );
      steps.forEach((step) => step.classList.remove("is-active"));
      progressElements.forEach((element) =>
        element.style.removeProperty("transform"),
      );
    },
  };
}
