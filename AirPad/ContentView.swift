//
//  ContentView.swift
//  AirPad
//
//  Created by shunathon Owens on 11/24/25.
//

import SwiftUI
import UIKit
import StoreKit
import Combine

// Root app view that navigates between Connection, Trackpad, and Keyboard screens.
struct ContentView: View {
    @ObservedObject private var network = NetworkManager.shared
    @ObservedObject private var proStore = ProStore.shared
    @State private var showMultiMacPaywall = false
    @ObservedObject private var keyboard = KeyboardPresenter.shared
    @AppStorage("autoKeyboard") private var autoKeyboard = true
    @Environment(\.requestReview) private var requestReview
    @AppStorage("connectSessionCount") private var connectSessionCount = 0
    @AppStorage("didAskForReview") private var didAskForReview = false

    var body: some View {
        NavigationStack {
            Group {
                if network.isConnected {
                    MainControlView(showKeyboard: $keyboard.visible)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Menu {
                                    if network.discoveredServices.isEmpty {
                                        Text("Searching for Macs…")
                                    }
                                    ForEach(network.discoveredServices, id: \.id) { service in
                                        Button {
                                            // Switching to a DIFFERENT Mac is a Pro feature;
                                            // the first/current Mac is always free.
                                            let isSwitch = service.name != network.currentMacName
                                            if isSwitch && !proStore.isPro {
                                                showMultiMacPaywall = true
                                            } else {
                                                network.connect(to: service)
                                            }
                                        } label: {
                                            if service.name == network.currentMacName {
                                                Label("\(service.name) (current)", systemImage: "checkmark")
                                            } else {
                                                Text(service.name)
                                            }
                                        }
                                    }
                                } label: {
                                    Label(network.currentMacName ?? "Mac", systemImage: "desktopcomputer")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Disconnect") { network.disconnect() }
                            }
                        }
                } else {
                    ConnectionView()
                }
            }
            .navigationTitle(network.isConnected ? (network.currentMacName ?? "AirPad") : "AirPad")
            .sheet(isPresented: $showMultiMacPaywall) {
                NavigationStack { PaywallView() }
            }
        }
        .onChange(of: network.isConnected) { _, connected in
            // A trackpad is useless if the phone sleeps mid-use: keep the
            // screen awake while connected, restore normal auto-lock after.
            UIApplication.shared.isIdleTimerDisabled = connected

            // One tasteful review ask after the 5th successful session — never nag.
            guard connected else { return }
            connectSessionCount += 1
            if connectSessionCount >= 5 && !didAskForReview {
                didAskForReview = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { requestReview() }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = network.isConnected
        }
        // The app's single remote keyboard (system keyboard + ⌘⌥⌃⇧ accessory
        // bar), hosted once at the root so every screen — trackpad or Live
        // Screen — shares it. Replaces the old custom keyboard sheet.
        .overlay(alignment: .bottom) {
            RemoteKeyboardInput(isVisible: $keyboard.visible, state: keyboard.state)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .onReceive(network.$macTextFieldFocused) { focused in
            // The Mac says a text field took keyboard focus: raise ours.
            if autoKeyboard && focused && network.isConnected { keyboard.visible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Coming back from the background: the old Bonjour browser is
            // wedged and never finds anything again — rescan fresh.
            if !network.isConnected { network.startBrowsing() }
        }
    }
}

// Connection screen that lists discovered AirBridge services and allows selection.
struct ConnectionView: View {
    @ObservedObject private var network = NetworkManager.shared
    @State private var searchPulse = false
    @State private var showQRScanner = false
    @State private var showAddressPrompt = false
    @State private var showRemotePaywall = false
    @State private var manualAddress = ""
    @State private var wokeMacName: String?

    var body: some View {
        VStack(spacing: 16) {
            if network.isPairing {
                VStack(spacing: 8) {
                    ProgressView("Pairing with Mac…")
                    Text("Approve the request on your Mac's screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            List {
                Section {
                    ForEach(network.discoveredServices, id: \.id) { service in
                        Button(action: { network.connect(to: service) }) {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading) {
                                    Text(service.name)
                                        .font(.headline)
                                    Text("Tap to connect")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if network.connectingServiceID == service.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(network.isPairing)
                    }
                } header: {
                    if !network.discoveredServices.isEmpty {
                        Text("Your Macs")
                    }
                } footer: {
                    if let error = network.lastErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay(alignment: .center) {
                if network.discoveredServices.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                        Text("Searching for Macs…")
                            .font(.headline)
                        Text("Open AirBridge on your Mac and make sure both devices are on the same Wi-Fi network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }

            // Bottom bar: one prominent primary action, then evenly spaced
            // icon-over-caption buttons (a row of full Labels doesn't fit an
            // iPhone width and squishes).
            VStack(spacing: 14) {
                Button {
                    showQRScanner = true
                } label: {
                    Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Spacer()
                    Button { network.startBrowsing() } label: {
                        bottomBarLabel("Refresh", "arrow.clockwise")
                    }
                    Spacer()
                    Menu {
                        let known = KnownMacStore.all().filter { $0.macAddress != nil }
                        if !known.isEmpty {
                            Section("Wake a sleeping Mac") {
                                ForEach(known) { mac in
                                    Button {
                                        wokeMacName = mac.name
                                        WakeOnLAN.wake(macAddress: mac.macAddress!)
                                        network.startBrowsing()
                                    } label: {
                                        Label(mac.name, systemImage: "power")
                                    }
                                }
                            }
                        }
                        Button {
                            // Remote/VPN connectivity is a Pro nicety; the
                            // trial unlocks it too (isPro covers both).
                            if ProStore.shared.isPro {
                                showAddressPrompt = true
                            } else {
                                showRemotePaywall = true
                            }
                        } label: {
                            Label("Connect by Address…", systemImage: "network")
                        }
                    } label: {
                        bottomBarLabel("Wake / IP", "power")
                    }
                    Spacer()
                    NavigationLink(destination: HelpView()) {
                        bottomBarLabel("Help", "questionmark.circle")
                    }
                    Spacer()
                    #if DEBUG
                    NavigationLink(destination: DebugLogView()) {
                        bottomBarLabel("Debug", "ladybug")
                    }
                    Spacer()
                    #endif
                    Button(role: .destructive) {
                        NetworkManager.shared.resetTrust()
                    } label: {
                        bottomBarLabel("Forget", "trash")
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showQRScanner) { QRScannerSheet() }
        .sheet(isPresented: $showRemotePaywall) {
            NavigationStack { PaywallView() }
        }
        .onAppear { network.startBrowsing() }
        .alert("Connect by Address", isPresented: $showAddressPrompt) {
            TextField("IP or hostname (e.g. 100.64.1.5)", text: $manualAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Connect") {
                var host = manualAddress
                var port = NetworkManager.defaultPort
                if let colon = host.lastIndex(of: ":"), let p = UInt16(host[host.index(after: colon)...]) {
                    port = p
                    host = String(host[..<colon])
                }
                network.connectToAddress(host, port: port)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("For connecting across networks (e.g. through Tailscale or another VPN) when your Mac can't be discovered automatically. AirBridge listens on port \(String(NetworkManager.defaultPort)).")
        }
        .alert("Wake packet sent", isPresented: .init(
            get: { wokeMacName != nil },
            set: { if !$0 { wokeMacName = nil } })) {
            Button("OK") { wokeMacName = nil }
        } message: {
            Text("Sent a Wake-on-LAN packet to \(wokeMacName ?? "the Mac"). It wakes only if \"Wake for network access\" is on (System Settings → Battery → Options) and the Mac is on this network. It may take a few seconds to appear.")
        }
    }

    private func bottomBarLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18))
            Text(title)
                .font(.caption2)
        }
        .frame(minWidth: 44)
    }
}

// Main control view. iPhone: trackpad on top, quick actions, 4-column tile
// grid. iPad / regular width: big trackpad beside a control column.
struct MainControlView: View {
    @Binding var showKeyboard: Bool
    @ObservedObject private var proStore = ProStore.shared
    @ObservedObject private var tv = TVSceneManager.shared
    @Environment(\.horizontalSizeClass) private var hSize

    private var tvChip: some View {
        Group {
            if tv.tvConnected {
                Label("TV connected — your Mac's screen is on the TV", systemImage: "tv.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
        }
    }

    var body: some View {
        if hSize == .regular {
            // iPad: side-by-side — a large trackpad with controls on the right.
            HStack(spacing: 14) {
                trackpad
                    .padding([.leading, .vertical])

                VStack(spacing: 12) {
                    TrialBanner()
                    tvChip
                    quickActions
                    tileGrid(columns: 2)
                    Spacer(minLength: 0)
                }
                .frame(width: 320)
                .padding([.trailing, .vertical])
            }
        } else {
            VStack(spacing: 12) {
                TrialBanner()
                    .padding(.top, 4)

                tvChip
                    .padding(.horizontal)

                trackpad
                    .padding(.horizontal)

                quickActions
                    .padding(.horizontal)

                tileGrid(columns: 4)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    private var trackpad: some View {
        TrackpadView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            // Desktop hop, one tap from the trackpad — no swipe gymnastics.
            Button {
                NetworkManager.shared.sendSwipe(fingers: 3, direction: "left")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Previous desktop")

            Button {
                NetworkManager.shared.sendClick(button: "left")
            } label: {
                Label("Click", systemImage: "cursorarrow.click")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                NetworkManager.shared.sendClick(button: "right")
            } label: {
                Label("Right", systemImage: "cursorarrow.rays")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showKeyboard = true
            } label: {
                Label("Keys", systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                NetworkManager.shared.sendSwipe(fingers: 3, direction: "right")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Next desktop")
        }
        .lineLimit(1)
    }

    // Modes & tools. Pro tiles route to the paywall once the trial ends.
    private func tileGrid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            modeTile("Air Mouse", "dot.circle.and.hand.point.up.left.fill", pro: true) { AirMouseView() }
            modeTile("Hand Mouse", "hand.point.up.left", pro: true) { HandMouseView() }
            modeTile("Live Screen", "display", pro: true) { LiveScreenView() }
            modeTile("Media", "playpause.fill", pro: true) { MediaControlsView() }
            modeTile("Desktops", "macwindow.on.rectangle", pro: true) { MacSwitcherView() }
            modeTile("Settings", "gearshape") { SettingsView() }
            modeTile("Help", "questionmark.circle") { HelpView() }
        }
    }

    private func modeTile<D: View>(_ title: String, _ icon: String, pro: Bool = false,
                                   @ViewBuilder destination: () -> D) -> some View {
        let locked = pro && !proStore.isPro
        return NavigationLink(destination: locked ? AnyView(PaywallView()) : AnyView(destination())) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}

struct SettingsView: View {
    @AppStorage("pointerSensitivity") private var pointerSensitivity: Double = 1.0
    @AppStorage("naturalScroll") private var naturalScroll: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("showTouches") private var showTouches: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Form {
            Section("Pointer") {
                HStack {
                    Text("Sensitivity")
                    Slider(value: $pointerSensitivity, in: 0.25...3.0, step: 0.05)
                }
            }
            Section("Scroll") {
                Toggle("Natural Scrolling", isOn: $naturalScroll)
            }
            Section("Haptics") {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
            }
            Section("Keyboard") {
                Toggle("Auto keyboard in Live Screen", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "autoKeyboard") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "autoKeyboard") }
                ))
                Text("Pops the keyboard up automatically when you click into a text field on the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Trackpad") {
                Toggle("Show Touch Indicators", isOn: $showTouches)
                Text("Draws a dot under each finger and shows how many fingers are detected — useful for checking that 3- and 4-finger gestures register.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("AirPad Pro") {
                if ProStore.shared.purchased {
                    Label("Pro unlocked — thank you!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    NavigationLink(destination: PaywallView()) {
                        Label("Unlock AirPad Pro", systemImage: "wand.and.stars")
                    }
                    Button {
                        Task { await ProStore.shared.restore() }
                    } label: {
                        Label("Restore Purchase", systemImage: "arrow.clockwise.circle")
                    }
                }
            }
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .foregroundStyle(.secondary)
                }
                Button {
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id0000000000?action=write-review") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Rate AirPad", systemImage: "star")
                }
                Text("AirPad turns your iPhone into a trackpad, keyboard, motion pointer, and camera-gesture controller for your Mac. Everything runs on your local network — nothing is collected or sent anywhere else.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Advanced") {
                // Device ID
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(SecurityManager.shared.currentDeviceID ?? "Unknown")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button {
                    UIPasteboard.general.string = SecurityManager.shared.currentDeviceID ?? ""
                } label: { Label("Copy Device ID", systemImage: "doc.on.doc") }

                // Fingerprint (short)
                let fpData = (try? SecurityManager.shared.getServerCertFingerprint()) ?? nil
                let fpShort = fpData.map { $0.base64EncodedString().prefix(16) } ?? "None"
                HStack {
                    Text("Server Fingerprint")
                    Spacer()
                    Text(String(fpShort))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button {
                    if let data = try? SecurityManager.shared.getServerCertFingerprint() {
                        UIPasteboard.general.string = data.base64EncodedString() ?? ""
                    }
                } label: { Label("Copy Fingerprint", systemImage: "doc.on.doc") }

                // Reset Trust
                Button(role: .destructive) {
                    NetworkManager.shared.resetTrust()
                } label: {
                    Label("Reset Trust (Forget Server)", systemImage: "trash")
                }
            }
            Section("Onboarding") {
                Button {
                    // Trigger the onboarding sheet to appear at the app level
                    hasCompletedOnboarding = false
                } label: {
                    Label("Show Onboarding", systemImage: "sparkles")
                }
            }
            #if DEBUG
            Section("Developer") {
                Toggle("Simulate Free (test paywall)", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "debug.simulateFree") },
                    set: {
                        UserDefaults.standard.set($0, forKey: "debug.simulateFree")
                        ProStore.shared.objectWillChange.send()  // refresh lock badges
                    }
                ))
                Text("DEBUG builds are always Pro unless this is on. Release builds use the real trial + purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .navigationTitle("Settings")
    }
}

struct DebugLogView: View {
    @ObservedObject private var network = NetworkManager.shared

    var body: some View {
        List(network.debugLogs, id: \.self) { line in
            Text(line).font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .navigationTitle("Debug Logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy All") {
                    UIPasteboard.general.string = network.debugLogs.joined(separator: "\n")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
