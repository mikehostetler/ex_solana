export default {
  mounted() {
    this.container = document.querySelector('#dashboard');
    this.isDragging = false;
    this.startY = 0;
    this.startHeight = 0;

    this.el.addEventListener('pointerdown', this.handlePointerDown.bind(this));
  },

  handlePointerDown(e) {
    if (e.button !== 0) return;
    
    e.preventDefault();
    e.stopPropagation();
    
    this.isDragging = true;
    this.el.setPointerCapture(e.pointerId);
    
    this.startY = e.clientY;
    this.startHeight = 0;

    const handlePointerMove = (moveEvent) => {
      if (!this.isDragging) return;
      
      const deltaY = this.startY - moveEvent.clientY;
      
      if (deltaY > 10) {
        const newHeight = Math.max(150, Math.min(600, deltaY));
        this.container.style.setProperty('--bottom', `${newHeight}px`);
      }
    };

    const handlePointerUp = (upEvent) => {
      if (!this.isDragging) return;
      
      this.isDragging = false;
      this.el.releasePointerCapture(upEvent.pointerId);
      
      document.removeEventListener('pointermove', handlePointerMove);
      document.removeEventListener('pointerup', handlePointerUp);
      
      const finalHeight = parseInt(
        getComputedStyle(this.container).getPropertyValue('--bottom')
      );
      
      if (finalHeight > 10) {
        const alpineComponent = Alpine.$data(this.container);
        if (alpineComponent) {
          alpineComponent.bottomOpen = true;
          alpineComponent.lastBottomSize = finalHeight;
          alpineComponent.saveToLocalStorage();
        }
      }
    };

    document.addEventListener('pointermove', handlePointerMove);
    document.addEventListener('pointerup', handlePointerUp);
  },

  destroyed() {
    this.el.removeEventListener('pointerdown', this.handlePointerDown);
  },
};
