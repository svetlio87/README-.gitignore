import SwiftUI
import AVFoundation

// MARK: - Model

final class MixerModel: ObservableObject {
    struct EQBandSetting { var freq: Float; var gain: Float = 0; var q: Float = 1 }

    struct Settings {
        var gain: Float = 0
        var hpf: Float = 70
        var gateThr: Float = -50, gateHyst: Float = 4, gateAtk: Float = 0.5
        var gateHold: Float = 30, gateRel: Float = 100
        var eq = [EQBandSetting(freq: 250), EQBandSetting(freq: 1000),
                  EQBandSetting(freq: 3000), EQBandSetting(freq: 6000)]
        var compThr: Float = -18, compRatio: Float = 2, compAtk: Float = 15
        var compRel: Float = 100, compMakeup: Float = 0
        var decay: Float = 1.0, preDelay: Float = 10, mixPct: Float = 15
        var ceiling: Float = -1
    }

    @Published var s = Settings() { didSet { push() } }
    @Published var running = false
    @Published var error: String?

    private let engine = DarbukaEngine()

    func peak() -> Float { engine.fx?.inputPeak ?? 0 }

    func toggle() {
        if running { engine.stop(); running = false; return }
        requestMic { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.error = "Mikrofon izni verilmedi"; return }
                do {
                    try self.engine.start()
                    self.push()
                    self.running = true
                    self.error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func requestMic(_ done: @escaping (Bool) -> Void) {
        if #available(iOS 17, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: done)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(done)
        }
    }

    private func push() {
        guard let fx = engine.fx else { return }
        fx.inputGainDB = s.gain
        fx.highPassHz = s.hpf
        fx.gate.p = .init(thresholdDB: s.gateThr, hysteresisDB: s.gateHyst,
                          attackMs: s.gateAtk, holdMs: s.gateHold, releaseMs: s.gateRel)
        let b = s.eq.map { EQ.Band(freq: $0.freq, gainDB: $0.gain, q: $0.q) }
        fx.eq.bands = (b[0], b[1], b[2], b[3])
        fx.comp.p = .init(thresholdDB: s.compThr, ratio: s.compRatio, attackMs: s.compAtk,
                          releaseMs: s.compRel, makeupDB: s.compMakeup)
        fx.reverb.p = .init(decaySec: s.decay, preDelayMs: s.preDelay, mix: s.mixPct / 100)
        fx.limiter.ceilingDB = s.ceiling
    }
}

// MARK: - Bileşenler

struct Param: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var unit = ""
    var log = false

    var body: some View {
        HStack {
            Text(title).font(.subheadline).frame(width: 84, alignment: .leading)
            if log {
                Slider(value: Binding(get: { Foundation.log(value) },
                                      set: { value = exp($0) }),
                       in: Foundation.log(range.lowerBound)...Foundation.log(range.upperBound))
            } else {
                Slider(value: $value, in: range)
            }
            Text(String(format: value >= 1000 ? "%.0f" : "%.1f", value) + unit)
                .font(.caption.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct Meter: View {
    let read: () -> Float
    @State private var level: Float = 0
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let db = 20 * log10(max(level, 1e-4))
        let frac = CGFloat(min(max((db + 60) / 60, 0), 1))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(db > -1 ? Color.red : (db > -12 ? Color.yellow : Color.green))
                    .frame(width: g.size.width * frac)
            }
        }
        .frame(height: 10)
        .onReceive(timer) { _ in level = read() }
    }
}

// MARK: - Ekran

struct ContentView: View {
    @StateObject private var vm = MixerModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GroupBox("Giriş") {
                    Param(title: "Gain", value: $vm.s.gain, range: 0...40, unit: " dB")
                    Param(title: "High-pass", value: $vm.s.hpf, range: 40...150, unit: " Hz")
                }
                GroupBox("Gate") {
                    Param(title: "Threshold", value: $vm.s.gateThr, range: -70 ... -20, unit: " dB")
                    Param(title: "Hysteresis", value: $vm.s.gateHyst, range: 0...10, unit: " dB")
                    Param(title: "Attack", value: $vm.s.gateAtk, range: 0.1...5, unit: " ms")
                    Param(title: "Hold", value: $vm.s.gateHold, range: 5...100, unit: " ms")
                    Param(title: "Release", value: $vm.s.gateRel, range: 20...300, unit: " ms")
                }
                GroupBox("EQ") {
                    ForEach(0..<4, id: \.self) { i in
                        VStack {
                            Text("Bant \(i + 1)").font(.caption).foregroundStyle(.secondary)
                            Param(title: "Frekans", value: $vm.s.eq[i].freq, range: 20...12000, unit: " Hz", log: true)
                            Param(title: "Gain", value: $vm.s.eq[i].gain, range: -12...12, unit: " dB")
                            Param(title: "Q", value: $vm.s.eq[i].q, range: 0.3...8)
                        }
                        if i < 3 { Divider() }
                    }
                }
                GroupBox("Kompresör") {
                    Param(title: "Threshold", value: $vm.s.compThr, range: -40...0, unit: " dB")
                    Param(title: "Ratio", value: $vm.s.compRatio, range: 1...6, unit: ":1")
                    Param(title: "Attack", value: $vm.s.compAtk, range: 5...50, unit: " ms")
                    Param(title: "Release", value: $vm.s.compRel, range: 40...300, unit: " ms")
                    Param(title: "Makeup", value: $vm.s.compMakeup, range: 0...12, unit: " dB")
                }
                GroupBox("Reverb") {
                    Param(title: "Decay", value: $vm.s.decay, range: 0.3...3, unit: " sn")
                    Param(title: "Pre-delay", value: $vm.s.preDelay, range: 0...50, unit: " ms")
                    Param(title: "Mix", value: $vm.s.mixPct, range: 0...40, unit: " %")
                }
                GroupBox("Limiter") {
                    Param(title: "Ceiling", value: $vm.s.ceiling, range: -6...0, unit: " dB")
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                HStack {
                    Button(vm.running ? "Durdur" : "Başlat") { vm.toggle() }
                        .buttonStyle(.borderedProminent)
                        .tint(vm.running ? .red : .accentColor)
                    Meter(read: vm.peak)
                }
                if let e = vm.error {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
            .background(.bar)
        }
    }
}
