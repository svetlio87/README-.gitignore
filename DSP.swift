import Foundation
import os

// MARK: - Math & Smooth Parameter Helpers

@inline(__always) func dbToLin(_ db: Float) -> Float { powf(10, db / 20) }
@inline(__always) func linToDb(_ lin: Float) -> Float { 20 * log10f(max(lin, 1e-4)) }
@inline(__always) func clampF(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(hi, max(lo, v)) }
@inline(__always) func flushDenormal(_ x: Float) -> Float { abs(x) < 1e-20 ? 0 : x }

struct SmoothFloat {
    private(set) var current: Float
    var target: Float
    private let alpha: Float

    init(_ value: Float = 0, alpha: Float = 0.0025) {
        self.current = value
        self.target = value
        self.alpha = alpha
    }

    @inline(__always) mutating func next() -> Float {
        current += (target - current) * alpha
        return current
    }
}

// MARK: - Parameter & Preset Types

enum InputChannelMode: String, CaseIterable, Codable {
    case in1 = "In 1"
    case in2 = "In 2"
    case stereo = "Stereo"
}

enum EQBandType: String, CaseIterable, Codable {
    case bell = "Bell"
    case lowShelf = "L-Shf"
    case highShelf = "H-Shf"
    case highPass = "L-Cut"
    case lowPass = "H-Cut"
}

struct EQBandParams: Codable, Equatable {
    var isEnabled: Bool = true
    var type: EQBandType = .bell
    var freq: Float
    var gainDb: Float = 0
    var q: Float = 1.0
}

enum DelayMode: String, CaseIterable, Codable {
    case stereo = "Stereo"
    case pingPong = "Ping-Pong"
    case tape = "Tape"
    case analog = "Analog"
}

enum DelayDivision: String, CaseIterable, Codable {
    case quarter = "1/4"
    case dottedEighth = "1/8D"
    case eighth = "1/8"
    case tripletEighth = "1/8T"
    case sixteenth = "1/16"

    var beats: Float {
        switch self {
        case .quarter: return 1.0
        case .dottedEighth: return 0.75
        case .eighth: return 0.5
        case .tripletEighth: return 1.0 / 3.0
        case .sixteenth: return 0.25
        }
    }
}

enum ReverbMode: String, CaseIterable, Codable {
    case hall = "Hall"
    case room = "Room"
    case plate = "Plate"
    case chamber = "Chamber"
}

struct EnsembleVoiceParams: Codable, Equatable {
    var isActive: Bool
    var octave: Int
    var volume: Float
    var pan: Float
    var hpfHz: Float
    var bowEqDb: Float
}

struct EnsembleParams: Codable, Equatable {
    var enabled: Bool = false
    var mix: Float = 0.35
    var levelDb: Float = 0
    var detuneCents: Float = 10.0
    var stereoWidth: Float = 0.8
    var presetName: String = "Solo + Wide"
    var voices: [EnsembleVoiceParams] = EnsembleParams.presetVoices("Solo + Wide")

    static func presetVoices(_ name: String) -> [EnsembleVoiceParams] {
        switch name {
        case "Lush Tutti":
            return [
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.85, pan: -0.85, hpfHz: 150, bowEqDb: 1.0),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.85, pan: 0.85, hpfHz: 150, bowEqDb: 1.0),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.78, pan: -0.45, hpfHz: 180, bowEqDb: 1.5),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.78, pan: 0.45, hpfHz: 180, bowEqDb: 1.5),
                EnsembleVoiceParams(isActive: true, octave: -12, volume: 0.65, pan: -0.25, hpfHz: 110, bowEqDb: -1.0),
                EnsembleVoiceParams(isActive: true, octave: -12, volume: 0.65, pan: 0.25, hpfHz: 110, bowEqDb: -1.0)
            ]
        case "Octave Shimmer":
            return [
                EnsembleVoiceParams(isActive: true, octave: -12, volume: 0.7, pan: -0.6, hpfHz: 100, bowEqDb: -0.5),
                EnsembleVoiceParams(isActive: true, octave: -12, volume: 0.7, pan: 0.6, hpfHz: 100, bowEqDb: -0.5),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.85, pan: -0.35, hpfHz: 160, bowEqDb: 1.5),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.85, pan: 0.35, hpfHz: 160, bowEqDb: 1.5),
                EnsembleVoiceParams(isActive: true, octave: 12, volume: 0.55, pan: -0.85, hpfHz: 260, bowEqDb: 2.0),
                EnsembleVoiceParams(isActive: true, octave: 12, volume: 0.55, pan: 0.85, hpfHz: 260, bowEqDb: 2.0)
            ]
        default:
            return [
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.9, pan: -0.55, hpfHz: 160, bowEqDb: 1.0),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.9, pan: 0.55, hpfHz: 160, bowEqDb: 1.0),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.75, pan: -0.25, hpfHz: 180, bowEqDb: 0.5),
                EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.75, pan: 0.25, hpfHz: 180, bowEqDb: 0.5),
                EnsembleVoiceParams(isActive: false, octave: -12, volume: 0.65, pan: -0.75, hpfHz: 110, bowEqDb: 0.0),
                EnsembleVoiceParams(isActive: false, octave: 12, volume: 0.55, pan: 0.75, hpfHz: 240, bowEqDb: 1.5)
            ]
        }
    }
}

struct EngineParams: Codable, Equatable {
    var bufferSize: Int = 64
    var gainDb: Float = 0
    var masterDb: Float = 0
    var muted: Bool = false

    // Gate
    var gateOn: Bool = false
    var gateThreshDb: Float = -50
    var gateHystDb: Float = 4
    var gateAttackMs: Float = 0.5
    var gateHoldMs: Float = 30
    var gateReleaseMs: Float = 100
    var gateLevelDb: Float = 0

    // S-Man EQ
    var eqOn: Bool = true
    var hpfHz: Float = 70
    var eqLevelDb: Float = 0
    var eqBands: [EQBandParams] = [
        EQBandParams(isEnabled: true, type: .lowShelf, freq: 90, gainDb: 0, q: 0.707),
        EQBandParams(isEnabled: true, type: .bell, freq: 250, gainDb: 0, q: 1.0),
        EQBandParams(isEnabled: true, type: .bell, freq: 800, gainDb: 0, q: 1.0),
        EQBandParams(isEnabled: true, type: .bell, freq: 2200, gainDb: 0, q: 1.0),
        EQBandParams(isEnabled: true, type: .bell, freq: 5000, gainDb: 0, q: 1.0),
        EQBandParams(isEnabled: true, type: .highShelf, freq: 10000, gainDb: 0, q: 0.707)
    ]

    // Compressor
    var compOn: Bool = true
    var compThreshDb: Float = -18
    var compRatio: Float = 2
    var compAttackMs: Float = 15
    var compReleaseMs: Float = 100
    var compMakeupDb: Float = 0
    var compLevelDb: Float = 0

    // Saturation
    var satOn: Bool = false
    var cabSimOn: Bool = false
    var satDriveDb: Float = 6
    var satWarmth: Float = 0.4
    var satToneHz: Float = 9000
    var satMix: Float = 0.5
    var satLevelDb: Float = 0

    // Tape
    var tapeOn: Bool = false
    var tapeDriveDb: Float = 3
    var tapeBumpDb: Float = 1.5
    var tapeToneHz: Float = 12000
    var tapeFlutter: Float = 0.15
    var tapeMix: Float = 1.0
    var tapeLevelDb: Float = 0

