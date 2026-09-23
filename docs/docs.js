// The documentation's contents: the section on screen is marked, the filter
// narrows the list, and every heading gets a link to itself.
(() => {
  const links = [...document.querySelectorAll(".toc a")];
  const sections = links.map((link) => document.querySelector(link.getAttribute("href"))).filter(Boolean);

  for (const heading of document.querySelectorAll(".doc h2, .doc h3[id]")) {
    const id = heading.id || heading.closest("section")?.id;
    if (!id) continue;
    const anchor = document.createElement("a");
    anchor.className = "anchor";
    anchor.href = `#${id}`;
    anchor.textContent = "#";
    anchor.setAttribute("aria-label", `Link to ${heading.textContent}`);
    heading.append(anchor);
  }

  const mark = (id) => {
    for (const link of links) {
      if (link.getAttribute("href") === `#${id}`) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
  };

  if ("IntersectionObserver" in window) {
    const visible = new Set();
    const spy = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) visible.add(entry.target);
          else visible.delete(entry.target);
        }
        const first = sections.find((section) => visible.has(section));
        if (first) mark(first.id);
      },
      { rootMargin: "-10% 0px -70% 0px" },
    );
    sections.forEach((section) => spy.observe(section));
  }

  const filter = document.getElementById("toc-filter");
  if (filter) {
    filter.addEventListener("input", () => {
      const query = filter.value.trim().toLowerCase();
      links.forEach((link, i) => {
        const text = `${link.textContent} ${sections[i]?.textContent ?? ""}`.toLowerCase();
        link.parentElement.hidden = query !== "" && !text.includes(query);
      });
    });
  }
})();
