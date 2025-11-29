/**
 * DashboardResize Hook
 * 
 * Handles drag-to-resize for dashboard panels.
 * Updates CSS variables and persists to localStorage.
 */

const clamp = (val, min, max) => Math.max(min, Math.min(max, val));

export default {
  mounted() {
    this.axis = this.el.dataset.axis; // 'x' | 'y' | 'x-inverse' | 'y-inverse'
    this.varName = this.el.dataset.var; // '--left', '--right', '--bottom'
    this.min = parseInt(this.el.dataset.min || "160", 10);
    this.max = parseInt(this.el.dataset.max || "800", 10);
    this.target = document.querySelector(this.el.dataset.target);
    this.layoutKey = this.target?.dataset.layoutKey;

    if (!this.target) {
      console.error("DashboardResize: target not found", this.el.dataset.target);
      return;
    }

    this.el.addEventListener("pointerdown", this.onDown.bind(this));
    this.el.addEventListener("keydown", this.onKeyDown.bind(this));
    
    // Load saved layout on mount
    this.loadLayout();
  },

  onDown(e) {
    e.preventDefault();
    this.el.setPointerCapture(e.pointerId);
    this.el.classList.add("resizing");

    const startX = e.clientX;
    const startY = e.clientY;
    const startValue = parseInt(
      getComputedStyle(this.target).getPropertyValue(this.varName) || "0",
      10
    );

    const move = (ev) => {
      const dx = ev.clientX - startX;
      const dy = ev.clientY - startY;

      let newValue;
      switch (this.axis) {
        case "x":
          newValue = clamp(startValue + dx, this.min, this.max);
          break;
        case "x-inverse":
          newValue = clamp(startValue - dx, this.min, this.max);
          break;
        case "y":
          newValue = clamp(startValue + dy, this.min, this.max);
          break;
        case "y-inverse":
          newValue = clamp(startValue - dy, this.min, this.max);
          break;
      }

      this.target.style.setProperty(this.varName, `${Math.round(newValue)}px`);
    };

    const up = () => {
      this.el.releasePointerCapture(e.pointerId);
      this.el.classList.remove("resizing");
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);

      this.saveLayout();
    };

    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  },

  onKeyDown(e) {
    const step = e.shiftKey ? 20 : 5;
    const current = parseInt(
      getComputedStyle(this.target).getPropertyValue(this.varName) || "0",
      10
    );

    let newValue = current;

    if (this.axis.includes("x")) {
      if (e.key === "ArrowLeft") newValue = current - step;
      if (e.key === "ArrowRight") newValue = current + step;
    }

    if (this.axis.includes("y")) {
      if (e.key === "ArrowUp") newValue = current - step;
      if (e.key === "ArrowDown") newValue = current + step;
    }

    if (newValue !== current) {
      e.preventDefault();
      newValue = clamp(newValue, this.min, this.max);
      this.target.style.setProperty(this.varName, `${newValue}px`);
      this.saveLayout();
    }
  },

  loadLayout() {
    if (!this.layoutKey) return;

    const saved = localStorage.getItem(this.layoutKey);
    if (!saved) return;

    try {
      const layout = JSON.parse(saved);
      
      if (layout.left != null) {
        this.target.style.setProperty("--left", `${layout.left}px`);
      }
      if (layout.right != null) {
        this.target.style.setProperty("--right", `${layout.right}px`);
      }
      if (layout.bottom != null) {
        this.target.style.setProperty("--bottom", `${layout.bottom}px`);
      }
    } catch (e) {
      console.error("Failed to parse layout from localStorage", e);
    }
  },

  saveLayout() {
    if (!this.layoutKey) return;

    const layout = this.readLayout();
    localStorage.setItem(this.layoutKey, JSON.stringify(layout));
  },

  readLayout() {
    const styles = getComputedStyle(this.target);
    return {
      left: parseInt(styles.getPropertyValue("--left") || "280", 10),
      right: parseInt(styles.getPropertyValue("--right") || "0", 10),
      bottom: parseInt(styles.getPropertyValue("--bottom") || "0", 10),
    };
  },

  destroyed() {
    // Cleanup listeners
    this.el.removeEventListener("pointerdown", this.onDown);
    this.el.removeEventListener("keydown", this.onKeyDown);
  },
};