    // Delay + Wet EQ + Volume
    var delayOn: Bool = false
    var delayMode: DelayMode = .stereo
    var delaySync: Bool = false
    var delayTimeMs: Float = 280
    var delayBpm: Float = 120
    var delayDivision: DelayDivision = .eighth
    var delayFeedback: Float = 0.3
    var delayLowCutHz: Float = 150
    var delayHighCutHz: Float = 6500
    var delayEqLowDb: Float = 0
    var delayEqMidDb: Float = 0
    var delayEqHighDb: Float = 0
    var delayModWidth: Float = 0.35
    var delayMix: Float = 0.2
    var delayLevelDb: Float = 0

    var effectiveDelayMs: Float {
        if delaySync {
            let ms = (60000.0 / max(delayBpm, 40)) * delayDivision.beats
            return clampF(ms, 20, 1500)
        }
        return clampF(delayTimeMs, 20, 1500)
    }

    // Reverb + Wet EQ + Volume
    var revOn: Bool = true
    var revMode: ReverbMode = .hall
    var revSize: Float = 0.55
    var revDecaySec: Float = 1.2
    var revPreDelayMs: Float = 12
    var revDampingHz: Float = 7000
    var revLowCutHz: Float = 180
    var revEqLowDb: Float = 0
    var revEqMidDb: Float = 0
    var revEqHighDb: Float = 0
    var revWidth: Float = 0.8
    var revMix: Float = 0.18
    var revLevelDb: Float = 0

    // Limiter
    var limiterCeilingDb: Float = -1
    var limiterLevelDb: Float = 0

    // Ensemble
    var ensemble: EnsembleParams = EnsembleParams()
}

struct EnginePreset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var params: EngineParams
}

// MARK: - BiquadFilter (Audio + Curve Display)

struct BiquadFilter {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    init() {}

    mutating func reset() { z1 = 0; z2 = 0 }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = flushDenormal(b1 * x - a1 * y + z2)
        z2 = flushDenormal(b2 * x - a2 * y)
        return y
    }

    private mutating func set(_ nb0: Double, _ nb1: Double, _ nb2: Double,
                              _ a0: Double, _ na1: Double, _ na2: Double) {
        b0 = Float(nb0 / a0)
        b1 = Float(nb1 / a0)
        b2 = Float(nb2 / a0)
        a1 = Float(na1 / a0)
        a2 = Float(na2 / a0)
    }

    mutating func configure(type: EQBandType, sampleRate: Float, freq: Float, gainDb: Float, q: Float) {
        let sr = Double(max(sampleRate, 8000))
        let f = Double(clampF(freq, 20, Float(sr * 0.45)))
        let qv = Double(clampF(q, 0.1, 20))
        let w = 2.0 * Double.pi * f / sr
        let cs = cos(w)
        let sn = sin(w)
        let alpha = sn / (2.0 * qv)
        let A = pow(10.0, Double(gainDb) / 40.0)

        switch type {
        case .bell:
            set(1 + alpha * A, -2 * cs, 1 - alpha * A,
                1 + alpha / A, -2 * cs, 1 - alpha / A)
        case .highPass:
            set((1 + cs) / 2, -(1 + cs), (1 + cs) / 2,
                1 + alpha, -2 * cs, 1 - alpha)
        case .lowPass:
            set((1 - cs) / 2, 1 - cs, (1 - cs) / 2,
                1 + alpha, -2 * cs, 1 - alpha)
        case .lowShelf:
            let beta = sqrt(A) * sn / qv
            set(A * ((A + 1) - (A - 1) * cs + beta),
                2 * A * ((A - 1) - (A + 1) * cs),
                A * ((A + 1) - (A - 1) * cs - beta),
                (A + 1) + (A - 1) * cs + beta,
                -2 * ((A - 1) + (A + 1) * cs),
                (A + 1) + (A - 1) * cs - beta)
        case .highShelf:
            let beta = sqrt(A) * sn / qv
            set(A * ((A + 1) + (A - 1) * cs + beta),
                -2 * A * ((A - 1) + (A + 1) * cs),
                A * ((A + 1) + (A - 1) * cs - beta),
                (A + 1) - (A - 1) * cs + beta,
                2 * ((A - 1) - (A + 1) * cs),
                (A + 1) - (A - 1) * cs - beta)
        }
    }

    func magnitudeDb(at freq: Float, sampleRate: Float) -> Float {
        let sr = Double(max(sampleRate, 8000))
        let w = 2.0 * Double.pi * Double(freq) / sr
        let cw = cos(w), sw = sin(w)
        let c2w = cos(2 * w), s2w = sin(2 * w)

        let numRe = Double(b0) + Double(b1) * cw + Double(b2) * c2w
        let numIm = -(Double(b1) * sw + Double(b2) * s2w)
        let denRe = 1.0 + Double(a1) * cw + Double(a2) * c2w
        let denIm = -(Double(a1) * sw + Double(a2) * s2w)

        let numSq = numRe * numRe + numIm * numIm
        let denSq = max(denRe * denRe + denIm * denIm, 1e-18)
        return Float(10.0 * log10(max(numSq / denSq, 1e-12)))
    }
}

// MARK: - Lock-Free Audio Config Snapshot (Value Types Only)

struct DSPConfig {
    var inputMode: InputChannelMode = .in1
    var spectrumActive: Bool = false
    var gainDb: Float = 0
    var masterDb: Float = 0
    var muted: Bool = false

    var gateOn: Bool = false
    var gateThreshDb: Float = -50
    var gateHystDb: Float = 4
    var gateAttackMs: Float = 0.5
    var gateHoldMs: Float = 30
    var gateReleaseMs: Float = 100
    var gateLevelDb: Float = 0

    var eqOn: Bool = true
    var hpfHz: Float = 70
    var eqLevelDb: Float = 0
    var band0 = EQBandParams(isEnabled: true, type: .lowShelf, freq: 90, gainDb: 0, q: 0.707)
    var band1 = EQBandParams(isEnabled: true, type: .bell, freq: 250, gainDb: 0, q: 1.0)
    var band2 = EQBandParams(isEnabled: true, type: .bell, freq: 800, gainDb: 0, q: 1.0)
    var band3 = EQBandParams(isEnabled: true, type: .bell, freq: 2200, gainDb: 0, q: 1.0)
    var band4 = EQBandParams(isEnabled: true, type: .bell, freq: 5000, gainDb: 0, q: 1.0)
    var band5 = EQBandParams(isEnabled: true, type: .highShelf, freq: 10000, gainDb: 0, q: 0.707)

    var compOn: Bool = true
    var compThreshDb: Float = -18
    var compRatio: Float = 2
    var compAttackMs: Float = 15
    var compReleaseMs: Float = 100
    var compMakeupDb: Float = 0
    var compLevelDb: Float = 0

    var satOn: Bool = false
    var cabSimOn: Bool = false
    var satDriveDb: Float = 6
    var satWarmth: Float = 0.4
    var satToneHz: Float = 9000
    var satMix: Float = 0.5
    var satLevelDb: Float = 0

    var tapeOn: Bool = false
    var tapeDriveDb: Float = 3
    var tapeBumpDb: Float = 1.5
    var tapeToneHz: Float = 12000
    var tapeFlutter: Float = 0.15
    var tapeMix: Float = 1.0
    var tapeLevelDb: Float = 0

    var delayOn: Bool = false
    var delayMode: DelayMode = .stereo
    var effectiveDelayMs: Float = 280
    var delayFeedback: Float = 0.3
    var delayLowCutHz: Float = 150
    var delayHighCutHz: Float = 6500
    var delayEqLowDb: Float = 0
    var delayEqMidDb: Float = 0
    var delayEqHighDb: Float = 0
    var delayModWidth: Float = 0.35
    var delayMix: Float = 0.2
    var delayLevelDb: Float = 0

