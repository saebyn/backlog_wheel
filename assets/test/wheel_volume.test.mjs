import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import WheelVolume, {readWheelVolume} from "../js/wheel_volume.js"
import RouletteWheel from "../js/roulette_wheel.js"

let stored
let gains
let oscillators
let closed

beforeEach(() => {
  stored = null
  gains = []
  oscillators = []
  closed = false
  globalThis.window = Object.assign(new EventTarget(), {
    localStorage: {
      getItem: () => stored,
      setItem: (_key, value) => { stored = value },
    },
    clearTimeout,
    AudioContext: class {
      currentTime = 10
      state = "running"
      destination = {}
      createGain() {
        const node = {
          gain: {
            setValueAtTime(value) { this.value = value },
            exponentialRampToValueAtTime() {},
          },
          connect(target) { this.target = target },
        }
        gains.push(node)
        return node
      }
      createOscillator() {
        const oscillator = {
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
  })
})

const mountControls = () => {
  const input = Object.assign(new EventTarget(), {
    value: "100",
    setAttribute(name, value) { this[name] = value },
  })
  const output = {}
  const hook = {
    ...WheelVolume,
    el: {querySelector: selector => selector === "input" ? input : output},
  }
  hook.mounted()
  return hook
}

const mountWheel = () => {
  const wheel = {
    ...RouletteWheel,
    el: {dataset: {}, querySelector: () => null},
    handleEvent() {},
  }
  wheel.mounted()
  return wheel
}

const setVolume = (controls, percent) => {
  controls.input.value = String(percent)
  controls.input.dispatchEvent(new Event("input"))
}

test("restores saved volume, validates storage, and tolerates blocked storage", () => {
  for (const [value, expected] of [[null, 1], ["", 1], ["invalid", 1], ["Infinity", 1],
    ["-1", 0], ["2", 1], ["0", 0], ["0.37", 0.37]]) {
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
  }
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
  assert.equal(gains[0].target, wheel.audioContext.destination)

  setVolume(controls, 40)
  assert.equal(gains[0].gain.value, 0.4)
  assert.equal(stored, "0.4")
  setVolume(controls, 0)
  assert.equal(gains[0].gain.value, 0)
  assert.equal(controls.output.textContent, "Muted")
  assert.equal(controls.input["aria-valuetext"], "Muted")
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
  const pending = new Map()
  let timerId = 0
  window.setTimeout = callback => {
    pending.set(++timerId, callback)
    return timerId
  }
  window.clearTimeout = id => pending.delete(id)
  const controls = mountControls()
  const wheel = mountWheel()
  wheel.playFlourish()
  assert.equal(pending.size, 4)
  pending.get(1)()
  assert.equal(oscillators.length, 1)
  setVolume(controls, 0)
  pending.get(2)()
  assert.equal(oscillators.length, 1)
  wheel.destroyed()
  assert.equal(pending.size, 0)
  controls.destroyed()
})
