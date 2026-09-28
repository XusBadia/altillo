// Altillo — Direction B. Hero open, nav reveal, scroll reveals.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const hero = document.getElementById("hero");
  const nav = document.getElementById("nav");

  // The notch starts closed (black pill with ears), then springs open.
  if (reduce) hero.classList.add("is-open");
  else {
    const open = () => setTimeout(() => hero.classList.add("is-open"), 650);
    if (document.readyState === "complete") open();
    else window.addEventListener("load", open, { once: true });
  }

  // The sticky nav takes over once the hero's own menu bar has scrolled away.
  const onScroll = () => nav.classList.toggle("is-visible", window.scrollY > 140);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // Fade + 8 px as sections arrive.
  const items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("is-in"));
    return;
  }
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      }
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  items.forEach((el) => io.observe(el));
})();