    var revOn: Bool = true
    var revMode: ReverbMode = .hall
    var revSize: Float = 0.55
    var revDecaySec: Float = 1.2
    var revPreDelayMs: Float = 12
    var revDampingHz: Float = 7000
    var revLowCutHz: Float = 180
    var revEqLowDb: Float = 0
    var revEqMidDb: Float = 0
    var revEqHighDb: Float = 0
    var revWidth: Float = 0.8
    var revMix: Float = 0.18
    var revLevelDb: Float = 0

    var limiterCeilingDb: Float = -1
    var limiterLevelDb: Float = 0

    var ensembleEnabled: Bool = false
    var ensembleMix: Float = 0.35
    var ensembleLevelDb: Float = 0
    var ensembleDetuneCents: Float = 10
    var ensembleStereoWidth: Float = 0.8
    var voice0 = EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.9, pan: -0.55, hpfHz: 160, bowEqDb: 1.0)
    var voice1 = EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.9, pan: 0.55, hpfHz: 160, bowEqDb: 1.0)
    var voice2 = EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.75, pan: -0.25, hpfHz: 180, bowEqDb: 0.5)
    var voice3 = EnsembleVoiceParams(isActive: true, octave: 0, volume: 0.75, pan: 0.25, hpfHz: 180, bowEqDb: 0.5)
    var voice4 = EnsembleVoiceParams(isActive: false, octave: -12, volume: 0.65, pan: -0.75, hpfHz: 110, bowEqDb: 0.0)
    var voice5 = EnsembleVoiceParams(isActive: false, octave: 12, volume: 0.55, pan: 0.75, hpfHz: 240, bowEqDb: 1.5)

    init() {}

    init(from p: EngineParams, inputMode: InputChannelMode, spectrumActive: Bool) {
        self.inputMode = inputMode
        self.spectrumActive = spectrumActive
        self.gainDb = p.gainDb
        self.masterDb = p.masterDb
        self.muted = p.muted

        self.gateOn = p.gateOn
        self.gateThreshDb = p.gateThreshDb
        self.gateHystDb = p.gateHystDb
        self.gateAttackMs = p.gateAttackMs
        self.gateHoldMs = p.gateHoldMs
        self.gateReleaseMs = p.gateReleaseMs
        self.gateLevelDb = p.gateLevelDb

        self.eqOn = p.eqOn
        self.hpfHz = p.hpfHz
        self.eqLevelDb = p.eqLevelDb
        if p.eqBands.count > 0 { band0 = p.eqBands[0] }
        if p.eqBands.count > 1 { band1 = p.eqBands[1] }
        if p.eqBands.count > 2 { band2 = p.eqBands[2] }
        if p.eqBands.count > 3 { band3 = p.eqBands[3] }
        if p.eqBands.count > 4 { band4 = p.eqBands[4] }
        if p.eqBands.count > 5 { band5 = p.eqBands[5] }

        self.compOn = p.compOn
        self.compThreshDb = p.compThreshDb
        self.compRatio = p.compRatio
        self.compAttackMs = p.compAttackMs
        self.compReleaseMs = p.compReleaseMs
        self.compMakeupDb = p.compMakeupDb
        self.compLevelDb = p.compLevelDb

        self.satOn = p.satOn
        self.cabSimOn = p.cabSimOn
        self.satDriveDb = p.satDriveDb
        self.satWarmth = p.satWarmth
        self.satToneHz = p.satToneHz
        self.satMix = p.satMix
        self.satLevelDb = p.satLevelDb

        self.tapeOn = p.tapeOn
        self.tapeDriveDb = p.tapeDriveDb
        self.tapeBumpDb = p.tapeBumpDb
        self.tapeToneHz = p.tapeToneHz
        self.tapeFlutter = p.tapeFlutter
        self.tapeMix = p.tapeMix
        self.tapeLevelDb = p.tapeLevelDb

        self.delayOn = p.delayOn
        self.delayMode = p.delayMode
        self.effectiveDelayMs = p.effectiveDelayMs
        self.delayFeedback = p.delayFeedback
        self.delayLowCutHz = p.delayLowCutHz
        self.delayHighCutHz = p.delayHighCutHz
        self.delayEqLowDb = p.delayEqLowDb
        self.delayEqMidDb = p.delayEqMidDb
        self.delayEqHighDb = p.delayEqHighDb
        self.delayModWidth = p.delayModWidth
        self.delayMix = p.delayMix
        self.delayLevelDb = p.delayLevelDb

        self.revOn = p.revOn
        self.revMode = p.revMode
        self.revSize = p.revSize
        self.revDecaySec = p.revDecaySec
        self.revPreDelayMs = p.revPreDelayMs
        self.revDampingHz = p.revDampingHz
        self.revLowCutHz = p.revLowCutHz
        self.revEqLowDb = p.revEqLowDb
        self.revEqMidDb = p.revEqMidDb
        self.revEqHighDb = p.revEqHighDb
        self.revWidth = p.revWidth
        self.revMix = p.revMix
        self.revLevelDb = p.revLevelDb

        self.limiterCeilingDb = p.limiterCeilingDb
        self.limiterLevelDb = p.limiterLevelDb

        self.ensembleEnabled = p.ensemble.enabled
        self.ensembleMix = p.ensemble.mix
        self.ensembleLevelDb = p.ensemble.levelDb
        self.ensembleDetuneCents = p.ensemble.detuneCents
        self.ensembleStereoWidth = p.ensemble.stereoWidth
        let v = p.ensemble.voices
        if v.count > 0 { voice0 = v[0] }
        if v.count > 1 { voice1 = v[1] }
        if v.count > 2 { voice2 = v[2] }
        if v.count > 3 { voice3 = v[3] }
        if v.count > 4 { voice4 = v[4] }
        if v.count > 5 { voice5 = v[5] }
    }
}

// MARK: - Stereo Gate

private final class StereoGate {
    private let sr: Float
    private let detDecay: Float
    private var openLin: Float = 0, closeLin: Float = 0
    private var atk: Float = 0, rel: Float = 0
    private var holdSamples = 0, holdLeft = 0
    private var env: Float = 0, gain: Float = 1
    private var levelSmooth = SmoothFloat(1)
    private(set) var isOpen = false

    init(sr: Float) {
        self.sr = sr
        detDecay = expf(-1 / (0.005 * sr))
    }

    func update(_ cfg: DSPConfig) {
        openLin = dbToLin(cfg.gateThreshDb)
        closeLin = dbToLin(cfg.gateThreshDb - cfg.gateHystDb)
        atk = expf(-1 / (max(cfg.gateAttackMs, 0.05) * 0.001 * sr))
        rel = expf(-1 / (max(cfg.gateReleaseMs, 1) * 0.001 * sr))
        holdSamples = Int(cfg.gateHoldMs * 0.001 * sr)
        levelSmooth.target = cfg.gateOn ? dbToLin(cfg.gateLevelDb) : 1
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float, enabled: Bool) {
        let lvl = levelSmooth.next()
        guard enabled else { isOpen = true; gain = 1; return }
        let a = max(abs(l), abs(r))
        env = flushDenormal(a > env ? a : env * detDecay)
        if isOpen {
            if env > closeLin { holdLeft = holdSamples }
            else if holdLeft > 0 { holdLeft -= 1 }
            else { isOpen = false }
        } else if env > openLin {
            isOpen = true
            holdLeft = holdSamples
        }
        let target: Float = isOpen ? 1 : 0
        let c = target > gain ? atk : rel
        gain = flushDenormal(target + c * (gain - target))
        let total = gain * lvl
        l *= total; r *= total
    }
}

