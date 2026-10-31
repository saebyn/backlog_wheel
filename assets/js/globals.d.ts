import type {LiveSocket} from "phoenix_live_view"

interface LiveReloader {
  enableServerLogs(): void
  disableServerLogs(): void
  openEditorAtCaller(target: EventTarget | null): void
  openEditorAtDef(target: EventTarget | null): void
}

declare global {
  interface Window {
    liveSocket: LiveSocket
    liveReloader: LiveReloader
    webkitAudioContext?: typeof AudioContext
  }

  interface WindowEventMap {
    "wheel:volume": CustomEvent<{volume: number}>
    "phx:wheel-format-editing": CustomEvent<{id: string}>
    "phx:live_reload:attached": CustomEvent<LiveReloader>
  }
}
