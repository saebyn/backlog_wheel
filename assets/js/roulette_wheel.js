const normalizeDegrees = (degrees) => ((degrees % 360) + 360) % 360

const cubicBezier = (x1, y1, x2, y2) => {
  const sampleCurve = (a1, a2, t) => 3 * a1 * (1 - t) * (1 - t) * t + 3 * a2 * (1 - t) * t * t + t * t * t
  const sampleDerivative = (a1, a2, t) => 3 * a1 * (1 - t) * (1 - 3 * t) + 3 * a2 * t * (2 - 3 * t) + 3 * t * t

  return (progress) => {
    let t = progress

    for (let i = 0; i < 5; i++) {
      const x = sampleCurve(x1, x2, t) - progress
      const derivative = sampleDerivative(x1, x2, t)
      if (Math.abs(derivative) < 0.001) break
      t -= x / derivative
    }

    return sampleCurve(y1, y2, t)
  }
}

const spinEasing = cubicBezier(0.08, 0.72, 0.12, 1)
const minPointerFlipIntervalMs = 130

const RouletteWheel = {
  mounted() {
    this.rotation = 0
    this.timeout = null
    this.soundTimeout = null
    this.pointerFrame = null
    this.lastPointerFlipAt = 0
    this.audioContext = null
    this.rotor = this.el.querySelector("[data-wheel-rotor]")
    this.pointer = this.el.querySelector("[data-wheel-pointer]")

    this.handleEvent("roulette:spin", ({winnerIndex, segmentCount, spinId, durationMs}) => {
      if (!this.rotor || segmentCount < 1) return

      window.clearTimeout(this.timeout)
      this.stopPointerTicks()

      const segmentDegrees = 360 / segmentCount
      const winnerCenter = winnerIndex * segmentDegrees + segmentDegrees / 2
      const currentPosition = normalizeDegrees(this.rotation + winnerCenter)
      const landingDelta = normalizeDegrees(360 - currentPosition)
      const fullTurns = 12 * 360
      const startingRotation = this.rotation
      const nextRotation = this.rotation + fullTurns + landingDelta

      this.rotor.style.transition = `transform ${durationMs}ms cubic-bezier(0.08, 0.72, 0.12, 1)`
      this.rotor.style.transform = `rotate(${nextRotation}deg)`
      this.rotation = nextRotation
      this.flipPointer()
      this.startPointerTicks(startingRotation, nextRotation, segmentDegrees, durationMs)
      this.startSpinSound(durationMs)

      this.timeout = window.setTimeout(() => {
        this.stopPointerTicks()
        this.stopSpinSound()
        this.playFlourish()
        this.pushEvent("spin_finished", {spinId})
      }, durationMs)
    })
  },

  destroyed() {
    window.clearTimeout(this.timeout)
    this.stopPointerTicks()
    this.stopSpinSound()
  },

  startPointerTicks(startingRotation, endingRotation, segmentDegrees, durationMs) {
    if (!this.pointer || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const startedAt = window.performance.now()
    const rotationDelta = endingRotation - startingRotation
    let lastEdge = Math.floor(startingRotation / segmentDegrees)

    const tick = (now) => {
      const progress = Math.min((now - startedAt) / durationMs, 1)
      const easedRotation = startingRotation + rotationDelta * spinEasing(progress)
      const currentEdge = Math.floor(easedRotation / segmentDegrees)

      if (currentEdge > lastEdge) {
        this.flipPointer(now)
        lastEdge = currentEdge
      }

      if (progress < 1) {
        this.pointerFrame = window.requestAnimationFrame(tick)
      }
    }

    this.pointerFrame = window.requestAnimationFrame(tick)
  },

  stopPointerTicks() {
    if (this.pointerFrame) window.cancelAnimationFrame(this.pointerFrame)
    this.pointerFrame = null
  },

  flipPointer(now = window.performance.now()) {
    if (now - this.lastPointerFlipAt < minPointerFlipIntervalMs) return

    this.lastPointerFlipAt = now
    this.pointer.classList.remove("wheel-pointer-flip")
    void this.pointer.offsetWidth
    this.pointer.classList.add("wheel-pointer-flip")
  },

  getAudioContext() {
    if (!this.audioContext) {
      const AudioContext = window.AudioContext || window.webkitAudioContext
      if (!AudioContext) return null
      this.audioContext = new AudioContext()
    }

    if (this.audioContext.state === "suspended") this.audioContext.resume()
    return this.audioContext
  },

  playTone(frequency, durationSeconds, volume = 0.08) {
    const context = this.getAudioContext()
    if (!context) return

    const oscillator = context.createOscillator()
    const gain = context.createGain()
    const start = context.currentTime

    oscillator.type = "triangle"
    oscillator.frequency.setValueAtTime(frequency, start)
    gain.gain.setValueAtTime(volume, start)
    gain.gain.exponentialRampToValueAtTime(0.001, start + durationSeconds)
    oscillator.connect(gain)
    gain.connect(context.destination)
    oscillator.start(start)
    oscillator.stop(start + durationSeconds)
  },

  startSpinSound(durationMs) {
    this.stopSpinSound()
    this.playTone(260, 0.035, 0.06)

    const startedAt = window.performance.now()
    const tick = () => {
      const elapsedRatio = Math.min((window.performance.now() - startedAt) / durationMs, 1)
      const frequency = 620 - elapsedRatio * 300
      const delayMs = 45 + Math.pow(elapsedRatio, 2.4) * 420

      this.playTone(frequency, 0.028, 0.045)

      if (elapsedRatio < 1) {
        this.soundTimeout = window.setTimeout(tick, delayMs)
      }
    }

    this.soundTimeout = window.setTimeout(tick, 45)
  },

  stopSpinSound() {
    window.clearTimeout(this.soundTimeout)
    this.soundTimeout = null
  },

  playFlourish() {
    ;[440, 554, 659, 880].forEach((frequency, index) => {
      window.setTimeout(() => this.playTone(frequency, 0.12, 0.07), index * 85)
    })
  }
}

export default RouletteWheel
