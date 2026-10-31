import {test} from "node:test"
import assert from "node:assert/strict"
import {JSDOM} from "jsdom"
import QuickWheelEntryForm from "../js/quick_wheel_entry_form.ts"

test("adding a quick wheel entry clears the input and returns focus to it", t => {
  const dom = new JSDOM('<form><input name="entry[title]" value="Play a game"><button>Add</button></form>')
  t.after(() => dom.window.close())
  const {window} = dom
  globalThis.window = window as unknown as Window & typeof globalThis

  const frames: FrameRequestCallback[] = []
  const timers: (() => void)[] = []
  window.requestAnimationFrame = callback => { frames.push(callback); return frames.length }
  window.setTimeout = ((callback: () => void) => { timers.push(callback); return timers.length }) as typeof window.setTimeout

  const form = window.document.querySelector("form")!
  const input = form.querySelector("input")!
  form.querySelector("button")!.focus()
  let entryAdded: (() => void) | undefined
  const hook = {
    ...QuickWheelEntryForm,
    el: form,
    handleEvent(name: string, callback: () => void) {
      if (name === "quick-wheel:entry-added") entryAdded = callback
    },
  }

  hook.mounted()
  assert.ok(entryAdded)
  entryAdded()
  assert.equal(input.value, "")

  while (frames.length) frames.shift()!(0)
  while (timers.length) timers.shift()!()
  assert.equal(window.document.activeElement, input)
})
