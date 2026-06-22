import SwiftUI
import UIKit
import Combine

struct LiveScreenView: View {
    @StateObject private var network = NetworkManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showDebugHUD: Bool = true
    @State private var hudHideWorkItem: DispatchWorkItem?

    // Streaming state
    @State private var isStreaming = false
    @State private var fitMode: ContentMode = .fit

    // Control vs View (zoom/pan) mode
    private enum ControlMode: String, CaseIterable, Identifiable { case pointer, view; var id: String { rawValue } }
    @State private var controlMode: ControlMode = .pointer

    // Fullscreen & overlays
//    @State private var isFullscreen = false
    @State private var isFullscreen = UIDevice.current.userInterfaceIdiom == .phone
    @State private var showOverlays = true
    @State private var showKeyboardSheet = false
    @State private var showShortcuts = false

    // Zoom & pan (view mode)
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Streaming parameters
    @State private var quality: Double = 0.7
    @State private var maxWidth: Int = 1600 // default higher resolution

    // Debounce restart and auto-hide overlays
    @State private var pendingRestartWorkItem: DispatchWorkItem?
    @State private var overlayAutoHideWorkItem: DispatchWorkItem?
    @State private var dragLocked: Bool = false

    // Auto-hide delay (seconds)
    private let overlayAutoHideDelay: TimeInterval = 3.0

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
                    GeometryReader { _ in
                        if controlMode == .view {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: fitMode == .fit ? .fit : .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .scaleEffect(zoom)
                                .offset(offset)
                                .gesture(viewGestures())
                                .animation(.snappy(duration: 0.15), value: zoom)
                                .animation(.snappy(duration: 0.15), value: offset)
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: fitMode == .fit ? .fit : .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 48))
                        Text("No frames yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                TrackpadGestureBridgeOverlay(isActive: controlMode == .pointer)
                EdgeGestureZones(isActive: isFullscreen && controlMode == .pointer)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16))
            .padding(isFullscreen ? 0 : 12)
            .ignoresSafeArea(edges: isFullscreen ? .all : [])
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Single tap toggles overlays when in fullscreen and not in pointer mode
                        withAnimation(.easeInOut(duration: 0.2)) { showOverlays.toggle() }
                        if showOverlays { scheduleOverlayAutoHide() } else { cancelOverlayAutoHide() }
                    }
                    .allowsHitTesting(isFullscreen && controlMode != .pointer)
            )

            // Overlays
            if showOverlays {
                overlayUI
            }

            VStack {
                HStack {
                    Button(action: {
                        stopStreamingIfNeeded()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                    .allowsHitTesting(true)
                    Spacer()
                }
                Spacer()
            }
            .opacity(isFullscreen ? 1 : 0)
            .zIndex(2)

            // Hotspot to reveal overlays when hidden in fullscreen pointer mode
            VStack {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .opacity(0.001)
                        .onTapGesture { bumpActivity() }
                        .accessibilityHidden(true)
                }
                Spacer()
            }
            .padding(8)
            .allowsHitTesting(isFullscreen && controlMode == .pointer && !showOverlays)
            .zIndex(3)

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
            .allowsHitTesting(false)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Live Screen")
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .onAppear {
            // Start streaming automatically when entering if not already
            if !isStreaming { startStreaming() }
            // Prepare auto-hide if applicable
            scheduleOverlayAutoHideIfNeeded()
        }
        .onDisappear { stopStreamingIfNeeded() }
        .sheet(isPresented: $showKeyboardSheet) { KeyboardView() }
        .sheet(isPresented: $showShortcuts) { AppShortcutsView() }
        .onChange(of: isStreaming) { _, streaming in
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = streaming
            }
            if streaming { scheduleOverlayAutoHideIfNeeded() } else { cancelOverlayAutoHide() }
        }
        .onChange(of: quality) { _, _ in scheduleRestartDebounced() }
        .onChange(of: maxWidth) { _, _ in scheduleRestartDebounced() }
        .onChange(of: isFullscreen) { _, _ in scheduleOverlayAutoHideIfNeeded() }
        .onChange(of: controlMode) { _, _ in scheduleOverlayAutoHideIfNeeded() }
        .onChange(of: network.debugMouseMoveCount) { _, _ in showDebugAndAutoHide() }
        .onChange(of: network.debugScrollCount) { _, _ in showDebugAndAutoHide() }
        .onChange(of: network.debugClickCount) { _, _ in showDebugAndAutoHide() }
    }

    // MARK: - Overlay UI
    private var overlayUI: some View {
        ZStack {
            // FPS (top-left)
            VStack { HStack { fpsOverlay; Spacer() }; Spacer() }
                .padding(8)

            // Top-right controls
            VStack {
                HStack {
                    Spacer()
                    topRightMenu
                }
                Spacer()
            }
            .padding(8)

            // Bottom controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if isFullscreen && controlMode == .pointer {
                        FloatingClickBar(dragLocked: $dragLocked)
                    } else {
                        HStack(spacing: 8) {
                            // Mode toggle
                            Picker("Mode", selection: $controlMode) {
                                Text("Pointer").tag(ControlMode.pointer)
                                Text("View").tag(ControlMode.view)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260)

                            Spacer()

                            // Clicks
                            Button { NetworkManager.shared.sendClick(button: "left") } label: {
                                Label("Click", systemImage: "cursorarrow.click")
                            }
                            .buttonStyle(.borderedProminent)

                            Button { NetworkManager.shared.sendClick(button: "right") } label: {
                                Label("Right", systemImage: "cursorarrow.rays")
                            }
                            .buttonStyle(.bordered)

                            // Keyboard
                            Button { showKeyboardSheet = true } label: {
                                Label("Keyboard", systemImage: "keyboard")
                            }
                            .buttonStyle(.bordered)

                            Button { showShortcuts = true } label: {
                                Label("Apps", systemImage: "square.grid.2x2")
                            }
                            .buttonStyle(.bordered)

                            // Start/Stop
                            Button(isStreaming ? "Stop" : "Start") {
                                if isStreaming { stopStreamingIfNeeded() } else { startStreaming() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .zIndex(1)
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

    private var topRightMenu: some View {
        Menu {
            Button("App Shortcuts") { showShortcuts = true }
            // Fit / Fill
            Picker("Content Mode", selection: $fitMode) {
                Text("Fit").tag(ContentMode.fit)
                Text("Fill").tag(ContentMode.fill)
            }

            // Zoom controls (only in view mode)
            if controlMode == .view {
                Button("Reset Zoom") { withAnimation { zoom = 1.0; lastZoom = 1.0; offset = .zero; lastOffset = .zero } }
            }

            // Quality
            Section("Quality") {
                qualitySlider
            }

            // Resolution
            Section("Max Width") {
                Button("640 px") { maxWidth = 640 }
                Button("1024 px") { maxWidth = 1024 }
                Button("1600 px") { maxWidth = 1600 }
                Button("2048 px") { maxWidth = 2048 }
            }

            // Full screen
            Button(isFullscreen ? "Exit Full Screen" : "Full Screen") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFullscreen.toggle()
                    showOverlays = !isFullscreen ? true : showOverlays
                }
            }

        } label: {
            Label("Options", systemImage: "ellipsis.circle")
                .font(.title3)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var qualitySlider: some View {
        HStack {
            Image(systemName: "cpu")
            Slider(value: $quality, in: 0.1...1.0, step: 0.05) {
                Text("Quality")
            } minimumValueLabel: {
                Text("Low").font(.caption)
            } maximumValueLabel: {
                Text("High").font(.caption)
            }
        }
    }

    // MARK: - Gestures (view mode)
    private func viewGestures() -> some Gesture {
        let mag = MagnificationGesture()
            .onChanged { value in
                zoom = (lastZoom * value).clamped(to: 0.5...4.0)
            }
            .onEnded { _ in
                lastZoom = zoom
            }

        let drag = DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                 height: lastOffset.height + value.translation.height)
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
    }

    private func stopStreamingIfNeeded() {
        if isStreaming {
            network.stopLiveScreen()
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

    // MARK: - Overlay auto-hide
    private func scheduleOverlayAutoHideIfNeeded() {
        cancelOverlayAutoHide()
        guard isFullscreen, controlMode == .pointer, isStreaming else { return }
        scheduleOverlayAutoHide()
    }

    private func scheduleOverlayAutoHide() {
        cancelOverlayAutoHide()
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) { self.showOverlays = false }
        }
        overlayAutoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + overlayAutoHideDelay, execute: work)
    }

    private func cancelOverlayAutoHide() {
        overlayAutoHideWorkItem?.cancel()
        overlayAutoHideWorkItem = nil
    }

    private func bumpActivity() {
        // Show overlays and restart hide timer when in fullscreen pointer mode
        guard isFullscreen, controlMode == .pointer else { return }
        if !showOverlays {
            withAnimation(.easeInOut(duration: 0.2)) { showOverlays = true }
        }
        scheduleOverlayAutoHide()
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
                               showTouches: showTouches)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .allowsHitTesting(isActive)
            .opacity(isActive ? 0.1 : 0) // keep visually invisible but hit-testable when active (alpha >= 0.01 for UIKit hit-testing)
            .background(Color.clear)
            .accessibilityHidden(true)
    }
}

private struct FloatingClickBar: View {
    @Binding var dragLocked: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button {
                NetworkManager.shared.sendClick(button: "left")
            } label: {
                Image(systemName: "cursorarrow.click")
                    .imageScale(.large)
            }
            .buttonStyle(.borderedProminent)

            Button {
                NetworkManager.shared.sendClick(button: "right")
            } label: {
                Image(systemName: "cursorarrow.rays")
                    .imageScale(.large)
            }
            .buttonStyle(.bordered)

            Button {
                dragLocked.toggle()
                if dragLocked {
                    NetworkManager.shared.sendMouseDown(button: "left")
                } else {
                    NetworkManager.shared.sendMouseUp(button: "left")
                }
            } label: {
                Image(systemName: dragLocked ? "hand.draw.fill" : "hand.draw")
                    .imageScale(.large)
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
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
