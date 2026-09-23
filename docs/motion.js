// Motion for the hero's gauge and the provider matrix. The page is complete
// without this file: the gauge stands at its first reading, and the matrix is
// simply there.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const art = document.querySelector(".hero-art");
  if (art) liveGauge(art, reduce);

  const matrix = document.querySelector(".matrix");
  if (!matrix) return;
  const rows = [...matrix.tBodies[0].rows];
  rows.forEach((row, i) => {
    row.style.setProperty("--i", i);
    [...row.cells].forEach((cell, c) => cell.style.setProperty("--c", c));
  });

  // The column under the pointer lights, header included.
  let hot = -1;
  const light = (column) => {
    if (column === hot) return;
    hot = column;
    for (const row of matrix.rows) {
      [...row.cells].forEach((cell, c) => cell.classList.toggle("col-hot", c === column && c > 0));
    }
  };
  matrix.addEventListener("pointerover", (event) => {
    const cell = event.target.closest("td, th");
    if (cell && matrix.contains(cell)) light(cell.cellIndex);
  });
  matrix.addEventListener("pointerleave", () => light(-1));

  if (reduce || !("IntersectionObserver" in window)) return;
  matrix.classList.add("armed");
  const seen = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const row = entry.target;
        row.classList.add("in");
        seen.unobserve(row);
        setTimeout(() => row.classList.add("settled"), 1400 + rows.indexOf(row) * 80);
      }
    },
    { rootMargin: "0px 0px -8% 0px" },
  );
  rows.forEach((row) => seen.observe(row));
})();

// The hero's gauge plays a five-hour session on its own: the reading climbs
// in small steps with quiet spells between, the week creeps up behind it, the
// dot on the outer orbit marks how much of the session's time has gone, and
// when the time runs out, or the limit does, it resets. The CSS eases between
// readings; this only names the next one every few seconds, and stops while
// the gauge is off screen or the tab is hidden.
function liveGauge(art, reduce) {
  const gauge = art.querySelector(".hero-gauge");
  const figure = art.querySelector("[data-figure]");
  const caption = art.querySelector("[data-caption]");
  const weekOut = art.querySelector("[data-week]");
  const paceOut = art.querySelector("[data-pace]");
  const ticks = [...gauge.querySelectorAll(".ticks line")];
  const first = Number(gauge.style.getPropertyValue("--v")) || 0;
  for (const line of ticks) line.classList.toggle("lit", first >= Number(line.dataset.at));
  if (reduce) return;

  const SESSION = 300;
  const STEP_MINUTES = 6;
  const STEP_MS = 2600;
  const state = { v: 66, w: 41, gone: 166 };
  let shown = 0;
  let frame = 0;

  const left = () => {
    const minutes = Math.max(0, SESSION - state.gone);
    return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
  };

  const count = (target, length, delay = 0) => {
    cancelAnimationFrame(frame);
    const from = shown;
    const start = performance.now() + delay;
    const ease = (t) => 1 - Math.pow(1 - t, 3);
    const tick = (now) => {
      const t = Math.min(1, Math.max(0, (now - start) / length));
      shown = from + (target - from) * ease(t);
      figure.textContent = `${Math.round(shown)}%`;
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
  };

  const paint = (length = 1100) => {
    gauge.style.setProperty("--v", state.v.toFixed(2));
    gauge.style.setProperty("--w", state.w.toFixed(2));
    gauge.style.setProperty("--t", ((state.gone / SESSION) * 100).toFixed(2));
    gauge.dataset.level = state.v >= 90 ? "high" : "";
    for (const line of ticks) line.classList.toggle("lit", state.v >= Number(line.dataset.at));
    weekOut.textContent = `${Math.round(state.w)}%`;
    const ahead = state.v > (state.gone / SESSION) * 100 + 12;
    paceOut.textContent = ahead ? "ahead of pace" : "on pace";
    paceOut.classList.toggle("ahead", ahead);
    count(state.v, length);
  };

  const reset = () => {
    gauge.classList.add("draining", "flash");
    caption.classList.add("reset");
    caption.textContent = "limit reset · a fresh five hours";
    state.v = 2 + Math.random() * 4;
    state.gone = 0;
    if (state.w > 94) state.w = 5;
    paint(1900);
    setTimeout(() => {
      gauge.classList.remove("draining", "flash");
      caption.classList.remove("reset");
    }, 2400);
  };

  const step = () => {
    state.gone += STEP_MINUTES;
    if (state.gone >= SESSION || state.v >= 97) {
      reset();
      return;
    }
    if (Math.random() < 0.62) {
      const used = 0.4 + Math.random() * 2.1;
      state.v = Math.min(99, state.v + used);
      state.w = Math.min(99, state.w + used * 0.16);
    }
    caption.textContent = `current session · resets in ${left()}`;
    paint();
  };

  // The intro (CSS) fills from nothing; the number follows it.
  count(state.v, 1800, 600);

  let timer = 0;
  let onScreen = true;
  const sync = () => {
    const run = onScreen && !document.hidden;
    art.classList.toggle("paused", !run);
    if (run && !timer) timer = setInterval(step, STEP_MS);
    if (!run && timer) {
      clearInterval(timer);
      timer = 0;
    }
  };
  document.addEventListener("visibilitychange", sync);
  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      onScreen = entries[0].isIntersecting;
      sync();
    }).observe(art);
  }
  setTimeout(sync, 2600);
}
