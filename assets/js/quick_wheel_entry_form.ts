import type {HookInterface} from "phoenix_live_view"

type QuickWheelEntryFormMethods = {
  mounted(): void
  refocus(input: HTMLInputElement): void
}

type QuickWheelEntryFormInstance = QuickWheelEntryFormMethods & Pick<HookInterface, "el" | "handleEvent">

const QuickWheelEntryForm: QuickWheelEntryFormMethods & ThisType<QuickWheelEntryFormInstance> = {
  mounted() {
    this.handleEvent("quick-wheel:entry-added", () => {
      const input = this.el.querySelector<HTMLInputElement>("input[name='entry[title]']")
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
