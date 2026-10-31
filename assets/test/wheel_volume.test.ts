import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import WheelVolume, {readWheelVolume, type WheelVolumeInstance} from "../js/wheel_volume.ts"
import RouletteWheel, {type RouletteWheelInstance} from "../js/roulette_wheel.ts"

type FakeGain = {
  gain: {value: number, setValueAtTime(value: number): void, exponentialRampToValueAtTime(): void}
  target?: unknown
  connect(target: unknown): void
}
type FakeOscillator = {frequency: {setValueAtTime(): void}, target?: unknown, connect(target: unknown): void, start(): void, stop(): void}

let stored: string | null
let gains: FakeGain[]
let oscillators: FakeOscillator[]
let closed: boolean

beforeEach(() => {
  stored = null
  gains = []
  oscillators = []
  closed = false
  globalThis.window = Object.assign(new EventTarget(), {
    localStorage: {
      getItem: () => stored,
      setItem: (_key: string, value: string) => { stored = value },
    },
    clearTimeout,
    AudioContext: class {
      currentTime = 10
      state = "running"
      destination = {}
      createGain() {
        const node: FakeGain = {
          gain: {
            value: 0,
            setValueAtTime(value) { this.value = value },
            exponentialRampToValueAtTime() {},
          },
          connect(target) { this.target = target },
        }
        gains.push(node)
        return node
      }
      createOscillator() {
        const oscillator: FakeOscillator = {
          frequency: {setValueAtTime() {}},
          connect(target) { this.target = target },
          start() {},
          stop() {},
        }
        oscillators.push(oscillator)
        return oscillator
      }
      close() { closed = true }
    },
  }) as unknown as Window & typeof globalThis
})

const mountControls = () => {
  const input = Object.assign(new EventTarget(), {
    value: "100",
    setAttribute(name: string, value: string) { (this as unknown as Record<string, unknown>)[name] = value },
  }) as EventTarget & {value: string, setAttribute(name: string, value: string): void, [key: string]: unknown}
  const output = {}
  const hook = {
    ...WheelVolume,
    el: {querySelector: (selector: string) => selector === "input" ? input : output},
  } as unknown as WheelVolumeInstance
  hook.mounted()
  return hook
}

const mountWheel = () => {
  const wheel = {
    ...RouletteWheel,
    el: {dataset: {}, querySelector: () => null},
    handleEvent() {},
  } as unknown as RouletteWheelInstance
  wheel.mounted()
  return wheel
}

const setVolume = (controls: WheelVolumeInstance, percent: number) => {
  controls.input.value = String(percent)
  controls.input.dispatchEvent(new Event("input"))
}

test("restores saved volume, validates storage, and tolerates blocked storage", () => {
  for (const [value, expected] of [[null, 1], ["", 1], ["invalid", 1], ["Infinity", 1],
    ["-1", 0], ["2", 1], ["0", 0], ["0.37", 0.37]] as [string | null, number][]) {
    stored = value
    assert.equal(readWheelVolume(), expected)
  }
  const controls = mountControls()
  assert.equal(controls.input.value, "37")
  assert.equal(controls.output.textContent, "37%")
  controls.destroyed()

  window.localStorage = {
    getItem() { throw new Error("blocked") },
    setItem() { throw new Error("blocked") },
  } as unknown as Storage
  const blockedControls = mountControls()
  const wheel = mountWheel()
  setVolume(blockedControls, 25)
  assert.equal(wheel.volume, 0.25)
  blockedControls.destroyed()
  wheel.destroyed()
})

test("scales every tone through master gain and mutes sounds already playing", () => {
  const controls = mountControls()
  const wheel = mountWheel()
  wheel.playTone(520, 0.028, 0.045)
  assert.equal(gains[0].gain.value, 1)
  assert.equal(gains[1].target, gains[0])
  assert.equal(gains[0].target, wheel.audioContext!.destination)

  setVolume(controls, 40)
  assert.equal(gains[0].gain.value, 0.4)
  assert.equal(stored, "0.4")
  setVolume(controls, 0)
  assert.equal(gains[0].gain.value, 0)
  assert.equal(controls.output.textContent, "Muted")
  assert.equal((controls.input as unknown as Record<string, unknown>)["aria-valuetext"], "Muted")
  wheel.playTone(880, 0.12, 0.07)
  assert.equal(oscillators.length, 1)

  setVolume(controls, 80)
  wheel.playTone(880, 0.12, 0.07)
  assert.equal(oscillators.length, 2)
  assert.equal(gains[0].gain.value, 0.8)
  assert.equal(gains[2].target, gains[0])
  wheel.destroyed()
  assert.equal(closed, true)
  setVolume(controls, 20)
  assert.equal(wheel.volume, 0.8)
  controls.destroyed()
})

test("mute persists across wheel navigation and does not create an audio context", () => {
  const controls = mountControls()
  setVolume(controls, 0)
  controls.destroyed()
  setVolume(controls, 100)
  assert.equal(stored, "0")

  const nextControls = mountControls()
  const nextWheel = mountWheel()
  assert.equal(nextControls.input.value, "0")
  nextWheel.playTone(520, 0.028)
  assert.equal(nextWheel.audioContext, null)
  nextControls.destroyed()
  nextWheel.destroyed()
})

test("winner notes use the current volume and pending notes are cancelled on navigation", () => {
  const pending = new Map<number, () => void>()
  let timerId = 0
  window.setTimeout = ((callback: () => void) => {
    pending.set(++timerId, callback)
    return timerId
  }) as typeof window.setTimeout
  window.clearTimeout = ((id: number) => pending.delete(id)) as typeof window.clearTimeout
  const controls = mountControls()
  const wheel = mountWheel()
  wheel.playFlourish()
  assert.equal(pending.size, 4)
  pending.get(1)!()
  assert.equal(oscillators.length, 1)
  setVolume(controls, 0)
  pending.get(2)!()
  assert.equal(oscillators.length, 1)
  wheel.destroyed()
  assert.equal(pending.size, 0)
  controls.destroyed()
})
