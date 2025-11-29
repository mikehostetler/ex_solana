/**
 * Alpine Dashboard Component
 * 
 * Manages panel toggle state (open/closed) and keyboard shortcuts.
 * Works in conjunction with DashboardResize hook.
 */

export default () => ({
  leftOpen: true,
  rightOpen: false,
  bottomOpen: false,
  lastLeftSize: 280,
  lastRightSize: 360,
  lastBottomSize: 240,
  container: null,

  init(el) {
    this.container = el;
    this.loadFromLocalStorage();
    this.setupKeyboardShortcuts();

    // Listen for external toggle events (e.g., from command palette)
    window.addEventListener("dashboard:toggle-left", () => this.toggleLeft());
    window.addEventListener("dashboard:toggle-right", () => this.toggleRight());
    window.addEventListener("dashboard:toggle-bottom", () => this.toggleBottom());
  },

  loadFromLocalStorage() {
    const key = this.container?.dataset.layoutKey;
    if (!key) return;

    const saved = localStorage.getItem(key);
    if (!saved) return;

    try {
      const layout = JSON.parse(saved);
      this.applyLayout(layout);
    } catch (e) {
      console.error("Failed to parse layout from localStorage", e);
    }
  },

  applyLayout(layout) {
    if (layout.left != null) {
      this.container.style.setProperty("--left", `${layout.left}px`);
      this.leftOpen = layout.left > 0;
      this.lastLeftSize = layout.left > 0 ? layout.left : 280;
    }

    if (layout.right != null) {
      this.container.style.setProperty("--right", `${layout.right}px`);
      this.rightOpen = layout.right > 0;
      this.lastRightSize = layout.right > 0 ? layout.right : 360;
    }

    if (layout.bottom != null) {
      this.container.style.setProperty("--bottom", `${layout.bottom}px`);
      this.bottomOpen = layout.bottom > 0;
      this.lastBottomSize = layout.bottom > 0 ? layout.bottom : 240;
    }
  },

  toggleLeft() {
    if (this.leftOpen) {
      this.lastLeftSize = parseInt(
        getComputedStyle(this.container).getPropertyValue("--left")
      );
      this.container.style.setProperty("--left", "0px");
      this.leftOpen = false;
    } else {
      this.container.style.setProperty("--left", `${this.lastLeftSize}px`);
      this.leftOpen = true;
    }
    this.saveLayout();
  },

  toggleRight() {
    if (this.rightOpen) {
      this.lastRightSize = parseInt(
        getComputedStyle(this.container).getPropertyValue("--right")
      );
      this.container.style.setProperty("--right", "0px");
      this.rightOpen = false;
    } else {
      this.container.style.setProperty("--right", `${this.lastRightSize}px`);
      this.rightOpen = true;
    }
    this.saveLayout();
  },

  toggleBottom() {
    if (this.bottomOpen) {
      this.lastBottomSize = parseInt(
        getComputedStyle(this.container).getPropertyValue("--bottom")
      );
      this.container.style.setProperty("--bottom", "0px");
      this.bottomOpen = false;
    } else {
      this.container.style.setProperty("--bottom", `${this.lastBottomSize}px`);
      this.bottomOpen = true;
    }
    this.saveLayout();
  },

  setupKeyboardShortcuts() {
    document.addEventListener("keydown", (e) => {
      const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0;
      const modifier = isMac ? e.metaKey : e.ctrlKey;

      if (!modifier) return;

      // Cmd/Ctrl + B: Toggle left sidebar
      if (e.key === "b" || e.key === "B") {
        e.preventDefault();
        this.toggleLeft();
      }

      // Cmd/Ctrl + J: Toggle bottom panel
      if (e.key === "j" || e.key === "J") {
        e.preventDefault();
        this.toggleBottom();
      }

      // Cmd/Ctrl + \: Toggle right panel
      if (e.key === "\\") {
        e.preventDefault();
        this.toggleRight();
      }
    });
  },

  saveLayout() {
    const key = this.container?.dataset.layoutKey;
    if (!key) return;

    const layout = {
      left: parseInt(getComputedStyle(this.container).getPropertyValue("--left")),
      right: parseInt(getComputedStyle(this.container).getPropertyValue("--right")),
      bottom: parseInt(getComputedStyle(this.container).getPropertyValue("--bottom")),
    };

    localStorage.setItem(key, JSON.stringify(layout));
  },
});
