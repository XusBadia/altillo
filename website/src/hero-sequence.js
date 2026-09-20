const FRAME_LIMIT = 24;
const LOAD_CONCURRENCY = 4;
const SEQUENCE_ROOT = "/media/hero-sequence";

/** A reversible, scroll-driven image sequence. The poster stays underneath it. */
export function mountHeroSequence({ canvas, poster, reducedMotion, onReady } = {}) {
  const context = canvas?.getContext("2d", { alpha: false });
  if (!context) return { setProgress() {}, resize() {}, destroy() {} };

  const motion = reducedMotion || window.matchMedia("(prefers-reduced-motion: reduce)");
  const connection = navigator.connection;
  const frames = new Map();
  // Compressed images cost a few MB; decoded images cost tens of MB. Keep the
  // former for reversals, but only decode a small window around the playhead.
  const sources = new Map();
  const pending = new Map();
  const failed = new Set();
  let manifest;
  let manifestRequest;
  let manifestFailed = false;
  let progress = 0;
  let direction = 1;
  let near = false;
  let destroyed = false;
  let announced = false;
  let firstFrameReady = false;
  let frameRequest = 0;
  let generation = 0;
  let width = 0;
  let height = 0;
  let lastDrawn = -1;
  let lastPosition = -1;
  let needsResizeDraw = true;
  let backgroundOrder = [];

  canvas.hidden = true;

  const enabled = () => !destroyed && !motion.matches && !connection?.saveData;
  const targetFrame = () => Math.round(progress * ((manifest?.count || 1) - 1));

  function priorities() {
    if (!manifest) return [];
    const target = targetFrame();
    const wanted = [];
    if (!firstFrameReady && !failed.has(0)) wanted.push(0);
    if (!wanted.includes(target)) wanted.push(target);
    for (let distance = 1; wanted.length < Math.min(FRAME_LIMIT, manifest.count); distance++) {
      const candidates = [target + distance * direction];
      if (distance % 2 === 0) candidates.push(target - distance / 2 * direction);
      for (const index of candidates) {
        if (index >= 0 && index < manifest.count && !wanted.includes(index)) wanted.push(index);
        if (wanted.length >= Math.min(FRAME_LIMIT, manifest.count)) break;
      }
    }
    return wanted;
  }

  function draw() {
    frameRequest = 0;
    if (!enabled() || !frames.size || !width || !height) return;
    const target = targetFrame();
    let closest;
    for (const index of frames.keys()) {
      // Late downloads must never make a forward gesture play backwards.
      if (lastDrawn >= 0 && target >= lastDrawn && (index < lastDrawn || index > target)) continue;
      if (lastDrawn >= 0 && target < lastDrawn && (index > lastDrawn || index < target)) continue;
      if (closest === undefined || Math.abs(index - target) < Math.abs(closest - target)) closest = index;
    }
    if (closest === undefined) return;
    const bitmap = frames.get(closest);
    // Touch the frame so the cache evicts its least recently used bitmap.
    frames.delete(closest);
    frames.set(closest, bitmap);
    const scale = Math.max(canvas.width / bitmap.width, canvas.height / bitmap.height);
    const drawnWidth = bitmap.width * scale;
    const drawnHeight = bitmap.height * scale;
    const positionX = width < height ? 0.62 - Math.min(progress / 0.4, 1) * 0.12 : 0.5;
    if (closest === lastDrawn && positionX === lastPosition && !needsResizeDraw) return;
    context.drawImage(
      bitmap,
      (canvas.width - drawnWidth) * positionX,
      (canvas.height - drawnHeight) * 0.5,
      drawnWidth,
      drawnHeight,
    );
    canvas.dataset.frame = String(closest);
    lastDrawn = closest;
    lastPosition = positionX;
    needsResizeDraw = false;
    canvas.hidden = false;
    if (firstFrameReady && !announced) {
      announced = true;
      onReady?.();
    }
  }

  function requestDraw() {
    if (!frameRequest && enabled()) frameRequest = requestAnimationFrame(draw);
  }

  function resize() {
    if (destroyed) return;
    const bounds = canvas.getBoundingClientRect();
    // A hidden canvas has no layout box; its poster has the same dimensions.
    const fallback = poster?.getBoundingClientRect();
    width = bounds.width || fallback?.width || canvas.parentElement?.clientWidth || 0;
    height = bounds.height || fallback?.height || canvas.parentElement?.clientHeight || 0;
    if (!width || !height) return;
    const ratio = Math.min(window.devicePixelRatio || 1, 1.5, 1600 / width);
    const nextWidth = Math.max(1, Math.round(width * ratio));
    const nextHeight = Math.max(1, Math.round(height * ratio));
    if (canvas.width !== nextWidth || canvas.height !== nextHeight) {
      canvas.width = nextWidth;
      canvas.height = nextHeight;
      needsResizeDraw = true;
    }
    requestDraw();
  }

  async function loadFrame(index, controller, version) {
    try {
      const name = String(index).padStart(3, "0");
      let blob = sources.get(index);
      if (!blob) {
        const response = await fetch(`${SEQUENCE_ROOT}/frame-${name}.webp`, { signal: controller.signal });
        if (!response.ok) throw new Error(`Sequence frame ${response.status}`);
        blob = await response.blob();
        if (controller.signal.aborted || version !== generation) return;
        sources.set(index, blob);
      }
      if (!priorities().includes(index)) return;
      const bitmap = await createImageBitmap(blob);
      if (version !== generation || controller.signal.aborted || !enabled() || !priorities().includes(index)) {
        bitmap.close();
        return;
      }
      frames.set(index, bitmap);
      if (index === 0) firstFrameReady = true;
      while (frames.size > FRAME_LIMIT) {
        const unwanted = [...frames.keys()].find((candidate) => !priorities().includes(candidate));
        const evicted = unwanted ?? frames.keys().next().value;
        frames.get(evicted).close();
        frames.delete(evicted);
      }
      requestDraw();
    } catch (error) {
      if (!controller.signal.aborted && version === generation) failed.add(index);
    } finally {
      if (pending.get(index) === controller) pending.delete(index);
      if (version === generation) pump();
    }
  }

  function pump() {
    if (!enabled() || !near || !manifest) return;
    const wanted = priorities();
    // Let in-flight requests finish; cancelling on every scroll event starves
    // the playhead on mobile networks. Their compressed results remain useful.
    for (const index of wanted) {
      if (pending.size >= LOAD_CONCURRENCY) break;
      if (frames.has(index) || pending.has(index) || failed.has(index)) continue;
      const controller = new AbortController();
      pending.set(index, controller);
      void loadFrame(index, controller, generation);
    }
    // Warm compressed frames while the scene is near. Sparse coverage first
    // means a fast swipe can show a nearby frame before the whole film arrives.
    for (const index of backgroundOrder) {
      if (pending.size >= LOAD_CONCURRENCY) break;
      if (sources.has(index) || pending.has(index) || failed.has(index)) continue;
      const controller = new AbortController();
      pending.set(index, controller);
      void loadFrame(index, controller, generation);
    }
  }

  async function start() {
    if (!enabled() || !near) return;
    if (manifest) {
      pump();
      return;
    }
    if (manifestRequest || manifestFailed) return;
    const controller = new AbortController();
    manifestRequest = controller;
    const version = generation;
    try {
      const response = await fetch(`${SEQUENCE_ROOT}/manifest.json`, { signal: controller.signal });
      if (!response.ok) throw new Error(`Sequence manifest ${response.status}`);
      const data = await response.json();
      if (!Number.isInteger(data.count) || data.count < 1 || !(data.width > 0) || !(data.height > 0)) {
        throw new Error("Invalid sequence manifest");
      }
      if (version !== generation || !enabled()) return;
      manifest = data;
      backgroundOrder = [];
      for (let index = 0; index < manifest.count; index += 8) backgroundOrder.push(index);
      for (let index = 0; index < manifest.count; index++) {
        if (index % 8 !== 0) backgroundOrder.push(index);
      }
      resize();
      pump();
    } catch (error) {
      if (!controller.signal.aborted && version === generation) manifestFailed = true;
    } finally {
      if (manifestRequest === controller) manifestRequest = undefined;
    }
  }

  function stop() {
    generation++;
    manifestRequest?.abort();
    manifestRequest = undefined;
    for (const controller of pending.values()) controller.abort();
    pending.clear();
    for (const bitmap of frames.values()) bitmap.close();
    frames.clear();
    sources.clear();
    lastDrawn = -1;
    lastPosition = -1;
    needsResizeDraw = true;
    firstFrameReady = false;
    if (frameRequest) cancelAnimationFrame(frameRequest);
    frameRequest = 0;
    canvas.hidden = true;
  }

  function preferencesChanged() {
    if (!enabled()) stop();
    else {
      resize();
      void start();
    }
  }

  const visibilityObserver = typeof IntersectionObserver === "function"
    ? new IntersectionObserver(([entry]) => {
        near = entry.isIntersecting;
        if (near) void start();
      }, { rootMargin: "800px 0px" })
    : null;
  visibilityObserver?.observe(canvas.parentElement || canvas);
  if (!visibilityObserver) {
    near = true;
    void start();
  }
  const sizeObserver = typeof ResizeObserver === "function" ? new ResizeObserver(resize) : null;
  sizeObserver?.observe(canvas.parentElement || canvas);
  if (canvas.parentElement) sizeObserver?.observe(canvas);
  motion.addEventListener?.("change", preferencesChanged);
  connection?.addEventListener?.("change", preferencesChanged);
  window.addEventListener("resize", resize, { passive: true });
  resize();

  return {
    setProgress(value) {
      const next = Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
      if (next !== progress) direction = next > progress ? 1 : -1;
      progress = next;
      requestDraw();
      pump();
    },
    resize,
    destroy() {
      if (destroyed) return;
      destroyed = true;
      stop();
      visibilityObserver?.disconnect();
      sizeObserver?.disconnect();
      motion.removeEventListener?.("change", preferencesChanged);
      connection?.removeEventListener?.("change", preferencesChanged);
      window.removeEventListener("resize", resize);
    },
  };
}
