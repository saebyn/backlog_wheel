const QuickWheelEntryForm = {
  mounted() {
    this.handleEvent("quick-wheel:entry-added", () => {
      const input = this.el.querySelector("input[name='entry[title]']")
      if (!input) return

      input.value = ""
      this.refocus(input)
    })
  },

  refocus(input) {
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => input.focus({preventScroll: true}))
      window.setTimeout(() => input.focus({preventScroll: true}), 0)
    })
  },
}

export default QuickWheelEntryForm
