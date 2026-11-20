import SwiftUI

struct ContentView: View {
    @StateObject private var vm = DarbukaEngine()
    @State private var currentPage: Int = 0
    @State private var selectedBand: Int = 0
    @State private var ensembleSubPage: Int = 0
    @State private var presetName: String = ""

    private let titles = [
        "S-Man Main", "S-Man Gate", "S-Man EQ", "S-Man Comp",
        "S-Man Saturation", "S-Man Tape", "S-Man Delay",
        "S-Man Reverb", "S-Man Limiter", "S-Man Ensemble"
    ]
    private let accents: [Color] = [
        Color(hex: 0x4AA3FF), Color(hex: 0x3DDC97), Color(hex: 0x31C6FF),
        Color(hex: 0xFF9F43), Color(hex: 0xFF5D8F), Color(hex: 0xF2B66D),
        Color(hex: 0x00E5FF), Color(hex: 0xA77BFF), Color(hex: 0xFF5A5A), Color(hex: 0xC57BFF)
    ]

    private var statusSubtitle: String {
        if vm.isRunning {
            let srK = vm.actualSampleRate / 1000.0
            let buf = vm.actualBufferFrames > 0 ? vm.actualBufferFrames : vm.params.bufferSize
            return String(format: "Running · %.1f kHz · Buffer %d · RT %.1f ms", srK, buf, vm.estimatedRoundTripMs)
        } else {
            return String(format: "Stopped · 48 kHz · Buffer %d", vm.params.bufferSize)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 10) {
                Button { vm.togglePower() } label: {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(vm.isRunning ? Color(hex: 0x3DDC97) : Color.white.opacity(0.08))
                        .foregroundColor(vm.isRunning ? .black : .white)
                        .clipShape(Circle())
                        .shadow(color: vm.isRunning ? Color(hex: 0x3DDC97).opacity(0.6) : .clear, radius: 10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("S-MAN MIX FX")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white)
                    Text(statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: 0x8B93A7))
                        .lineLimit(1)
                }

                Spacer()

                if vm.params.muted {
                    Text("MUTE")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: 0xFF4D4D))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Status / Safety Warning Banner
            if !vm.statusNote.isEmpty {
                Text(vm.statusNote)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xFF4D4D).opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: 0xFF4D4D).opacity(0.6), lineWidth: 1)
                    )
                    .cornerRadius(10)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            // Chip Bar
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(titles.indices, id: \.self) { i in
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) { currentPage = i }
                            } label: {
                                Text(titles[i])
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(currentPage == i ? accents[i] : Color.white.opacity(0.06))
                                    .foregroundColor(currentPage == i ? .black : Color(hex: 0x8B93A7))
                                    .clipShape(Capsule())
                            }
                            .id(i)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: currentPage) { page in
                    vm.activePageIndex = page
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(page, anchor: .center)
                    }
                }
            }

            // 10-Page Pager
            TabView(selection: $currentPage) {
                MainPageView(vm: vm, presetName: $presetName).tag(0)
                GatePageView(vm: vm).tag(1)
                SManEQPageView(vm: vm, selectedBand: $selectedBand).tag(2)
                CompPageView(vm: vm).tag(3)
                SaturationPageView(vm: vm).tag(4)
                TapePageView(vm: vm).tag(5)
                DelayPageView(vm: vm).tag(6)
                ReverbPageView(vm: vm).tag(7)
                LimiterPageView(vm: vm).tag(8)
                EnsemblePagedView(vm: vm, subPage: $ensembleSubPage).tag(9)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(hex: 0x07080D).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - 0. S-Man Main Page

struct MainPageView: View {
    @ObservedObject var vm: DarbukaEngine
    @Binding var presetName: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Live Output Scope Graphic
                mainScopeCard.frame(height: 64)

                // Audio Route + Input Channel Mode + Buffer 32/64/128
                VStack(spacing: 8) {
                    HStack {
                        Text("ROUTE: \(vm.audioRouteName)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: 0x8B93A7))
                            .lineLimit(1)
                        Spacer()
                        Text(vm.isRunning
                             ? String(format: "Buffer %d (%.1f ms)", vm.actualBufferFrames, vm.actualBufferMs)
                             : "Buffer \(vm.params.bufferSize)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 6) {
                        ForEach(InputChannelMode.allCases, id: \.self) { mode in
                            Button(mode.rawValue) { vm.inputMode = mode }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(vm.inputMode == mode ? Color(hex: 0x3DDC97) : Color.white.opacity(0.06))
                                .foregroundColor(vm.inputMode == mode ? .black : Color(hex: 0x8B93A7))
                                .cornerRadius(9)
                        }
                    }

                    HStack(spacing: 5) {
                        ForEach([32, 64, 128, 256, 512], id: \.self) { sz in
                            Button("\(sz)") { vm.setBufferSize(sz) }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(vm.params.bufferSize == sz ? Color(hex: 0x4AA3FF) : Color.white.opacity(0.06))
                                .foregroundColor(vm.params.bufferSize == sz ? .black : Color(hex: 0x8B93A7))
                                .cornerRadius(9)
                        }
                    }
                }
                .padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                // Dual Vertical Studio Faders (GAIN & MASTER)
                HStack(spacing: 16) {
                    VerticalStudioFader(
                        title: "GAIN",
                        value: $vm.params.gainDb,
                        range: 0...40,
                        accent: Color(hex: 0x4AA3FF),
                        meterDb: vm.inputLevelDb,
                        readout: String(format: "+%.1f dB", vm.params.gainDb)
                    )
                    VerticalStudioFader(
                        title: "MASTER",
                        value: $vm.params.masterDb,
                        range: -60...6,
                        accent: Color(hex: 0x3DDC97),
                        meterDb: vm.outputLevelDb,
                        readout: vm.params.masterDb <= -59.5 ? "-∞ dB" : String(format: "%+.1f dB", vm.params.masterDb)
                    )
                }
                .padding(14).background(Color(hex: 0x10141D)).cornerRadius(18)

                Button { vm.params.muted.toggle() } label: {
                    Text(vm.params.muted ? "🔇 MUTED" : "🔊 MUTE")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(vm.params.muted ? Color(hex: 0xFF4D4D) : Color.white.opacity(0.08))
                        .foregroundColor(.white).cornerRadius(14)
                }

                // Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRESETS").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                    HStack {
                        TextField("Preset name", text: $presetName)
                            .textFieldStyle(.plain).padding(8)
                            .background(Color.white.opacity(0.08)).cornerRadius(8).foregroundColor(.white)
                        Button("Save") { vm.savePreset(name: presetName); presetName = "" }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(hex: 0x3DDC97)).foregroundColor(.black).cornerRadius(8)
                    }
                    if vm.presets.isEmpty {
                        Text("No saved presets yet.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x8B93A7))
                    } else {
                        ForEach(vm.presets) { item in
                            HStack {
                                Text((vm.activePresetId == item.id ? "✓ " : "") + item.name)
                                    .foregroundColor(.white)
                                    .onTapGesture { vm.loadPreset(item) }
                                Spacer()
                                Button("✕") { vm.deletePreset(item) }.foregroundColor(Color(hex: 0xFF5A5A))
                            }
                            .padding(8).background(Color.white.opacity(0.05)).cornerRadius(10)
                        }
                    }
                }
                .padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }
            .padding(14)
        }
    }

    private var mainScopeCard: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            let mid = size.height / 2
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: mid))
            axis.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(axis, with: .color(Color.white.opacity(0.10)), lineWidth: 1)

            let hist = vm.mainScopeHistory
            guard !hist.isEmpty else { return }
            let stepW = size.width / CGFloat(hist.count)
            for i in hist.indices {
                let amp = CGFloat(hist[i]) * (size.height * 0.42)
                let x = (CGFloat(i) + 0.5) * stepW
                var bar = Path()
                bar.move(to: CGPoint(x: x, y: mid - max(2, amp)))
                bar.addLine(to: CGPoint(x: x, y: mid + max(2, amp)))
                let col: Color = hist[i] > 0.92 ? Color(hex: 0xFF4D4D) : (hist[i] > 0.75 ? Color(hex: 0xFFD166) : Color(hex: 0x4AA3FF))
                ctx.stroke(bar, with: .color(vm.isRunning ? col : Color.white.opacity(0.15)),
                           style: StrokeStyle(lineWidth: max(2, stepW * 0.55), lineCap: .round))
            }
        }
    }
}

