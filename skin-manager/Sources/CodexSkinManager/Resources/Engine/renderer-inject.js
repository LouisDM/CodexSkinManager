(payload) => {
  const STATE_KEY = "__CODEX_SKIN_MANAGER__";
  const DISABLED_KEY = "__CODEX_SKIN_MANAGER_DISABLED__";
  const STYLE_ID = "codex-skin-manager-style";
  const CHROME_ID = "codex-skin-manager-chrome";
  const ROOT_PREFIX = "codex-skin-template-";
  const previous = window[STATE_KEY];

  const removeTemplateClasses = () => {
    if (!document.documentElement) return;
    for (const className of [...document.documentElement.classList]) {
      if (className.startsWith(ROOT_PREFIX)) document.documentElement.classList.remove(className);
    }
  };

  // Only an explicit one-shot apply may clear a prior restore marker. Watch-mode
  // repairs never receive this flag, so a restore cannot race with the watcher.
  if (payload.clearDisabledState === true) delete window[DISABLED_KEY];

  if (window[DISABLED_KEY]) {
    if (typeof previous?.cleanup === "function") previous.cleanup();
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    removeTemplateClasses();
    return { installed: false, disabled: true, version: payload.version };
  }

  if (
    previous?.version === payload.version
    && previous?.skinId === payload.skinId
    && typeof previous.ensure === "function"
  ) {
    previous.ensure();
    return { installed: true, reused: true, skinId: payload.skinId, version: payload.version };
  }

  if (typeof previous?.cleanup === "function") previous.cleanup();
  document.getElementById(STYLE_ID)?.remove();
  document.getElementById(CHROME_ID)?.remove();
  removeTemplateClasses();

  if (!/^codex-skin-template-[a-z0-9-]+$/.test(payload.rootClass)) {
    throw new Error("Invalid manager-owned skin root class");
  }
  let active = true;
  let observer;
  let debounceTimer;
  let safetyTimer;

  const ensure = () => {
    if (!active || !document.documentElement || !document.head || !document.body) return false;
    removeTemplateClasses();
    document.documentElement.classList.add(payload.rootClass);

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      document.head.append(style);
    }
    if (style.textContent !== payload.css) style.textContent = payload.css;
    style.dataset.skinManagerVersion = payload.version;
    style.dataset.skinId = payload.skinId;

    let chrome = document.getElementById(CHROME_ID);
    if (!chrome) {
      chrome = document.createElement("div");
      chrome.id = CHROME_ID;
      chrome.setAttribute("aria-hidden", "true");
      Object.assign(chrome.style, {
        position: "fixed",
        inset: "0",
        zIndex: "2147483646",
        pointerEvents: "none",
      });
      document.body.append(chrome);
    }
    return true;
  };

  const cleanup = () => {
    if (!active) return true;
    active = false;
    observer?.disconnect();
    clearTimeout(debounceTimer);
    clearInterval(safetyTimer);
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    removeTemplateClasses();
    if (window[STATE_KEY]?.version === payload.version) delete window[STATE_KEY];
    return true;
  };

  const verify = () => {
    const style = document.getElementById(STYLE_ID);
    const chrome = document.getElementById(CHROME_ID);
    return Boolean(
      active
      && style?.dataset.skinManagerVersion === payload.version
      && style?.dataset.skinId === payload.skinId
      && style.sheet?.cssRules.length > 0
      && chrome?.getAttribute("aria-hidden") === "true"
      && getComputedStyle(chrome).pointerEvents === "none"
      && document.documentElement?.classList.contains(payload.rootClass)
      && getComputedStyle(document.documentElement)
        .getPropertyValue("--codex-skin-template-active").trim() === payload.template
    );
  };

  const state = {
    skinId: payload.skinId,
    version: payload.version,
    rootClass: payload.rootClass,
    ensure,
    cleanup,
    verify,
  };
  window[STATE_KEY] = state;
  ensure();

  if (document.documentElement) {
    observer = new MutationObserver(() => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(ensure, 180);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
  safetyTimer = setInterval(ensure, 5_000);
  return { installed: true, reused: false, skinId: payload.skinId, version: payload.version };
}
