import { describe, it, expect, beforeEach, vi } from 'vitest'
import { fireEvent } from '@testing-library/dom'
import ThemeSwitcher from '../../js/hooks/theme_switcher'

describe('ThemeSwitcher', () => {
  beforeEach(() => {
    localStorage.clear()
    document.body.innerHTML = ''
    document.documentElement.removeAttribute('data-theme')
  })

  it('applies saved theme on mount', () => {
    localStorage.setItem('jido-theme', 'emerald')
    
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu">
          <button data-theme="linear"></button>
          <button data-theme="emerald"></button>
          <button data-theme="amber"></button>
        </div>
      </div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    expect(document.documentElement.getAttribute('data-theme')).toBe('emerald')
  })

  it('applies default theme when no saved theme exists', () => {
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu">
          <button data-theme="linear"></button>
        </div>
      </div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    expect(document.documentElement.getAttribute('data-theme')).toBe('linear')
  })

  it('changes theme and persists to localStorage on button click', () => {
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu" class="">
          <button data-theme="linear">Linear</button>
          <button data-theme="emerald">Emerald</button>
          <button data-theme="amber">Amber</button>
        </div>
      </div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    const emeraldButton = document.querySelector('[data-theme="emerald"]')
    fireEvent.click(emeraldButton)
    
    expect(document.documentElement.getAttribute('data-theme')).toBe('emerald')
    expect(localStorage.getItem('jido-theme')).toBe('emerald')
  })

  it('hides menu after theme selection', () => {
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu" class="">
          <button data-theme="amber">Amber</button>
        </div>
      </div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    const menu = document.getElementById('theme-menu')
    const button = document.querySelector('[data-theme="amber"]')
    
    fireEvent.click(button)
    
    expect(menu.classList.contains('hidden')).toBe(true)
  })

  it('closes menu when clicking outside', () => {
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu" class="">Menu</div>
      </div>
      <div id="outside">Outside</div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    const menu = document.getElementById('theme-menu')
    const outside = document.getElementById('outside')
    
    fireEvent.click(outside)
    
    expect(menu.classList.contains('hidden')).toBe(true)
  })

  it('cleans up event listeners on destroyed', () => {
    document.body.innerHTML = `
      <div id="theme-switcher">
        <div id="theme-menu">
          <button data-theme="linear">Linear</button>
        </div>
      </div>`
    
    const hook = {
      el: document.getElementById('theme-switcher'),
      ...ThemeSwitcher
    }
    hook.mounted()
    
    const button = document.querySelector('[data-theme="linear"]')
    
    // Destroy the hook
    hook.destroyed()
    
    // Click should not change theme after destroyed
    const currentTheme = document.documentElement.getAttribute('data-theme')
    fireEvent.click(button)
    
    // Theme should remain the same (no handler to update it)
    expect(document.documentElement.getAttribute('data-theme')).toBe(currentTheme)
  })
})
