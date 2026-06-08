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
    this.pointerFrame = null
    this.lastPointerFlipAt = 0
    this.audioContext = null
    this.spinning = false
    this.rotor = this.el.querySelector("[data-wheel-rotor]")
    this.pointer = this.el.querySelector("[data-wheel-pointer]")
    this.votingSessionId = this.el.dataset.votingSessionId
    this.rotation = this.initialRotation()
    this.applyRotation()

    this.handleEvent("roulette:spin", ({landingDegrees, segments, spinId, durationMs, fullTurns}) => {
      if (!this.rotor || !segments || segments.length < 1) return

      window.clearTimeout(this.timeout)
      this.stopPointerTicks()

      const currentPosition = normalizeDegrees(this.rotation + landingDegrees)
      const landingDelta = normalizeDegrees(360 - currentPosition)
      const fullTurnDegrees = fullTurns * 360
      const startingRotation = this.rotation
      const nextRotation = this.rotation + fullTurnDegrees + landingDelta
      const edgeCrossings = this.edgeCrossingsForSpin(segments, startingRotation, nextRotation)

      this.spinning = true
      this.rotor.style.transition = `transform ${durationMs}ms cubic-bezier(0.08, 0.72, 0.12, 1)`
      this.rotor.style.transform = `rotate(${nextRotation}deg)`
      this.rotation = nextRotation
      this.startPointerTicks(startingRotation, nextRotation, edgeCrossings, durationMs)

      this.timeout = window.setTimeout(() => {
        this.stopPointerTicks()
        this.spinning = false
        this.playFlourish()
        this.pushEvent("spin_finished", {spinId})
      }, durationMs)
    })
  },

  updated() {
    this.rotor = this.el.querySelector("[data-wheel-rotor]")
    this.pointer = this.el.querySelector("[data-wheel-pointer]")
    const votingSessionId = this.el.dataset.votingSessionId

    if (votingSessionId !== this.votingSessionId) {
      this.votingSessionId = votingSessionId
      this.rotation = this.initialRotation()
    }

    if (!this.spinning) this.applyRotation()
  },

  destroyed() {
    window.clearTimeout(this.timeout)
    this.stopPointerTicks()
  },

  edgeCrossingsForSpin(segments, startingRotation, endingRotation) {
    const edges = [...new Set(
      segments
        .flatMap(({start_degrees, end_degrees}) => [start_degrees, end_degrees])
        .map(edgeDegrees => normalizeDegrees(edgeDegrees))
    )]
    const crossings = []

    edges.forEach(edgeDegrees => {
      const firstTurn = Math.floor((startingRotation + edgeDegrees) / 360)
      const lastTurn = Math.ceil((endingRotation + edgeDegrees) / 360)

      for (let turn = firstTurn; turn <= lastTurn; turn++) {
        const crossingRotation = turn * 360 - edgeDegrees
        if (crossingRotation > startingRotation && crossingRotation <= endingRotation) {
          crossings.push(crossingRotation)
        }
      }
    })

    return crossings.sort((a, b) => a - b)
  },

  startPointerTicks(startingRotation, endingRotation, edgeCrossings, durationMs) {
    if (!this.pointer || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const startedAt = window.performance.now()
    const rotationDelta = endingRotation - startingRotation
    let nextEdgeIndex = 0

    const tick = (now) => {
      const progress = Math.min((now - startedAt) / durationMs, 1)
      const easedRotation = startingRotation + rotationDelta * spinEasing(progress)

      while (nextEdgeIndex < edgeCrossings.length && easedRotation >= edgeCrossings[nextEdgeIndex]) {
        this.tickPointerEdge(now)
        nextEdgeIndex += 1
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

  applyRotation() {
    if (!this.rotor) return

    this.rotor.style.transition = "none"
    this.rotor.style.transform = `rotate(${this.rotation}deg)`
  },

  initialRotation() {
    const rotation = Number.parseFloat(this.el.dataset.initialRotation)
    return Number.isFinite(rotation) ? rotation : 0
  },

  tickPointerEdge(now = window.performance.now()) {
    if (now - this.lastPointerFlipAt < minPointerFlipIntervalMs) return

    this.lastPointerFlipAt = now
    this.pointer.classList.remove("wheel-pointer-flip")
    void this.pointer.offsetWidth
    this.pointer.classList.add("wheel-pointer-flip")
    this.playTone(520, 0.028, 0.045)
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

  playFlourish() {
    ;[440, 554, 659, 880].forEach((frequency, index) => {
      window.setTimeout(() => this.playTone(frequency, 0.12, 0.07), index * 85)
    })
  }
}

export default RouletteWheel