// MARK: - 6-Band Stereo S-Man EQ

private final class StereoEQ {
    private let sr: Float
    private var hpfL = BiquadFilter(), hpfR = BiquadFilter()
    private var l0 = BiquadFilter(), l1 = BiquadFilter(), l2 = BiquadFilter(),
                l3 = BiquadFilter(), l4 = BiquadFilter(), l5 = BiquadFilter()
    private var r0 = BiquadFilter(), r1 = BiquadFilter(), r2 = BiquadFilter(),
                r3 = BiquadFilter(), r4 = BiquadFilter(), r5 = BiquadFilter()
    private var b0On = true, b1On = true, b2On = true, b3On = true, b4On = true, b5On = true
    private var eqOn = true
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) { self.sr = sr }

    func update(_ cfg: DSPConfig) {
        eqOn = cfg.eqOn
        levelSmooth.target = cfg.eqOn ? dbToLin(cfg.eqLevelDb) : 1
        hpfL.configure(type: .highPass, sampleRate: sr, freq: cfg.hpfHz, gainDb: 0, q: 0.707)
        hpfR.configure(type: .highPass, sampleRate: sr, freq: cfg.hpfHz, gainDb: 0, q: 0.707)
        b0On = cfg.band0.isEnabled; b1On = cfg.band1.isEnabled; b2On = cfg.band2.isEnabled
        b3On = cfg.band3.isEnabled; b4On = cfg.band4.isEnabled; b5On = cfg.band5.isEnabled

        l0.configure(type: cfg.band0.type, sampleRate: sr, freq: cfg.band0.freq, gainDb: cfg.band0.gainDb, q: cfg.band0.q)
        r0.configure(type: cfg.band0.type, sampleRate: sr, freq: cfg.band0.freq, gainDb: cfg.band0.gainDb, q: cfg.band0.q)
        l1.configure(type: cfg.band1.type, sampleRate: sr, freq: cfg.band1.freq, gainDb: cfg.band1.gainDb, q: cfg.band1.q)
        r1.configure(type: cfg.band1.type, sampleRate: sr, freq: cfg.band1.freq, gainDb: cfg.band1.gainDb, q: cfg.band1.q)
        l2.configure(type: cfg.band2.type, sampleRate: sr, freq: cfg.band2.freq, gainDb: cfg.band2.gainDb, q: cfg.band2.q)
        r2.configure(type: cfg.band2.type, sampleRate: sr, freq: cfg.band2.freq, gainDb: cfg.band2.gainDb, q: cfg.band2.q)
        l3.configure(type: cfg.band3.type, sampleRate: sr, freq: cfg.band3.freq, gainDb: cfg.band3.gainDb, q: cfg.band3.q)
        r3.configure(type: cfg.band3.type, sampleRate: sr, freq: cfg.band3.freq, gainDb: cfg.band3.gainDb, q: cfg.band3.q)
        l4.configure(type: cfg.band4.type, sampleRate: sr, freq: cfg.band4.freq, gainDb: cfg.band4.gainDb, q: cfg.band4.q)
        r4.configure(type: cfg.band4.type, sampleRate: sr, freq: cfg.band4.freq, gainDb: cfg.band4.gainDb, q: cfg.band4.q)
        l5.configure(type: cfg.band5.type, sampleRate: sr, freq: cfg.band5.freq, gainDb: cfg.band5.gainDb, q: cfg.band5.q)
        r5.configure(type: cfg.band5.type, sampleRate: sr, freq: cfg.band5.freq, gainDb: cfg.band5.gainDb, q: cfg.band5.q)
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let lvl = levelSmooth.next()
        l = hpfL.process(l)
        r = hpfR.process(r)
        guard eqOn else { return }
        if b0On { l = l0.process(l); r = r0.process(r) }
        if b1On { l = l1.process(l); r = r1.process(r) }
        if b2On { l = l2.process(l); r = r2.process(r) }
        if b3On { l = l3.process(l); r = r3.process(r) }
        if b4On { l = l4.process(l); r = r4.process(r) }
        if b5On { l = l5.process(l); r = r5.process(r) }
        l *= lvl; r *= lvl
    }
}

// MARK: - Stereo Compressor

private final class StereoCompressor {
    private let sr: Float
    private var atk: Float = 0, rel: Float = 0
    private var thr: Float = -18, slope: Float = 0.5, makeup: Float = 0
    private var levelSmooth = SmoothFloat(1)
    private var env: Float = 0
    private(set) var lastGrDb: Float = 0

    init(sr: Float) { self.sr = sr }

    func update(_ cfg: DSPConfig) {
        atk = expf(-1 / (max(cfg.compAttackMs, 0.1) * 0.001 * sr))
        rel = expf(-1 / (max(cfg.compReleaseMs, 1) * 0.001 * sr))
        thr = cfg.compThreshDb
        slope = 1 - 1 / max(cfg.compRatio, 1)
        makeup = cfg.compMakeupDb
        levelSmooth.target = cfg.compOn ? dbToLin(cfg.compLevelDb) : 1
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float, enabled: Bool) {
        let lvl = levelSmooth.next()
        guard enabled else { lastGrDb = 0; return }
        let a = max(abs(l), abs(r))
        let c = a > env ? atk : rel
        env = flushDenormal(a + c * (env - a))
        let over = 20 * log10f(max(env, 1e-6)) - thr
        let gr = over > 0 ? over * slope : 0
        lastGrDb = max(gr, lastGrDb * 0.999)
        let g = dbToLin(makeup - gr) * lvl
        l *= g; r *= g
    }
}

// MARK: - Saturation + Cab Sim

private final class StereoSaturation {
    private let sr: Float
    private var toneL = BiquadFilter(), toneR = BiquadFilter()
    private var cabHpL = BiquadFilter(), cabHpR = BiquadFilter()
    private var cabBodyL = BiquadFilter(), cabBodyR = BiquadFilter()
    private var cabLpL = BiquadFilter(), cabLpR = BiquadFilter()

    private var enabled = false
    private var cabOn = false
    private var driveLin: Float = 1
    private var warmth: Float = 0.4
    private var mixSmooth = SmoothFloat(0.5)
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) {
        self.sr = sr
        cabHpL.configure(type: .highPass, sampleRate: sr, freq: 95, gainDb: 0, q: 0.707)
        cabHpR.configure(type: .highPass, sampleRate: sr, freq: 95, gainDb: 0, q: 0.707)
        cabBodyL.configure(type: .bell, sampleRate: sr, freq: 240, gainDb: 2.5, q: 0.9)
        cabBodyR.configure(type: .bell, sampleRate: sr, freq: 240, gainDb: 2.5, q: 0.9)
        cabLpL.configure(type: .lowPass, sampleRate: sr, freq: 5200, gainDb: 0, q: 0.9)
        cabLpR.configure(type: .lowPass, sampleRate: sr, freq: 5200, gainDb: 0, q: 0.9)
    }

    func update(_ cfg: DSPConfig) {
        enabled = cfg.satOn
        cabOn = cfg.cabSimOn
        driveLin = dbToLin(cfg.satDriveDb)
        warmth = cfg.satWarmth
        mixSmooth.target = cfg.satMix
        levelSmooth.target = cfg.satOn ? dbToLin(cfg.satLevelDb) : 1
        toneL.configure(type: .lowPass, sampleRate: sr, freq: cfg.satToneHz, gainDb: 0, q: 0.707)
        toneR.configure(type: .lowPass, sampleRate: sr, freq: cfg.satToneHz, gainDb: 0, q: 0.707)
    }

    @inline(__always) private func shape(_ x: Float) -> Float {
        let bias = warmth * 0.25
        let d = x * driveLin
        let s = tanhf(d + bias) - tanhf(bias)
        return s / max(1, sqrtf(driveLin) * 0.7)
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let mix = mixSmooth.next()
        let lvl = levelSmooth.next()
        guard enabled else { return }
        let dryL = l, dryR = r
        var wL = toneL.process(shape(l))
        var wR = toneR.process(shape(r))
        if cabOn {
            wL = cabLpL.process(cabBodyL.process(cabHpL.process(wL)))
            wR = cabLpR.process(cabBodyR.process(cabHpR.process(wR)))
        }
        l = (dryL * (1 - mix) + wL * mix) * lvl
        r = (dryR * (1 - mix) + wR * mix) * lvl
    }
}

