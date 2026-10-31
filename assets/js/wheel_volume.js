const storageKey = "backlog-wheel:sfx-volume"
export const volumeEvent = "wheel:volume"

const normalizeVolume = value => {
  const volume = Number(value)
  return value === null || value === "" || !Number.isFinite(volume)
    ? 1
    : Math.min(1, Math.max(0, volume))
}

export const readWheelVolume = () => {
  try {
    return normalizeVolume(window.localStorage.getItem(storageKey))
  } catch {
    return 1
  }
}

const WheelVolume = {
  mounted() {
    this.input = this.el.querySelector("input")
    this.output = this.el.querySelector("output")
    this.showVolume(readWheelVolume())
    this.onInput = () => {
      const volume = normalizeVolume(Number(this.input.value) / 100)
      this.showVolume(volume)
      try {
        window.localStorage.setItem(storageKey, String(volume))
      } catch {
        // Volume still works when browser storage is unavailable.
      }
      window.dispatchEvent(new CustomEvent(volumeEvent, {detail: {volume}}))
    }
    this.input.addEventListener("input", this.onInput)
  },

  showVolume(volume) {
    const percent = Math.round(volume * 100)
    this.input.value = String(percent)
    this.output.textContent = percent === 0 ? "Muted" : `${percent}%`
    this.input.setAttribute("aria-valuetext", this.output.textContent)
  },

  destroyed() {
    this.input.removeEventListener("input", this.onInput)
  },
}

export default WheelVolume
