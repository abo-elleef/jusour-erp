// Programmatically inject a toast into the existing toast-controller container.
// type: "notice" | "alert" | "warning"
// dismissAfter: ms before auto-dismiss (0 = never auto-dismiss)
export function showToast(message, { type = "notice", dismissAfter = 5000 } = {}) {
  const container = document.getElementById("toast-container")
  if (!container) return

  const iconMap = {
    notice: `<svg class="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
    </svg>`,
    alert: `<svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
    </svg>`,
    warning: `<svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
    </svg>`
  }

  const cardClasses = {
    notice: "bg-emerald-50/95 border-emerald-200 text-emerald-900",
    alert: "bg-red-50/95 border-red-200 text-red-900",
    warning: "bg-amber-50/95 border-amber-200 text-amber-900"
  }

  const role = type === "notice" ? "status" : "alert"
  const safeMessage = message.replace(/</g, "&lt;").replace(/>/g, "&gt;")

  const div = document.createElement("div")
  div.setAttribute("data-toast-target", "item")
  div.setAttribute("role", role)
  if (dismissAfter > 0) div.dataset.toastDismissValue = String(dismissAfter)
  div.className = `pointer-events-auto flex items-start gap-3 rounded-2xl border px-4 py-3 text-sm shadow-lg backdrop-blur-sm ${cardClasses[type] || cardClasses.notice}`
  div.innerHTML = `
    <span class="shrink-0 mt-0.5" aria-hidden="true">${iconMap[type] || iconMap.notice}</span>
    <p class="flex-1 min-w-0 leading-snug font-medium">${safeMessage}</p>
    <button type="button"
            data-action="toast#dismiss"
            class="shrink-0 -me-1 -mt-0.5 rounded-lg p-1 text-current/60 hover:text-current hover:bg-black/5 transition-colors"
            aria-label="Close">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    </button>
  `

  container.appendChild(div)
}
