// Reads CHANGELOG.md from the repository, so the site never needs its own copy:
// a "what's new" card for a release this visitor hasn't seen, and the full
// history on changelog.html.
(() => {
  const SOURCE = "https://raw.githubusercontent.com/lunanoir21/quickshell-flare/main/CHANGELOG.md";
  const FALLBACK = "https://github.com/lunanoir21/quickshell-flare/blob/main/CHANGELOG.md";
  const SEEN = "flare-seen-release";

  const escape = (text) => text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  function inline(text) {
    return escape(text)
      .replace(/`([^`]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
  }

  // Just enough Markdown for a changelog: "## version" headings, paragraphs
  // and "- " lists whose items may wrap onto indented lines.
  function parse(markdown) {
    const releases = [];
    let current = null;
    for (const line of markdown.split("\n")) {
      const heading = line.match(/^##\s+(.+?)\s*$/);
      if (heading) {
        current = { version: heading[1], lines: [] };
        releases.push(current);
      } else if (current) {
        current.lines.push(line);
      }
    }
    return releases.map((release) => ({ version: release.version, html: blocks(release.lines) }));
  }

  function blocks(lines) {
    const out = [];
    let list = null;
    let para = null;
    const flush = () => {
      if (para) out.push(`<p>${inline(para.join(" "))}</p>`);
      para = null;
    };
    const endList = () => {
      if (list) out.push(`<ul>${list.map((item) => `<li>${inline(item)}</li>`).join("")}</ul>`);
      list = null;
    };
    for (const raw of lines) {
      const line = raw.trimEnd();
      if (/^\s*$/.test(line)) {
        flush();
        endList();
      } else if (/^- /.test(line)) {
        flush();
        list = list || [];
        list.push(line.slice(2));
      } else if (list && /^\s{2,}\S/.test(line)) {
        list[list.length - 1] += " " + line.trim();
      } else {
        endList();
        para = para || [];
        para.push(line.trim());
      }
    }
    flush();
    endList();
    return out.join("");
  }

  const storage = {
    get() {
      try {
        return localStorage.getItem(SEEN);
      } catch {
        return null;
      }
    },
    set(value) {
      try {
        localStorage.setItem(SEEN, value);
      } catch {}
    },
  };

  function popup(release) {
    const dialog = document.createElement("dialog");
    dialog.className = "news";
    dialog.setAttribute("aria-labelledby", "news-title");
    dialog.innerHTML = `
      <p class="news-kicker">What's new</p>
      <h2 class="news-title" id="news-title">flare ${escape(release.version)}</h2>
      <div class="news-body">${release.html}</div>
      <div class="news-actions">
        <a href="changelog.html">Full changelog</a>
        <button type="button" class="news-close">Got it</button>
      </div>`;
    const dismiss = () => {
      storage.set(release.version);
      dialog.classList.remove("in");
      setTimeout(() => dialog.remove(), 220);
    };
    dialog.querySelector(".news-close").addEventListener("click", dismiss);
    dialog.querySelector(".news-actions a").addEventListener("click", () => storage.set(release.version));
    dialog.addEventListener("cancel", (e) => {
      e.preventDefault();
      dismiss();
    });
    dialog.addEventListener("keydown", (e) => e.key === "Escape" && dismiss());
    document.body.append(dialog);
    // The open attribute, not show(): a card that appears on its own must not
    // take focus away from the page.
    dialog.setAttribute("open", "");
    requestAnimationFrame(() => requestAnimationFrame(() => dialog.classList.add("in")));
  }

  function renderLog(target, releases) {
    target.innerHTML = releases
      .map(
        (release, i) => `
        <article class="release" id="v${escape(release.version)}">
          <header>
            <h2>${escape(release.version)}</h2>
            ${i === 0 ? '<span class="latest">Latest</span>' : ""}
            <a class="release-link" href="https://github.com/lunanoir21/quickshell-flare/releases/tag/v${encodeURIComponent(release.version)}">Release</a>
          </header>
          <div class="release-body">${release.html}</div>
        </article>`
      )
      .join("");
  }

  const log = document.getElementById("log");

  fetch(SOURCE, { cache: "no-cache" })
    .then((response) => {
      if (!response.ok) throw new Error(String(response.status));
      return response.text();
    })
    .then((markdown) => {
      const releases = parse(markdown);
      if (releases.length === 0) throw new Error("empty");
      for (const node of document.querySelectorAll("[data-version]")) node.textContent = `v${releases[0].version}`;
      if (log) {
        renderLog(log, releases);
        storage.set(releases[0].version);
      } else if (storage.get() !== releases[0].version) {
        popup(releases[0]);
      }
    })
    .catch(() => {
      if (log) log.innerHTML = `<p>The changelog could not be loaded here. <a href="${FALLBACK}">Read CHANGELOG.md on GitHub</a>.</p>`;
    });
})();
