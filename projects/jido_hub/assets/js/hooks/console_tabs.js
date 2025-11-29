export default {
  mounted() {
    this.tabs = this.el.querySelectorAll('.tab[data-tab]');
    this.contentSections = this.el.querySelectorAll('.console-content-section');
    this.clearBtn = this.el.querySelector('[data-action="clear"]');
    
    this.tabs.forEach(tab => {
      tab.addEventListener('click', this.handleTabClick.bind(this));
    });

    if (this.clearBtn) {
      this.clearBtn.addEventListener('click', this.handleClear.bind(this));
    }

    this.setupInputHandlers();
  },

  handleTabClick(e) {
    const clickedTab = e.currentTarget;
    const targetTab = clickedTab.dataset.tab;
    
    this.tabs.forEach(tab => {
      tab.classList.remove('tab-active');
    });
    
    clickedTab.classList.add('tab-active');
    
    this.contentSections.forEach(section => {
      if (section.dataset.section === targetTab) {
        section.style.display = 'flex';
      } else {
        section.style.display = 'none';
      }
    });
  },

  handleClear() {
    const activeTab = this.el.querySelector('.tab.tab-active');
    if (!activeTab) return;

    const targetTab = activeTab.dataset.tab;
    const output = this.el.querySelector(`[data-output="${targetTab}"]`);
    
    if (output) {
      const entries = output.querySelectorAll('.console-log-entry');
      entries.forEach(entry => entry.remove());
    }
  },

  setupInputHandlers() {
    const consoleInput = this.el.querySelector('[data-input="console"]');
    
    if (consoleInput) {
      consoleInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          this.handleConsoleInput(consoleInput);
        }
      });
    }
  },

  handleConsoleInput(input) {
    const value = input.value.trim();
    if (!value) return;

    const output = this.el.querySelector('[data-output="console"]');
    if (!output) return;

    const entry = document.createElement('div');
    entry.className = 'console-log-entry console-info';
    entry.innerHTML = `
      <span class="console-icon">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
          <path fill-rule="evenodd" d="M4.5 13a3.5 3.5 0 0 1-1.41-6.705A3.5 3.5 0 0 1 9.72 4.124a2.5 2.5 0 0 1 3.197 3.018A3.001 3.001 0 0 1 12 13H4.5Zm.72-5.03a.75.75 0 0 0 1.06 1.06l.97-.97v2.69a.75.75 0 0 0 1.5 0V8.06l.97.97a.75.75 0 1 0 1.06-1.06L8.53 5.72a.75.75 0 0 0-1.06 0L5.22 7.97Z" clip-rule="evenodd" />
        </svg>
      </span>
      <span class="console-message">> ${this.escapeHtml(value)}</span>
    `;
    
    output.appendChild(entry);
    output.scrollTop = output.scrollHeight;

    try {
      const result = (0, eval)(value);
      const resultEntry = document.createElement('div');
      resultEntry.className = 'console-log-entry console-success';
      resultEntry.innerHTML = `
        <span class="console-icon">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
            <path fill-rule="evenodd" d="M12.416 3.376a.75.75 0 0 1 .208 1.04l-5 7.5a.75.75 0 0 1-1.154.114l-3-3a.75.75 0 0 1 1.06-1.06l2.353 2.353 4.493-6.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
          </svg>
        </span>
        <span class="console-message">${this.formatResult(result)}</span>
      `;
      output.appendChild(resultEntry);
    } catch (error) {
      const errorEntry = document.createElement('div');
      errorEntry.className = 'console-log-entry console-error';
      errorEntry.innerHTML = `
        <span class="console-icon">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
            <path fill-rule="evenodd" d="M6.701 2.25c.577-1 2.02-1 2.598 0l5.196 9a1.5 1.5 0 0 1-1.299 2.25H2.804a1.5 1.5 0 0 1-1.3-2.25l5.197-9ZM8 4a.75.75 0 0 1 .75.75v3a.75.75 0 1 1-1.5 0v-3A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" />
          </svg>
        </span>
        <span class="console-message">${this.escapeHtml(error.message)}</span>
      `;
      output.appendChild(errorEntry);
    }

    output.scrollTop = output.scrollHeight;
    input.value = '';
  },

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  formatResult(value) {
    if (value === undefined) return 'undefined';
    if (value === null) return 'null';
    if (typeof value === 'string') return `"${this.escapeHtml(value)}"`;
    if (typeof value === 'object') {
      try {
        return this.escapeHtml(JSON.stringify(value, null, 2));
      } catch {
        return this.escapeHtml(String(value));
      }
    }
    return this.escapeHtml(String(value));
  },

  destroyed() {
    this.tabs.forEach(tab => {
      tab.removeEventListener('click', this.handleTabClick);
    });
    
    if (this.clearBtn) {
      this.clearBtn.removeEventListener('click', this.handleClear);
    }
  },
};
