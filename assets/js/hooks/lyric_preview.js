import {createLyricRoll} from "../lyric_roll"
import {createLyricTicker} from "../lyric_ticker"

const LyricPreview = {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.lyricLine = this.el.querySelector("#lyric-preview-line")
    this.outgoingLine = this.el.querySelector("#lyric-preview-line-outgoing")
    this.roll = createLyricRoll(this.lyricLine, this.outgoingLine)
    this.ticker = createLyricTicker()
    this.lyrics = []
    this.offsetMs = 0

    this.onPlay = () => this.startTick()

    if (this.audio) {
      this.audio.addEventListener("play", this.onPlay)
    }

    this.handleEvent("preview-sync", (payload) => this.applySync(payload))
  },

  destroyed() {
    this.ticker.stop()
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
    this.ticker.start(
      () => this.audio && !this.audio.paused,
      () => this.mediaPositionMs(),
      this.roll,
      () => this.lyrics
    )
  },

  mediaPositionMs() {
    const offset = this.offsetMs || 0
    if (this.audio && Number.isFinite(this.audio.currentTime)) {
      return Math.max(0, this.audio.currentTime * 1000 + offset)
    }
    return Math.max(0, offset)
  }
}

export default LyricPreview
