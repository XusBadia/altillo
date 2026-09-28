// Fade + rise on scroll. Reduced motion is handled in CSS (everything shown).
const io = new IntersectionObserver(
  (entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      }
    }
  },
  { rootMargin: "0px 0px -12% 0px", threshold: 0.08 }
);
document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