// MARK: - Analog Tape

private final class StereoTape {
    private let sr: Float
    private let bufL: UnsafeMutablePointer<Float>
    private let bufR: UnsafeMutablePointer<Float>
    private let bufSize = 2048
    private var idx = 0
    private var lfoPhase: Float = 0

    private var bumpL = BiquadFilter(), bumpR = BiquadFilter()
    private var toneL = BiquadFilter(), toneR = BiquadFilter()
    private var enabled = false
    private var driveLin: Float = 1
    private var flutter: Float = 0.15
    private var mixSmooth = SmoothFloat(1)
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) {
        self.sr = sr
        bufL = .allocate(capacity: bufSize); bufL.initialize(repeating: 0, count: bufSize)
        bufR = .allocate(capacity: bufSize); bufR.initialize(repeating: 0, count: bufSize)
    }

    deinit { bufL.deallocate(); bufR.deallocate() }

    func update(_ cfg: DSPConfig) {
        enabled = cfg.tapeOn
        driveLin = dbToLin(cfg.tapeDriveDb)
        flutter = cfg.tapeFlutter
        mixSmooth.target = cfg.tapeMix
        levelSmooth.target = cfg.tapeOn ? dbToLin(cfg.tapeLevelDb) : 1
        bumpL.configure(type: .lowShelf, sampleRate: sr, freq: 95, gainDb: cfg.tapeBumpDb, q: 0.707)
        bumpR.configure(type: .lowShelf, sampleRate: sr, freq: 95, gainDb: cfg.tapeBumpDb, q: 0.707)
        toneL.configure(type: .lowPass, sampleRate: sr, freq: cfg.tapeToneHz, gainDb: 0, q: 0.707)
        toneR.configure(type: .lowPass, sampleRate: sr, freq: cfg.tapeToneHz, gainDb: 0, q: 0.707)
    }

    @inline(__always) private func readInterp(_ buf: UnsafeMutablePointer<Float>, delay: Float) -> Float {
        let d = clampF(delay, 1, Float(bufSize - 3))
        let i0 = Int(d)
        let frac = d - Float(i0)
        let p0 = (idx - i0 + bufSize) % bufSize
        let p1 = (p0 - 1 + bufSize) % bufSize
        return buf[p0] * (1 - frac) + buf[p1] * frac
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let mix = mixSmooth.next()
        let lvl = levelSmooth.next()
        guard enabled else { return }
        let dryL = l, dryR = r
        var xL = tanhf(bumpL.process(l) * driveLin) / max(1, sqrtf(driveLin) * 0.85)
        var xR = tanhf(bumpR.process(r) * driveLin) / max(1, sqrtf(driveLin) * 0.85)
        xL = toneL.process(xL)
        xR = toneR.process(xR)

        bufL[idx] = xL
        bufR[idx] = xR

        lfoPhase += 2 * Float.pi * 3.8 / sr
        if lfoPhase > 2 * Float.pi { lfoPhase -= 2 * Float.pi }
        let modSamples = (1.5 + sinf(lfoPhase)) * flutter * (0.0015 * sr)
        let wetL: Float, wetR: Float
        if flutter > 0.005 {
            wetL = readInterp(bufL, delay: 4 + modSamples)
            wetR = readInterp(bufR, delay: 4 + modSamples * 0.92)
        } else {
            wetL = xL; wetR = xR
        }
        idx += 1; if idx == bufSize { idx = 0 }

        l = (dryL * (1 - mix) + wetL * mix) * lvl
        r = (dryR * (1 - mix) + wetR * mix) * lvl
    }
}

// MARK: - Stereo Delay + Dedicated 3-Band Wet EQ + Smooth Volume

private final class StereoDelay {
    private let sr: Float
    private let bufL: UnsafeMutablePointer<Float>
    private let bufR: UnsafeMutablePointer<Float>
    private let maxSamples: Int
    private var writeIdx = 0
    private var lfoPhase: Float = 0

    private var hpL = BiquadFilter(), hpR = BiquadFilter()
    private var lpL = BiquadFilter(), lpR = BiquadFilter()
    private var eqLowL = BiquadFilter(), eqLowR = BiquadFilter()
    private var eqMidL = BiquadFilter(), eqMidR = BiquadFilter()
    private var eqHighL = BiquadFilter(), eqHighR = BiquadFilter()

    private var enabled = false
    private var mode: DelayMode = .stereo
    private var delaySamples: Float = 13440
    private var feedback: Float = 0.3
    private var modWidth: Float = 0.35
    private var mixSmooth = SmoothFloat(0.2)
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) {
        self.sr = sr
        maxSamples = Int(sr * 2.0) + 16
        bufL = .allocate(capacity: maxSamples); bufL.initialize(repeating: 0, count: maxSamples)
        bufR = .allocate(capacity: maxSamples); bufR.initialize(repeating: 0, count: maxSamples)
    }

    deinit { bufL.deallocate(); bufR.deallocate() }

    func update(_ cfg: DSPConfig) {
        enabled = cfg.delayOn
        mode = cfg.delayMode
        delaySamples = clampF(cfg.effectiveDelayMs * 0.001 * sr, 10, Float(maxSamples - 8))
        feedback = clampF(cfg.delayFeedback, 0, 0.92)
        modWidth = cfg.delayModWidth
        mixSmooth.target = cfg.delayMix
        levelSmooth.target = cfg.delayOn ? dbToLin(cfg.delayLevelDb) : 1

        hpL.configure(type: .highPass, sampleRate: sr, freq: cfg.delayLowCutHz, gainDb: 0, q: 0.707)
        hpR.configure(type: .highPass, sampleRate: sr, freq: cfg.delayLowCutHz, gainDb: 0, q: 0.707)
        lpL.configure(type: .lowPass, sampleRate: sr, freq: cfg.delayHighCutHz, gainDb: 0, q: 0.707)
        lpR.configure(type: .lowPass, sampleRate: sr, freq: cfg.delayHighCutHz, gainDb: 0, q: 0.707)

        eqLowL.configure(type: .lowShelf, sampleRate: sr, freq: 160, gainDb: cfg.delayEqLowDb, q: 0.707)
        eqLowR.configure(type: .lowShelf, sampleRate: sr, freq: 160, gainDb: cfg.delayEqLowDb, q: 0.707)
        eqMidL.configure(type: .bell, sampleRate: sr, freq: 1000, gainDb: cfg.delayEqMidDb, q: 0.9)
        eqMidR.configure(type: .bell, sampleRate: sr, freq: 1000, gainDb: cfg.delayEqMidDb, q: 0.9)
        eqHighL.configure(type: .highShelf, sampleRate: sr, freq: 5500, gainDb: cfg.delayEqHighDb, q: 0.707)
        eqHighR.configure(type: .highShelf, sampleRate: sr, freq: 5500, gainDb: cfg.delayEqHighDb, q: 0.707)
    }

    @inline(__always) private func readTap(_ buf: UnsafeMutablePointer<Float>, delay: Float) -> Float {
        let d = clampF(delay, 1, Float(maxSamples - 4))
        let i0 = Int(d)
        let frac = d - Float(i0)
        var p0 = writeIdx - i0; if p0 < 0 { p0 += maxSamples }
        var p1 = p0 - 1; if p1 < 0 { p1 += maxSamples }
        return buf[p0] * (1 - frac) + buf[p1] * frac
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let wetGain = mixSmooth.next() * levelSmooth.next()
        guard enabled else { return }

        lfoPhase += 2 * Float.pi * 0.65 / sr
        if lfoPhase > 2 * Float.pi { lfoPhase -= 2 * Float.pi }
        let mod = sinf(lfoPhase) * modWidth * (0.0018 * sr)

        let tapL = readTap(bufL, delay: delaySamples + mod)
        let tapR = readTap(bufR, delay: delaySamples * (mode == .stereo ? (1 + modWidth * 0.03) : 1.0) - mod)

        var fbL = lpL.process(hpL.process(tapL))
        var fbR = lpR.process(hpR.process(tapR))
        if mode == .tape || mode == .analog {
            fbL = tanhf(fbL * 1.3) * 0.92
            fbR = tanhf(fbR * 1.3) * 0.92
        }

        if mode == .pingPong {
            let monoIn = (l + r) * 0.5
            bufL[writeIdx] = flushDenormal(monoIn + fbR * feedback)
            bufR[writeIdx] = flushDenormal(fbL * feedback)
        } else {
            bufL[writeIdx] = flushDenormal(l + fbL * feedback)
            bufR[writeIdx] = flushDenormal(r + fbR * feedback)
        }

        writeIdx += 1; if writeIdx == maxSamples { writeIdx = 0 }

        let wetL = eqHighL.process(eqMidL.process(eqLowL.process(fbL)))
        let wetR = eqHighR.process(eqMidR.process(eqLowR.process(fbR)))
        let mid = (wetL + wetR) * 0.5
        let side = (wetL - wetR) * 0.5 * (0.3 + modWidth * 0.7)
        l += (mid + side) * wetGain
        r += (mid - side) * wetGain
    }
}