struct VerticalStudioFader: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let accent: Color
    let meterDb: Float
    let readout: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundColor(Color(hex: 0x8B93A7))

            HStack(spacing: 12) {
                GeometryReader { geo in
                    let norm = CGFloat(max(0, min(1, (meterDb + 60) / 60)))
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0x3DDC97), Color(hex: 0xFFD166), Color(hex: 0xFF4D4D)], startPoint: .bottom, endPoint: .top))
                            .frame(height: geo.size.height * norm)
                    }
                }
                .frame(width: 8, height: 190)

                GeometryReader { geo in
                    let h = geo.size.height
                    let norm = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                    let yPos = h * (1.0 - max(0, min(1, norm)))

                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.black.opacity(0.55)).frame(width: 10)
                        Capsule().fill(accent).frame(width: 10, height: max(0, h - yPos))

                        RoundedRectangle(cornerRadius: 7)
                            .fill(LinearGradient(colors: [Color(hex: 0xF5F7FA), Color(hex: 0x9BA3B5)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 44, height: 26)
                            .overlay(Rectangle().fill(Color.black.opacity(0.55)).frame(width: 26, height: 2))
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
                            .position(x: geo.size.width / 2, y: max(13, min(h - 13, yPos)))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let pct = 1.0 - max(0, min(1, drag.location.y / h))
                                value = range.lowerBound + Float(pct) * (range.upperBound - range.lowerBound)
                            }
                    )
                }
                .frame(width: 52, height: 190)
            }

            Text(readout)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 1. S-Man Gate Page (Interactive Transfer Curve + Hysteresis + FX Volume)

struct GatePageView: View {
    @ObservedObject var vm: DarbukaEngine
    @State private var dragNode: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Gate", subtitle: "Transfer curve + stage cleanup", accent: Color(hex: 0x3DDC97), isOn: $vm.params.gateOn)

                gateCurveCard.frame(height: 170)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(vm.params.gateOn ? (vm.gateOpen ? "OPEN" : "CLOSED") : "BYPASS")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(vm.params.gateOn ? (vm.gateOpen ? Color(hex: 0x3DDC97) : Color(hex: 0xFF5A5A)) : Color(hex: 0x8B93A7))
                        Spacer()
                        Text(String(format: "RED -%.1f dB", vm.params.gateOn ? vm.gateGrDb : 0))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(Color(hex: 0x3DDC97))
                        Text(String(format: "· IN %.1f dB", vm.inputLevelDb))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Color(hex: 0x8B93A7))
                    }
                    MeterBar(levelNorm: CGFloat(max(0, min(1, (vm.inputLevelDb + 70) / 70))),
                             markerNorm: CGFloat(max(0, min(1, (vm.params.gateThreshDb + 70) / 70))),
                             color: Color(hex: 0x3DDC97))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                VStack(spacing: 10) {
                    ParamSlider(title: "THRESH", value: $vm.params.gateThreshDb, range: -70...0, tint: Color(hex: 0x3DDC97), text: String(format: "%.1f dB", vm.params.gateThreshDb))
                    ParamSlider(title: "RANGE / FLOOR", value: $vm.params.gateFloorDb, range: -70...0, tint: Color(hex: 0x31C6FF),
                                text: vm.params.gateFloorDb <= -69.5 ? "-70 dB (Full)" : String(format: "%.1f dB", vm.params.gateFloorDb))
                    ParamSlider(title: "HYST", value: $vm.params.gateHystDb, range: 0...10, tint: Color(hex: 0x3DDC97), text: String(format: "%.1f dB", vm.params.gateHystDb))
                    ParamSlider(title: "ATTACK", value: $vm.params.gateAttackMs, range: 0.1...5, tint: Color(hex: 0x3DDC97), text: String(format: "%.1f ms", vm.params.gateAttackMs))
                    ParamSlider(title: "HOLD", value: $vm.params.gateHoldMs, range: 5...100, tint: Color(hex: 0x3DDC97), text: "\(Int(vm.params.gateHoldMs)) ms")
                    ParamSlider(title: "RELEASE", value: $vm.params.gateReleaseMs, range: 20...300, tint: Color(hex: 0x3DDC97), text: "\(Int(vm.params.gateReleaseMs)) ms")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.gateLevelDb, range: -24...12, tint: Color(hex: 0x3DDC97), text: String(format: "%+.1f dB", vm.params.gateLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private var gateCurveCard: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 20
            let xOf: (Float) -> CGFloat = { db in pad + CGFloat((clampF(db, -70, 0) + 70) / 70) * (w - 2 * pad) }
            let yOf: (Float) -> CGFloat = { db in h - pad - CGFloat((clampF(db, -70, 0) + 70) / 70) * (h - 2 * pad) }
            let openDb = clampF(vm.params.gateThreshDb, -70, 0)
            let closeDb = clampF(openDb - vm.params.gateHystDb, -70, openDb)
            let floorDb = clampF(vm.params.gateFloorDb, -70, 0)
            let dropYDb = clampF(openDb + floorDb, -70, openDb)

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x0B0E14))
                Canvas { ctx, _ in
                    for d in [-56, -42, -28, -14, 0] {
                        var v = Path()
                        v.move(to: CGPoint(x: xOf(Float(d)), y: yOf(-70)))
                        v.addLine(to: CGPoint(x: xOf(Float(d)), y: yOf(0)))
                        ctx.stroke(v, with: .color(Color.white.opacity(d == 0 ? 0.14 : 0.08)), lineWidth: 1)

                        var hz = Path()
                        hz.move(to: CGPoint(x: xOf(-70), y: yOf(Float(d))))
                        hz.addLine(to: CGPoint(x: xOf(0), y: yOf(Float(d))))
                        ctx.stroke(hz, with: .color(Color.white.opacity(d == 0 ? 0.14 : 0.08)), lineWidth: 1)

                        if d != 0 {
                            ctx.draw(Text("\(d)").font(.system(size: 8)).foregroundColor(Color(hex: 0x8B93A7)),
                                     at: CGPoint(x: xOf(Float(d)), y: h - 8), anchor: .center)
                        }
                    }

                    // 1:1 diagonal reference
                    var ref = Path()
                    ref.move(to: CGPoint(x: xOf(-70), y: yOf(-70)))
                    ref.addLine(to: CGPoint(x: xOf(0), y: yOf(0)))
                    ctx.stroke(ref, with: .color(Color.white.opacity(0.16)), lineWidth: 1)

                    // Shaded Hysteresis band
                    if vm.params.gateHystDb > 0.2 {
                        let hystRect = CGRect(
                            x: xOf(closeDb),
                            y: yOf(0),
                            width: max(0, xOf(openDb) - xOf(closeDb)),
                            height: yOf(-70) - yOf(0)
                        )
                        ctx.fill(Path(hystRect), with: .color(Color(hex: 0x3DDC97).opacity(0.12)))

                        let closeFloorDb = clampF(closeDb + floorDb, -70, closeDb)
                        let closeStartX = clampF(-70 - floorDb, -70, closeDb)
                        var hystCurve = Path()
                        hystCurve.move(to: CGPoint(x: xOf(-70), y: yOf(-70)))
                        if closeStartX > -70 {
                            hystCurve.addLine(to: CGPoint(x: xOf(closeStartX), y: yOf(-70)))
                        }
                        hystCurve.addLine(to: CGPoint(x: xOf(closeDb), y: yOf(closeFloorDb)))
                        hystCurve.addLine(to: CGPoint(x: xOf(closeDb), y: yOf(closeDb)))
                        hystCurve.addLine(to: CGPoint(x: xOf(openDb), y: yOf(openDb)))
                        ctx.stroke(hystCurve, with: .color(Color(hex: 0x3DDC97).opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }

                    // Main Gate transfer curve (accounts for Range/Floor attenuation)
                    let startX = clampF(-70 - floorDb, -70, openDb)
                    var curve = Path()
                    curve.move(to: CGPoint(x: xOf(-70), y: yOf(-70)))
                    if startX > -70 {
                        curve.addLine(to: CGPoint(x: xOf(startX), y: yOf(-70)))
                    }
                    curve.addLine(to: CGPoint(x: xOf(openDb), y: yOf(dropYDb)))
                    curve.addLine(to: CGPoint(x: xOf(openDb), y: yOf(openDb)))
                    curve.addLine(to: CGPoint(x: xOf(0), y: yOf(0)))
                    ctx.stroke(curve, with: .color(vm.params.gateOn ? Color(hex: 0x3DDC97) : .gray), lineWidth: 3)

                    // Live smooth input/output signal dot
                    if vm.isRunning {
                        let inDb = clampF(vm.inputLevelDb, -70, 0)
                        let outDb = vm.params.gateOn ? clampF(inDb - vm.gateGrDb, -70, 0) : inDb
                        let dotX = xOf(inDb), dotY = yOf(outDb)
                        let dot = Path(ellipseIn: CGRect(x: dotX - 4.5, y: dotY - 4.5, width: 9, height: 9))
                        ctx.fill(dot, with: .color(.white))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Draggable Range/Floor Handle (bottom of step) & Threshold Handle (knee)
                Circle()
                    .fill(Color(hex: 0x31C6FF))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                    .position(x: xOf(openDb), y: yOf(dropYDb))

                Circle()
                    .fill(Color(hex: 0x3DDC97))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .position(x: xOf(openDb), y: yOf(openDb))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if dragNode == nil {
                            let dOpen = hypot(val.location.x - xOf(openDb), val.location.y - yOf(openDb))
                            let dFloor = hypot(val.location.x - xOf(openDb), val.location.y - yOf(dropYDb))
                            dragNode = (dFloor < dOpen && abs(val.location.y - yOf(openDb)) > 10) ? 1 : 0
                        }
                        if dragNode == 0 {
                            let db = Float((val.location.x - pad) / max(w - 2 * pad, 1)) * 70 - 70
                            vm.params.gateThreshDb = clampF(db, -70, 0)
                        } else {
                            let yDb = Float((h - pad - val.location.y) / max(h - 2 * pad, 1)) * 70 - 70
                            vm.params.gateFloorDb = yDb <= -68.5 ? -70 : clampF(yDb - openDb, -70, 0)
                        }
                    }
                    .onEnded { _ in dragNode = nil }
            )
        }
    }
}

