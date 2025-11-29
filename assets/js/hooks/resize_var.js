export default {
  mounted() {
    this.varName = this.el.dataset.var;
    this.axis = this.el.dataset.axis;
    this.min = parseInt(this.el.dataset.min) || 100;
    this.max = parseInt(this.el.dataset.max) || 1000;
    
    this.container = document.querySelector('#dashboard');
    this.startPos = 0;
    this.startSize = 0;
    this.isDragging = false;

    this.handlePointerDown = this.handlePointerDown.bind(this);
    this.handlePointerMove = this.handlePointerMove.bind(this);
    this.handlePointerUp = this.handlePointerUp.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);

    this.el.addEventListener('pointerdown', this.handlePointerDown);
    this.el.addEventListener('keydown', this.handleKeyDown);
  },

  handlePointerDown(e) {
    e.preventDefault();
    this.isDragging = true;
    this.el.setPointerCapture(e.pointerId);
    
    this.startPos = this.axis === 'x' ? e.clientX : e.clientY;
    this.startSize = parseInt(
      getComputedStyle(this.container).getPropertyValue(this.varName)
    );

    document.addEventListener('pointermove', this.handlePointerMove);
    document.addEventListener('pointerup', this.handlePointerUp);
    
    document.body.style.cursor = this.axis === 'x' ? 'ew-resize' : 'ns-resize';
    document.body.style.userSelect = 'none';
  },

  handlePointerMove(e) {
    if (!this.isDragging) return;
    
    e.preventDefault();
    const currentPos = this.axis === 'x' ? e.clientX : e.clientY;
    let delta = currentPos - this.startPos;
    
    if (this.varName === '--right') {
      delta = -delta;
    }
    
    if (this.axis === 'y') {
      delta = -delta;
    }
    
    let newSize = this.startSize + delta;
    newSize = Math.max(this.min, Math.min(this.max, newSize));
    
    this.container.style.setProperty(this.varName, `${newSize}px`);
  },

  handlePointerUp(e) {
    if (!this.isDragging) return;
    
    this.isDragging = false;
    this.el.releasePointerCapture(e.pointerId);
    
    document.removeEventListener('pointermove', this.handlePointerMove);
    document.removeEventListener('pointerup', this.handlePointerUp);
    
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    
    this.saveToLocalStorage();
  },

  handleKeyDown(e) {
    const step = e.shiftKey ? 20 : 5;
    let currentSize = parseInt(
      getComputedStyle(this.container).getPropertyValue(this.varName)
    );

    if (this.axis === 'x' && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
      e.preventDefault();
      let delta = e.key === 'ArrowRight' ? step : -step;
      
      if (this.varName === '--right') {
        delta = -delta;
      }
      
      let newSize = currentSize + delta;
      newSize = Math.max(this.min, Math.min(this.max, newSize));
      this.container.style.setProperty(this.varName, `${newSize}px`);
      this.saveToLocalStorage();
    } else if (this.axis === 'y' && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
      e.preventDefault();
      let delta = e.key === 'ArrowDown' ? step : -step;
      let newSize = currentSize + delta;
      newSize = Math.max(this.min, Math.min(this.max, newSize));
      this.container.style.setProperty(this.varName, `${newSize}px`);
      this.saveToLocalStorage();
    }
  },

  saveToLocalStorage() {
    const key = this.container?.dataset.layoutKey;
    if (!key) return;

    const layout = {
      left: parseInt(getComputedStyle(this.container).getPropertyValue('--left')),
      right: parseInt(getComputedStyle(this.container).getPropertyValue('--right')),
      bottom: parseInt(getComputedStyle(this.container).getPropertyValue('--bottom')),
    };

    localStorage.setItem(key, JSON.stringify(layout));
  },

  destroyed() {
    this.el.removeEventListener('pointerdown', this.handlePointerDown);
    this.el.removeEventListener('keydown', this.handleKeyDown);
    document.removeEventListener('pointermove', this.handlePointerMove);
    document.removeEventListener('pointerup', this.handlePointerUp);
    
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
  },
};
