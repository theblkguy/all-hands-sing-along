const LyricPreview = {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.lyricLine = this.el.querySelector("#lyric-preview-line")
    this.lyrics = []
    this.offsetMs = 0
    this.raf = null

    this.tick = this.tick.bind(this)
    this.onPlay = this.startTick.bind(this)

    if (this.audio) {
      this.audio.addEventListener("play", this.onPlay)
    }

    this.handleEvent("preview-sync", (payload) => this.applySync(payload))
  },

  destroyed() {
    this.stopTick()
    if (this.audio) {
      this.audio.removeEventListener("play", this.onPlay)
      this.audio.pause()
      this.audio.removeAttribute("src")
      this.audio.load()
    }
  },

  applySync(payload) {
    if (payload.lyrics) this.lyrics = payload.lyrics
    this.offsetMs = payload.offset_ms || 0

    const nextSrc = payload.audio_url || null
    const currentSrc = this.audio && this.audio.getAttribute("data-src")
    const trackChanged = !!(nextSrc && currentSrc !== nextSrc)

    if (trackChanged && this.audio) {
      this.audio.setAttribute("data-src", nextSrc)
      this.audio.src = nextSrc
      this.audio.currentTime = 0
      this.audio.play().catch(() => {})
    }

    this.startTick()
  },

  startTick() {
    this.stopTick()
    this.tick()
  },

  stopTick() {
    if (this.raf) {
      cancelAnimationFrame(this.raf)
      this.raf = null
    }
  },

  mediaPositionMs() {
    const offset = this.offsetMs || 0
    if (this.audio && Number.isFinite(this.audio.currentTime)) {
      return Math.max(0, this.audio.currentTime * 1000 + offset)
    }
    return Math.max(0, offset)
  },

  tick() {
    this.renderLyrics(this.mediaPositionMs())
    if (this.audio && !this.audio.paused) {
      this.raf = requestAnimationFrame(this.tick)
    }
  },

  renderLyrics(positionMs) {
    if (!this.lyricLine) return
    let current = {text: "", time_ms: 0}
    for (const line of this.lyrics) {
      if (line.time_ms <= positionMs) current = line
    }
    this.lyricLine.textContent = current.text || ""
  }
}

export default LyricPreview
