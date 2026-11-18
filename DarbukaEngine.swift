import AVFoundation
import AudioToolbox

// Kullanım:
//   let engine = DarbukaEngine()
//   try engine.start()
//   engine.fx.gate.p.thresholdDB = -45
//   engine.fx.reverb.p.mix = 0.2
//
// Gerekli: Info.plist -> NSMicrophoneUsageDescription, ve mikrofon izni (AVAudioApplication.requestRecordPermission).

final class DarbukaEngine {
    private var unit: AudioUnit?
    private(set) var fx: FXChain!

    private static let maxFrames = 4096
    private let inBuf = UnsafeMutablePointer<Float>.allocate(capacity: DarbukaEngine.maxFrames)
    private let inList = AudioBufferList.allocate(maximumBuffers: 1)

    deinit {
        stop()
        inBuf.deallocate()
        free(inList.unsafeMutablePointer)
    }

    func start() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try s.setPreferredSampleRate(48000)
        try s.setPreferredIOBufferDuration(64.0 / 48000.0)
        try s.setActive(true)
        if let usb = s.availableInputs?.first(where: { $0.portType == .usbAudio }) {
            try s.setPreferredInput(usb)
        }
        print("sr:", s.sampleRate, "buffer ms:", s.ioBufferDuration * 1000) // gerçek değerler

        let sr = s.sampleRate
        fx = FXChain(sampleRate: Float(sr))

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "DarbukaEngine", code: -1)
        }
        try check(AudioComponentInstanceNew(comp, &unit))
        guard let u = unit else { throw NSError(domain: "DarbukaEngine", code: -2) }

        // Giriş (bus 1) açık; çıkış (bus 0) zaten açık.
        var on: UInt32 = 1
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO,
                                       kAudioUnitScope_Input, 1, &on, 4))

        // Giriş: mono, çıkış: stereo (aynı sinyal iki kanala), non-interleaved Float32
        func format(_ ch: UInt32) -> AudioStreamBasicDescription {
            AudioStreamBasicDescription(
                mSampleRate: sr, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: ch, mBitsPerChannel: 32, mReserved: 0)
        }
        let fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var inFmt = format(1), outFmt = format(2)
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
    }

    func stop() {
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
        unit = nil
    }

    private func check(_ s: OSStatus) throws {
        if s != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
    }

    // MARK: - Render (ses thread'i: tahsis yok, kilit yok)

    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ ts: UnsafePointer<AudioTimeStamp>,
                            _ frames: UInt32,
                            _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let unit, let ioData else { return noErr }
        let out = UnsafeMutableAudioBufferListPointer(ioData)
        let n = Int(frames)
        guard n <= DarbukaEngine.maxFrames else { silence(out); return noErr }

        // Mikrofon girişini (bus 1) kendi buffer'ımıza çek
        inList[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4,
                                mData: UnsafeMutableRawPointer(inBuf))
        let st = AudioUnitRender(unit, flags, ts, 1, frames, inList.unsafeMutablePointer)
        if st != noErr { silence(out); return noErr }

        fx.process(inBuf, count: n)

        for b in out {
            if let d = b.mData { memcpy(d, inBuf, n * 4) }
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
