//
//  ContentView.swift
//  AirPad
//
//  Created by shunathon Owens on 11/24/25.
//

import SwiftUI
import UIKit

// Root app view that navigates between Connection, Trackpad, and Keyboard screens.
struct ContentView: View {
    @ObservedObject private var network = NetworkManager.shared
    @State private var showKeyboard = false

    var body: some View {
        NavigationStack {
            Group {
                if network.isConnected {
                    MainControlView(showKeyboard: $showKeyboard)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Menu {
                                    if network.discoveredServices.isEmpty {
                                        Text("Searching for Macs…")
                                    }
                                    ForEach(network.discoveredServices, id: \.id) { service in
                                        Button {
                                            network.connect(to: service)
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
        }
        .sheet(isPresented: $showKeyboard) {
            KeyboardView()
                .presentationDetents([.medium, .large])
        }
    }
}

// Connection screen that lists discovered AirBridge services and allows selection.
struct ConnectionView: View {
    @ObservedObject private var network = NetworkManager.shared

    var body: some View {
        VStack(spacing: 16) {
            if network.isPairing {
                ProgressView("Pairing with Mac…")
            }

            List(network.discoveredServices, id: \.id) { service in
                Button(action: { network.connect(to: service) }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(service.name)
                                .font(.headline)
                            Text("\(service.host ?? "Resolving…") : \(service.port ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if network.connectingServiceID == service.id {
                            ProgressView()
                        }
                    }
                }
                .disabled(network.isPairing)
            }
            .overlay(alignment: .center) {
                if network.discoveredServices.isEmpty {
                    ContentUnavailableView("Searching for Macs", systemImage: "bonjour", description: Text("Looking for _airbridge._tcp services on your network."))
                }
            }

            HStack {
                Button {
                    network.startBrowsing()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                if let error = network.lastErrorMessage {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink(destination: HelpView()) {
                    Label("Help", systemImage: "questionmark.circle")
                }

                NavigationLink(destination: DebugLogView()) {
                    Label("Debug", systemImage: "ladybug.fill")
                }

                Button(role: .destructive) {
                    NetworkManager.shared.resetTrust()
                } label: {
                    Label("Forget Server", systemImage: "trash")
                }
            }
            .padding(.horizontal)
        }
        .onAppear { network.startBrowsing() }
    }
}

// Main control view showing a trackpad and a button to open the keyboard.
struct MainControlView: View {
    @Binding var showKeyboard: Bool

    var body: some View {
        VStack(spacing: 12) {
            TrackpadView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()

            HStack {
                Button {
                    showKeyboard = true
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleAndIcon)

                Button {
                    NetworkManager.shared.sendClick(button: "left")
                } label: {
                    Label("Click", systemImage: "cursorarrow.click")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)

                Button {
                    NetworkManager.shared.sendClick(button: "right")
                } label: {
                    Label("Right Click", systemImage: "cursorarrow.rays")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)
                
                NavigationLink(destination: AirMouseView()) {
                    Label("Air Mouse", systemImage: "dot.circle.and.hand.point.up.left.fill")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)

                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)

                NavigationLink(destination: LiveScreenView()) {
                    Label("Live Screen", systemImage: "display")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)

                NavigationLink(destination: AppShortcutsView()) {
                    Label("Apps", systemImage: "app")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)
            }
            .padding([.horizontal, .bottom])
        }
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
            Section("Trackpad") {
                Toggle("Show Touch Indicators", isOn: $showTouches)
                Text("Draws a dot under each finger and shows how many fingers are detected — useful for checking that 3- and 4-finger gestures register.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Mode") {
                Picker("Control Mode", selection: .constant(0)) {
                    Text("Trackpad").tag(0)
                    Text("Air Mouse").tag(1)
                }
                .pickerStyle(.segmented)
                Text("More modes coming soon: Drawing Tablet, Media Remote, etc.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("AirPad enhances your Mac with a customizable trackpad and keyboard controller.")
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
