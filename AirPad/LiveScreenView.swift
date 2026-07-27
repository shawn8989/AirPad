import SwiftUI
import UIKit
import Combine

struct LiveScreenView: View {
    /// When true (the home screen's "TV Setup" tile), the guided
    /// mirror-from-Mac tip shows as soon as the live picture is up.
    var startWithMirrorTip: Bool = false

    @StateObject private var network = NetworkManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showDebugHUD: Bool = true
    @State private var hudHideWorkItem: DispatchWorkItem?

    // Streaming state
    @State private var isStreaming = false
    @State private var fitMode: ContentMode = .fit

    // Control vs View (zoom/pan) mode
    fileprivate enum ControlMode: String, CaseIterable, Identifiable { case pointer, touch, view; var id: String { rawValue } }
    @State private var controlMode: ControlMode = .pointer

    // Fullscreen
    @State private var isFullscreen = UIDevice.current.userInterfaceIdiom == .phone
    @ObservedObject private var keyboard = KeyboardPresenter.shared
    @State private var lastFrameAt = Date()
    @State private var showShortcuts = false
    @State private var showOptions = false
    @State private var showTVHelp = false
    @State private var showMirrorTip = false

    // Fullscreen chrome auto-hide (windowed mode always shows it).
    @State private var chromeVisible = true
    @State private var chromeHideWorkItem: DispatchWorkItem?

    // Zoom & pan (view mode)
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Streaming parameters
    @State private var quality: Double = 0.7
    @State private var maxWidth: Int = 1600 // default higher resolution

    // Debounce restart of the stream on quality/size changes
    @State private var pendingRestartWorkItem: DispatchWorkItem?
    @State private var dragLocked: Bool = false

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(isFullscreen ? 1 : 0).ignoresSafeArea()

            // Live image area
            ZStack {
                RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16)
                    .fill(.thinMaterial)
                    .allowsHitTesting(false)

                if let img = network.liveImage {
                    // The zoom/pan set in View mode STAYS applied in Pointer and
                    // Touch — otherwise lining up a region then switching to
                    // control it snapped the picture back and made View useless.
                    // Only the zoom/pan gestures are View-only.
                    GeometryReader { _ in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: fitMode == .fit ? .fit : .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .scaleEffect(zoom)
                            .offset(offset)
                            .animation(.snappy(duration: 0.15), value: zoom)
                            .animation(.snappy(duration: 0.15), value: offset)
                            .gesture(controlMode == .view ? viewGestures() : nil)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 48))
                        Text("No frames yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if network.streamErrorReason == "screen_recording_permission" {
                            Text("The Mac needs Screen Recording permission:\nSystem Settings → Privacy & Security → Screen Recording → enable AirBridge, then relaunch AirBridge.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Retrying automatically…")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding()
                }