// MARK: - Stereo Reverb + Dedicated 3-Band Wet EQ + Smooth Volume

private struct CombUnit {
    let buf: UnsafeMutablePointer<Float>
    let maxSize: Int
    var activeSize: Int
    var idx = 0
    var lp: Float = 0
    var fb: Float = 0.8
    var damp: Float = 0.3

    init(maxSize: Int) {
        self.maxSize = maxSize
        self.activeSize = maxSize
        buf = .allocate(capacity: maxSize)
        buf.initialize(repeating: 0, count: maxSize)
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = buf[idx]
        lp = flushDenormal(y * (1 - damp) + lp * damp)
        buf[idx] = flushDenormal(x + lp * fb)
        idx += 1; if idx >= activeSize { idx = 0 }
        return y
    }
}

private struct AllpassUnit {
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
        buf[idx] = flushDenormal(x + b * 0.5)
        idx += 1; if idx == size { idx = 0 }
        return b - x
    }
}

private final class StereoReverb {
    private let sr: Float
    private let combsL: UnsafeMutablePointer<CombUnit>
    private let combsR: UnsafeMutablePointer<CombUnit>
    private let apsL: UnsafeMutablePointer<AllpassUnit>
    private let apsR: UnsafeMutablePointer<AllpassUnit>
    private let preL: UnsafeMutablePointer<Float>
    private let preR: UnsafeMutablePointer<Float>
    private let preMaxSize: Int
    private var preIdx = 0, preDelaySamples = 0
    private let baseCombs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]

    private var hpL = BiquadFilter(), hpR = BiquadFilter()
    private var eqLowL = BiquadFilter(), eqLowR = BiquadFilter()
    private var eqMidL = BiquadFilter(), eqMidR = BiquadFilter()
    private var eqHighL = BiquadFilter(), eqHighR = BiquadFilter()

    private var enabled = true
    private var width: Float = 0.8
    private var mixSmooth = SmoothFloat(0.18)
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) {
        self.sr = sr
        let k = sr / 44100.0 * 1.35
        let apLens = [556, 441, 341, 225]
        combsL = .allocate(capacity: 8); combsR = .allocate(capacity: 8)
        apsL = .allocate(capacity: 4); apsR = .allocate(capacity: 4)
        preMaxSize = Int(sr * 0.15) + 8
        preL = .allocate(capacity: preMaxSize); preL.initialize(repeating: 0, count: preMaxSize)
        preR = .allocate(capacity: preMaxSize); preR.initialize(repeating: 0, count: preMaxSize)

        for i in 0..<8 {
            let maxC = Int(Float(baseCombs[i]) * k) + 64
            (combsL + i).initialize(to: CombUnit(maxSize: maxC))
            (combsR + i).initialize(to: CombUnit(maxSize: maxC + 23))
        }
        for i in 0..<4 {
            let sz = Int(Float(apLens[i]) * (sr / 44100.0))
            (apsL + i).initialize(to: AllpassUnit(size: max(16, sz)))
            (apsR + i).initialize(to: AllpassUnit(size: max(16, sz + 23)))
        }
    }

    deinit {
        for i in 0..<8 { combsL[i].buf.deallocate(); combsR[i].buf.deallocate() }
        for i in 0..<4 { apsL[i].buf.deallocate(); apsR[i].buf.deallocate() }
        combsL.deallocate(); combsR.deallocate(); apsL.deallocate(); apsR.deallocate()
        preL.deallocate(); preR.deallocate()
    }

    func update(_ cfg: DSPConfig) {
        enabled = cfg.revOn
        width = cfg.revWidth
        mixSmooth.target = cfg.revMix
        levelSmooth.target = cfg.revOn ? dbToLin(cfg.revLevelDb) : 1
        preDelaySamples = min(Int(cfg.revPreDelayMs * 0.001 * sr), preMaxSize - 2)

        hpL.configure(type: .highPass, sampleRate: sr, freq: cfg.revLowCutHz, gainDb: 0, q: 0.707)
        hpR.configure(type: .highPass, sampleRate: sr, freq: cfg.revLowCutHz, gainDb: 0, q: 0.707)

        eqLowL.configure(type: .lowShelf, sampleRate: sr, freq: 180, gainDb: cfg.revEqLowDb, q: 0.707)
        eqLowR.configure(type: .lowShelf, sampleRate: sr, freq: 180, gainDb: cfg.revEqLowDb, q: 0.707)
        eqMidL.configure(type: .bell, sampleRate: sr, freq: 1200, gainDb: cfg.revEqMidDb, q: 0.9)
        eqMidR.configure(type: .bell, sampleRate: sr, freq: 1200, gainDb: cfg.revEqMidDb, q: 0.9)
        eqHighL.configure(type: .highShelf, sampleRate: sr, freq: 6000, gainDb: cfg.revEqHighDb, q: 0.707)
        eqHighR.configure(type: .highShelf, sampleRate: sr, freq: 6000, gainDb: cfg.revEqHighDb, q: 0.707)

        let modeScale: Float
        let modeDampMul: Float
        switch cfg.revMode {
        case .hall: modeScale = 1.05; modeDampMul = 1.0
        case .room: modeScale = 0.62; modeDampMul = 0.85
        case .plate: modeScale = 0.85; modeDampMul = 1.25
        case .chamber: modeScale = 0.78; modeDampMul = 0.95
        }
        let sizeFactor = (0.45 + 0.75 * cfg.revSize) * modeScale * (sr / 44100.0)
        let d = max(cfg.revDecaySec, 0.2)
        let dampCoeff = clampF(1 - expf(-2 * Float.pi * clampF(cfg.revDampingHz * modeDampMul, 800, 18000) / sr), 0.05, 0.95)
        let damp = 1 - dampCoeff

        for i in 0..<8 {
            let szL = min(combsL[i].maxSize - 1, max(64, Int(Float(baseCombs[i]) * sizeFactor)))
            let szR = min(combsR[i].maxSize - 1, max(64, Int(Float(baseCombs[i] + 23) * sizeFactor)))
            combsL[i].activeSize = szL
            combsR[i].activeSize = szR
            if combsL[i].idx >= szL { combsL[i].idx = 0 }
            if combsR[i].idx >= szR { combsR[i].idx = 0 }
            combsL[i].fb = powf(10, -3 * Float(szL) / (d * sr))
            combsR[i].fb = powf(10, -3 * Float(szR) / (d * sr))
            combsL[i].damp = damp
            combsR[i].damp = damp
        }
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let wetGain = mixSmooth.next() * levelSmooth.next()
        guard enabled else { return }

        preL[preIdx] = hpL.process(l)
        preR[preIdx] = hpR.process(r)
        var rIdx = preIdx - preDelaySamples
        if rIdx < 0 { rIdx += preMaxSize }
        preIdx += 1; if preIdx == preMaxSize { preIdx = 0 }

        let inL = preL[rIdx] * 0.15
        let inR = preR[rIdx] * 0.15

        var wL: Float = 0, wR: Float = 0
        for i in 0..<8 {
            wL += combsL[i].process(inL)
            wR += combsR[i].process(inR)
        }
        for i in 0..<4 {
            wL = apsL[i].process(wL)
            wR = apsR[i].process(wR)
        }

        wL = eqHighL.process(eqMidL.process(eqLowL.process(wL)))
        wR = eqHighR.process(eqMidR.process(eqLowR.process(wR)))

        let mid = (wL + wR) * 0.5
        let side = (wL - wR) * 0.5 * width
        l += (mid + side) * wetGain
        r += (mid - side) * wetGain
    }
}

