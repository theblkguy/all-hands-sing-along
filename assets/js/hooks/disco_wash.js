const DiscoWash = {
  mounted() {
    this.canvas = this.el
    this.ctx = this.canvas.getContext("2d")
    this.particles = []
    this.raf = null
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    this.tick = this.tick.bind(this)
    this.onResize = this.onResize.bind(this)
    this.onVisibility = this.onVisibility.bind(this)

    window.addEventListener("resize", this.onResize)
    document.addEventListener("visibilitychange", this.onVisibility)

    this.onResize()
    this.seed()

    if (this.reduced) {
      this.draw(0)
      return
    }

    this.start()
  },

  destroyed() {
    this.stop()
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisibility)
  },

  onResize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const width = window.innerWidth
    const height = window.innerHeight
    this.canvas.width = Math.floor(width * dpr)
    this.canvas.height = Math.floor(height * dpr)
    this.canvas.style.width = `${width}px`
    this.canvas.style.height = `${height}px`
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.width = width
    this.height = height
  },

  seed() {
    const count = Math.min(140, Math.floor((this.width * this.height) / 14000))
    this.particles = Array.from({length: count}, () => this.spawn(true))
  },

  spawn(anywhere) {
    return {
      x: Math.random() * this.width,
      y: anywhere ? Math.random() * this.height : this.height + Math.random() * 40,
      r: 0.4 + Math.random() * 1.6,
      speed: 0.08 + Math.random() * 0.22,
      drift: (Math.random() - 0.5) * 0.18,
      twinkle: Math.random() * Math.PI * 2,
      flash: Math.random()
    }
  },

  onVisibility() {
    if (this.reduced) return
    if (document.hidden) this.stop()
    else this.start()
  },

  start() {
    if (this.raf) return
    this.last = performance.now()
    this.raf = requestAnimationFrame(this.tick)
  },

  stop() {
    if (this.raf) cancelAnimationFrame(this.raf)
    this.raf = null
  },

  tick(now) {
    const dt = Math.min(32, now - (this.last || now))
    this.last = now
    this.draw(dt)
    this.raf = requestAnimationFrame(this.tick)
  },

  draw(dt) {
    const {ctx, width, height} = this
    ctx.fillStyle = "#050506"
    ctx.fillRect(0, 0, width, height)

    const t = (this.last || 0) / 1000

    for (const p of this.particles) {
      if (!this.reduced) {
        p.y -= p.speed * (dt / 16)
        p.x += Math.sin(t * 0.35 + p.twinkle) * p.drift
        if (p.y < -8) Object.assign(p, this.spawn(false), {y: height + 8})
      }

      const sparkle = 0.35 + 0.65 * Math.abs(Math.sin(t * 2.4 + p.twinkle))
      const facet = p.flash > 0.92 ? 0.55 + 0.45 * Math.abs(Math.sin(t * 9 + p.twinkle)) : sparkle
      ctx.beginPath()
      ctx.fillStyle =
        p.flash > 0.86
          ? `rgba(250, 230, 180, ${0.35 + facet * 0.65})`
          : `rgba(255, 255, 255, ${0.18 + sparkle * 0.55})`
      ctx.arc(p.x, p.y, p.r * (0.7 + facet * 0.6), 0, Math.PI * 2)
      ctx.fill()
    }
  }
}

export default DiscoWash
