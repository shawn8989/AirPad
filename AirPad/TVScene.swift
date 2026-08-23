//
//  TVScene.swift
//  AirPad
//
//  TV Mode: when the iPhone is screen-mirrored to a TV (AirPlay or an HDMI
//  adapter), iOS offers the app the external display as a SECOND screen.
//  Instead of mirroring the phone, we render the Mac's live desktop fullscreen
//  on the TV and the phone becomes the controller — so a Mac in another room
//  is watchable and drivable from the couch.
//
//  Pieces:
//  - AirPadAppDelegate: routes the external-display scene session to our
//    TVSceneDelegate (the default config handles the phone's own scene).
//  - TVSceneDelegate: hosts TVScreenView in a plain UIWindow on the TV.
//  - TVSceneManager: owns the "TV wants the stream" lifecycle — starts the
//    live stream at TV quality, keeps it alive with a watchdog, and stops it
//    only when neither the TV nor the Live Screen view needs it.
//  - TVScreenView: the fullscreen, non-interactive picture shown on the TV.
//

import SwiftUI
import UIKit
import Combine

final class AirPadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Both role spellings: iOS renamed the external-display role and
        // versions differ in which one they use.
        let role = connectingSceneSession.role
        if role == .windowExternalDisplayNonInteractive
            || role.rawValue == "UIWindowSceneSessionRoleExternalDisplay" {
            let config = UISceneConfiguration(name: "TV", sessionRole: role)
            config.delegateClass = TVSceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: "Default", sessionRole: role)
    }
}

final class TVSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: TVScreenView())
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        TVSceneManager.shared.tvConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        TVSceneManager.shared.tvConnected = false
        window = nil
    }
}

/// Owns the TV side of the live-stream lifecycle. The stream is shared with
/// LiveScreenView: whoever needs it starts it; it stops only when nobody does.
/// Main-actor: every caller (scene delegates, SwiftUI views) is already on the
/// main thread, and ProStore/NetworkManager's published state lives there too.
@MainActor
final class TVSceneManager: ObservableObject {
    static let shared = TVSceneManager()

    @Published var tvConnected = false {
        didSet {
            guard tvConnected != oldValue else { return }
            if tvConnected { startTVStream() } else { stopTVStream() }
        }
    }

    /// True while a LiveScreenView is streaming on the phone (set by that view)
    /// so a TV disconnect doesn't kill the phone's own stream.
    var phoneWantsStream = false

    private var lastFrameAt = Date()
    private var watchdog: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    private func startTVStream() {
        guard ProStore.shared.isPro else { return }  // TV Mode rides on Live Screen (Pro)
        NetworkManager.shared.startLiveScreen(maxWidth: 1920, quality: 0.75)
        lastFrameAt = Date()

        // Track frames + reconnects like LiveScreenView does.
        NetworkManager.shared.$liveImage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.lastFrameAt = Date() }
            .store(in: &cancellables)
        NetworkManager.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self, connected, self.tvConnected, !self.phoneWantsStream else { return }
                NetworkManager.shared.startLiveScreen(maxWidth: 1920, quality: 0.75)
            }
            .store(in: &cancellables)

        // Watchdog only drives the stream when the phone's Live Screen isn't
        // open — otherwise the two would fight over quality/resolution.
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.tvConnected else { return }
                if !self.phoneWantsStream,
                   Date().timeIntervalSince(self.lastFrameAt) > 3 && NetworkManager.shared.isConnected {
                    NetworkManager.shared.startLiveScreen(maxWidth: 1920, quality: 0.75)
                }
            }
        }
    }

    private func stopTVStream() {
        watchdog?.cancel()
        watchdog = nil
        cancellables.removeAll()
        if !phoneWantsStream {
            NetworkManager.shared.stopLiveScreen()
        }
    }
}

/// What the TV shows: the Mac's desktop, fullscreen, nothing else.
struct TVScreenView: View {
    @ObservedObject private var network = NetworkManager.shared
    @ObservedObject private var proStore = ProStore.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !proStore.isPro {
                banner("TV Mode is part of Wield Pro",
                       detail: "Unlock Pro on your iPhone to put your Mac's screen on the TV.")
            } else if let image = network.liveImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else if network.isConnected {
                banner("Wield — \(network.currentMacName ?? "Mac")",
                       detail: "Waiting for the picture…")
            } else {
                banner("Wield",
                       detail: "Connect to your Mac on the iPhone to show it here.")
            }
        }
    }

    private func banner(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
