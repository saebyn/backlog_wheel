import {test} from "node:test"
import assert from "node:assert/strict"
import {JSDOM} from "jsdom"
import WheelVolume, {type WheelVolumeInstance} from "../js/wheel_volume.ts"

test("volume controls restore and persist the browser setting and notify the wheel", t => {
  const dom = new JSDOM('<div id="volume"><input type="range" min="0" max="100"><output></output></div>', {url: "https://example.test"})
  const {window} = dom
  globalThis.window = window as unknown as Window & typeof globalThis
  globalThis.CustomEvent = window.CustomEvent as typeof CustomEvent
  window.localStorage.setItem("backlog-wheel:sfx-volume", "0.35")

  const hook = {...WheelVolume, el: window.document.querySelector("#volume")!} as unknown as WheelVolumeInstance
  hook.mounted()
  t.after(() => { hook.destroyed(); dom.window.close() })
  const input = window.document.querySelector("input")!
  const output = window.document.querySelector("output")!
  assert.equal(input.value, "35")
  assert.equal(output.textContent, "35%")

  let notifiedVolume: number | undefined
  window.addEventListener("wheel:volume", event => { notifiedVolume = (event as CustomEvent<{volume: number}>).detail.volume })
  input.value = "70"
  input.dispatchEvent(new window.Event("input", {bubbles: true}))

  assert.equal(window.localStorage.getItem("backlog-wheel:sfx-volume"), "0.7")
  assert.equal(output.textContent, "70%")
  assert.equal(notifiedVolume, 0.7)
})
