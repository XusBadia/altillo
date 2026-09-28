(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const mobile = window.matchMedia("(max-width: 760px)");

  /* --- Fit kit pieces to their container: --an-scale = min(max, width / base) */
  const fit = (el) => {
    const wide = window.innerWidth >= 1100 && el.dataset.fitWide;
    const base = wide ? +el.dataset.fitWide : mobile.matches && el.dataset.fitMobile ? +el.dataset.fitMobile : +el.dataset.fit;
    const max = +(el.dataset.fitMax || 1);
    const w = el.clientWidth - (parseFloat(getComputedStyle(el).paddingLeft) + parseFloat(getComputedStyle(el).paddingRight));
    el.style.setProperty("--an-scale", Math.min(max, w / base).toFixed(4));
  };
  const fitted = document.querySelectorAll("[data-fit]");
  const ro = new ResizeObserver((entries) => entries.forEach((e) => fit(e.target)));
  fitted.forEach((el) => { fit(el); ro.observe(el); });

  /* --- Nav hairline once scrolled */
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("is-scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* --- Copy command */
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    let t;
    btn.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(btn.dataset.copy); } catch { /* ignore */ }
      btn.classList.add("is-copied");
      clearTimeout(t);
      t = setTimeout(() => btn.classList.remove("is-copied"), 1600);
    });
  });

  /* --- Reveal on scroll */
  const reveals = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    reveals.forEach((el) => el.classList.add("is-in"));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -10% 0px", threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  }

  /* --- Hero: the terminal asks, the notch knocks and opens (one shot) */
  const scene = document.querySelector("[data-scene]");
  if (!scene) return;
  const typeEl = scene.querySelector("[data-type]");
  const text = typeEl.dataset.type;
  const steps = (n) => scene.querySelectorAll(`.t-step[data-step="${n}"]`);
  const phases = document.querySelectorAll("[data-steps] .steps__item");
  const phase = (n) => phases.forEach((p) => {
    const k = +p.dataset.phase;
    p.classList.toggle("is-on", k === n);
    p.classList.toggle("is-past", k < n);
  });
  const show = (n) => steps(n).forEach((el) => el.classList.add("is-shown"));

  const finalState = () => {
    typeEl.textContent = text;
    [1, 2, 3].forEach(show);
    scene.classList.add("is-asked", "is-knock", "is-open");
    phase(3);
  };
  if (reduce) { finalState(); return; }

  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const run = async () => {
    phase(1);
    await wait(350);
    for (let i = 1; i <= text.length; i++) {
      typeEl.textContent = text.slice(0, i);
      await wait(text[i - 1] === " " ? 34 : 24 + Math.random() * 18);
    }
    await wait(260);
    show(1);
    await wait(320);
    show(2);
    await wait(300);
    show(3);
    scene.classList.add("is-asked");
    await wait(380);
    phase(2);
    scene.classList.add("is-knock");
    await wait(900);
    phase(3);
    scene.classList.add("is-open");
  };

  // Start when the scene is on screen (it is, on load, for most viewports).
  const start = new IntersectionObserver((entries) => {
    if (entries.some((e) => e.isIntersecting)) { start.disconnect(); run(); }
  }, { threshold: 0.25 });
  start.observe(scene);
})();
