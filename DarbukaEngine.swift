import Foundation
import AVFoundation
import AudioToolbox
import UIKit

private struct SavedEngineState: Codable {
    var params: EngineParams
    var inputMode: InputChannelMode
}

final class DarbukaEngine: ObservableObject {
    @Published var params = EngineParams() { didSet { pushParams(); scheduleSaveLastState() } }
    @Published var inputMode: InputChannelMode = .in1 { didSet { pushParams(); scheduleSaveLastState() } }
    @Published var isRunning = false
    @Published var actualSampleRate: Float = 48000
    @Published var actualBufferFrames: Int = 64
    @Published var actualBufferMs: Float = 64.0 / 48.0
    @Published var estimatedRoundTripMs: Float = 6.0
    @Published var statusNote: String = ""
    @Published var audioRouteName: String = "iPhone Mic"
    @Published var inputLevelDb: Float = -70
    @Published var outputLevelDb: Float = -60
    @Published var gateOpen: Bool = true
    @Published var gateGrDb: Float = 0
    @Published var compGrDb: Float = 0
    @Published var limGrDb: Float = 0
    @Published var spectrumBins: [Float] = Array(repeating: 0, count: 24)
    @Published var gateHistory: [Float] = Array(repeating: -60, count: 48)
    @Published var gateOpenHistory: [Bool] = Array(repeating: true, count: 48)
    @Published var limOutHistory: [Float] = Array(repeating: -60, count: 48)
    @Published var limGrHistory: [Float] = Array(repeating: 0, count: 48)
    @Published var mainScopeHistory: [Float] = Array(repeating: 0, count: 48)
    @Published var presets: [EnginePreset] = []
    @Published var activePresetId: UUID?

    var isSpectrumActive: Bool = false {
        didSet {
            if isSpectrumActive != oldValue { pushParams() }
        }
    }
    var activePageIndex: Int = 0 {
        didSet { isSpectrumActive = (activePageIndex == 2) }
    }

    private var unit: AudioUnit?
    private var fx: FXChain?
    private var hwInChannels: Int = 1

    private static let maxFrames = 4096
    private let inBufL = UnsafeMutablePointer<Float>.allocate(capacity: DarbukaEngine.maxFrames)
    private let inBufR = UnsafeMutablePointer<Float>.allocate(capacity: DarbukaEngine.maxFrames)
    private let inList = AudioBufferList.allocate(maximumBuffers: 2)

    private var meterTimer: Timer?
    private var stateSaveTimer: Timer?
    private var tapTimes: [CFAbsoluteTime] = []
    private var routeObserver: NSObjectProtocol?
    private var interruptObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var termObserver: NSObjectProtocol?
    private var shouldKeepRunning = false
    private var isInBackground = false
    private let presetsKey = "s_man_mixer_fx_presets_v1"
    private let lastStateKey = "s_man_mixer_fx_last_state_v1"

    init() {
        loadLastState()
        loadSavedPresets()
        refreshRouteInfo()
        observeAudioNotifications()
        setIdleTimerDisabled(true)
    }

