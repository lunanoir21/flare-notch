// The page's language. English is the page itself; another language comes from
// i18n/<lang>.js, whose keys match the data-i18n attributes (a block's
// innerHTML) and data-i18n-attr ("attribute:key", ";" between pairs). The head
// script has already picked the language into <html data-lang>: ?lang= first,
// then the last choice, then the browser's. Scripts ask for their own strings
// with flareT(key, english, {vars}).
(() => {
  const root = document.documentElement;
  const lang = root.dataset.lang || "en";
  const dict = (window.flareI18n && window.flareI18n[lang]) || {};
  const fill = (text, vars) => text.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));

  window.flareT = (key, english, vars = {}) => fill(lang !== "en" && dict[key] != null ? dict[key] : english, vars);

  if (lang !== "en") {
    root.lang = lang;
    for (const node of document.querySelectorAll("[data-i18n]")) {
      const text = dict[node.dataset.i18n];
      if (text != null) node.innerHTML = text;
    }
    for (const node of document.querySelectorAll("[data-i18n-attr]")) {
      for (const pair of node.dataset.i18nAttr.split(";")) {
        const [attr, key] = pair.split(":");
        if (dict[key] != null) node.setAttribute(attr, dict[key]);
      }
    }
  }
  root.classList.remove("i18n-pending");

  // The switch sits beside the theme button and names the other language in
  // that language.
  const labels = { en: ["EN", "Switch to English"], tr: ["TR", "Türkçeye geç"] };
  const other = lang === "en" ? "tr" : "en";
  const theme = document.querySelector(".top .theme");
  if (!theme) return;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "lang";
  button.lang = other;
  button.textContent = labels[other][0];
  button.setAttribute("aria-label", labels[other][1]);
  button.addEventListener("click", () => {
    try {
      localStorage.setItem("flare-lang", other);
    } catch {}
    const url = new URL(location.href);
    url.searchParams.set("lang", other);
    history.replaceState(null, "", url);
    location.reload();
  });
  theme.before(button);
})();
