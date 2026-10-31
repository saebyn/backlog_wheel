import {test} from "node:test"
import assert from "node:assert/strict"
import {JSDOM} from "jsdom"
import ThemeColorPicker from "../js/theme_color_picker.ts"

test("choosing a theme color updates the form field and notifies the form", t => {
  const dom = new JSDOM('<form><input id="primary" value="#000000"><input type="color" data-target="primary" value="#000000"></form>')
  t.after(() => dom.window.close())
  const {window} = dom
  globalThis.document = window.document
  globalThis.Event = window.Event

  const form = window.document.querySelector("form")!
  const text = form.querySelector<HTMLInputElement>("#primary")!
  const picker = form.querySelector<HTMLInputElement>('[type="color"]')!
  const notifications: {type: string, value: string}[] = []
  for (const type of ["input", "change"]) {
    form.addEventListener(type, event => {
      if (event.target === text) notifications.push({type: event.type, value: text.value})
    })
  }

  const hook = {...ThemeColorPicker, el: picker}
  hook.mounted()
  picker.value = "#aabbcc"
  picker.dispatchEvent(new window.Event("input", {bubbles: true}))

  assert.equal(text.value, "#aabbcc")
  assert.deepEqual(notifications, [
    {type: "input", value: "#aabbcc"},
    {type: "change", value: "#aabbcc"},
  ])
})
