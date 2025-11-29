import { describe, it, expect, beforeEach, vi } from 'vitest'
import CommandPalette from '../../js/hooks/command_palette'

describe('CommandPalette', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
  })

  it('triggers toggle_command_palette on Cmd+K', () => {
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: 'k',
      metaKey: true,
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).toHaveBeenCalledWith('toggle_command_palette', {})
  })

  it('triggers toggle_command_palette on Ctrl+K', () => {
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: 'k',
      ctrlKey: true,
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).toHaveBeenCalledWith('toggle_command_palette', {})
  })

  it('triggers close_command_palette on Escape', () => {
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).toHaveBeenCalledWith('close_command_palette', {})
  })

  it('triggers toggle_shortcuts_help on ? when not in input', () => {
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: '?',
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).toHaveBeenCalledWith('toggle_shortcuts_help', {})
  })

  it('does not trigger ? shortcut when inside input', () => {
    document.body.innerHTML = '<input id="test-input" />'
    const input = document.getElementById('test-input')
    input.focus()
    
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: '?',
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).not.toHaveBeenCalledWith('toggle_shortcuts_help', {})
  })

  it('does not trigger ? shortcut when inside textarea', () => {
    document.body.innerHTML = '<textarea id="test-textarea"></textarea>'
    const textarea = document.getElementById('test-textarea')
    textarea.focus()
    
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    const event = new KeyboardEvent('keydown', {
      key: '?',
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    expect(hook.pushEvent).not.toHaveBeenCalledWith('toggle_shortcuts_help', {})
  })

  it('cleans up event listeners on destroyed', () => {
    const hook = { pushEvent: vi.fn() }
    CommandPalette.mounted.call(hook)
    
    // Destroy the hook
    CommandPalette.destroyed.call(hook)
    
    // Dispatch event after destroyed
    const event = new KeyboardEvent('keydown', {
      key: 'k',
      metaKey: true,
      bubbles: true,
      cancelable: true
    })
    
    window.dispatchEvent(event)
    
    // Should not have been called since listener was removed
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })
})
