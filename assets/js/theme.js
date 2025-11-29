// Theme management with system preference support and extensive debugging
// Hardened for Phoenix LiveView DOM patching
(() => {
  const KEY = "jido_hub:theme";
  const THEMES = ["system", "light", "dark", "cupcake", "wireframe", "business", "nord", "dracula", "night"];
  const DEBUG = true;
  const log = (...args) => DEBUG && console.debug("[theme]", ...args);

  const getSystemTheme = () => {
    const isDark = matchMedia("(prefers-color-scheme: dark)").matches;
    log("getSystemTheme:", isDark ? "dark" : "light");
    return isDark ? "dark" : "light";
  };

  const applyTheme = (theme) => {
    const resolved = theme === "system" ? getSystemTheme() : theme;
    const html = document.documentElement;
    const current = html.getAttribute("data-theme");
    
    log("applyTheme:", { requested: theme, resolved, current });
    
    if (current !== resolved) {
      html.setAttribute("data-theme", resolved);
      log("✓ Applied theme:", theme, "=>", resolved);
    } else {
      log("  (theme already set)");
    }
  };

  const setTheme = (theme) => {
    const next = THEMES.includes(theme) ? theme : "system";
    log("setTheme called:", { requested: theme, normalized: next });
    
    try {
      const prev = localStorage.getItem(KEY);
      if (prev !== next) {
        localStorage.setItem(KEY, next);
        log("✓ Saved to localStorage:", next);
      } else {
        log("  (already in localStorage)");
      }
    } catch (err) {
      console.warn("[theme] localStorage error:", err);
    }
    
    applyTheme(next);
  };

  // Initialize ASAP using saved preference or system default
  log("=== INITIALIZING ===");
  try {
    const saved = localStorage.getItem(KEY);
    log("Saved theme from localStorage:", saved);
    setTheme(saved || "system");
  } catch (err) {
    console.warn("[theme] localStorage read error:", err);
    applyTheme("system");
  }

  // Listen for system preference changes
  const mq = matchMedia("(prefers-color-scheme: dark)");
  const handleSystemChange = (e) => {
    log("System preference changed:", e.matches ? "dark" : "light");
    try {
      const saved = localStorage.getItem(KEY) || "system";
      if (saved === "system") {
        log("Re-applying system theme");
        applyTheme("system");
      } else {
        log("Ignoring system change (user has explicit theme:", saved + ")");
      }
    } catch (err) {
      console.warn("[theme] Error handling system change:", err);
    }
  };

  if (mq.addEventListener) {
    mq.addEventListener("change", handleSystemChange);
    log("Listening for system preference changes (modern)");
  } else if (mq.addListener) {
    mq.addListener(handleSystemChange); // Safari fallback
    log("Listening for system preference changes (legacy)");
  }

  // Cross-tab synchronization (only apply, don't re-write to avoid loops)
  window.addEventListener("storage", (e) => {
    if (e.key === KEY) {
      log("Storage event from another tab:", e.newValue);
      applyTheme(e.newValue || "system");
    }
  });

  // Re-apply after LiveView navigation/patches to survive DOM updates
  window.addEventListener("phx:page-loading-stop", () => {
    log("LiveView navigation complete, re-applying theme");
    try {
      const saved = localStorage.getItem(KEY) || "system";
      applyTheme(saved);
    } catch (err) {
      console.warn("[theme] Error re-applying after navigation:", err);
    }
  });

  // Optional: allow server to trigger theme changes via push_event
  window.addEventListener("phx:set-theme", (e) => {
    log("Server-triggered theme change:", e?.detail?.theme);
    setTheme(e?.detail?.theme);
  });

  // Click delegation for theme buttons with data-set-theme attribute
  // This survives LiveView DOM patching without needing re-binding
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-set-theme]");
    if (!btn) return;
    
    const theme = btn.getAttribute("data-set-theme");
    log("Button clicked:", theme);
    setTheme(theme);
    
    // Auto-close dropdown if button is inside one
    const dropdown = btn.closest("details");
    if (dropdown) {
      dropdown.removeAttribute("open");
      log("Closed dropdown");
    }
  });

  // Public API for debugging and manual control
  window.__theme = {
    setTheme,
    getSystemTheme,
    get current() {
      return document.documentElement.getAttribute("data-theme");
    },
    get saved() {
      try {
        return localStorage.getItem(KEY);
      } catch (_) {
        return null;
      }
    },
    debug() {
      console.group("🎨 Theme Debug Info");
      console.log("Current theme (DOM):", this.current);
      console.log("Saved theme (localStorage):", this.saved);
      console.log("System preference:", getSystemTheme());
      console.log("Available themes:", THEMES);
      
      const html = document.documentElement;
      console.log("\n<html> attributes:");
      for (let attr of html.attributes) {
        console.log(`  ${attr.name}="${attr.value}"`);
      }
      
      const styles = getComputedStyle(html);
      console.log("\nCSS Variables (checking multiple formats):");
      
      // Test both formats
      const vars = [
        "--color-base-100",
        "--color-base-200", 
        "--color-base-300",
        "--color-base-content",
        "--color-primary",
        "color-scheme"
      ];
      
      for (const varName of vars) {
        const value = styles.getPropertyValue(varName).trim();
        if (value) {
          console.log(`  ${varName}:`, value);
        } else {
          console.log(`  ${varName}:`, "❌ NOT FOUND");
        }
      }
      
      console.log("\nComputed colors:");
      console.log("  background-color:", styles.backgroundColor);
      console.log("  color:", styles.color);
      
      console.log("\nLocalStorage contents:");
      try {
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i);
          if (key?.startsWith("phx")) {
            console.log(`  ${key}:`, localStorage.getItem(key));
          }
        }
      } catch (err) {
        console.log("  Error reading localStorage:", err);
      }
      
      console.groupEnd();
    },
    // Test all themes in sequence
    async testAll(delayMs = 1000) {
      console.log("🧪 Testing all themes...");
      for (const theme of THEMES) {
        console.log(`Setting: ${theme}`);
        this.setTheme(theme);
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
      console.log("✓ Test complete");
    }
  };

  log("=== INITIALIZED ===");
  log("Use window.__theme.debug() for diagnostics");
  log("Use window.__theme.testAll() to cycle through themes");
})();