                TrackpadGestureBridgeOverlay(isActive: controlMode == .pointer)
                AbsoluteTouchOverlay(isActive: controlMode == .touch,
                                     imageSize: network.liveImage?.size,
                                     fill: fitMode == .fill,
                                     zoom: zoom,
                                     offset: offset)
                EdgeGestureZones(isActive: isFullscreen && controlMode == .pointer)
                // The remote keyboard itself is hosted once at the root
                // (ContentView) — this screen only toggles KeyboardPresenter.
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16))
            .padding(isFullscreen ? 0 : 12)
            .ignoresSafeArea(edges: isFullscreen ? .all : [])
            // Chrome: always visible in windowed mode. In FULL SCREEN it fades
            // out after a few idle seconds so it stops covering the Mac's
            // screen, and any touch brings it straight back — the old build
            // either hid it permanently or blocked the picture forever.
            VStack {
                HStack(spacing: 8) {
                    if isFullscreen {
                        Button {
                            stopStreamingIfNeeded()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    fpsOverlay
                    Spacer()
                    topRightMenu
                }
                .padding(8)
                Spacer()
                controlBar
                    .padding(.horizontal, 8)
                    .padding(.bottom, isFullscreen ? 12 : 4)
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
            .animation(.easeInOut(duration: 0.25), value: chromeVisible)
            .zIndex(2)

            // When the chrome is hidden, this slim handle stays as the visible
            // affordance (and a direct way back) so the controls are never a
            // secret. Tapping anywhere on the picture also brings them back.
            if !chromeVisible {
                VStack {
                    Spacer()
                    Button {
                        revealChrome()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.up")
                            Text("Controls")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .opacity(0.75)
                    }
                    .padding(.bottom, isFullscreen ? 12 : 6)
                }
                .transition(.opacity)
                .zIndex(3)
            }

            // Guided "mirror the Mac to the TV" tip: walks the user through
            // starting AirPlay ON THE MAC using the live picture + pointer.
            if showMirrorTip {
                VStack {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mirror your Mac to the TV")
                                .font(.caption.weight(.bold))
                            Text("On the Mac's screen above, click the Control Center icon (two toggles, top-right of the menu bar) → Screen Mirroring → pick your TV. Then watch the TV and control from any page here.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            withAnimation { showMirrorTip = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 52)
                    .padding(.horizontal, 12)
                    Spacer()
                }
                .zIndex(3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // TV Mode: the picture is on the television; this screen is the remote.
            if TVSceneManager.shared.tvConnected {
                VStack {
                    Label("Showing on TV — Pointer/Touch controls it", systemImage: "tv")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(4)
            }

            // Debug HUD for event counters
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow.motionlines"); Text("Moves: \(network.debugMouseMoveCount)")
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right"); Text("Scrolls: \(network.debugScrollCount)")
                        Image(systemName: "cursorarrow.click"); Text("Clicks: \(network.debugClickCount)")
                    }
                    .font(.caption.monospacedDigit())
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .opacity(showDebugHUD ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showDebugHUD)
                    Spacer()
                }
                .padding(8)
                Spacer()
            }
            .padding(.top, 52)  // below the back/FPS/Options row
            .allowsHitTesting(false)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Live Screen")
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .onAppear {
            // Start streaming automatically when entering if not already
            if !isStreaming { startStreaming() }
            if startWithMirrorTip { showMirrorTip = true }
        }
        .onDisappear { stopStreamingIfNeeded() }
        .onReceive(network.$liveImage) { image in
            if image != nil {
                lastFrameAt = Date()
                if network.streamErrorReason != nil { network.streamErrorReason = nil }
            }
        }
        .onChange(of: network.isConnected) { _, connected in
            // The stream dies with the old connection on auto-reconnect;
            // re-request it on the fresh one.
            if connected && isStreaming {
                network.startLiveScreen(maxWidth: maxWidth, quality: quality)
            }
        }
        .task {
            // Stream watchdog: if we're supposed to be streaming but frames
            // stopped for >3s, re-request the stream (covers reconnects and
            // transient capture failures on the Mac).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if isStreaming && Date().timeIntervalSince(lastFrameAt) > 3 && network.isConnected {
                    network.startLiveScreen(maxWidth: maxWidth, quality: quality)
                }
            }
        }
        .sheet(isPresented: $showShortcuts) { AppShortcutsView() }
        .sheet(isPresented: $showOptions) { optionsSheet }
        .sheet(isPresented: $showTVHelp) { tvHelpSheet }
        .onChange(of: isStreaming) { _, streaming in
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = streaming
            }
        }
        .onChange(of: quality) { _, _ in scheduleRestartDebounced() }
        .onChange(of: maxWidth) { _, _ in scheduleRestartDebounced() }
        // Any interaction with the Mac counts as "the user is here": it shows
        // the chrome and restarts the idle timer.
        .onChange(of: network.debugMouseMoveCount) { _, _ in showDebugAndAutoHide(); revealChrome() }
        .onChange(of: network.debugScrollCount) { _, _ in showDebugAndAutoHide(); revealChrome() }
        .onChange(of: network.debugClickCount) { _, _ in showDebugAndAutoHide(); revealChrome() }
        .onChange(of: isFullscreen) { _, _ in revealChrome() }
        .onChange(of: controlMode) { _, _ in revealChrome() }
    }

    // MARK: - Control bar (persistent, labeled)

    /// The always-visible control strip: mode picker on top, one row of
    /// captioned buttons below. Every control is labeled — icon-only buttons
    /// left people guessing, and auto-hiding made them unclickable.
    private var controlBar: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $controlMode) {
                Text("Pointer").tag(ControlMode.pointer)
                Text("Touch").tag(ControlMode.touch)
                Text("View").tag(ControlMode.view)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            HStack(spacing: 4) {
                barButton("Desktop", "chevron.left") {
                    NetworkManager.shared.sendSwipe(fingers: 3, direction: "left", skipFullscreen: true)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                barButton("Click", "cursorarrow.click", tint: .accentColor) {
                    NetworkManager.shared.sendClick(button: "left")
                }
                barButton("Right", "cursorarrow.rays") {
                    NetworkManager.shared.sendClick(button: "right")
                }
                barButton(dragLocked ? "Release" : "Drag",
                          dragLocked ? "hand.draw.fill" : "hand.draw",
                          tint: dragLocked ? .orange : nil) {
                    dragLocked.toggle()
                    if dragLocked {
                        NetworkManager.shared.sendMouseDown(button: "left")
                    } else {
                        NetworkManager.shared.sendMouseUp(button: "left")
                    }
                }
                barButton("Keys", "keyboard") {
                    keyboard.visible = true
                }
                barButton("Apps", "square.grid.2x2") {
                    showShortcuts = true
                }
                barButton("TV", "tv") {
                    showTVHelp = true
                }
                barButton("Desktop", "chevron.right") {
                    NetworkManager.shared.sendSwipe(fingers: 3, direction: "right", skipFullscreen: true)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: 500)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func barButton(_ title: String, _ icon: String, tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tint ?? .primary)
            .frame(minWidth: 42, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fpsOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text(String(format: "%.1f FPS", network.liveFPS))
        }
        .font(.caption.monospacedDigit())
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // The Options button opens a real settings SHEET. The old pull-down menu
    // held a Slider — which SwiftUI menus don't support: broken layout
    // constraints, taps dismissing the menu, no landscape scrolling.
    private var topRightMenu: some View {
        Button {
            showOptions = true
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(.title3)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("Stream") {
                    HStack {
                        Text("Quality")
                        Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(quality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                    Picker("Resolution", selection: $maxWidth) {
                        Text("640").tag(640)
                        Text("1024").tag(1024)
                        Text("1600").tag(1600)
                        Text("2048").tag(2048)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Frame rate")
                        Spacer()
                        Text(String(format: "%.1f FPS", network.liveFPS))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button(isStreaming ? "Stop Stream" : "Start Stream") {
                        if isStreaming { stopStreamingIfNeeded() } else { startStreaming() }
                    }
                }

                Section("Display") {
                    Picker("Scaling", selection: $fitMode) {
                        Text("Fit (whole screen)").tag(ContentMode.fit)
                        Text("Fill (crop edges)").tag(ContentMode.fill)
                    }
                    Toggle("Full screen", isOn: Binding(
                        get: { isFullscreen },
                        set: { newValue in withAnimation(.easeInOut(duration: 0.2)) { isFullscreen = newValue } }))
                    // Available in every mode now that zoom persists across them.
                    Button("Reset zoom (this picture)") {
                        withAnimation { zoom = 1.0; lastZoom = 1.0; offset = .zero; lastOffset = .zero }
                    }
                    .disabled(abs(zoom - 1) < 0.01 && offset == .zero)
                } footer: {
                    Text("In full screen the controls fade out after a few seconds so they stop covering the Mac — touch the screen or tap Controls to bring them back.")
                }

                Section {
                    Button("Reset zoom on the Mac (⌘0)") {
                        NetworkManager.shared.sendKeyCombo(29, command: true, option: false,
                                                           control: false, shift: false)
                    }
                } footer: {
                    Text("Sends ⌘0 to the app in front on the Mac — use it if an app was left zoomed in.")
                }

                Section {
                    Button {
                        showOptions = false
                        showShortcuts = true
                    } label: {
                        Label("App Shortcuts & Launcher", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    Text("Pointer = trackpad on the video. Touch = tap exactly what you see (double-tap opens, two fingers scroll, hold to drag). View = zoom and pan without sending clicks.")
                }
            }
            .navigationTitle("Live Screen Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showOptions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// TV setup guide. The recommended path is mirroring FROM THE MAC — the
    /// phone stays completely free, the TV gets native AirPlay quality, and
    /// the Mac's audio comes along. Phone-side mirroring is the fallback.
    private var tvHelpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mirror from your Mac", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Use the live picture and pointer to click the Mac's Control Center icon (top-right of its menu bar) → Screen Mirroring → choose your TV. The TV shows the Mac at full quality with sound, and this phone stays free to use any mode.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showTVHelp = false
                        withAnimation { showMirrorTip = true }
                    } label: {
                        Label("Guide me on the live screen", systemImage: "hand.point.up.left")
                    }
                } header: {
                    Text("Best way")
                }

                Section("Sound") {
                    Text("The Mac's audio can go to a different speaker than the TV — use the speaker picker on the Media page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Other ways") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wired HDMI adapter", systemImage: "cable.connector")
                            .font(.subheadline.weight(.semibold))
                        Text("Plug this phone into the TV with an HDMI adapter: the TV shows only the Mac's screen (TV Mode) while the phone stays the controller.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Label("Phone screen mirroring", systemImage: "iphone.badge.play")
                            .font(.subheadline.weight(.semibold))
                        Text("Control Center on this phone → Screen Mirroring → your TV. On some iOS versions the TV mirrors everything the phone shows, so it will follow you between pages.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Show your Mac on a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTVHelp = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Gestures (view mode)
    private func viewGestures() -> some Gesture {
        let mag = MagnificationGesture()
            .onChanged { value in
                zoom = (lastZoom * value).clamped(to: 0.5...4.0)
                revealChrome()
            }
            .onEnded { _ in
                lastZoom = zoom
            }

        let drag = DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                 height: lastOffset.height + value.translation.height)
                revealChrome()
            }
            .onEnded { _ in
                lastOffset = offset
            }

        let doubleTap = TapGesture(count: 2)
            .onEnded {
                withAnimation(.snappy) {
                    if abs(zoom - 1.0) < 0.01 {
                        zoom = 2.0; lastZoom = 2.0
                    } else {
                        zoom = 1.0; lastZoom = 1.0; offset = .zero; lastOffset = .zero
                    }
                }
            }

        return SimultaneousGesture(mag, drag).exclusively(before: doubleTap)
    }

    // MARK: - Streaming control
    private func startStreaming() {
        network.startLiveScreen(maxWidth: maxWidth, quality: quality)
        isStreaming = true
        TVSceneManager.shared.phoneWantsStream = true
    }

    private func stopStreamingIfNeeded() {
        if isStreaming {
            TVSceneManager.shared.phoneWantsStream = false
            // The TV shares this stream — leaving the phone's Live Screen must
            // not black out the television.
            if !TVSceneManager.shared.tvConnected {
                network.stopLiveScreen()
            }
            isStreaming = false
        }
    }

    private func scheduleRestartDebounced() {
        pendingRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [quality, maxWidth, isStreaming] in
            guard isStreaming else { return }
            // Stop then start after a short pause
            network.stopLiveScreen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                network.startLiveScreen(maxWidth: maxWidth, quality: quality)
            }
        }
        pendingRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Shows the controls and restarts the idle countdown. In windowed mode the
    /// chrome simply stays up — only full screen hides it, and only after the
    /// user has stopped interacting for a few seconds.
    private func revealChrome() {
        chromeHideWorkItem?.cancel()
        if !chromeVisible { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = true } }
        guard isFullscreen else { return }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { chromeVisible = false }
        }
        chromeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func showDebugAndAutoHide() {
        showDebugHUD = true
        hudHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) { showDebugHUD = false }
        }
        hudHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}

// MARK: - Trackpad overlay wrapper
private struct TrackpadGestureBridgeOverlay: View {
    @AppStorage("pointerSensitivity") private var pointerSensitivity: Double = 1.0
    @AppStorage("naturalScroll") private var naturalScroll: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("showTouches") private var showTouches: Bool = true

    var isActive: Bool

    var body: some View {
        TrackpadGestureBridge(pointerSensitivity: pointerSensitivity,
                               naturalScroll: naturalScroll,
                               hapticsEnabled: hapticsEnabled,
                               showTouches: showTouches,
                               // A pinch here zooms the picture, never the Mac.
                               pinchZoomsMac: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .allowsHitTesting(isActive)
            .opacity(isActive ? 0.1 : 0) // keep visually invisible but hit-testable when active (alpha >= 0.01 for UIKit hit-testing)
            .background(Color.clear)
            .accessibilityHidden(true)
    }
}

private struct EdgeGestureZones: View {
    var isActive: Bool

    var body: some View {
        ZStack {
            // Top edge: drag down for App Exposé
            Rectangle()
                .fill(Color.clear)
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height > 30 {
                        NetworkManager.shared.sendSwipe(fingers: 3, direction: "down")
                        NetworkManager.shared.sendAction("three_swipe_down")
                    }
                })
                .allowsHitTesting(isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Bottom edge: drag up for Mission Control
            Rectangle()
                .fill(Color.clear)
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < -30 {
                        NetworkManager.shared.sendSwipe(fingers: 3, direction: "up")
                        NetworkManager.shared.sendAction("three_swipe_up")
                    }
                })
                .allowsHitTesting(isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .opacity(isActive ? 0.001 : 0)
        .accessibilityHidden(true)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    NavigationStack { LiveScreenView() }
}
