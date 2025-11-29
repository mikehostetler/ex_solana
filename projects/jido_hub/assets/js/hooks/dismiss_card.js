export default {
  mounted() {
    this.handleDismiss = (e) => {
      if (e.target.closest('[data-dismiss]')) {
        e.preventDefault();
        this.el.style.transition = 'opacity 200ms ease-out, transform 200ms ease-out';
        this.el.style.opacity = '0';
        this.el.style.transform = 'scale(0.95)';
        
        setTimeout(() => {
          this.el.style.maxHeight = this.el.offsetHeight + 'px';
          this.el.style.overflow = 'hidden';
          
          requestAnimationFrame(() => {
            this.el.style.transition = 'max-height 200ms ease-out, margin 200ms ease-out, padding 200ms ease-out';
            this.el.style.maxHeight = '0';
            this.el.style.marginTop = '0';
            this.el.style.marginBottom = '0';
            this.el.style.paddingTop = '0';
            this.el.style.paddingBottom = '0';
          });
          
          setTimeout(() => {
            this.el.remove();
          }, 200);
        }, 200);
      }
    };
    
    this.el.addEventListener('click', this.handleDismiss);
  },
  
  destroyed() {
    this.el.removeEventListener('click', this.handleDismiss);
  }
};