// MARK: - 2. S-Man EQ Page (Grid + Live Spectrum + Selected Fill + Draggable Bands + FX Volume)

struct SManEQPageView: View {
    @ObservedObject var vm: DarbukaEngine
    @Binding var selectedBand: Int
    private let colors: [Color] = [
        Color(hex: 0xFF9F43), Color(hex: 0xFFD166), Color(hex: 0x3DDC97),
        Color(hex: 0x31C6FF), Color(hex: 0xA77BFF), Color(hex: 0xFF5D8F)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man EQ", subtitle: "6-band parametric EQ + live RTA", accent: Color(hex: 0x31C6FF), isOn: $vm.params.eqOn)

                SManEQGraphView(vm: vm, selectedBand: $selectedBand, colors: colors)
                    .frame(height: 210)

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<6, id: \.self) { i in
                            Button("\(i + 1)") { selectedBand = i }
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(selectedBand == i ? colors[i] : Color.white.opacity(0.08))
                                .foregroundColor(selectedBand == i ? .black : .white)
                                .clipShape(Circle())
                                .opacity(vm.params.eqBands[i].isEnabled ? 1 : 0.4)
                        }
                        Spacer()
                        Button(vm.params.eqBands[selectedBand].isEnabled ? "BAND ON" : "BYPASS") {
                            vm.params.eqBands[selectedBand].isEnabled.toggle()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(vm.params.eqBands[selectedBand].isEnabled ? Color(hex: 0x3DDC97) : Color.white.opacity(0.1))
                        .foregroundColor(vm.params.eqBands[selectedBand].isEnabled ? .black : .white)
                        .cornerRadius(8)
                    }
                    HStack(spacing: 4) {
                        ForEach(EQBandType.allCases, id: \.self) { t in
                            Button(t.rawValue) { vm.params.eqBands[selectedBand].type = t }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(vm.params.eqBands[selectedBand].type == t ? Color(hex: 0x31C6FF) : Color.white.opacity(0.06))
                                .foregroundColor(vm.params.eqBands[selectedBand].type == t ? .black : Color(hex: 0x8B93A7))
                                .cornerRadius(7)
                        }
                    }
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                VStack(spacing: 10) {
                    ParamSlider(title: "FREQ", value: $vm.params.eqBands[selectedBand].freq, range: 20...20000, tint: Color(hex: 0x31C6FF), text: "\(Int(vm.params.eqBands[selectedBand].freq)) Hz")
                    ParamSlider(title: "GAIN", value: $vm.params.eqBands[selectedBand].gainDb, range: -18...18, tint: Color(hex: 0x31C6FF), text: String(format: "%+.1f dB", vm.params.eqBands[selectedBand].gainDb))
                    ParamSlider(title: "Q", value: $vm.params.eqBands[selectedBand].q, range: 0.2...12, tint: Color(hex: 0x31C6FF), text: String(format: "%.2f", vm.params.eqBands[selectedBand].q))
                    ParamSlider(title: "LOW CUT", value: $vm.params.hpfHz, range: 20...200, tint: Color(hex: 0x31C6FF), text: "\(Int(vm.params.hpfHz)) Hz")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.eqLevelDb, range: -24...12, tint: Color(hex: 0x31C6FF), text: String(format: "%+.1f dB", vm.params.eqLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }
}

private struct SManEQGraphView: View {
    @ObservedObject var vm: DarbukaEngine
    @Binding var selectedBand: Int
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x0B0E14))

                Canvas { ctx, size in
                    drawEQGrid(ctx, size: size)
                    drawSpectrum(ctx, size: size)
                    drawSelectedBandFill(ctx, size: size)
                    drawCombinedCurve(ctx, size: size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                ForEach(0..<min(6, vm.params.eqBands.count), id: \.self) { i in
                    let b = vm.params.eqBands[i]
                    let xPos = CGFloat(log10f(max(20, b.freq) / 20.0) / 3.0) * w
                    let yPos = (b.type == .highPass || b.type == .lowPass)
                        ? h / 2
                        : h / 2 - CGFloat(b.gainDb / 21.0) * (h / 2)

                    ZStack {
                        Circle()
                            .fill((vm.params.eqOn && b.isEnabled) ? colors[i] : Color.gray)
                            .frame(width: selectedBand == i ? 28 : 22, height: selectedBand == i ? 28 : 22)
                            .overlay(Circle().stroke(Color.white, lineWidth: selectedBand == i ? 2 : 0))
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .position(x: max(14, min(w - 14, xPos)), y: max(14, min(h - 14, yPos)))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                selectedBand = i
                                let normX = max(0, min(1, Float(val.location.x / max(w, 1))))
                                vm.params.eqBands[i].freq = 20.0 * powf(1000.0, normX)
                                if b.type != .highPass && b.type != .lowPass {
                                    let g = Float((h / 2 - val.location.y) / max(h / 2, 1)) * 21.0
                                    vm.params.eqBands[i].gainDb = max(-18, min(18, g))
                                }
                            }
                    )
                }
            }
        }
    }

    private func drawEQGrid(_ ctx: GraphicsContext, size: CGSize) {
        let freqs: [(Float, String?)] = [
            (30, "30"), (50, nil), (100, "100"), (200, nil), (500, "500"),
            (1000, "1k"), (2000, nil), (5000, "5k"), (10000, "10k"), (16000, nil)
        ]
        for (f, label) in freqs {
            let px = CGFloat(log10f(f / 20.0) / 3.0) * size.width
            var p = Path()
            p.move(to: CGPoint(x: px, y: 0))
            p.addLine(to: CGPoint(x: px, y: size.height))
            ctx.stroke(p, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
            if let label {
                ctx.draw(
                    Text(label).font(.system(size: 9)).foregroundColor(Color(hex: 0x8B93A7)),
                    at: CGPoint(x: px + 3, y: size.height - 9),
                    anchor: .leading
                )
            }
        }
        for dbVal in [-12, -6, 0, 6, 12] {
            let py = size.height / 2 - CGFloat(Float(dbVal) / 21.0) * (size.height / 2)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: py))
            p.addLine(to: CGPoint(x: size.width, y: py))
            ctx.stroke(p, with: .color(Color.white.opacity(dbVal == 0 ? 0.22 : 0.06)), lineWidth: 1)
        }
    }

    private func drawSpectrum(_ ctx: GraphicsContext, size: CGSize) {
        guard vm.isRunning, !vm.spectrumBins.isEmpty else { return }
        let count = vm.spectrumBins.count
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for i in 0..<count {
            let x = (CGFloat(i) + 0.5) / CGFloat(count) * size.width
            let y = size.height - CGFloat(vm.spectrumBins[i]) * (size.height * 0.78)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.20), Color(hex: 0x31C6FF).opacity(0.04)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    private func drawSelectedBandFill(_ ctx: GraphicsContext, size: CGSize) {
        guard vm.params.eqOn, selectedBand < vm.params.eqBands.count else { return }
        let b = vm.params.eqBands[selectedBand]
        guard b.isEnabled else { return }

        var f = BiquadFilter()
        f.configure(type: b.type, sampleRate: vm.actualSampleRate, freq: b.freq, gainDb: b.gainDb, q: b.q)

        var path = Path()
        let steps = 70
        for s in 0...steps {
            let frac = CGFloat(s) / CGFloat(steps)
            let freq = 20.0 * powf(1000.0, Float(frac))
            let db = max(-21, min(21, f.magnitudeDb(at: freq, sampleRate: vm.actualSampleRate)))
            let y = size.height / 2 - CGFloat(db / 21.0) * (size.height / 2)
            let pt = CGPoint(x: frac * size.width, y: y)
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        path.addLine(to: CGPoint(x: 0, y: size.height / 2))
        path.closeSubpath()
        ctx.fill(path, with: .color(colors[selectedBand].opacity(0.20)))
    }

    private func drawCombinedCurve(_ ctx: GraphicsContext, size: CGSize) {
        var filters: [BiquadFilter] = []
        var hp = BiquadFilter()
        hp.configure(type: .highPass, sampleRate: vm.actualSampleRate, freq: vm.params.hpfHz, gainDb: 0, q: 0.707)
        filters.append(hp)
        if vm.params.eqOn {
            for b in vm.params.eqBands where b.isEnabled {
                var f = BiquadFilter()
                f.configure(type: b.type, sampleRate: vm.actualSampleRate, freq: b.freq, gainDb: b.gainDb, q: b.q)
                filters.append(f)
            }
        }

        var path = Path()
        let steps = 80
        for s in 0...steps {
            let frac = CGFloat(s) / CGFloat(steps)
            let freq = 20.0 * powf(1000.0, Float(frac))
            let totalDb = filters.reduce(Float(0)) { $0 + $1.magnitudeDb(at: freq, sampleRate: vm.actualSampleRate) }
            let clamped = max(-21, min(21, totalDb))
            let y = size.height / 2 - CGFloat(clamped / 21.0) * (size.height / 2)
            let pt = CGPoint(x: frac * size.width, y: y)
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(vm.params.eqOn ? Color(hex: 0xFFD166) : .gray), lineWidth: 2.5)
    }
}

// MARK: - 3. S-Man Comp Page (Transfer Curve + FX Volume)

struct CompPageView: View {
    @ObservedObject var vm: DarbukaEngine
    @State private var dragNode: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Comp", subtitle: "Transfer curve + gain reduction", accent: Color(hex: 0xFF9F43), isOn: $vm.params.compOn)

                compCurveCard.frame(height: 165)

                HStack {
                    Text("GAIN REDUCTION").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                    Spacer()
                    Text(String(format: "-%.1f dB", vm.compGrDb)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundColor(Color(hex: 0xFF9F43))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(14)

                VStack(spacing: 10) {
                    ParamSlider(title: "THRESH", value: $vm.params.compThreshDb, range: -40...0, tint: Color(hex: 0xFF9F43), text: String(format: "%.1f dB", vm.params.compThreshDb))
                    ParamSlider(title: "RATIO", value: $vm.params.compRatio, range: 1...6, tint: Color(hex: 0xFF9F43), text: String(format: "%.1f:1", vm.params.compRatio))
                    ParamSlider(title: "ATTACK", value: $vm.params.compAttackMs, range: 5...50, tint: Color(hex: 0xFF9F43), text: "\(Int(vm.params.compAttackMs)) ms")
                    ParamSlider(title: "RELEASE", value: $vm.params.compReleaseMs, range: 40...300, tint: Color(hex: 0xFF9F43), text: "\(Int(vm.params.compReleaseMs)) ms")
                    ParamSlider(title: "MAKEUP", value: $vm.params.compMakeupDb, range: 0...12, tint: Color(hex: 0xFF9F43), text: String(format: "%.1f dB", vm.params.compMakeupDb))
                    ParamSlider(title: "FX VOLUME", value: $vm.params.compLevelDb, range: -24...12, tint: Color(hex: 0xFF9F43), text: String(format: "%+.1f dB", vm.params.compLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private func compOutDb(_ inDb: Float) -> Float {
        inDb < vm.params.compThreshDb ? inDb : vm.params.compThreshDb + (inDb - vm.params.compThreshDb) / max(1, vm.params.compRatio)
    }

    private var compCurveCard: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 18
            let xOf: (Float) -> CGFloat = { db in pad + CGFloat((db + 60) / 60) * (w - 2 * pad) }
            let yOf: (Float) -> CGFloat = { db in h - pad - CGFloat((db + 60) / 60) * (h - 2 * pad) }

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x0B0E14))
                Canvas { ctx, _ in
                    for d in stride(from: -48, through: -12, by: 12) {
                        var v = Path()
                        v.move(to: CGPoint(x: xOf(Float(d)), y: yOf(-60)))
                        v.addLine(to: CGPoint(x: xOf(Float(d)), y: yOf(0)))
                        ctx.stroke(v, with: .color(Color.white.opacity(0.08)), lineWidth: 1)

                        var hz = Path()
                        hz.move(to: CGPoint(x: xOf(-60), y: yOf(Float(d))))
                        hz.addLine(to: CGPoint(x: xOf(0), y: yOf(Float(d))))
                        ctx.stroke(hz, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                    }
                    var ref = Path()
                    ref.move(to: CGPoint(x: xOf(-60), y: yOf(-60)))
                    ref.addLine(to: CGPoint(x: xOf(0), y: yOf(0)))
                    ctx.stroke(ref, with: .color(Color.white.opacity(0.16)), lineWidth: 1)

                    var curve = Path()
                    curve.move(to: CGPoint(x: xOf(-60), y: yOf(-60)))
                    curve.addLine(to: CGPoint(x: xOf(vm.params.compThreshDb), y: yOf(vm.params.compThreshDb)))
                    curve.addLine(to: CGPoint(x: xOf(0), y: yOf(compOutDb(0))))
                    ctx.stroke(curve, with: .color(vm.params.compOn ? Color(hex: 0xFF9F43) : .gray), lineWidth: 3)

                    if vm.isRunning && vm.inputLevelDb > -59 {
                        let dotX = xOf(vm.inputLevelDb)
                        let dotY = yOf(compOutDb(vm.inputLevelDb))
                        let dot = Path(ellipseIn: CGRect(x: dotX - 4.5, y: dotY - 4.5, width: 9, height: 9))
                        ctx.fill(dot, with: .color(.white))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                ForEach([0, 1], id: \.self) { idx in
                    let px = idx == 0 ? xOf(vm.params.compThreshDb) : xOf(0)
                    let py = idx == 0 ? yOf(vm.params.compThreshDb) : yOf(compOutDb(0))
                    Circle()
                        .fill(Color(hex: 0xFF9F43))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: px, y: py)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if dragNode == nil {
                            let d0 = hypot(val.location.x - xOf(vm.params.compThreshDb), val.location.y - yOf(vm.params.compThreshDb))
                            let d1 = hypot(val.location.x - xOf(0), val.location.y - yOf(compOutDb(0)))
                            dragNode = d0 <= d1 ? 0 : 1
                        }
                        if dragNode == 0 {
                            let db = Float((val.location.x - pad) / max(w - 2 * pad, 1)) * 60 - 60
                            vm.params.compThreshDb = clampF(db, -40, -1)
                        } else {
                            let yDb = Float((h - pad - val.location.y) / max(h - 2 * pad, 1)) * 60 - 60
                            let minOut = vm.params.compThreshDb + (-vm.params.compThreshDb) / 6.0
                            let clampedOut = clampF(yDb, minOut, 0)
                            let denom = max(0.5, clampedOut - vm.params.compThreshDb)
                            vm.params.compRatio = clampF(-vm.params.compThreshDb / denom, 1, 6)
                        }
                    }
                    .onEnded { _ in dragNode = nil }
            )
        }
    }
}

// MARK: - 4. S-Man Saturation Page (Waveshaper Curve + FX Volume)

struct SaturationPageView: View {
    @ObservedObject var vm: DarbukaEngine
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Saturation", subtitle: "Warm tube / transistor drive + cab sim", accent: Color(hex: 0xFF5D8F), isOn: $vm.params.satOn)

                satCurveView.frame(height: 140)

                HStack {
                    Text("SPEAKER / CABINET SIM").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                    Spacer()
                    Toggle("", isOn: $vm.params.cabSimOn).labelsHidden().tint(Color(hex: 0x3DDC97))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(14)

                VStack(spacing: 10) {
                    ParamSlider(title: "DRIVE", value: $vm.params.satDriveDb, range: 0...24, tint: Color(hex: 0xFF5D8F), text: String(format: "%.1f dB", vm.params.satDriveDb))
                    ParamSlider(title: "WARMTH", value: $vm.params.satWarmth, range: 0...1, tint: Color(hex: 0xFF5D8F), text: "\(Int(vm.params.satWarmth * 100))%")
                    ParamSlider(title: "TONE", value: $vm.params.satToneHz, range: 2000...20000, tint: Color(hex: 0xFF5D8F), text: "\(Int(vm.params.satToneHz)) Hz")
                    ParamSlider(title: "MIX", value: $vm.params.satMix, range: 0...1, tint: Color(hex: 0xFF5D8F), text: "\(Int(vm.params.satMix * 100))%")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.satLevelDb, range: -24...12, tint: Color(hex: 0xFF5D8F), text: String(format: "%+.1f dB", vm.params.satLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private var satCurveView: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            var axes = Path()
            axes.move(to: CGPoint(x: 0, y: size.height / 2))
            axes.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            axes.move(to: CGPoint(x: size.width / 2, y: 0))
            axes.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            ctx.stroke(axes, with: .color(Color.white.opacity(0.12)), lineWidth: 1)

            let g = dbToLin(vm.params.satDriveDb)
            let bias = vm.params.satWarmth * 0.3
            let norm = max(0.001, tanhf(g))
            var curve = Path()
            let steps = 80
            for s in 0...steps {
                let frac = Float(s) / Float(steps)
                let v = frac * 2 - 1
                let yVal = clampF((tanhf(g * v + bias) - tanhf(bias)) / norm, -1, 1)
                let pt = CGPoint(x: CGFloat(frac) * size.width,
                                 y: size.height / 2 - CGFloat(yVal) * (size.height * 0.43))
                if s == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
            }
            ctx.stroke(curve, with: .color(vm.params.satOn ? Color(hex: 0xFF5D8F) : .gray), lineWidth: 3)

            if vm.params.cabSimOn {
                ctx.draw(Text("CAB SIM").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: 0x3DDC97)),
                         at: CGPoint(x: size.width - 10, y: 12), anchor: .trailing)
            }
        }
    }
}

// MARK: - 5. S-Man Tape Page (Animated Spinning Reels + Mix + FX Volume)

struct TapePageView: View {
    @ObservedObject var vm: DarbukaEngine
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Tape", subtitle: "Analog tape warmth, bump & flutter", accent: Color(hex: 0xF2B66D), isOn: $vm.params.tapeOn)

                TapeReelsView(spinning: vm.isRunning && vm.params.tapeOn, flutter: vm.params.tapeFlutter)
                    .frame(height: 115)
                    .padding(10)
                    .background(Color(hex: 0x10141D))
                    .cornerRadius(16)

                VStack(spacing: 10) {
                    ParamSlider(title: "DRIVE", value: $vm.params.tapeDriveDb, range: 0...18, tint: Color(hex: 0xF2B66D), text: String(format: "%.1f dB", vm.params.tapeDriveDb))
                    ParamSlider(title: "BUMP", value: $vm.params.tapeBumpDb, range: 0...6, tint: Color(hex: 0xF2B66D), text: String(format: "%.1f dB", vm.params.tapeBumpDb))
                    ParamSlider(title: "TONE", value: $vm.params.tapeToneHz, range: 3000...20000, tint: Color(hex: 0xF2B66D), text: "\(Int(vm.params.tapeToneHz)) Hz")
                    ParamSlider(title: "FLUTTER", value: $vm.params.tapeFlutter, range: 0...1, tint: Color(hex: 0xF2B66D), text: "\(Int(vm.params.tapeFlutter * 100))%")
                    ParamSlider(title: "MIX", value: $vm.params.tapeMix, range: 0...1, tint: Color(hex: 0x3DDC97), text: "\(Int(vm.params.tapeMix * 100))%")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.tapeLevelDb, range: -24...12, tint: Color(hex: 0xF2B66D), text: String(format: "%+.1f dB", vm.params.tapeLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }
}

private struct TapeReelsView: View {
    let spinning: Bool
    let flutter: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !spinning)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let wobble = spinning ? Double(flutter) * 0.25 * sin(t * 9.0) : 0
            let angle = spinning ? (t * 2.8 + wobble) : 0
            Canvas { ctx, size in
                let accent = Color(hex: 0xF2B66D)
                let y = size.height * 0.46
                let r = min(size.height * 0.36, 36)
                let cL = CGPoint(x: size.width * 0.27, y: y)
                let cR = CGPoint(x: size.width * 0.73, y: y)

                var tapePath = Path()
                tapePath.move(to: CGPoint(x: cL.x - r * 0.5, y: size.height * 0.88))
                let sag = spinning ? CGFloat(sin(t * 7.5) * Double(flutter) * 4.0) : 0
                tapePath.addQuadCurve(
                    to: CGPoint(x: cR.x + r * 0.5, y: size.height * 0.88),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.88 + sag)
                )
                ctx.stroke(tapePath, with: .color(accent.opacity(0.45)), lineWidth: 3)

                for center in [cL, cR] {
                    drawReel(ctx, center: center, radius: r, angle: angle, color: accent)
                }
            }
        }
    }

    private func drawReel(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double, color: Color) {
        let outer = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let innerR = radius * 0.22
        let inner = Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2))
        ctx.stroke(outer, with: .color(color), lineWidth: 3.2)
        ctx.stroke(inner, with: .color(color), lineWidth: 2.5)

        var spokes = Path()
        for k in 0..<3 {
            let a = angle + Double(k) * (2.0 * Double.pi / 3.0)
            spokes.move(to: CGPoint(x: center.x + CGFloat(cos(a)) * innerR, y: center.y + CGFloat(sin(a)) * innerR))
            spokes.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius))
        }
        ctx.stroke(spokes, with: .color(color), lineWidth: 3)
    }
}

