export default {
  mounted() {
    this.passwordShown = false
    
    const buttonId = this.el.id
    let inputId
    
    if (buttonId === 'password-toggle-button') {
      inputId = 'user_password'
    } else if (buttonId === 'password-confirmation-toggle-button') {
      inputId = 'user_password_confirmation'
    } else {
      inputId = 'user_password'
    }
    
    this.handleClick = (e) => {
      e.preventDefault()
      e.stopPropagation()
      
      const input = document.querySelector(`#${inputId}`)
      const eyeIcon = this.el.querySelector('.hero-eye')
      const eyeSlashIcon = this.el.querySelector('.hero-eye-slash')
      
      if (input) {
        this.passwordShown = !this.passwordShown
        input.type = this.passwordShown ? 'text' : 'password'
        this.el.setAttribute('aria-label', this.passwordShown ? 'Hide password' : 'Show password')
        
        if (eyeIcon && eyeSlashIcon) {
          if (this.passwordShown) {
            eyeIcon.classList.add('hidden')
            eyeSlashIcon.classList.remove('hidden')
          } else {
            eyeIcon.classList.remove('hidden')
            eyeSlashIcon.classList.add('hidden')
          }
        }
      }
    }
    
    this.el.addEventListener('click', this.handleClick)
  },
  
  destroyed() {
    this.el.removeEventListener('click', this.handleClick)
  }
}