// MARK: - 6-Voice Violin Ensemble

private final class EnsembleVoiceDSP {
    private let sr: Float
    private let buf: UnsafeMutablePointer<Float>
    private let bufSize = 8192
    private var writeIdx = 0
    private var phase: Float = 0
    private var lfoPhase: Float = 0
    private var hpf = BiquadFilter()
    private var bowEq = BiquadFilter()

    private var active = false
    private var pitchRatio: Float = 1
    private var gainL: Float = 0, gainR: Float = 0
    private let windowSize: Float = 2048

    init(sr: Float, seedOffset: Float) {
        self.sr = sr
        self.lfoPhase = seedOffset
        buf = .allocate(capacity: bufSize); buf.initialize(repeating: 0, count: bufSize)
    }

    deinit { buf.deallocate() }

    func update(_ v: EnsembleVoiceParams, detuneCents: Float, stereoWidth: Float, voiceIndex: Int) {
        active = v.isActive
        let voiceOffset = (Float(voiceIndex) - 2.5) * 0.4
        let totalCents = Float(v.octave) * 100.0 + voiceOffset * detuneCents
        pitchRatio = powf(2.0, totalCents / 1200.0)

        let p = clampF(v.pan * stereoWidth, -1, 1)
        let angle = (p + 1) * 0.25 * Float.pi
        let normGain = v.volume * 0.42
        gainL = normGain * cosf(angle)
        gainR = normGain * sinf(angle)

        hpf.configure(type: .highPass, sampleRate: sr, freq: v.hpfHz, gainDb: 0, q: 0.707)
        bowEq.configure(type: .bell, sampleRate: sr, freq: 2800, gainDb: v.bowEqDb, q: 1.1)
    }

    @inline(__always) private func readFrac(_ delay: Float) -> Float {
        let d = clampF(delay, 1, Float(bufSize - 3))
        let i0 = Int(d)
        let frac = d - Float(i0)
        var p0 = writeIdx - i0; if p0 < 0 { p0 += bufSize }
        var p1 = p0 - 1; if p1 < 0 { p1 += bufSize }
        return buf[p0] * (1 - frac) + buf[p1] * frac
    }

    @inline(__always) func process(_ mono: Float, outL: inout Float, outR: inout Float) {
        guard active else { return }
        buf[writeIdx] = mono

        lfoPhase += 2 * Float.pi * 0.45 / sr
        if lfoPhase > 2 * Float.pi { lfoPhase -= 2 * Float.pi }

        var y: Float
        if abs(pitchRatio - 1.0) < 0.0005 {
            let chorusDelay: Float = 160 + sinf(lfoPhase) * 45
            y = readFrac(chorusDelay)
        } else {
            let phase2 = phase + 0.5
            let p2 = phase2 >= 1 ? phase2 - 1 : phase2
            let d1 = 4 + phase * windowSize
            let d2 = 4 + p2 * windowSize
            let w1 = 0.5 * (1 - cosf(2 * Float.pi * phase))
            let w2 = 1 - w1
            y = readFrac(d1) * w1 + readFrac(d2) * w2

            phase += (1.0 - pitchRatio) / windowSize
            while phase >= 1 { phase -= 1 }
            while phase < 0 { phase += 1 }
        }

        writeIdx += 1; if writeIdx == bufSize { writeIdx = 0 }

        y = bowEq.process(hpf.process(y))
        outL += y * gainL
        outR += y * gainR
    }
}

private final class StereoEnsemble {
    private let voices: [EnsembleVoiceDSP]
    private var enabled = false
    private var mixSmooth = SmoothFloat(0.35)
    private var levelSmooth = SmoothFloat(1)

    init(sr: Float) {
        voices = (0..<6).map { EnsembleVoiceDSP(sr: sr, seedOffset: Float($0) * 1.05) }
    }

    func update(_ cfg: DSPConfig) {
        enabled = cfg.ensembleEnabled
        mixSmooth.target = cfg.ensembleMix
        levelSmooth.target = cfg.ensembleEnabled ? dbToLin(cfg.ensembleLevelDb) : 1
        voices[0].update(cfg.voice0, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 0)
        voices[1].update(cfg.voice1, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 1)
        voices[2].update(cfg.voice2, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 2)
        voices[3].update(cfg.voice3, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 3)
        voices[4].update(cfg.voice4, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 4)
        voices[5].update(cfg.voice5, detuneCents: cfg.ensembleDetuneCents, stereoWidth: cfg.ensembleStereoWidth, voiceIndex: 5)
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let mix = mixSmooth.next()
        let lvl = levelSmooth.next()
        guard enabled else { return }
        let mono = (l + r) * 0.5
        var wL: Float = 0, wR: Float = 0
        for v in voices { v.process(mono, outL: &wL, outR: &wR) }
        let dry = 1 - mix * 0.45
        l = l * dry + wL * mix * lvl
        r = r * dry + wR * mix * lvl
    }
}

// MARK: - Lookahead Brickwall Limiter

private final class StereoLimiter {
    private let lookBufL: UnsafeMutablePointer<Float>
    private let lookBufR: UnsafeMutablePointer<Float>
    private let delayLen: Int
    private var idx = 0
    private let rel: Float
    private var ceil: Float = 0.89
    private var levelSmooth = SmoothFloat(1)
    private var g: Float = 1
    private(set) var lastGrDb: Float = 0

    init(sr: Float) {
        delayLen = max(8, Int(0.0015 * sr))
        lookBufL = .allocate(capacity: delayLen); lookBufL.initialize(repeating: 0, count: delayLen)
        lookBufR = .allocate(capacity: delayLen); lookBufR.initialize(repeating: 0, count: delayLen)
        rel = expf(-1 / (0.1 * sr))
    }