    deinit {
        stateSaveTimer?.invalidate()
        stopAudio()
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = interruptObserver { NotificationCenter.default.removeObserver(o) }
        if let o = mediaResetObserver { NotificationCenter.default.removeObserver(o) }
        if let o = bgObserver { NotificationCenter.default.removeObserver(o) }
        if let o = fgObserver { NotificationCenter.default.removeObserver(o) }
        if let o = activeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = termObserver { NotificationCenter.default.removeObserver(o) }
        inBufL.deallocate()
        inBufR.deallocate()
        free(inList.unsafeMutablePointer)
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Power & Session Control

    func togglePower() {
        if isRunning {
            shouldKeepRunning = false
            stopAudio()
            return
        }
        shouldKeepRunning = true
        requestMic { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.shouldKeepRunning = false
                    self.statusNote = "Microphone permission denied. Enable it in Settings > Privacy & Security > Microphone."
                    return
                }
                do {
                    try self.startAudio()
                } catch {
                    self.shouldKeepRunning = false
                    self.stopAudio()
                    self.statusNote = error.localizedDescription
                }
            }
        }
    }

    func setBufferSize(_ size: Int) {
        params.bufferSize = size
        guard isRunning else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setPreferredIOBufferDuration(Double(size) / Double(max(actualSampleRate, 8000)))
        refreshSessionMetrics()
    }

    private func requestMic(_ done: @escaping (Bool) -> Void) {
        if #available(iOS 17, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: done)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(done)
        }
    }

    private func startAudio() throws {
        stopAudio()

        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try s.setPreferredSampleRate(48000)
        try s.setPreferredIOBufferDuration(Double(params.bufferSize) / 48000.0)
        try s.setActive(true)
        if let usb = s.availableInputs?.first(where: { $0.portType == .usbAudio }) {
            try? s.setPreferredInput(usb)
        }
        if s.maximumInputNumberOfChannels >= 2 {
            try? s.setPreferredInputNumberOfChannels(2)
        }

        let sr = Float(s.sampleRate > 0 ? s.sampleRate : 48000)
        let inCh = max(1, min(2, s.inputNumberOfChannels))
        actualSampleRate = sr
        hwInChannels = inCh

        let chain = FXChain(sampleRate: sr)
        chain.updateConfig(DSPConfig(from: params, inputMode: inputMode, spectrumActive: isSpectrumActive))
        fx = chain

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "DarbukaEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "RemoteIO audio component not found."])
        }
        try check(AudioComponentInstanceNew(comp, &unit))
        guard let u = unit else {
            throw NSError(domain: "DarbukaEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create AudioUnit instance."])
        }

        var on: UInt32 = 1
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO,
                                       kAudioUnitScope_Input, 1, &on, 4))

        func format(_ ch: UInt32) -> AudioStreamBasicDescription {
            AudioStreamBasicDescription(
                mSampleRate: Double(sr), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: ch, mBitsPerChannel: 32, mReserved: 0)
        }
        let fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var inFmt = format(UInt32(inCh))
        var outFmt = format(2)
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Output, 1, &inFmt, fmtSize))
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input, 0, &outFmt, fmtSize))

        var cb = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback,
                                       kAudioUnitScope_Input, 0, &cb,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)))

        try check(AudioUnitInitialize(u))
        try check(AudioOutputUnitStart(u))

        isRunning = true
        refreshSessionMetrics()
        refreshRouteInfo()
        if !isInBackground {
            startMeterTimer()
            setIdleTimerDisabled(true)
        }
    }

    private func stopAudio() {
        meterTimer?.invalidate()
        meterTimer = nil

        if let u = unit {
            AudioOutputUnitStop(u)
            AudioUnitUninitialize(u)
            AudioComponentInstanceDispose(u)
            unit = nil
        }
        fx = nil
        isRunning = false
        inputLevelDb = -70
        outputLevelDb = -60
        gateGrDb = 0
        compGrDb = 0
        limGrDb = 0
        spectrumBins = Array(repeating: 0, count: 24)
        gateHistory = Array(repeating: -60, count: 48)
        gateOpenHistory = Array(repeating: true, count: 48)
        limOutHistory = Array(repeating: -60, count: 48)
        limGrHistory = Array(repeating: 0, count: 48)
        mainScopeHistory = Array(repeating: 0, count: 48)
        gateOpen = true
        refreshRouteInfo()
    }

    private func pushParams() {
        fx?.updateConfig(DSPConfig(from: params, inputMode: inputMode, spectrumActive: isSpectrumActive))
    }

    private func check(_ s: OSStatus) throws {
        if s != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
    }

    // MARK: - Metrics, Route & Metering

    private func refreshSessionMetrics() {
        let s = AVAudioSession.sharedInstance()
        let sr = Float(s.sampleRate > 0 ? s.sampleRate : 48000)
        actualSampleRate = sr
        let dur = s.ioBufferDuration > 0 ? s.ioBufferDuration : Double(params.bufferSize) / Double(sr)
        actualBufferFrames = max(16, Int(round(dur * Double(sr))))
        actualBufferMs = Float(dur * 1000.0)
        let rt = (s.inputLatency + s.outputLatency + dur * 2.0) * 1000.0
        estimatedRoundTripMs = Float(max(rt, Double(actualBufferMs * 2)))
    }

    private func refreshRouteInfo() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inName = route.inputs.first?.portName ?? "iPhone Mic"
        let outPort = route.outputs.first
        let outName = outPort?.portName ?? "Speaker"
        audioRouteName = "\(inName) → \(outName)"

        if isRunning && outPort?.portType == .builtInSpeaker && !params.muted {
            statusNote = "Speaker output active — use headphones or USB interface to avoid feedback."
        } else if statusNote.hasPrefix("Speaker output active") {
            statusNote = ""
        }
    }

    private func observeAudioNotifications() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshRouteInfo()
            if self.isRunning {
                let s = AVAudioSession.sharedInstance()
                let newSr = Float(s.sampleRate > 0 ? s.sampleRate : 48000)
                let newCh = max(1, min(2, s.inputNumberOfChannels))
                if abs(newSr - self.actualSampleRate) > 1 || newCh != self.hwInChannels {
                    try? self.startAudio()
                } else {
                    self.refreshSessionMetrics()
                }
            }
        }
        interruptObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                if self.isRunning {
                    self.stopAudio()
                }
            } else if type == .ended && self.shouldKeepRunning && !self.isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, self.shouldKeepRunning, !self.isRunning else { return }
                    try? self.startAudio()
                }
            }
        }
        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stopAudio()
            if self.shouldKeepRunning {
                try? self.startAudio()
            }
        }
        bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isInBackground = true
            self.saveLastStateNow()
            self.meterTimer?.invalidate()
            self.meterTimer = nil
            self.setIdleTimerDisabled(false)
        }
        fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isInBackground = false
            if self.shouldKeepRunning && !self.isRunning {
                try? self.startAudio()
            } else if self.isRunning {
                self.refreshSessionMetrics()
                self.refreshRouteInfo()
                if self.meterTimer == nil { self.startMeterTimer() }
            }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isInBackground = false
            self.setIdleTimerDisabled(true)
            if self.shouldKeepRunning && !self.isRunning {
                try? self.startAudio()
            } else if self.isRunning && self.meterTimer == nil {
                self.startMeterTimer()
            }
        }
        termObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveLastStateNow()
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    private func scheduleSaveLastState() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.saveLastStateNow()
        }
    }

    private func saveLastStateNow() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = nil
        let state = SavedEngineState(params: params, inputMode: inputMode)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: lastStateKey)
        }
    }

    private func loadLastState() {
        if let data = UserDefaults.standard.data(forKey: lastStateKey),
           let decoded = try? JSONDecoder().decode(SavedEngineState.self, from: data) {
            params = decoded.params
            inputMode = decoded.inputMode
        }
    }

    private func startMeterTimer() {
        guard !isInBackground else { return }
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let fx = self.fx else { return }
            let inDb = clampF(linToDb(fx.inputPeak), -70, 0)
            let outDb = clampF(linToDb(fx.outputPeak), -60, 0)
            self.inputLevelDb = inDb
            self.outputLevelDb = outDb
            self.gateOpen = fx.gateOpen
            self.gateGrDb = fx.gateGrDb
            self.compGrDb = fx.compGrDb
            self.limGrDb = fx.limGrDb

            if self.activePageIndex == 0 {
                self.mainScopeHistory.removeFirst()
                self.mainScopeHistory.append(clampF((outDb + 60.0) / 60.0, 0, 1))
            } else if self.activePageIndex == 1 {
                self.gateHistory.removeFirst()
                self.gateHistory.append(inDb)
                self.gateOpenHistory.removeFirst()
                self.gateOpenHistory.append(fx.gateOpen)
            } else if self.activePageIndex == 2 {
                fx.copySpectrum(into: &self.spectrumBins)
            } else if self.activePageIndex == 8 {
                self.limOutHistory.removeFirst()
                self.limOutHistory.append(outDb)
                self.limGrHistory.removeFirst()
                self.limGrHistory.append(fx.limGrDb)
            }
        }
    }

    // MARK: - Tap Tempo & Presets

    func tapTempo() {
        let now = CFAbsoluteTimeGetCurrent()
        if let last = tapTimes.last, now - last > 2.0 {
            tapTimes.removeAll()
        }
        tapTimes.append(now)
        if tapTimes.count > 5 { tapTimes.removeFirst() }
        guard tapTimes.count >= 2 else { return }

        var total: Double = 0
        var count = 0
        for i in 1..<tapTimes.count {
            let dt = tapTimes[i] - tapTimes[i - 1]
            if dt >= 0.25 && dt <= 1.5 {
                total += dt
                count += 1
            }
        }
        guard count > 0 else { return }
        let avgDt = total / Double(count)
        let bpm = clampF(Float(60.0 / avgDt), 40, 240)
        params.delayBpm = round(bpm)
        if !params.delaySync {
            params.delayTimeMs = clampF(60000.0 / params.delayBpm, 20, 1500)
        }
    }

    func applyEnsemblePreset(_ name: String) {
        params.ensemble.presetName = name
        params.ensemble.voices = EnsembleParams.presetVoices(name)
        switch name {
        case "Lush Tutti":
            params.ensemble.mix = 0.52
            params.ensemble.detuneCents = 14
            params.ensemble.stereoWidth = 0.95
        case "Octave Shimmer":
            params.ensemble.mix = 0.48
            params.ensemble.detuneCents = 12
            params.ensemble.stereoWidth = 0.9
        default:
            params.ensemble.mix = 0.35
            params.ensemble.detuneCents = 8
            params.ensemble.stereoWidth = 0.78
        }
    }

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed
        let item = EnginePreset(name: finalName, params: params)
        presets.insert(item, at: 0)
        activePresetId = item.id
        persistPresets()
    }

    func loadPreset(_ item: EnginePreset) {
        params = item.params
        activePresetId = item.id
    }

    func deletePreset(_ item: EnginePreset) {
        presets.removeAll { $0.id == item.id }
        if activePresetId == item.id { activePresetId = nil }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    private func loadSavedPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([EnginePreset].self, from: data) {
            presets = decoded
        }
    }

    // MARK: - Audio Thread Render (No Allocations, No Locks)

    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ ts: UnsafePointer<AudioTimeStamp>,
                            _ frames: UInt32,
                            _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let unit, let ioData, let fx else { return noErr }
        let out = UnsafeMutableAudioBufferListPointer(ioData)
        let n = Int(frames)
        guard n > 0 && n <= DarbukaEngine.maxFrames else { silence(out); return noErr }

        inList.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(hwInChannels)
        inList[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4,
                                mData: UnsafeMutableRawPointer(inBufL))
        if hwInChannels == 2 {
            inList[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4,
                                    mData: UnsafeMutableRawPointer(inBufR))
        }

        let st = AudioUnitRender(unit, flags, ts, 1, frames, inList.unsafeMutablePointer)
        if st != noErr { silence(out); return noErr }

        if hwInChannels == 1 {
            memcpy(inBufR, inBufL, n * 4)
        } else {
            switch fx.inputMode {
            case .in1: memcpy(inBufR, inBufL, n * 4)
            case .in2: memcpy(inBufL, inBufR, n * 4)
            case .stereo: break
            }
        }

        fx.process(left: inBufL, right: inBufR, count: n)

        if out.count >= 2 {
            if let d0 = out[0].mData { memcpy(d0, inBufL, n * 4) }
            if let d1 = out[1].mData { memcpy(d1, inBufR, n * 4) }
        } else if let d0 = out.first?.mData {
            memcpy(d0, inBufL, n * 4)
        }
        return noErr
    }

    @inline(__always)
    private func silence(_ out: UnsafeMutableAudioBufferListPointer) {
        for b in out {
            if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
        }
    }
}

private let renderCallback: AURenderCallback = { ref, flags, ts, _, frames, ioData in
    Unmanaged<DarbukaEngine>.fromOpaque(ref).takeUnretainedValue()
        .render(flags, ts, frames, ioData)
}
