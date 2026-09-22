//
//  AirPadApp.swift
//  AirPad
//
//  Created by shunathon Owens on 11/24/25.
//

import SwiftUI

@main
struct AirPadApp: App {
    // Routes external-display (TV) scene sessions to TVSceneDelegate.
    @UIApplicationDelegateAdaptor(AirPadAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        NetworkManager.shared.tryAutoReconnectOnForeground()
                    } else {
                        // Anything still held belongs to the MAC, and leaving the
                        // app strands it there with no way back: the Mac keeps the
                        // button down and every cursor move drags. Hand Mouse is
                        // the worst case — backgrounding interrupts the camera
                        // session, so no more frames arrive, the recognizer never
                        // reaches its hand-lost threshold, and a pinch-drag is
                        // held indefinitely.
                        NetworkManager.shared.releaseHeldInput()
                    }
                }
                .sheet(
                    isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { presented in
                            // If the sheet is dismissed (including swipe down), mark onboarding as completed
                            if presented == false { hasCompletedOnboarding = true }
                        }
                    ),
                    onDismiss: {
                        // Extra safety: if dismissed without tapping Done, persist completion
                        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
                    }
                ) {
                    OnboardingView()
                }
        }
    }
}
