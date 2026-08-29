const prefersReducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches

export function createLyricRoll(currentEl, outgoingEl) {
  let lastText = ""

  const settleCurrent = () => {
    currentEl.classList.remove("is-enter")
    currentEl.classList.add("is-current")
  }

  return {
    show(text) {
      const next = text || ""
      if (next === lastText) return

      const previous = lastText
      lastText = next

      if (!next) {
        currentEl.textContent = ""
        outgoingEl.textContent = ""
        settleCurrent()
        return
      }

      if (prefersReducedMotion() || !previous) {
        outgoingEl.textContent = ""
        currentEl.textContent = next
        settleCurrent()
        return
      }

      outgoingEl.textContent = previous
      outgoingEl.classList.remove("is-outgoing")
      void outgoingEl.offsetWidth
      outgoingEl.classList.add("is-outgoing")

      currentEl.textContent = next
      currentEl.classList.remove("is-current")
      currentEl.classList.add("is-enter")
      void currentEl.offsetWidth
      settleCurrent()
    }
  }
}
