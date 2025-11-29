const DropdownMenu = {
  mounted() {
    this.handleClickOutside = (e) => {
      if (!this.el.contains(e.target)) {
        this.closeDropdown()
      }
    }

    this.handleEscape = (e) => {
      if (e.key === 'Escape') {
        this.closeDropdown()
      }
    }

    this.el.addEventListener('toggle', (e) => {
      if (this.el.open) {
        document.addEventListener('click', this.handleClickOutside, true)
        document.addEventListener('keydown', this.handleEscape)
      } else {
        this.removeListeners()
      }
    })
  },

  closeDropdown() {
    this.el.open = false
    this.removeListeners()
  },

  removeListeners() {
    document.removeEventListener('click', this.handleClickOutside, true)
    document.removeEventListener('keydown', this.handleEscape)
  },

  destroyed() {
    this.removeListeners()
  }
}

export default DropdownMenu
