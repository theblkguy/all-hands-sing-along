export function createLyricTicker() {
  let raf = null

  const stop = () => {
    if (raf) {
      cancelAnimationFrame(raf)
      raf = null
    }
  }

  const render = (roll, lyrics, positionMs) => {
    if (!roll) return
    let current = {text: "", time_ms: 0}
    for (const line of lyrics || []) {
      if (line.time_ms <= positionMs) current = line
    }
    roll.show(current.text || "")
  }

  return {
    stop,
    render,
    start(shouldContinue, getPositionMs, roll, getLyrics) {
      stop()
      const tick = () => {
        render(roll, getLyrics(), getPositionMs())
        if (shouldContinue()) raf = requestAnimationFrame(tick)
      }
      tick()
    }
  }
}
