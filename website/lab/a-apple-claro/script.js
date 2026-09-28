// Altillo «Apple claro»: fit the notch kit to its containers, reveal on
// scroll, and open the hero notch once.
(() => {
  const root = document.documentElement;
  root.classList.add("js");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const ZOOM = 0.947368; // notch.css: 760 pt of app → 720 px at scale 1

  // --- Fit: data-fit = authored width the content needs; data-max caps it.
  const hero = document.querySelector("[data-hero]");
  const heroBezel = hero && hero.querySelector(".an-bezel");

  const fit = () => {
    document.querySelectorAll("[data-fit]").forEach((el) => {
      const cs = getComputedStyle(el);
      const w = el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      const base = Number((w < 700 && el.dataset.fitSm) || el.dataset.fit);
      const max = Number(el.dataset.max || 1);
      el.style.setProperty("--an-scale", Math.min(max, w / (base * ZOOM)).toFixed(4));
    });
    if (hero && heroBezel) {
      const cs = getComputedStyle(hero);
      const w = hero.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      const base = w < 700 ? 780 : 980; // bezel width in app points
      heroBezel.style.width = base + "px";
      hero.style.setProperty("--an-scale", Math.min(1.5, w / (base * ZOOM)).toFixed(4));
    }
  };
  fit();
  let raf = 0;
  addEventListener("resize", () => {
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(fit);
  });

  // --- Reveal: fade + 8 px rise, once.
  const items = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("is-in"));
  } else {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          e.target.classList.add("is-in");
          io.unobserve(e.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    items.forEach((el, i) => {
      // Stagger siblings in the hero copy a touch.
      if (el.closest(".hero__copy")) el.style.transitionDelay = `${i * 60}ms`;
      io.observe(el);
    });
  }

  // --- Hero: the closed pill opens into the shelf, once.
  const notch = document.querySelector(".hero-notch");
  if (notch) {
    if (reduce) {
      notch.classList.remove("is-closed");
    } else {
      const open = () => requestAnimationFrame(() => requestAnimationFrame(() => notch.classList.remove("is-closed")));
      addEventListener("load", () => setTimeout(open, 450), { once: true });
    }
  }
})();
