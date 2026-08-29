const ClipboardCopy = {
  mounted() {
    this.button = this.el.matches("[data-copy-button]")
      ? this.el
      : this.el.querySelector("[data-copy-button]")
    this.label = this.el.querySelector("[data-copy-label]")
    this.pre = this.el.querySelector("pre")
    this.idleLabel = (this.label && this.label.textContent) || "Copy"

    this.onClick = async () => {
      const copied = await this.copyText(this.copyValue())

      if (copied && this.label) {
        this.label.textContent = "Copied"
        window.clearTimeout(this.resetTimer)
        this.resetTimer = window.setTimeout(() => {
          if (this.label) this.label.textContent = this.idleLabel
        }, 1600)
        return
      }

      this.selectNode(this.pre || this.el)
    }

    this.button && this.button.addEventListener("click", this.onClick)
  },
  destroyed() {
    window.clearTimeout(this.resetTimer)
    this.button && this.button.removeEventListener("click", this.onClick)
  },
  copyValue() {
    const fromAttr = this.el.getAttribute("data-copy-text")
    if (fromAttr != null && fromAttr !== "") return fromAttr.trim()
    return ((this.pre && this.pre.textContent) || "").trim()
  },
  async copyText(text) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text)
        return true
      }
    } catch (_error) {}

    const field = document.createElement("textarea")
    field.value = text
    field.setAttribute("readonly", "")
    field.style.position = "fixed"
    field.style.left = "-9999px"
    document.body.appendChild(field)
    field.select()
    let ok = false
    try {
      ok = document.execCommand("copy")
    } catch (_error) {}
    field.remove()
    return ok
  },
  selectNode(node) {
    if (!node) return
    const range = document.createRange()
    range.selectNodeContents(node)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }
}

export default ClipboardCopy
