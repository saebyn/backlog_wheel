import type {HookInterface} from "phoenix_live_view"

type Navigation = Pick<HookInterface, "el"> & {listeners?: AbortController}

export default {
  mounted(this: Navigation) {
    this.listeners = new AbortController()
    const options = {capture: true, signal: this.listeners.signal}
    window.addEventListener("beforeunload", event => {
      if (this.el.dataset.dirty === "true") {
        event.preventDefault()
        event.returnValue = ""
      }
    }, options)
    window.addEventListener("click", event => {
      if (this.el.dataset.dirty !== "true" || event.button !== 0 ||
          event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return
      const link = event.target instanceof Element && event.target.closest("a[data-phx-link]")
      if (link && !window.confirm("Leave without saving your preset changes?")) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }, options)
  },
  destroyed(this: Navigation) {
    this.listeners?.abort()
  },
}