    deinit { lookBufL.deallocate(); lookBufR.deallocate() }

    func update(_ cfg: DSPConfig) {
        ceil = dbToLin(cfg.limiterCeilingDb)
        levelSmooth.target = dbToLin(cfg.limiterLevelDb)
    }

    @inline(__always) func process(_ l: inout Float, _ r: inout Float) {
        let lvl = levelSmooth.next()
        let dL = lookBufL[idx], dR = lookBufR[idx]
        lookBufL[idx] = l * lvl
        lookBufR[idx] = r * lvl
        idx += 1; if idx == delayLen { idx = 0 }

        let a = max(max(abs(l * lvl), abs(r * lvl)), max(abs(dL), abs(dR)))
        let t: Float = a > ceil ? ceil / a : 1
        g = flushDenormal(t < g ? g * 0.75 + t * 0.25 : t + rel * (g - t))
        let gr = max(0, -20 * log10f(max(g, 1e-6)))
        lastGrDb = max(gr, lastGrDb * 0.999)

        l = clampF(dL * g, -1, 1)
        r = clampF(dR * g, -1, 1)
    }
}

// MARK: - 24-Band Logarithmic Spectrum Analyzer (Runs Only When EQ View Is Open)

private struct BandpassState {
    var b0: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0
    var env: Float = 0
}

private final class SpectrumAnalyzer {
    static let bandCount = 24
    private let bands: UnsafeMutablePointer<BandpassState>
    private let decay: Float

    init(sr: Float) {
        bands = .allocate(capacity: SpectrumAnalyzer.bandCount)
        decay = expf(-1 / (0.11 * sr))
        for i in 0..<SpectrumAnalyzer.bandCount {
            let frac = (Float(i) + 0.5) / Float(SpectrumAnalyzer.bandCount)
            let freq = min(sr * 0.45, 20.0 * powf(1000.0, frac))
            let w = 2.0 * Float.pi * freq / sr
            let cs = cosf(w)
            let alpha = sinf(w) / (2.0 * 3.2)
            let a0 = 1.0 + alpha
            let st = BandpassState(
                b0: alpha / a0,
                b2: -alpha / a0,
                a1: -2.0 * cs / a0,
                a2: (1.0 - alpha) / a0,
                z1: 0, z2: 0, env: 0
            )
            (bands + i).initialize(to: st)
        }
    }

    deinit {
        bands.deinitialize(count: SpectrumAnalyzer.bandCount)
        bands.deallocate()
    }

    @inline(__always) func process(_ x: Float) {
        for i in 0..<SpectrumAnalyzer.bandCount {
            var b = bands[i]
            let y = b.b0 * x + b.z1
            b.z1 = flushDenormal(-b.a1 * y + b.z2)
            b.z2 = flushDenormal(b.b2 * x - b.a2 * y)
            let a = abs(y)
            b.env = flushDenormal(a > b.env ? a : b.env * decay)
            bands[i] = b
        }
    }

    func copyNormalized(into out: inout [Float]) {
        if out.count != SpectrumAnalyzer.bandCount {
            out = Array(repeating: 0, count: SpectrumAnalyzer.bandCount)
        }
        for i in 0..<SpectrumAnalyzer.bandCount {
            let db = linToDb(bands[i].env)
            out[i] = clampF((db + 60.0) / 60.0, 0, 1)
        }
    }
}

// MARK: - Full Stereo FX Chain

final class FXChain {
    private let configLock: UnsafeMutablePointer<os_unfair_lock>
    private var pendingConfig = DSPConfig()
    private var configDirty = true
    private var activeConfig = DSPConfig()

    private let gate: StereoGate
    private let eq: StereoEQ
    private let comp: StereoCompressor
    private let sat: StereoSaturation
    private let tape: StereoTape
    private let ensemble: StereoEnsemble
    private let delay: StereoDelay
    private let reverb: StereoReverb
    private let limiter: StereoLimiter
    private let analyzer: SpectrumAnalyzer

    private var inGainSmooth = SmoothFloat(1)
    private var masterSmooth = SmoothFloat(1)

    private(set) var inputPeak: Float = 0
    private(set) var outputPeak: Float = 0
    private(set) var gateOpen: Bool = true
    private(set) var compGrDb: Float = 0
    private(set) var limGrDb: Float = 0
    private(set) var inputMode: InputChannelMode = .in1

    init(sampleRate: Float) {
        configLock = .allocate(capacity: 1)
        configLock.initialize(to: os_unfair_lock())
        gate = StereoGate(sr: sampleRate)
        eq = StereoEQ(sr: sampleRate)
        comp = StereoCompressor(sr: sampleRate)
        sat = StereoSaturation(sr: sampleRate)
        tape = StereoTape(sr: sampleRate)
        ensemble = StereoEnsemble(sr: sampleRate)
        delay = StereoDelay(sr: sampleRate)
        reverb = StereoReverb(sr: sampleRate)
        limiter = StereoLimiter(sr: sampleRate)
        analyzer = SpectrumAnalyzer(sr: sampleRate)
        applyConfig(activeConfig)
    }

    deinit {
        configLock.deinitialize(count: 1)
        configLock.deallocate()
    }

    func copySpectrum(into out: inout [Float]) {
        analyzer.copyNormalized(into: &out)
    }

    func updateConfig(_ cfg: DSPConfig) {
        os_unfair_lock_lock(configLock)
        pendingConfig = cfg
        configDirty = true
        os_unfair_lock_unlock(configLock)
    }

    private func applyConfig(_ cfg: DSPConfig) {
        inputMode = cfg.inputMode
        inGainSmooth.target = dbToLin(cfg.gainDb)
        masterSmooth.target = cfg.muted || cfg.masterDb <= -59.5 ? 0 : dbToLin(cfg.masterDb)
        gate.update(cfg)
        eq.update(cfg)
        comp.update(cfg)
        sat.update(cfg)
        tape.update(cfg)
        ensemble.update(cfg)
        delay.update(cfg)
        reverb.update(cfg)
        limiter.update(cfg)
    }

    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count n: Int) {
        if os_unfair_lock_trylock(configLock) {
            if configDirty {
                activeConfig = pendingConfig
                configDirty = false
                os_unfair_lock_unlock(configLock)
                applyConfig(activeConfig)
            } else {
                os_unfair_lock_unlock(configLock)
            }
        }

        var inPk: Float = 0
        var outPk: Float = 0
        let runSpectrum = activeConfig.spectrumActive

        for i in 0..<n {
            let inG = inGainSmooth.next()
            let mG = masterSmooth.next()

            var l = left[i] * inG
            var r = right[i] * inG
            inPk = max(inPk, max(abs(l), abs(r)))

            gate.process(&l, &r, enabled: activeConfig.gateOn)
            eq.process(&l, &r)
            comp.process(&l, &r, enabled: activeConfig.compOn)
            sat.process(&l, &r)
            tape.process(&l, &r)
            ensemble.process(&l, &r)
            delay.process(&l, &r)
            reverb.process(&l, &r)

            l *= mG
            r *= mG
            limiter.process(&l, &r)

            if runSpectrum {
                analyzer.process((l + r) * 0.5)
            }
            outPk = max(outPk, max(abs(l), abs(r)))
            left[i] = l
            right[i] = r
        }

        inputPeak = max(inPk, inputPeak * 0.88)
        outputPeak = max(outPk, outputPeak * 0.88)
        gateOpen = gate.isOpen
        compGrDb = comp.lastGrDb
        limGrDb = limiter.lastGrDb
    }
}