// MARK: - 6. S-Man Delay Page (Taps + Dedicated Wet EQ + FX Volume)

struct DelayPageView: View {
    @ObservedObject var vm: DarbukaEngine
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Delay", subtitle: "Stereo / Ping-Pong / Tape / Analog", accent: Color(hex: 0x00E5FF), isOn: $vm.params.delayOn)

                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        ForEach(DelayMode.allCases, id: \.self) { m in
                            Button(m.rawValue) { vm.params.delayMode = m }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(vm.params.delayMode == m ? Color(hex: 0x00E5FF) : Color.white.opacity(0.06))
                                .foregroundColor(vm.params.delayMode == m ? .black : Color(hex: 0x8B93A7))
                                .cornerRadius(9)
                        }
                    }

                    HStack(spacing: 6) {
                        Button(vm.params.delaySync ? "SYNC ON" : "FREE ms") { vm.params.delaySync.toggle() }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(vm.params.delaySync ? Color(hex: 0x00E5FF) : Color.white.opacity(0.08))
                            .foregroundColor(vm.params.delaySync ? .black : .white)
                            .cornerRadius(8)

                        Button("TAP TEMPO") { vm.tapTempo() }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(8)

                        Spacer()
                        Text("\(Int(vm.params.delayBpm)) BPM · \(Int(vm.params.effectiveDelayMs)) ms")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(Color(hex: 0x00E5FF))
                    }

                    if vm.params.delaySync {
                        HStack(spacing: 5) {
                            ForEach(DelayDivision.allCases, id: \.self) { div in
                                Button(div.rawValue) { vm.params.delayDivision = div }
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(vm.params.delayDivision == div ? Color(hex: 0x00E5FF) : Color.white.opacity(0.06))
                                    .foregroundColor(vm.params.delayDivision == div ? .black : Color(hex: 0x8B93A7))
                                    .cornerRadius(7)
                            }
                        }
                    }
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                delayTapCanvas.frame(height: 135)

                VStack(spacing: 10) {
                    if !vm.params.delaySync {
                        ParamSlider(title: "TIME", value: $vm.params.delayTimeMs, range: 20...1500, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayTimeMs)) ms")
                    } else {
                        ParamSlider(title: "BPM", value: $vm.params.delayBpm, range: 40...240, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayBpm)) BPM")
                    }
                    ParamSlider(title: "FEEDBACK", value: $vm.params.delayFeedback, range: 0...0.9, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayFeedback * 100))%")
                    ParamSlider(title: "MOD / WIDTH", value: $vm.params.delayModWidth, range: 0...1, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayModWidth * 100))%")
                    ParamSlider(title: "MIX", value: $vm.params.delayMix, range: 0...0.8, tint: Color(hex: 0x3DDC97), text: "\(Int(vm.params.delayMix * 100))%")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.delayLevelDb, range: -24...12, tint: Color(hex: 0x00E5FF), text: String(format: "%+.1f dB", vm.params.delayLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                // Dedicated Delay Wet EQ
                VStack(alignment: .leading, spacing: 10) {
                    Text("S-MAN DELAY EQ (WET)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: 0x00E5FF))
                    WetEQCurveCanvas(
                        sampleRate: vm.actualSampleRate,
                        lowCutHz: vm.params.delayLowCutHz,
                        highCutHz: vm.params.delayHighCutHz,
                        lowFreq: 160, lowDb: vm.params.delayEqLowDb,
                        midFreq: 1000, midDb: vm.params.delayEqMidDb,
                        highFreq: 5500, highDb: vm.params.delayEqHighDb,
                        accent: Color(hex: 0x00E5FF),
                        enabled: vm.params.delayOn
                    ).frame(height: 68)
                    ParamSlider(title: "LOW CUT", value: $vm.params.delayLowCutHz, range: 40...800, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayLowCutHz)) Hz")
                    ParamSlider(title: "HIGH CUT", value: $vm.params.delayHighCutHz, range: 1200...16000, tint: Color(hex: 0x00E5FF), text: "\(Int(vm.params.delayHighCutHz)) Hz")
                    ParamSlider(title: "EQ LOW", value: $vm.params.delayEqLowDb, range: -12...12, tint: Color(hex: 0x00E5FF), text: String(format: "%+.1f dB", vm.params.delayEqLowDb))
                    ParamSlider(title: "EQ MID", value: $vm.params.delayEqMidDb, range: -12...12, tint: Color(hex: 0x00E5FF), text: String(format: "%+.1f dB", vm.params.delayEqMidDb))
                    ParamSlider(title: "EQ HIGH", value: $vm.params.delayEqHighDb, range: -12...12, tint: Color(hex: 0x00E5FF), text: String(format: "%+.1f dB", vm.params.delayEqHighDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private var delayTapCanvas: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            let mid = size.height / 2
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: mid))
            axis.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(axis, with: .color(Color.white.opacity(0.12)), lineWidth: 1)

            ctx.draw(Text("L").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7)), at: CGPoint(x: 10, y: 12))
            ctx.draw(Text("R").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7)), at: CGPoint(x: 10, y: size.height - 12))

            var dry = Path()
            dry.move(to: CGPoint(x: 26, y: mid - 36))
            dry.addLine(to: CGPoint(x: 26, y: mid + 36))
            ctx.stroke(dry, with: .color(Color.white.opacity(0.85)), lineWidth: 3)

            let ms = vm.params.effectiveDelayMs
            let fb = vm.params.delayFeedback
            let totalMs: Float = 2600
            let warm = vm.params.delayMode == .tape || vm.params.delayMode == .analog
            let colL = vm.params.delayOn ? (warm ? Color(hex: 0xF2B66D) : Color(hex: 0x00E5FF)) : .gray
            let colR = vm.params.delayOn ? (warm ? Color(hex: 0xFF9F43) : Color(hex: 0x3DDC97)) : .gray

            var prev = CGPoint(x: 26, y: mid)
            for n in 1...12 {
                let tMs = Float(n) * ms
                if tMs > totalMs { break }
                let px = 26 + CGFloat(tMs / totalMs) * (size.width - 40)
                let amp = powf(max(0.06, fb), Float(n)) * 0.92
                let bh = max(4, CGFloat(amp) * (mid - 14))

                if vm.params.delayMode == .pingPong {
                    let isL = n % 2 == 1
                    let ty = isL ? (mid - bh) : (mid + bh)
                    var link = Path()
                    link.move(to: prev)
                    link.addLine(to: CGPoint(x: px, y: ty))
                    ctx.stroke(link, with: .color(vm.params.delayOn ? Color(hex: 0x00E5FF).opacity(0.22) : Color.white.opacity(0.08)), lineWidth: 1.5)
                    prev = CGPoint(x: px, y: ty)

                    var bar = Path()
                    bar.move(to: CGPoint(x: px, y: mid))
                    bar.addLine(to: CGPoint(x: px, y: ty))
                    ctx.stroke(bar, with: .color(isL ? colL : colR), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else {
                    let off = CGFloat(vm.params.delayModWidth * 5)
                    var barL = Path()
                    barL.move(to: CGPoint(x: px, y: mid - 2))
                    barL.addLine(to: CGPoint(x: px, y: mid - bh))
                    ctx.stroke(barL, with: .color(colL), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                    var barR = Path()
                    barR.move(to: CGPoint(x: px + off, y: mid + 2))
                    barR.addLine(to: CGPoint(x: px + off, y: mid + bh * 0.9))
                    ctx.stroke(barR, with: .color(colR), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - 7. S-Man Reverb Page (Envelope + Dedicated Wet EQ + FX Volume)

struct ReverbPageView: View {
    @ObservedObject var vm: DarbukaEngine
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Reverb", subtitle: "Studio Hall / Room / Plate / Chamber", accent: Color(hex: 0xA77BFF), isOn: $vm.params.revOn)

                HStack(spacing: 6) {
                    ForEach(ReverbMode.allCases, id: \.self) { m in
                        Button(m.rawValue) { vm.params.revMode = m }
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(vm.params.revMode == m ? Color(hex: 0xA77BFF) : Color.white.opacity(0.06))
                            .foregroundColor(vm.params.revMode == m ? .black : Color(hex: 0x8B93A7))
                            .cornerRadius(9)
                    }
                }.padding(10).background(Color(hex: 0x10141D)).cornerRadius(14)

                reverbEnvelopeCanvas.frame(height: 135)

                VStack(spacing: 10) {
                    ParamSlider(title: "SIZE", value: $vm.params.revSize, range: 0.1...1.0, tint: Color(hex: 0xA77BFF), text: "\(Int(vm.params.revSize * 100))%")
                    ParamSlider(title: "DECAY", value: $vm.params.revDecaySec, range: 0.3...6.0, tint: Color(hex: 0xA77BFF), text: String(format: "%.2f s", vm.params.revDecaySec))
                    ParamSlider(title: "PRE-DELAY", value: $vm.params.revPreDelayMs, range: 0...120, tint: Color(hex: 0xA77BFF), text: "\(Int(vm.params.revPreDelayMs)) ms")
                    ParamSlider(title: "WIDTH", value: $vm.params.revWidth, range: 0...1, tint: Color(hex: 0xA77BFF), text: "\(Int(vm.params.revWidth * 100))%")
                    ParamSlider(title: "MIX", value: $vm.params.revMix, range: 0...0.8, tint: Color(hex: 0x3DDC97), text: "\(Int(vm.params.revMix * 100))%")
                    ParamSlider(title: "FX VOLUME", value: $vm.params.revLevelDb, range: -24...12, tint: Color(hex: 0xA77BFF), text: String(format: "%+.1f dB", vm.params.revLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                // Dedicated Reverb Wet EQ
                VStack(alignment: .leading, spacing: 10) {
                    Text("S-MAN REVERB EQ (WET)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: 0xA77BFF))
                    WetEQCurveCanvas(
                        sampleRate: vm.actualSampleRate,
                        lowCutHz: vm.params.revLowCutHz,
                        highCutHz: vm.params.revDampingHz,
                        lowFreq: 180, lowDb: vm.params.revEqLowDb,
                        midFreq: 1200, midDb: vm.params.revEqMidDb,
                        highFreq: 6000, highDb: vm.params.revEqHighDb,
                        accent: Color(hex: 0xA77BFF),
                        enabled: vm.params.revOn
                    ).frame(height: 68)
                    ParamSlider(title: "LOW CUT", value: $vm.params.revLowCutHz, range: 40...500, tint: Color(hex: 0xA77BFF), text: "\(Int(vm.params.revLowCutHz)) Hz")
                    ParamSlider(title: "DAMPING", value: $vm.params.revDampingHz, range: 1500...16000, tint: Color(hex: 0xA77BFF), text: "\(Int(vm.params.revDampingHz)) Hz")
                    ParamSlider(title: "EQ LOW", value: $vm.params.revEqLowDb, range: -12...12, tint: Color(hex: 0xA77BFF), text: String(format: "%+.1f dB", vm.params.revEqLowDb))
                    ParamSlider(title: "EQ MID", value: $vm.params.revEqMidDb, range: -12...12, tint: Color(hex: 0xA77BFF), text: String(format: "%+.1f dB", vm.params.revEqMidDb))
                    ParamSlider(title: "EQ HIGH", value: $vm.params.revEqHighDb, range: -12...12, tint: Color(hex: 0xA77BFF), text: String(format: "%+.1f dB", vm.params.revEqHighDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private var reverbEnvelopeCanvas: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            let maxT: Float = 6.5
            let xOf: (Float) -> CGFloat = { t in CGFloat(t / maxT) * (size.width - 24) + 12 }
            let baseY = size.height - 20

            for t in [0, 1, 2, 4, 6] {
                let px = xOf(Float(t))
                var grid = Path()
                grid.move(to: CGPoint(x: px, y: 8))
                grid.addLine(to: CGPoint(x: px, y: size.height - 18))
                ctx.stroke(grid, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
                ctx.draw(Text("\(t)s").font(.system(size: 9)).foregroundColor(Color(hex: 0x8B93A7)),
                         at: CGPoint(x: px + 4, y: size.height - 9), anchor: .leading)
            }

            let pre = vm.params.revPreDelayMs / 1000.0
            let dec = clampF(vm.params.revDecaySec * (0.55 + vm.params.revSize * 0.75), 0.3, 6.2)
            let sx = xOf(pre)
            let ex = xOf(min(maxT, pre + dec))
            let atk: Float = vm.params.revMode == .hall ? 0.20 : (vm.params.revMode == .plate ? 0.04 : 0.08)
            let pxPeak = xOf(min(maxT, pre + atk))

            var env = Path()
            env.move(to: CGPoint(x: sx, y: baseY))
            env.addLine(to: CGPoint(x: pxPeak, y: 20))
            for i in 1...32 {
                let f = Float(i) / 32.0
                let x = pxPeak + CGFloat(f) * (ex - pxPeak)
                let y = baseY - CGFloat(powf(1 - f, 2.4)) * (size.height - 40)
                env.addLine(to: CGPoint(x: x, y: y))
            }
            env.addLine(to: CGPoint(x: ex, y: baseY))
            env.closeSubpath()

            let topCol = vm.params.revOn ? Color(hex: 0xA77BFF).opacity(0.45) : Color.gray.opacity(0.2)
            ctx.fill(env, with: .linearGradient(
                Gradient(colors: [topCol, Color(hex: 0xA77BFF).opacity(0.03)]),
                startPoint: CGPoint(x: 0, y: 20),
                endPoint: CGPoint(x: 0, y: baseY)
            ))

            let dampRatio = clampF(log10f(vm.params.revDampingHz / 1500) / log10f(16000 / 1500), 0.15, 1)
            let dex = pxPeak + (ex - pxPeak) * CGFloat(dampRatio)
            var dampPath = Path()
            dampPath.move(to: CGPoint(x: pxPeak, y: 28))
            for i in 1...20 {
                let f = Float(i) / 20.0
                let x = pxPeak + CGFloat(f) * (dex - pxPeak)
                let y = baseY - CGFloat(powf(1 - f, 2.8)) * (size.height - 48)
                dampPath.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(dampPath, with: .color(vm.params.revOn ? Color(hex: 0x31C6FF) : .gray),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
    }
}

private struct WetEQCurveCanvas: View {
    let sampleRate: Float
    let lowCutHz: Float
    let highCutHz: Float
    let lowFreq: Float
    let lowDb: Float
    let midFreq: Float
    let midDb: Float
    let highFreq: Float
    let highDb: Float
    let accent: Color
    let enabled: Bool

    var body: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: size.height / 2))
            zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(zero, with: .color(Color.white.opacity(0.14)), lineWidth: 1)

            var hp = BiquadFilter(), lp = BiquadFilter(), lf = BiquadFilter(), mf = BiquadFilter(), hf = BiquadFilter()
            hp.configure(type: .highPass, sampleRate: sampleRate, freq: lowCutHz, gainDb: 0, q: 0.707)
            lp.configure(type: .lowPass, sampleRate: sampleRate, freq: highCutHz, gainDb: 0, q: 0.707)
            lf.configure(type: .lowShelf, sampleRate: sampleRate, freq: lowFreq, gainDb: lowDb, q: 0.707)
            mf.configure(type: .bell, sampleRate: sampleRate, freq: midFreq, gainDb: midDb, q: 0.9)
            hf.configure(type: .highShelf, sampleRate: sampleRate, freq: highFreq, gainDb: highDb, q: 0.707)

            var path = Path()
            let steps = 60
            for s in 0...steps {
                let frac = CGFloat(s) / CGFloat(steps)
                let f = 20.0 * powf(1000.0, Float(frac))
                let db = hp.magnitudeDb(at: f, sampleRate: sampleRate)
                    + lp.magnitudeDb(at: f, sampleRate: sampleRate)
                    + lf.magnitudeDb(at: f, sampleRate: sampleRate)
                    + mf.magnitudeDb(at: f, sampleRate: sampleRate)
                    + hf.magnitudeDb(at: f, sampleRate: sampleRate)
                let y = size.height / 2 - CGFloat(clampF(db, -15, 15) / 15.0) * (size.height * 0.44)
                let pt = CGPoint(x: frac * size.width, y: y)
                if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(enabled ? accent : .gray), lineWidth: 2.2)
        }
    }
}

// MARK: - 8. S-Man Limiter Page (Scrolling Peak + GR Graph + FX Volume)

struct LimiterPageView: View {
    @ObservedObject var vm: DarbukaEngine
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionHeader(title: "S-Man Limiter", subtitle: "Lookahead brickwall protection", accent: Color(hex: 0xFF5A5A), isOn: nil)

                limiterScopeGraph.frame(height: 130)

                VStack(spacing: 8) {
                    HStack {
                        Text("OUTPUT").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                        Spacer()
                        Text(String(format: "%.1f dB", vm.outputLevelDb)).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundColor(.white)
                    }
                    MeterBar(levelNorm: CGFloat(max(0, min(1, (vm.outputLevelDb + 60) / 60))),
                             markerNorm: CGFloat((vm.params.limiterCeilingDb + 60) / 60),
                             color: Color(hex: 0x3DDC97))

                    HStack {
                        Text("GR").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                        Spacer()
                        Text(String(format: "-%.1f dB", vm.limGrDb)).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundColor(Color(hex: 0xFF5A5A))
                    }
                    .padding(.top, 4)
                    MeterBar(levelNorm: CGFloat(min(1, vm.limGrDb / 12.0)), markerNorm: nil, color: Color(hex: 0xFF5A5A))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                VStack(spacing: 10) {
                    ParamSlider(title: "CEILING", value: $vm.params.limiterCeilingDb, range: -6...0, tint: Color(hex: 0xFF5A5A), text: String(format: "%.1f dB", vm.params.limiterCeilingDb))
                    ParamSlider(title: "FX VOLUME", value: $vm.params.limiterLevelDb, range: -24...6, tint: Color(hex: 0xFF5A5A), text: String(format: "%+.1f dB", vm.params.limiterLevelDb))
                }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
            }.padding(14)
        }
    }

    private var limiterScopeGraph: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
            ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

            let yOf: (Float) -> CGFloat = { db in
                let norm = clampF((db + 60) / 60, 0, 1)
                return size.height - 10 - CGFloat(norm) * (size.height - 20)
            }

            let outHist = vm.limOutHistory
            let grHist = vm.limGrHistory
            if outHist.count >= 2 {
                var outPath = Path()
                var grPath = Path()
                for i in outHist.indices {
                    let x = CGFloat(i) / CGFloat(outHist.count - 1) * size.width
                    let oy = yOf(outHist[i])
                    let gy = 8 + CGFloat(clampF(grHist[i] / 12.0, 0, 1)) * (size.height * 0.65)
                    if i == 0 {
                        outPath.move(to: CGPoint(x: x, y: oy))
                        grPath.move(to: CGPoint(x: x, y: 8))
                        grPath.addLine(to: CGPoint(x: x, y: gy))
                    } else {
                        outPath.addLine(to: CGPoint(x: x, y: oy))
                        grPath.addLine(to: CGPoint(x: x, y: gy))
                    }
                }
                grPath.addLine(to: CGPoint(x: size.width, y: 8))
                grPath.closeSubpath()
                ctx.fill(grPath, with: .color(Color(hex: 0xFF5A5A).opacity(0.32)))
                ctx.stroke(outPath, with: .color(Color(hex: 0x3DDC97)), lineWidth: 2.2)
            }

            let ceilY = yOf(vm.params.limiterCeilingDb)
            var ceilLine = Path()
            ceilLine.move(to: CGPoint(x: 0, y: ceilY))
            ceilLine.addLine(to: CGPoint(x: size.width, y: ceilY))
            ctx.stroke(ceilLine, with: .color(Color(hex: 0xFF5A5A)), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
        }
    }
}

// MARK: - 9. S-Man Ensemble Page (Realistic Concert Stereo Stage + FX Volume)

struct EnsemblePagedView: View {
    @ObservedObject var vm: DarbukaEngine
    @Binding var subPage: Int

    private let tabs = ["Stage & Mix", "Violin 1–2", "Violin 3–4", "Violin 5–6"]
    private let presets = ["Solo + Wide", "Lush Tutti", "Octave Shimmer"]

    var body: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "S-Man Ensemble", subtitle: "6-Voice Violin Layering", accent: Color(hex: 0xC57BFF), isOn: $vm.params.ensemble.enabled)
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button(tabs[i]) { withAnimation { subPage = i } }
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(subPage == i ? Color(hex: 0xC57BFF).opacity(0.22) : Color(hex: 0x10141D))
                        .foregroundColor(subPage == i ? Color(hex: 0xC57BFF) : Color(hex: 0x8B93A7))
                        .cornerRadius(9)
                }
            }.padding(.horizontal, 14)

            TabView(selection: $subPage) {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STEREO STAGE & LAYER DISTRIBUTION")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0xC57BFF))
                            HStack {
                                Text("\(vm.params.ensemble.voices.filter { $0.isActive }.count) Active Layers")
                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                Spacer()
                                Text(String(format: "Detune: %.1f ct | Mix: %d%%", vm.params.ensemble.detuneCents, Int(round(vm.params.ensemble.mix * 100))))
                                    .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: 0x8B93A7))
                            }
                            StereoStageMap(
                                voices: $vm.params.ensemble.voices,
                                width: vm.params.ensemble.stereoWidth,
                                detuneCents: vm.params.ensemble.detuneCents,
                                enabled: vm.params.ensemble.enabled,
                                isRunning: vm.isRunning
                            )
                        }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)

                        VStack(spacing: 10) {
                            ParamSlider(title: "Mix (Wet / Dry)", value: $vm.params.ensemble.mix, range: 0...1, tint: Color(hex: 0x3DDC97), text: "\(Int(round(vm.params.ensemble.mix * 100)))%")
                            ParamSlider(title: "FX VOLUME", value: $vm.params.ensemble.levelDb, range: -24...12, tint: Color(hex: 0xC57BFF), text: String(format: "%+.1f dB", vm.params.ensemble.levelDb))
                            ParamSlider(title: "Group Detune", value: $vm.params.ensemble.detuneCents, range: 0...25, tint: Color(hex: 0xC57BFF), text: String(format: "%.1f ct", vm.params.ensemble.detuneCents))
                            ParamSlider(title: "Stereo Width", value: $vm.params.ensemble.stereoWidth, range: 0...1, tint: Color(hex: 0xFF9F43), text: "\(Int(round(vm.params.ensemble.stereoWidth * 100)))%")
                            HStack(spacing: 6) {
                                ForEach(presets, id: \.self) { name in
                                    Button(name) { vm.applyEnsemblePreset(name) }
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(vm.params.ensemble.presetName == name ? Color(hex: 0xC57BFF) : Color.white.opacity(0.08))
                                        .foregroundColor(vm.params.ensemble.presetName == name ? .black : .white)
                                        .cornerRadius(9)
                                }
                            }
                        }.padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
                    }.padding(.horizontal, 14)
                }.tag(0)

                ForEach(0..<3, id: \.self) { p in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<2, id: \.self) { k in
                                let vIdx = p * 2 + k
                                ViolinCardView(index: vIdx, voice: $vm.params.ensemble.voices[vIdx])
                            }
                        }.padding(.horizontal, 14)
                    }.tag(p + 1)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

