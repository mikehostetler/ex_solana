const CommandPalette = {
  mounted() {
    console.log("[CommandPalette] Hook mounted on element:", this.el.id)
    this.onKeyDown = (e) => {
      console.log("[CommandPalette] Key pressed:", e.key, "Meta:", e.metaKey, "Ctrl:", e.ctrlKey)
      
      const active = document.activeElement;
      const inInput = active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA" || active.isContentEditable);
      
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        console.log("[CommandPalette] Cmd+K pressed, toggling palette")
        e.preventDefault();
        this.pushEvent("toggle_command_palette", {});
        console.log("[CommandPalette] pushEvent called")
      } else if (e.key === "Escape") {
        console.log("[CommandPalette] Escape pressed, closing palette")
        this.pushEvent("close_command_palette", {});
      } else if (e.key === "?" && !inInput) {
        console.log("[CommandPalette] ? pressed, toggling shortcuts")
        e.preventDefault();
        this.pushEvent("toggle_shortcuts_help", {});
      }
    };
    window.addEventListener("keydown", this.onKeyDown);
    console.log("[CommandPalette] Keydown listener attached to window")
  },
  
  destroyed() {
    console.log("[CommandPalette] Hook destroyed")
    window.removeEventListener("keydown", this.onKeyDown);
  }
};

export default CommandPalette;
