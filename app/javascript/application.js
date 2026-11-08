// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// The mouse wheel must never change a number field's value. Browsers step a
// focused <input type="number"> on wheel, so users who scroll the page with
// the pointer over a field change it without noticing. Blurring the field
// first removes the trigger and still lets the page scroll.
document.addEventListener("wheel", (event) => {
  const el = document.activeElement
  if (el instanceof HTMLInputElement && el.type === "number" && el === event.target) {
    el.blur()
  }
}, { capture: true, passive: true })

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").catch(() => {})
  })
}
