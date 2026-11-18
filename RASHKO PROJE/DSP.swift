import Foundation

// Gerçek zamanlı güvenli: render sırasında bellek tahsisi / kilit yok.
// Parametreler `p` struct'ı ile değişir; katsayılar bir sonraki blokta refresh() ile yenilenir.

@inline(__always) func dbToLin(_ db: Float) -> Float { powf(10, db / 20) }

// MARK: - Biquad (minimum-phase IIR)

struct Biquad {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    private mutating func set(_ nb0: Float, _ nb1: Float, _ nb2: Float,
                              _ a0: Float, _ na1: Float, _ na2: Float) {
        b0 = nb0 / a0; b1 = nb1 / a0; b2 = nb2 / a0
        a1 = na1 / a0; a2 = na2 / a0
    }

    mutating func highpass(_ f: Float, q: Float = 0.7071, sr: Float) {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let c = cosf(w), alpha = sinf(w) / (2 * q)
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    mutating func lowpass(_ f: Float, q: Float = 0.7071, sr: Float) {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let c = cosf(w), alpha = sinf(w) / (2 * q)
        set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    mutating func peaking(_ f: Float, gainDB: Float, q: Float, sr: Float) {
        let A = powf(10, gainDB / 40)
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let c = cosf(w), alpha = sinf(w) / (2 * q)
        set(1 + alpha * A, -2 * c, 1 - alpha * A, 1 + alpha / A, -2 * c, 1 - alpha / A)
    }
}

// MARK: - Gate (look-ahead yok, hysteresis var)

final class Gate {
    struct Params {
        var thresholdDB: Float = -50
        var hysteresisDB: Float = 4
        var attackMs: Float = 0.5
        var holdMs: Float = 30
        var releaseMs: Float = 100
    }
    var p = Params() { didSet { dirty = true } }

    private var dirty = true
    private let sr: Float
    private let detDecay: Float
    private var openLin: Float = 0, closeLin: Float = 0
    private var atk: Float = 0, rel: Float = 0
    private var hold = 0, holdLeft = 0
    private var env: Float = 0, gain: Float = 0
    private var isOpen = false

    init(sr: Float) {
        self.sr = sr
        detDecay = expf(-1 / (0.005 * sr)) // dedektör: anlık yükselir, ~5 ms düşer
    }

    func refresh() {
        guard dirty else { return }
        dirty = false
        openLin = dbToLin(p.thresholdDB)
        closeLin = dbToLin(p.thresholdDB - p.hysteresisDB)
        atk = expf(-1 / (max(p.attackMs, 0.01) * 0.001 * sr))
        rel = expf(-1 / (max(p.releaseMs, 1) * 0.001 * sr))
        hold = Int(p.holdMs * 0.001 * sr)
    }

    @inline(__always) func process(_ x: Float) -> Float {
        let a = abs(x)
        env = a > env ? a : env * detDecay
        if isOpen {
            if env > closeLin { holdLeft = hold }
            else if holdLeft > 0 { holdLeft -= 1 }
            else { isOpen = false }
        } else if env > openLin {
            isOpen = true
            holdLeft = hold
        }
        let target: Float = isOpen ? 1 : 0
        let c = target > gain ? atk : rel
        gain = target + c * (gain - target)
        return x * gain
    }
}

// MARK: - 4 bantlı parametrik EQ

final class EQ {
    struct Band { var freq: Float; var gainDB: Float = 0; var q: Float = 1 }
    var bands: (Band, Band, Band, Band) = (Band(freq: 250), Band(freq: 1000),
                                           Band(freq: 3000), Band(freq: 6000)) {
        didSet { dirty = true }
    }

    private var dirty = true
    private let sr: Float
    private var f0 = Biquad(), f1 = Biquad(), f2 = Biquad(), f3 = Biquad()

    init(sr: Float) { self.sr = sr }

    func refresh() {
        guard dirty else { return }
        dirty = false
        f0.peaking(bands.0.freq, gainDB: bands.0.gainDB, q: bands.0.q, sr: sr)
        f1.peaking(bands.1.freq, gainDB: bands.1.gainDB, q: bands.1.q, sr: sr)
        f2.peaking(bands.2.freq, gainDB: bands.2.gainDB, q: bands.2.q, sr: sr)
        f3.peaking(bands.3.freq, gainDB: bands.3.gainDB, q: bands.3.q, sr: sr)
    }

    @inline(__always) func process(_ x: Float) -> Float {
        f3.process(f2.process(f1.process(f0.process(x))))
    }
}

// MARK: - Kompresör (feed-forward, yavaş attack)

final class Compressor {
    struct Params {
        var thresholdDB: Float = -18
        var ratio: Float = 2
        var attackMs: Float = 15
        var releaseMs: Float = 100
        var makeupDB: Float = 0
    }
    var p = Params() { didSet { dirty = true } }

    private var dirty = true
    private let sr: Float
    private var atk: Float = 0, rel: Float = 0
    private var thr: Float = -18, slope: Float = 0.5, makeup: Float = 0
    private var env: Float = 0

    init(sr: Float) { self.sr = sr }

    func refresh() {
        guard dirty else { return }
        dirty = false
        atk = expf(-1 / (max(p.attackMs, 0.1) * 0.001 * sr))
        rel = expf(-1 / (max(p.releaseMs, 1) * 0.001 * sr))
        thr = p.thresholdDB
        slope = 1 - 1 / max(p.ratio, 1)
        makeup = p.makeupDB
    }

    @inline(__always) func process(_ x: Float) -> Float {
        let a = abs(x)
        let c = a > env ? atk : rel
        env = a + c * (env - a)
        let over = 20 * log10f(max(env, 1e-6)) - thr
        let gr = over > 0 ? over * slope : 0
        return x * dbToLin(makeup - gr)
    }
}

// MARK: - Reverb (Freeverb tabanlı, decay süresi RT60 ile ayarlanır)

private struct Comb {
    let buf: UnsafeMutablePointer<Float>
    let size: Int
    var idx = 0
    var lp: Float = 0
    var fb: Float = 0.8
    let damp: Float = 0.3

    init(size: Int) {
        self.size = size
        buf = .allocate(capacity: size)
        buf.initialize(repeating: 0, count: size)
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = buf[idx]
        lp = y * (1 - damp) + lp * damp
        buf[idx] = x + lp * fb
        idx += 1; if idx == size { idx = 0 }
        return y
    }
}

private struct Allpass {
    let buf: UnsafeMutablePointer<Float>
    let size: Int
    var idx = 0

    init(size: Int) {
        self.size = size
        buf = .allocate(capacity: size)
        buf.initialize(repeating: 0, count: size)
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let b = buf[idx]
        buf[idx] = x + b * 0.5
        idx += 1; if idx == size { idx = 0 }
        return b - x
    }
}

final class Reverb {
    struct Params {
        var decaySec: Float = 1.0
        var preDelayMs: Float = 10
        var mix: Float = 0.15
    }
    var p = Params() { didSet { dirty = true } }

    private var dirty = true
    private let sr: Float
    private let combs: UnsafeMutablePointer<Comb>
    private let aps: UnsafeMutablePointer<Allpass>
    private let pre: UnsafeMutablePointer<Float>
    private let preSize: Int
    private var preIdx = 0, preDelay = 0
    private var mix: Float = 0.15
    private var hp = Biquad(), lp = Biquad() // reverb girişi: 200 Hz HP, 7 kHz LP

    init(sr: Float) {
        self.sr = sr
        let k = sr / 44100
        let combLens = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let apLens = [556, 441, 341, 225]
        combs = .allocate(capacity: 8)
        aps = .allocate(capacity: 4)
        preSize = Int(sr * 0.06) + 1
        pre = .allocate(capacity: preSize)
        pre.initialize(repeating: 0, count: preSize)
        for i in 0..<8 { (combs + i).initialize(to: Comb(size: Int(Float(combLens[i]) * k))) }
        for i in 0..<4 { (aps + i).initialize(to: Allpass(size: Int(Float(apLens[i]) * k))) }
        hp.highpass(200, sr: sr)
        lp.lowpass(7000, sr: sr)
    }

    deinit {
        for i in 0..<8 { combs[i].buf.deallocate() }
        for i in 0..<4 { aps[i].buf.deallocate() }
        combs.deallocate(); aps.deallocate(); pre.deallocate()
    }

    func refresh() {
        guard dirty else { return }
        dirty = false
        let d = max(p.decaySec, 0.1)
        for i in 0..<8 { combs[i].fb = powf(10, -3 * Float(combs[i].size) / (d * sr)) }
        preDelay = min(Int(p.preDelayMs * 0.001 * sr), preSize - 1)
        mix = p.mix
    }

    /// dry geciktirilmez; wet ayrı yoldan eklenir
    @inline(__always) func process(_ x: Float) -> Float {
        pre[preIdx] = x
        var r = preIdx - preDelay
        if r < 0 { r += preSize }
        preIdx += 1; if preIdx == preSize { preIdx = 0 }

        let v = lp.process(hp.process(pre[r])) * 0.15
        var w: Float = 0
        for i in 0..<8 { w += combs[i].process(v) }
        for i in 0..<4 { w = aps[i].process(w) }
        return x + w * mix
    }
}

// MARK: - Çıkış limiter (anlık attack, güvenlik amaçlı)

final class Limiter {
    var ceilingDB: Float = -1 { didSet { dirty = true } }

    private var dirty = true
    private let rel: Float
    private var ceil: Float = 0.89
    private var g: Float = 1

    init(sr: Float) { rel = expf(-1 / (0.1 * sr)) }

    func refresh() {
        guard dirty else { return }
        dirty = false
        ceil = dbToLin(ceilingDB)
    }

    @inline(__always) func process(_ x: Float) -> Float {
        let a = abs(x)
        let t: Float = a > ceil ? ceil / a : 1
        g = t < g ? t : t + rel * (g - t)
        return max(-1, min(1, x * g))
    }
}

// MARK: - Zincir

final class FXChain {
    var inputGainDB: Float = 0 { didSet { inGain = dbToLin(inputGainDB) } }
    var highPassHz: Float = 70 { didSet { hpDirty = true } }
    private(set) var inputPeak: Float = 0 // 0...1, arayüzde peak göstergesi için

    let gate: Gate
    let eq: EQ
    let comp: Compressor
    let reverb: Reverb
    let limiter: Limiter

    private let sr: Float
    private var inGain: Float = 1
    private var hp = Biquad()
    private var hpDirty = true

    init(sampleRate: Float) {
        sr = sampleRate
        gate = Gate(sr: sampleRate)
        eq = EQ(sr: sampleRate)
        comp = Compressor(sr: sampleRate)
        reverb = Reverb(sr: sampleRate)
        limiter = Limiter(sr: sampleRate)
    }

    /// Mono buffer üzerinde yerinde işler.
    func process(_ buf: UnsafeMutablePointer<Float>, count n: Int) {
        if hpDirty { hpDirty = false; hp.highpass(highPassHz, sr: sr) }
        gate.refresh(); eq.refresh(); comp.refresh(); reverb.refresh(); limiter.refresh()

        var peak: Float = 0
        for i in 0..<n {
            var x = buf[i] * inGain
            peak = max(peak, abs(x))
            x = hp.process(x)
            x = gate.process(x)
            x = eq.process(x)
            x = comp.process(x)
            x = reverb.process(x)
            buf[i] = limiter.process(x)
        }
        inputPeak = max(peak, inputPeak * 0.9)
    }
}
