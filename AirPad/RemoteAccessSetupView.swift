import SwiftUI

struct RemoteAccessSetupView: View {
    @ObservedObject private var network = NetworkManager.shared
    @ObservedObject private var pro = ProStore.shared
    @State private var selectedID = ""
    @State private var address = ""
    @State private var scan = false
    @State private var error: String?
    @State private var testing = false
    private var selected: KnownMac? { network.savedMacs.first { $0.id == selectedID } }

    var body: some View {
        Form {
            Section {
                Text("Use your Mac and shared files from another Wi-Fi network or cellular connection.")
                if !pro.isPro { NavigationLink("Unlock Wield Pro") { PaywallView() } }
            }
            Section {
                Text("Install Tailscale on your iPhone and Mac, sign in to the same Tailscale account, and connect both devices. Personal use has a free plan.")
                Link("Get Tailscale", destination: URL(string: "https://tailscale.com/download")!)
                Link("Set up automatic connection", destination: URL(string: "https://tailscale.com/docs/features/client/ios-vpn-on-demand")!)
            } header: { Text("1. Connect your devices") } footer: {
                Text("Tailscale is a separate service. You do not need a Wield account or router port forwarding.")
            }
            Section {
                Text("While on the same Wi-Fi, update Wield Host and choose Show Pairing QR. Scan the new code to enable secure access; your older local pairing can stay in place.")
                Button("Scan Mac pairing QR", systemImage: "qrcode.viewfinder") { scan = true }
                if network.savedMacs.isEmpty { Text("Your Mac appears here after pairing.").foregroundStyle(.secondary) }
                else {
                    Picker("Mac", selection: $selectedID) {
                        Text("Choose a Mac").tag("")
                        ForEach(network.savedMacs) { mac in Text(mac.name).tag(mac.id) }
                    }
                    if let selected {
                        Label(network.hasSecurePairing(selected) ? "Secure pairing saved" : "Scan a new QR to upgrade pairing",
                              systemImage: network.hasSecurePairing(selected) ? "checkmark.shield" : "qrcode")
                    }
                }
            } header: { Text("2. Pair before leaving home") }
            Section {
                TextField("Mac's Tailscale name or IP", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Save and test remote connection") {
                    guard let selected else { return }
                    do {
                        try network.saveRemoteAddress(address, for: selected)
                        if let saved = network.savedMacs.first(where: { $0.id == selected.id }) {
                            error = nil; testing = true
                            network.connectSavedMac(saved, remoteOnly: true)
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(selected == nil || !pro.isPro || address.trimmingCharacters(in: .whitespaces).isEmpty)
                if testing {
                    Label(network.connectionStatus, systemImage: network.isSecureConnection && network.isRemoteConnection ? "checkmark.circle" : "network")
                    if network.isSecureConnection && network.isRemoteConnection {
                        Text("Connection verified. For a true away-from-home check, turn off iPhone Wi-Fi and test again over cellular.")
                            .font(.footnote)
                    }
                }
                if let error = error ?? network.lastErrorMessage { Text(error).foregroundStyle(.red) }
                if let selected, selected.remoteAddress != nil {
                    Button("Remove saved remote address", role: .destructive) {
                        network.forgetRemoteAddress(for: selected); address = ""; testing = false
                    }
                }
            } header: { Text("3. Save your Mac") } footer: {
                Text("Copy the Mac's address from Tailscale. After setup, tap your saved Mac on Wield's connection screen. Local access is preferred when available.")
            }
            Section {
                Text("Enable Accessibility and Screen Recording for the installed Wield Host. Turn on Launch at Login and, if wanted, Keep available while plugged in.")
                if network.isSecureConnection && network.currentMacID == selectedID {
                    readiness("Accessibility", key: "accessibility")
                    readiness("Screen Recording", key: "screenRecording")
                    readiness("Launch at Login", key: "launchAtLogin")
                    readiness("Keep available while plugged in", key: "keepAvailable")
                }
                Text("The Mac must be on, connected, and running Wield Host. Sleep, shutdown, or restarting to a login screen can prevent access. Wield does not unlock FileVault or wake a Mac across the internet.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("For Files, choose shared folders in Wield Host. You can then browse and transfer individual files without approving each transfer on the Mac.")
            } header: { Text("4. Leave your Mac ready") }
        }
        .navigationTitle("Access away from home")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scan) { QRScannerSheet() }
        .onAppear {
            network.startBrowsing()
            if selectedID.isEmpty { selectedID = network.currentMacID ?? network.savedMacs.first?.id ?? "" }
            address = selected?.remoteAddress?.display ?? ""
        }
        .onChange(of: selectedID) { _, _ in address = selected?.remoteAddress?.display ?? ""; testing = false }
        .onChange(of: network.savedMacs) { _, _ in
            if selectedID.isEmpty { selectedID = network.currentMacID ?? network.savedMacs.first?.id ?? "" }
        }
    }
    @ViewBuilder private func readiness(_ title: String, key: String) -> some View {
        if let ready = network.remoteReadiness[key] {
            Label(title + (ready ? ": enabled" : ": check on Mac"), systemImage: ready ? "checkmark.circle" : "info.circle")
                .font(.footnote)
        }
    }
}
