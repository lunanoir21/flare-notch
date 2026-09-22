// A working copy of flare's notch, fixed to this page's edge.
(() => {
  const providers = [
    {
      id: "claude",
      name: "Claude",
      colour: "#D97757",
      plan: "Pro",
      figure: "27%",
      fraction: 0.27,
      windows: [
        { label: "Current session", reset: "Resets in 3h 12m", used: 0.27 },
        { label: "Weekly (all models)", reset: "Resets Thu 03:00", used: 0.69 },
      ],
      sessions: [
        { pid: 48213, name: "fix-bar-overlap", project: "hypr", age: "42m", state: "busy" },
        { pid: 51877, name: "release-notes", project: "quickshell-flare", age: "12m", state: "waiting" },
        { pid: 50342, name: "try-kwin-layer-shell", project: "notes", age: "1h 5m", state: "idle" },
      ],
    },
    {
      id: "codex",
      name: "Codex",
      colour: "#6E7BFF",
      plan: "Plus",
      figure: "12%",
      fraction: 0.12,
      windows: [
        { label: "5h limit", reset: "Resets in 1h 40m", used: 0.12 },
        { label: "Weekly limit", reset: "Resets Mon 09:00", used: 0.41 },
      ],
    },
    {
      id: "opencode",
      name: "OpenCode",
      colour: "#C9CED6",
      figure: "15K",
      fraction: 1,
      unmetered: true,
      tokens: "15K",
      note: "Runs on your own API keys, so there is no limit to show: tokens today instead.",
    },
  ];

  const logo = (id) => `assets/logos/${id}.svg`;
  const barColour = (used) => (used >= 0.7 ? "var(--high)" : used >= 0.5 ? "var(--mid)" : "var(--good)");
  const stateLabel = { busy: "working", waiting: "waiting on you", idle: "idle" };
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const C = 2 * Math.PI * 25;

  const storage = {
    get(key) {
      try {
        return localStorage.getItem(key);
      } catch {
        return null;
      }
    },
    set(key, value) {
      try {
        localStorage.setItem(key, value);
      } catch {}
    },
  };

  let style = ["classic", "aura", "compact"].includes(storage.get("flare-style")) ? storage.get("flare-style") : "classic";
  let lead = "claude";
  let sessionsOpen = false;
  let openId = null;
  let closeTimer = null;

  const el = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (key === "text") node.textContent = value;
      else if (key === "html") node.innerHTML = value;
      else node.setAttribute(key, value);
    }
    for (const child of [].concat(children)) if (child) node.append(child);
    return node;
  };

  const svg = (markup, cls) => {
    const wrap = document.createElement("span");
    wrap.innerHTML = markup;
    const node = wrap.firstElementChild;
    if (cls) node.setAttribute("class", cls);
    return node;
  };

  // ---------- side notch: classic and aura ----------

  const SVGNS = "http://www.w3.org/2000/svg";
  const px = (name) => parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name)) || 0;

  // A filled shape plus an open hairline along its screen-facing edges; the
  // hairline stops where the shape meets the screen edge, as flare's does.
  function shapeSvg() {
    const svgEl = document.createElementNS(SVGNS, "svg");
    svgEl.setAttribute("class", "shape");
    svgEl.setAttribute("aria-hidden", "true");
    const fill = document.createElementNS(SVGNS, "path");
    fill.setAttribute("class", "fill");
    const edge = document.createElementNS(SVGNS, "path");
    edge.setAttribute("class", "edge");
    svgEl.append(fill, edge);
    return { svgEl, fill, edge };
  }

  function drawShape(shape, left, top, width, height, outline) {
    shape.svgEl.style.left = `${left}px`;
    shape.svgEl.style.top = `${top}px`;
    shape.svgEl.setAttribute("width", width);
    shape.svgEl.setAttribute("height", height);
    shape.svgEl.setAttribute("viewBox", `0 0 ${width} ${height}`);
    shape.fill.setAttribute("d", outline + " Z");
    shape.edge.setAttribute("d", outline);
  }

  const side = el("div", { class: "flare flare-side", "data-style": style });
  const body = el("div", { class: "body", role: "group", "aria-label": "flare notch (a demo)" });
  const sideShape = shapeSvg();
  side.append(sideShape.svgEl, body);

  // Welded to the left edge: a concave flare above and below, rounded body.
  function drawSide() {
    const W = body.offsetWidth;
    const H = body.offsetHeight;
    if (!W || !H) return;
    const r = px("--flare-r");
    const R = px("--body-r");
    const d = `M0 0 A${r} ${r} 0 0 0 ${r} ${r} L${W - R} ${r} A${R} ${R} 0 0 1 ${W} ${r + R} L${W} ${r + H - R} A${R} ${R} 0 0 1 ${W - R} ${r + H} L${r} ${r + H} A${r} ${r} 0 0 0 0 ${H + 2 * r}`;
    drawShape(sideShape, 0, -r, W, H + 2 * r, d);
  }
  new ResizeObserver(drawSide).observe(body);

  function ring(p, isLead) {
    const arc = svg(
      `<svg viewBox="0 0 60 60" aria-hidden="true"><circle class="track" cx="30" cy="30" r="25"/><circle class="arc" cx="30" cy="30" r="25" stroke="${
        p.unmetered ? "#808080" : p.colour
      }" stroke-dasharray="${C}" stroke-dashoffset="${C}"/></svg>`
    );
    const button = el(
      "button",
      {
        class: "ring" + (isLead ? " lead" : ""),
        type: "button",
        "data-id": p.id,
        "aria-expanded": "false",
        "aria-controls": "flare-card",
        "aria-label": p.unmetered ? `${p.name}: ${p.tokens} tokens today` : `${p.name}: ${p.figure} of the current window used`,
      },
      [el("span", { class: "face" }, [arc, el("img", { src: logo(p.id), alt: "" })]), el("span", { class: "figure", text: p.figure })]
    );
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        button.querySelector(".arc").setAttribute("stroke-dashoffset", String(C * (1 - p.fraction)));
      })
    );
    button.addEventListener("pointerenter", (e) => e.pointerType === "mouse" && open(p.id));
    button.addEventListener("pointerleave", (e) => e.pointerType === "mouse" && scheduleClose());
    button.addEventListener("focus", () => open(p.id));
    button.addEventListener("click", () => open(p.id));
    return button;
  }

  function renderSide() {
    body.replaceChildren();
    side.dataset.style = style;
    if (style === "aura") {
      const p = providers.find((x) => x.id === lead);
      const glow = el("div", { class: "aura-glow" });
      glow.style.background = `radial-gradient(120% 60% at 50% 18%, ${p.colour}38, transparent 70%)`;
      const rest = el(
        "div",
        { class: "aura-rest" },
        providers
          .filter((x) => x.id !== lead)
          .map((x) => {
            const b = el("button", { type: "button", "aria-label": `Show ${x.name}` }, [el("img", { src: logo(x.id), alt: "" }), x.figure]);
            b.addEventListener("click", () => {
              lead = x.id;
              close(true);
              renderSide();
            });
            return b;
          })
      );
      body.append(glow, ring(p, true), el("span", { class: "aura-name", text: p.name }), rest);
    } else {
      for (const p of providers) body.append(ring(p, false));
    }
  }

  // ---------- the hover card ----------

  const card = el("div", { class: "card", id: "flare-card", role: "region", "aria-label": "Usage detail" });
  const tail = svg(
    '<svg viewBox="0 0 26 36" aria-hidden="true"><path class="fill" d="M26 0C26 9 12.6 13.7 0 18C12.6 22.3 26 27 26 36Z"/><path class="edge" d="M26 0C26 9 12.6 13.7 0 18C12.6 22.3 26 27 26 36"/></svg>',
    "tail"
  );
  const cardInner = el("div");
  card.append(tail, cardInner);
  card.addEventListener("pointerenter", () => clearTimeout(closeTimer));
  card.addEventListener("pointerleave", (e) => e.pointerType === "mouse" && scheduleClose());

  function windowBlock(w) {
    const fill = el("span");
    fill.style.width = "0%";
    fill.style.background = barColour(w.used);
    requestAnimationFrame(() => requestAnimationFrame(() => (fill.style.width = `${Math.round(w.used * 100)}%`)));
    return el("div", { class: "window" }, [
      el("div", { class: "window-head" }, [el("span", { text: w.label }), el("span", { class: "reset", text: w.reset })]),
      el("div", { class: "bar", role: "img", "aria-label": `${Math.round(w.used * 100)}% used` }, [fill]),
      el("div", { class: "used", text: `${Math.round(w.used * 100)}% used` }),
    ]);
  }

  function sessionsBlock(p) {
    const waiting = p.sessions.filter((s) => s.state === "waiting").length;
    const jumped = el("p", { class: "jumped", "aria-live": "polite" });
    const head = el("button", { class: "sessions-head", type: "button", "aria-expanded": String(sessionsOpen), "aria-controls": "flare-sessions" }, [
      el("span", { text: "Sessions" }),
      el("span", { class: "count" + (waiting ? " waiting" : ""), text: String(p.sessions.length) }),
      svg('<svg viewBox="0 0 10 10" fill="none" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 1.5 7 5 3.5 8.5"/></svg>', "chevron"),
    ]);
    const list = el(
      "ul",
      { id: "flare-sessions" },
      p.sessions.map((s) => {
        const row = el("button", { class: "session", type: "button" }, [
          el("span", { class: `dot ${s.state}`, "aria-hidden": "true" }),
          el("span", {}, [el("span", { class: "session-name", text: s.name }), el("span", { class: "session-sub", text: `${s.project} · ${s.age}` })]),
          el("span", { class: `session-state ${s.state}` }, [
            el("span", { class: "label", text: stateLabel[s.state] }),
            svg('<svg viewBox="0 0 12 12" fill="none" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 9.5 9.5 2.5M4.5 2.5h5v5"/></svg>', "go"),
          ]),
        ]);
        row.setAttribute("aria-label", `${s.name}, ${s.project}, ${stateLabel[s.state]}. Bring its terminal to the front.`);
        row.addEventListener("click", () => {
          jumped.textContent = `flare focus ${s.pid} — on your desktop, this brings the terminal to the front.`;
        });
        return el("li", {}, [row]);
      })
    );
    const fold = el("div", { class: "fold" + (sessionsOpen ? " open" : "") }, [list]);
    list.inert = !sessionsOpen;
    head.addEventListener("click", () => {
      sessionsOpen = !sessionsOpen;
      head.setAttribute("aria-expanded", String(sessionsOpen));
      fold.classList.toggle("open", sessionsOpen);
      list.inert = !sessionsOpen;
    });
    return el("div", { class: "sessions" }, [head, fold, jumped]);
  }

  function renderCard(p) {
    const parts = [
      el("p", { class: "card-title" }, [el("img", { src: logo(p.id), alt: "" }), `${p.name} Usage`]),
      p.plan ? el("p", { class: "card-plan", text: p.plan }) : null,
    ];
    if (p.unmetered) {
      parts.push(el("p", { class: "tokens", text: p.tokens }), el("p", { class: "card-note", text: p.note }));
    } else {
      for (const w of p.windows) parts.push(windowBlock(w));
    }
    if (p.sessions) parts.push(sessionsBlock(p));
    cardInner.replaceChildren(...parts);
  }

  function place() {
    if (!openId) return;
    const anchor = body.querySelector(`.ring[data-id="${openId}"]`);
    if (!anchor) return;
    const r = anchor.querySelector("svg").getBoundingClientRect();
    const b = body.getBoundingClientRect();
    const centre = r.top + r.height / 2;
    const h = card.offsetHeight;
    const top = Math.max(8, Math.min(window.innerHeight - h - 8, centre - h / 2));
    card.style.left = `${b.right + 16}px`;
    card.style.top = `${top}px`;
    tail.style.top = `${Math.max(14, Math.min(h - 50, centre - top - 18))}px`;
  }

  function open(id) {
    clearTimeout(closeTimer);
    if (openId !== id) {
      openId = id;
      renderCard(providers.find((p) => p.id === id));
    }
    for (const b of body.querySelectorAll(".ring")) b.setAttribute("aria-expanded", String(b.dataset.id === id));
    place();
    card.classList.add("open");
  }

  function close(now) {
    clearTimeout(closeTimer);
    const shut = () => {
      card.classList.remove("open");
      for (const b of body.querySelectorAll(".ring")) b.setAttribute("aria-expanded", "false");
      openId = null;
    };
    if (now) shut();
    else closeTimer = setTimeout(shut, 0);
  }

  function scheduleClose() {
    clearTimeout(closeTimer);
    closeTimer = setTimeout(() => close(true), 260);
  }

  new ResizeObserver(place).observe(card);
  window.addEventListener("resize", place);

  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || !openId) return;
    const ring = body.querySelector(`.ring[data-id="${openId}"]`);
    close(true);
    if (card.contains(document.activeElement) && ring) ring.focus({ preventScroll: true });
  });

  document.addEventListener("focusin", (e) => {
    if (openId && !card.contains(e.target) && !body.contains(e.target)) close(true);
  });

  document.addEventListener("pointerdown", (e) => {
    if (openId && !card.contains(e.target) && !body.contains(e.target)) close(true);
  });

  // ---------- compact: a strip on the top edge ----------

  const top = el("div", { class: "flare flare-top" });
  const strip = el(
    "button",
    { class: "strip", type: "button", "aria-expanded": "false", "aria-controls": "flare-panel", "aria-label": "flare, compact: open the panel" },
    providers.map((p) => el("span", {}, [el("img", { src: logo(p.id), alt: "" }), p.figure]))
  );
  const panel = el("div", { class: "panel", id: "flare-panel" }, [
    el(
      "div",
      {},
      el(
        "div",
        { class: "panel-rows" },
        providers.map((p) => {
          if (p.unmetered)
            return el("div", { class: "panel-row" }, [
              el("div", { class: "window-head" }, [el("span", {}, [el("img", { src: logo(p.id), alt: "" }), p.name]), el("span", { class: "reset", text: `${p.tokens} tokens today` })]),
            ]);
          const w = p.windows[0];
          const fill = el("span");
          fill.style.width = `${Math.round(w.used * 100)}%`;
          fill.style.background = barColour(w.used);
          return el("div", { class: "panel-row" }, [
            el("div", { class: "window-head" }, [el("span", {}, [el("img", { src: logo(p.id), alt: "" }), p.name]), el("span", { class: "reset", text: w.reset })]),
            el("div", { class: "bar" }, [fill]),
            el("div", { class: "used", text: `${Math.round(w.used * 100)}% used · ${w.label}` }),
          ]);
        })
      )
    ),
  ]);
  panel.firstElementChild.inert = true;
  const topShape = shapeSvg();

  // Welded to the top edge; the panel grows the same shape downward.
  function drawTop() {
    const W = top.offsetWidth;
    const H = top.offsetHeight;
    if (!W || !H) return;
    const r = 16;
    const R = 16;
    const d = `M0 0 A${r} ${r} 0 0 1 ${r} ${r} L${r} ${H - R} A${R} ${R} 0 0 0 ${r + R} ${H} L${r + W - R} ${H} A${R} ${R} 0 0 0 ${r + W} ${H - R} L${r + W} ${r} A${r} ${r} 0 0 1 ${2 * r + W} 0`;
    drawShape(topShape, -r, 0, W + 2 * r, H, d);
  }
  new ResizeObserver(drawTop).observe(top);
  strip.addEventListener("click", () => {
    const opening = strip.getAttribute("aria-expanded") !== "true";
    strip.setAttribute("aria-expanded", String(opening));
    panel.classList.toggle("open", opening);
    panel.firstElementChild.inert = !opening;
  });
  top.append(topShape.svgEl, strip, panel);

  // ---------- switching looks ----------

  const pointer = document.querySelector(".pointer");
  const touch = window.matchMedia("(hover: none)").matches;

  function apply(next) {
    style = next;
    storage.set("flare-style", style);
    close(true);
    const compact = style === "compact";
    side.hidden = compact;
    top.hidden = !compact;
    if (!compact) renderSide();
    else {
      strip.setAttribute("aria-expanded", "false");
      panel.classList.remove("open");
      panel.firstElementChild.inert = true;
    }
    for (const b of document.querySelectorAll(".look")) b.setAttribute("aria-pressed", String(b.dataset.look === style));
    if (pointer) {
      pointer.dataset.dir = compact ? "up" : "left";
      pointer.querySelector(".words").textContent = compact
        ? "Now it is a strip on the top edge. Click it."
        : `The notch on this page's left edge works. ${touch ? "Tap" : "Hover"} ${style === "aura" ? "the ring" : "a ring"}.`;
    }
  }

  for (const b of document.querySelectorAll(".look")) b.addEventListener("click", () => apply(b.dataset.look));

  // ---------- theme ----------

  const themeButton = document.querySelector(".theme");
  function syncThemeLabel() {
    const light = document.documentElement.dataset.theme === "light";
    if (themeButton) themeButton.setAttribute("aria-label", light ? "Switch to the black theme" : "Switch to the white theme");
  }
  if (themeButton) {
    syncThemeLabel();
    themeButton.addEventListener("click", () => {
      const light = document.documentElement.dataset.theme !== "light";
      if (light) document.documentElement.dataset.theme = "light";
      else delete document.documentElement.dataset.theme;
      storage.set("flare-theme", light ? "light" : "black");
      syncThemeLabel();
    });
  }

  // ---------- copy buttons ----------

  for (const pre of document.querySelectorAll("pre.copyable")) {
    const button = el("button", { class: "copy", type: "button", text: "Copy" });
    button.addEventListener("click", async () => {
      const text = [...pre.querySelectorAll("code")]
        .map((c) => c.cloneNode(true))
        .map((c) => {
          c.querySelectorAll(".prompt, .comment").forEach((n) => n.remove());
          return c.textContent.replace(/[ \t]+$/gm, "");
        })
        .join("\n")
        .trim();
      try {
        await navigator.clipboard.writeText(text);
        button.textContent = "Copied";
      } catch {
        button.textContent = "Select and copy";
      }
      setTimeout(() => (button.textContent = "Copy"), 1600);
    });
    pre.append(button);
  }

  const header = document.querySelector(".top");
  if (header) header.after(side, top, card);
  else document.body.prepend(side, top, card);
  if (reduceMotion) card.style.transition = "none";
  apply(style);
})();