struct StereoStageMap: View {
    @Binding var voices: [EnsembleVoiceParams]
    let width: Float
    let detuneCents: Float
    let enabled: Bool
    let isRunning: Bool

    @State private var draggedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(enabled && isRunning))) { timeline in
                let tNow = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let origin = CGPoint(x: w / 2, y: h * 0.16)

                    ZStack {
                        Canvas { ctx, size in
                            drawStageEnvironment(ctx, size: size, origin: origin, tNow: tNow)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        ForEach(voices.indices, id: \.self) { i in
                            let v = voices[i]
                            let active = enabled && v.isActive
                            let pos = voicePoint(index: i, voice: v, width: w, height: h, tNow: active && isRunning ? tNow : 0)
                            let col = voiceColor(v.octave)
                            let glowSize = CGFloat(24 + v.volume * 20)

                            ZStack {
                                if active {
                                    Circle()
                                        .fill(col.opacity(0.22))
                                        .frame(width: glowSize, height: glowSize)
                                }
                                Circle()
                                    .fill(active ? col : Color.gray.opacity(0.32))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(draggedIndex == i ? 0.95 : (active ? 0.45 : 0)), lineWidth: draggedIndex == i ? 2 : 1)
                                    )
                                Text("V\(i + 1)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .position(pos)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        draggedIndex = i
                                        let normPan = Float((val.location.x - w / 2) / max(w * 0.42 * CGFloat(max(width, 0.15)), 1))
                                        voices[i].pan = clampF(normPan, -1, 1)
                                        let depthNorm = Float((val.location.y - h * 0.36) / max(h * 0.50, 1))
                                        voices[i].volume = clampF(1.0 - depthNorm * 0.8, 0.15, 1.0)
                                    }
                                    .onEnded { _ in draggedIndex = nil }
                            )
                        }
                    }
                }
                .frame(height: 170)
            }

            HStack {
                Text("L").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                Spacer()
                Text("-12 Bass · 0 Unison · +12 Air")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: 0x8B93A7))
                Spacer()
                Text("R").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
            }
            .padding(.horizontal, 4)
        }
    }

    private func voiceColor(_ octave: Int) -> Color {
        octave < 0 ? Color(hex: 0xFF9F43) : (octave > 0 ? Color(hex: 0x31C6FF) : Color(hex: 0x3DDC97))
    }

    private func voicePoint(index i: Int, voice v: EnsembleVoiceParams, width w: CGFloat, height h: CGFloat, tNow: TimeInterval) -> CGPoint {
        let drift = tNow > 0 ? CGFloat(sin(tNow * 2.2 + Double(i) * 1.25)) * CGFloat(detuneCents * 0.35) : 0
        let x = w / 2 + CGFloat(clampF(v.pan * width, -1, 1)) * (w * 0.42) + drift
        let octDepth: Float = v.octave < 0 ? 0.08 : (v.octave > 0 ? -0.04 : 0.0)
        let volDepth = (1.0 - clampF(v.volume, 0, 1)) * 0.36
        let lane = Float(i % 3) * 0.04
        let yFrac = clampF(0.38 + volDepth + octDepth + lane, 0.34, 0.88)
        return CGPoint(x: max(16, min(w - 16, x)), y: h * CGFloat(yFrac))
    }

    private func drawStageEnvironment(_ ctx: GraphicsContext, size: CGSize, origin: CGPoint, tNow: TimeInterval) {
        let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
        ctx.fill(bg, with: .color(Color(hex: 0x0B0E14)))

        ctx.fill(
            bg,
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xC57BFF).opacity(enabled ? 0.16 : 0.05), Color.clear]),
                center: origin,
                startRadius: 4,
                endRadius: size.width * 0.72
            )
        )

        for dFrac in [0.34, 0.60, 0.88] {
            let span = size.width * CGFloat(dFrac) * 0.52
            let sideY = origin.y + size.height * CGFloat(dFrac) * 0.56
            let ctrlY = origin.y + size.height * CGFloat(dFrac) * 0.98
            var arc = Path()
            arc.move(to: CGPoint(x: origin.x - span, y: sideY))
            arc.addQuadCurve(
                to: CGPoint(x: origin.x + span, y: sideY),
                control: CGPoint(x: origin.x, y: ctrlY)
            )
            ctx.stroke(arc, with: .color(Color.white.opacity(0.09)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        for targetX in [size.width * 0.08, size.width * 0.5, size.width * 0.92] {
            var ray = Path()
            ray.move(to: origin)
            ray.addLine(to: CGPoint(x: targetX, y: size.height))
            ctx.stroke(ray, with: .color(Color.white.opacity(targetX == size.width * 0.5 ? 0.14 : 0.07)), lineWidth: 1)
        }

        for i in voices.indices {
            let v = voices[i]
            guard enabled && v.isActive else { continue }
            let pos = voicePoint(index: i, voice: v, width: size.width, height: size.height, tNow: isRunning ? tNow : 0)
            var link = Path()
            link.move(to: origin)
            link.addLine(to: pos)
            ctx.stroke(link, with: .color(voiceColor(v.octave).opacity(0.24 * Double(v.volume))), lineWidth: 1.4)
        }

        if isRunning {
            let pulse = CGFloat(10 + ((tNow * 1.6).truncatingRemainder(dividingBy: 1.0)) * 18)
            let alpha = 0.35 * (1.0 - ((tNow * 1.6).truncatingRemainder(dividingBy: 1.0)))
            let ring = Path(ellipseIn: CGRect(x: origin.x - pulse, y: origin.y - pulse, width: pulse * 2, height: pulse * 2))
            ctx.stroke(ring, with: .color(Color.white.opacity(alpha)), lineWidth: 1.5)
        }
        let lead = Path(ellipseIn: CGRect(x: origin.x - 6, y: origin.y - 6, width: 12, height: 12))
        ctx.fill(lead, with: .color(.white))
        ctx.draw(Text("LEAD").font(.system(size: 8, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7)),
                 at: CGPoint(x: origin.x, y: origin.y - 12))
    }
}

// MARK: - Shared UI Helpers

struct SectionHeader: View {
    let title: String; let subtitle: String; let accent: Color
    var isOn: Binding<Bool>?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold)).foregroundColor(accent)
                Text(subtitle).font(.system(size: 12)).foregroundColor(Color(hex: 0x8B93A7))
            }
            Spacer()
            if let binding = isOn { Toggle("", isOn: binding).labelsHidden().tint(accent) }
        }
    }
}

