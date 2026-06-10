const ThemeColorPicker = {
  mounted() {
    this.el.addEventListener("input", () => this.copyColor())
  },

  copyColor() {
    const target = document.getElementById(this.el.dataset.target)

    if (!target) return

    target.value = this.el.value
    target.dispatchEvent(new Event("input", {bubbles: true}))
    target.dispatchEvent(new Event("change", {bubbles: true}))
  },
}

export default ThemeColorPicker
