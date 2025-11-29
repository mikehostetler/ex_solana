export default () => ({
  leftOpen: true,
  rightOpen: null,
  bottomOpen: null,
  lastLeftSize: 280,
  lastRightSize: 360,
  lastBottomSize: 240,
  container: null,
  isMobile: false,

  init() {
    this.container = this.$el;
    if (!this.container) return;
    
    const defaultRightOpen = this.container.dataset.defaultRightOpen === 'true';
    const defaultBottomOpen = this.container.dataset.defaultBottomOpen === 'true';
    
    this.rightOpen = defaultRightOpen;
    this.bottomOpen = defaultBottomOpen;
    
    this.checkMobile();
    
    const hasLocalStorage = this.loadFromLocalStorage();
    
    if (!hasLocalStorage) {
      if (!this.bottomOpen) {
        this.container.style.setProperty('--bottom', '0px');
      } else {
        this.container.style.setProperty('--bottom', `${this.lastBottomSize}px`);
      }
      
      if (!this.rightOpen) {
        this.container.style.setProperty('--right', '0px');
      } else {
        this.container.style.setProperty('--right', `${this.lastRightSize}px`);
      }
      
      if (!this.leftOpen) {
        this.container.style.setProperty('--left', '0px');
      }
    }

    window.addEventListener('resize', () => this.checkMobile());

    // Keyboard shortcuts
    document.addEventListener("keydown", (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "b") {
        e.preventDefault();
        this.toggleLeft();
      }
      if ((e.metaKey || e.ctrlKey) && e.key === "j") {
        e.preventDefault();
        this.toggleBottom();
      }
      if ((e.metaKey || e.ctrlKey) && e.key === "\\") {
        e.preventDefault();
        this.toggleRight();
      }
    });
  },

  checkMobile() {
    const wasMobile = this.isMobile;
    this.isMobile = window.innerWidth <= 1020;
    
    if (this.isMobile && !wasMobile) {
      this.leftOpen = false;
      const leftPanel = this.container?.querySelector('.dashboard-left');
      if (leftPanel) leftPanel.setAttribute('data-open', 'false');
    } else if (!this.isMobile && wasMobile) {
      this.leftOpen = true;
      const leftPanel = this.container?.querySelector('.dashboard-left');
      if (leftPanel) leftPanel.removeAttribute('data-open');
    }
  },

  loadFromLocalStorage() {
    const key = this.container?.dataset.layoutKey;
    if (!key) return false;

    const saved = localStorage.getItem(key);
    if (!saved) return false;

    try {
      const layout = JSON.parse(saved);
      this.applyLayout(layout);
      return true;
    } catch (e) {
      console.error("Failed to parse layout from localStorage", e);
      return false;
    }
  },

  applyLayout(layout) {
    if (layout.left != null) {
      this.container.style.setProperty("--left", `${layout.left}px`);
      this.leftOpen = layout.left > 0;
      if (layout.left > 0) this.lastLeftSize = layout.left;
    }

    if (layout.right != null) {
      this.container.style.setProperty("--right", `${layout.right}px`);
      this.rightOpen = layout.right > 0;
      if (layout.right > 0) this.lastRightSize = layout.right;
    }

    if (layout.bottom != null) {
      this.container.style.setProperty("--bottom", `${layout.bottom}px`);
      this.bottomOpen = layout.bottom > 0;
      if (layout.bottom > 0) this.lastBottomSize = layout.bottom;
    }
  },

  saveToLocalStorage() {
    const key = this.container?.dataset.layoutKey;
    if (!key) return;

    const layout = {
      left: parseInt(
        getComputedStyle(this.container).getPropertyValue("--left")
      ),
      right: parseInt(
        getComputedStyle(this.container).getPropertyValue("--right")
      ),
      bottom: parseInt(
        getComputedStyle(this.container).getPropertyValue("--bottom")
      ),
    };

    localStorage.setItem(key, JSON.stringify(layout));
  },

  toggleLeft() {
    if (this.isMobile) {
      const leftPanel = this.container?.querySelector('.dashboard-left');
      if (leftPanel) {
        const isOpen = leftPanel.getAttribute('data-open') === 'true';
        leftPanel.setAttribute('data-open', !isOpen ? 'true' : 'false');
        this.leftOpen = !isOpen;
      }
    } else {
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
      this.saveToLocalStorage();
    }
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
    this.saveToLocalStorage();
  },

  toggleBottom() {
    if (this.bottomOpen) {
      this.lastBottomSize = parseInt(
        getComputedStyle(this.container).getPropertyValue("--bottom")
      );
      
      const bottomPanel = this.container?.querySelector('.dashboard-bottom');
      if (bottomPanel) {
        bottomPanel.setAttribute('data-closed', 'true');
      }
      
      setTimeout(() => {
        this.container.style.setProperty("--bottom", "0px");
        this.bottomOpen = false;
        this.saveToLocalStorage();
      }, 300);
    } else {
      this.container.style.setProperty("--bottom", `${this.lastBottomSize}px`);
      this.bottomOpen = true;
      
      setTimeout(() => {
        const bottomPanel = this.container?.querySelector('.dashboard-bottom');
        if (bottomPanel) {
          bottomPanel.removeAttribute('data-closed');
        }
      }, 50);
      
      this.saveToLocalStorage();
    }
  },
});
