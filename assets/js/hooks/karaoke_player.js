const KaraokePlayer = {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.lyricLine = this.el.querySelector("#lyric-line")
    this.lyrics = []
    this.sync = {playing: false, position_ms: 0, server_time_ms: 0, offset_ms: 0}
    this.raf = null

    this.tick = this.tick.bind(this)
    this.onAudioPause = this.onAudioPause.bind(this)
    this.onAudioPlay = this.onAudioPlay.bind(this)

    if (this.audio) {
      this.audio.addEventListener("pause", this.onAudioPause)
      this.audio.addEventListener("play", this.onAudioPlay)
    }

    this.handleEvent("player-sync", (payload) => this.applySync(payload))
  },

  destroyed() {
    this.stopTick()
    if (this.audio) {
      this.audio.removeEventListener("pause", this.onAudioPause)
      this.audio.removeEventListener("play", this.onAudioPlay)
    }
  },

  applySync(payload) {
    this.lyrics = payload.lyrics || []
    const nextPlaying = !!payload.playing
    const nextOffset = payload.offset_ms || 0
    const nextSrc = payload.audio_url || null
    const currentSrc = this.audio && this.audio.getAttribute("data-src")
    const trackChanged = !!(nextSrc && currentSrc !== nextSrc)

    this.sync = {
      playing: nextPlaying,
      position_ms: payload.position_ms || 0,
      server_time_ms: payload.server_time_ms || Date.now(),
      offset_ms: nextOffset
    }

    if (this.audio) {
      this.audio.muted = !!payload.muted
      if (payload.show_controls === false) {
        this.audio.removeAttribute("controls")
      } else {
        this.audio.setAttribute("controls", "")
      }
    }

    if (trackChanged && this.audio) {
      this.audio.setAttribute("data-src", nextSrc)
      this.audio.src = nextSrc
    }

    if (!this.audio) {
      if (nextPlaying) this.startTick()
      else this.freezeLyrics()
      return
    }

    const targetSec = (payload.position_ms || 0) / 1000
    const shouldSeek =
      trackChanged ||
      (nextPlaying && this.audio.paused && Number.isFinite(targetSec) &&
        Math.abs((this.audio.currentTime || 0) - targetSec) > 0.4)

    if (shouldSeek && Number.isFinite(targetSec)) {
      this.audio.currentTime = targetSec
    }

    if (nextPlaying) {
      this.audio.play().catch(() => {})
      this.startTick()
    } else {
      this.audio.pause()
      this.freezeLyrics()
    }
  },

  onAudioPause() {
    this.freezeLyrics()
  },

  onAudioPlay() {
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

  freezeLyrics() {
    this.stopTick()
    this.renderLyrics(this.mediaPositionMs())
  },

  mediaPositionMs() {
    const hasSrc =
      this.audio && (this.audio.getAttribute("data-src") || this.audio.currentSrc)
    const offset = this.sync.offset_ms || 0

    if (hasSrc && Number.isFinite(this.audio.currentTime)) {
      return Math.max(0, this.audio.currentTime * 1000 + offset)
    }

    return this.clientPositionMs()
  },

  clientPositionMs() {
    const {position_ms, server_time_ms, offset_ms, playing} = this.sync
    if (!playing) return Math.max(0, position_ms + (offset_ms || 0))
    return Math.max(0, position_ms + (Date.now() - server_time_ms) + (offset_ms || 0))
  },

  tick() {
    this.renderLyrics(this.mediaPositionMs())
    if (this.sync.playing && !(this.audio && this.audio.paused)) {
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

export default KaraokePlayer
