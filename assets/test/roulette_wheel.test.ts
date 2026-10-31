import {test} from "node:test"
import assert from "node:assert/strict"
import {JSDOM} from "jsdom"
import RouletteWheel from "../js/roulette_wheel.ts"

type Spin = {
  landingDegrees: number
  segments: {start_degrees: number, end_degrees: number}[]
  spinId: string
  durationMs: number
  fullTurns: number
}

function mountWheel(reducedMotion = false) {
  const dom = new JSDOM('<div id="wheel" data-initial-rotation="30"><div data-wheel-pointer></div><svg data-wheel-rotor></svg></div>', {url: "https://example.test"})
  const {window} = dom
  globalThis.window = window as unknown as Window & typeof globalThis
  window.matchMedia = ((query: string) => ({matches: query === "(prefers-reduced-motion: reduce)" && reducedMotion})) as unknown as typeof window.matchMedia

  let now = 0
  let nextId = 0
  const timers = new Map<number, {at: number, callback: () => void}>()
  const frames = new Map<number, FrameRequestCallback>()
  window.setTimeout = ((callback: () => void, delay = 0) => {
    const id = ++nextId
    timers.set(id, {at: now + delay, callback})
    return id
  }) as typeof window.setTimeout
  window.clearTimeout = id => { if (id !== undefined) timers.delete(id) }
  window.requestAnimationFrame = callback => {
    const id = ++nextId
    frames.set(id, callback)
    return id
  }
  window.cancelAnimationFrame = id => { frames.delete(id) }
  Object.defineProperty(window.performance, "now", {value: () => now})

  let onSpin: ((payload: Spin) => void) | undefined
  const pushed: {event: string, payload: unknown}[] = []
  const hook = {
    ...RouletteWheel,
    el: window.document.querySelector<HTMLElement>("#wheel")!,
    handleEvent(event: string, callback: (payload: Spin) => void) {
      if (event === "roulette:spin") onSpin = callback
    },
    pushEvent(event: string, payload: unknown) { pushed.push({event, payload}) },
  }
  hook.mounted()
  assert.ok(onSpin)
  return {
    dom,
    hook,
    pushed,
    frames,
    rotor: window.document.querySelector<SVGElement>("[data-wheel-rotor]")!,
    pointer: window.document.querySelector<HTMLElement>("[data-wheel-pointer]")!,
    spin: onSpin,
    advance(milliseconds: number) {
      now += milliseconds
      for (const [id, timer] of timers) {
        if (timer.at <= now) {
          timers.delete(id)
          timer.callback()
        }
      }
    },
    frame(milliseconds: number) {
      now += milliseconds
      const callbacks = [...frames.values()]
      frames.clear()
      callbacks.forEach(callback => callback(now))
    },
  }
}

const spin: Spin = {
  landingDegrees: 45,
  segments: [{start_degrees: 0, end_degrees: 180}, {start_degrees: 180, end_degrees: 360}],
  spinId: "quick-42",
  durationMs: 5000,
  fullTurns: 2,
}

test("a spin lands on the selected segment and reports completion after the animation", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  assert.equal(wheel.rotor.style.transform, "rotate(30deg)")

  wheel.spin(spin)
  assert.equal(wheel.rotor.style.transform, "rotate(1035deg)")
  assert.match(wheel.rotor.style.transition, /5000ms/)
  wheel.advance(4999)
  assert.deepEqual(wheel.pushed, [])
  wheel.advance(1)
  assert.deepEqual(wheel.pushed, [{event: "spin_finished", payload: {spinId: "quick-42"}}])
})

test("an empty spin leaves the wheel in place and sends no completion", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  wheel.spin({...spin, segments: []})
  wheel.advance(5000)
  assert.equal(wheel.rotor.style.transform, "rotate(30deg)")
  assert.deepEqual(wheel.pushed, [])
})

test("a wheel with one entry still spins and reports its result", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  wheel.spin({...spin, landingDegrees: 90, fullTurns: 1, segments: [{start_degrees: 0, end_degrees: 360}]})
  assert.equal(wheel.rotor.style.transform, "rotate(630deg)")
  wheel.advance(5000)
  assert.deepEqual(wheel.pushed, [{event: "spin_finished", payload: {spinId: "quick-42"}}])
})

test("switching voting sessions displays the new session's saved wheel position", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  wheel.hook.el.dataset.votingSessionId = "first"
  wheel.hook.updated()
  assert.equal(wheel.rotor.style.transform, "rotate(30deg)")

  wheel.hook.el.dataset.votingSessionId = "second"
  wheel.hook.el.dataset.initialRotation = "120"
  wheel.hook.updated()
  assert.equal(wheel.rotor.style.transform, "rotate(120deg)")
})

test("a page update during a spin preserves the in-progress wheel animation", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  wheel.spin(spin)
  wheel.hook.updated()
  assert.equal(wheel.rotor.style.transform, "rotate(1035deg)")
  assert.match(wheel.rotor.style.transition, /5000ms/)
})

test("finishing a spin plays the winner's four-note sound", t => {
  const wheel = mountWheel(true)
  t.after(() => { wheel.hook.destroyed(); wheel.dom.window.close() })
  const notes: number[] = []
  class AudioContextStub {
    currentTime = 0
    state = "running"
    destination = {}
    createGain() {
      return {gain: {setValueAtTime() {}, exponentialRampToValueAtTime() {}}, connect() {}}
    }
    createOscillator() {
      let frequency = 0
      return {
        type: "",
        frequency: {setValueAtTime(value: number) { frequency = value }},
        connect() {},
        start() { notes.push(frequency) },
        stop() {},
      }
    }
    close() {}
  }
  Object.defineProperty(wheel.dom.window, "AudioContext", {value: AudioContextStub})
  wheel.spin(spin)
  wheel.advance(5000)
  wheel.advance(85)
  wheel.advance(85)
  wheel.advance(85)
  assert.deepEqual(notes, [440, 554, 659, 880])
})

test("pointer ticks during a spin unless reduced motion is requested", () => {
  const animated = mountWheel()
  animated.spin(spin)
  animated.frame(500)
  assert.equal(animated.pointer.classList.contains("wheel-pointer-flip"), true)
  animated.hook.destroyed()
  animated.dom.window.close()

  const reduced = mountWheel(true)
  reduced.spin(spin)
  reduced.frame(500)
  assert.equal(reduced.pointer.classList.contains("wheel-pointer-flip"), false)
  reduced.hook.destroyed()
  reduced.dom.window.close()
})

test("leaving the wheel during a spin cancels the pending completion and animation", t => {
  const wheel = mountWheel()
  t.after(() => wheel.dom.window.close())
  wheel.spin(spin)
  wheel.hook.destroyed()

  wheel.frame(500)
  wheel.advance(5000)
  assert.deepEqual(wheel.pushed, [])
  assert.equal(wheel.pointer.classList.contains("wheel-pointer-flip"), false)
})
