/**
 * Modal Hook
 * Handles showing/hiding modals based on LiveView assigns
 */
const Modal = {
  mounted() {
    this.show = this.el.dataset.show === "true"
    if (this.show) {
      this.showModal()
    }
  },

  updated() {
    const show = this.el.dataset.show === "true"
    
    if (show && !this.show) {
      this.showModal()
    } else if (!show && this.show) {
      this.hideModal()
    }
    
    this.show = show
  },

  showModal() {
    const id = this.el.id
    
    // Show the modal container
    this.el.classList.remove("hidden")
    
    // Show and fade in the background
    const bg = document.getElementById(`${id}-bg`)
    if (bg) {
      bg.style.transition = "opacity 300ms ease-out"
      bg.style.opacity = "0"
      setTimeout(() => bg.style.opacity = "1", 10)
    }
    
    // Show and animate the modal content
    const container = document.getElementById(`${id}-container`)
    if (container) {
      container.style.transition = "all 300ms ease-out"
      container.style.opacity = "0"
      container.style.transform = "translateY(1rem) scale(0.95)"
      setTimeout(() => {
        container.style.opacity = "1"
        container.style.transform = "translateY(0) scale(1)"
      }, 10)
      
      // Focus first focusable element
      setTimeout(() => {
        const focusable = container.querySelector('input, button, [tabindex]:not([tabindex="-1"])')
        if (focusable) focusable.focus()
      }, 300)
    }
    
    // Prevent body scroll
    document.body.classList.add("overflow-hidden")
  },

  hideModal() {
    const id = this.el.id
    
    // Fade out background
    const bg = document.getElementById(`${id}-bg`)
    if (bg) {
      bg.style.opacity = "0"
    }
    
    // Fade out and scale down container
    const container = document.getElementById(`${id}-container`)
    if (container) {
      container.style.opacity = "0"
      container.style.transform = "translateY(1rem) scale(0.95)"
    }
    
    // Hide the modal after transition
    setTimeout(() => {
      this.el.classList.add("hidden")
    }, 200)
    
    // Restore body scroll
    document.body.classList.remove("overflow-hidden")
  }
}

export default Modal
