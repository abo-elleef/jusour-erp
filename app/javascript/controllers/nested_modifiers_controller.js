import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groups", "groupTemplate", "group", "modifiers", "modifierTemplate", "modifier", "destroy"]

  addGroup(event) {
    event.preventDefault()
    const content = this.groupTemplateTarget.innerHTML.replace(/NEW_GROUP/g, new Date().getTime())
    this.groupsTarget.insertAdjacentHTML("beforeend", content)
  }

  removeGroup(event) {
    event.preventDefault()
    const group = event.target.closest("[data-nested-modifiers-target='group']")
    const destroy = group.querySelector("[data-nested-modifiers-target='destroy']")
    if (destroy && destroy.name.includes("[_destroy]")) {
      destroy.value = "1"
      group.classList.add("hidden")
    } else {
      group.remove()
    }
  }

  addModifier(event) {
    event.preventDefault()
    const group = event.target.closest("[data-nested-modifiers-target='group']")
    const container = group.querySelector("[data-nested-modifiers-target='modifiers']")
    const template = group.querySelector("[data-nested-modifiers-target='modifierTemplate']")
    const content = template.innerHTML.replace(/NEW_MOD/g, new Date().getTime())
    container.insertAdjacentHTML("beforeend", content)
  }

  removeModifier(event) {
    event.preventDefault()
    const row = event.target.closest("[data-nested-modifiers-target='modifier']")
    const destroy = row.querySelector("[data-nested-modifiers-target='destroy']")
    if (destroy && destroy.name.includes("[_destroy]")) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