struct ParamSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let tint: Color
    let text: String
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0x8B93A7))
                Spacer()
                Text(text).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundColor(.white)
            }
            Slider(value: $value, in: range).tint(tint)
        }
    }
}

struct MeterBar: View {
    let levelNorm: CGFloat
    let markerNorm: CGFloat?
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, levelNorm)))
                if let m = markerNorm {
                    Rectangle().fill(Color.white).frame(width: 2)
                        .offset(x: geo.size.width * max(0, min(1, m)))
                }
            }
        }.frame(height: 12)
    }
}

struct ViolinCardView: View {
    let index: Int
    @Binding var voice: EnsembleVoiceParams
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("VIOLIN \(index + 1)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Spacer()
                Picker("Oct", selection: $voice.octave) {
                    Text("-12").tag(-12); Text("0").tag(0); Text("+12").tag(12)
                }.pickerStyle(.segmented).frame(width: 120)
                Toggle("", isOn: $voice.isActive).labelsHidden().tint(Color(hex: 0x3DDC97))
            }
            ParamSlider(title: "VOLUME", value: $voice.volume, range: 0...1, tint: Color(hex: 0x3DDC97), text: "\(Int(round(voice.volume * 100)))%")
            ParamSlider(title: "PAN", value: $voice.pan, range: -1...1, tint: Color(hex: 0x31C6FF), text: abs(voice.pan) < 0.04 ? "CENTER" : (voice.pan < 0 ? "L\(Int(abs(voice.pan)*100))" : "R\(Int(voice.pan*100))"))
            ParamSlider(title: "HPF", value: $voice.hpfHz, range: 80...400, tint: Color(hex: 0x31C6FF), text: "\(Int(voice.hpfHz)) Hz")
            ParamSlider(title: "BOW EQ", value: $voice.bowEqDb, range: -6...6, tint: Color(hex: 0xFF9F43), text: String(format: "%+.1f dB", voice.bowEqDb))
        }
        .padding(12).background(Color(hex: 0x10141D)).cornerRadius(16)
        .opacity(voice.isActive ? 1.0 : 0.48)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}
