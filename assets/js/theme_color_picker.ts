type ThemeColorPickerMethods = {mounted(): void, copyColor(): void}
type ThemeColorPickerInstance = ThemeColorPickerMethods & {el: HTMLInputElement}

const ThemeColorPicker: ThemeColorPickerMethods & ThisType<ThemeColorPickerInstance> = {
  mounted() {
    this.el.addEventListener("input", () => this.copyColor())
  },

  copyColor() {
    const target = document.getElementById(this.el.dataset.target!) as HTMLInputElement | null

    if (!target) return

    target.value = this.el.value
    target.dispatchEvent(new Event("input", {bubbles: true}))
    target.dispatchEvent(new Event("change", {bubbles: true}))
  },
}

export default ThemeColorPicker
