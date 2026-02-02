//
//  AirPadApp.swift
//  AirPad
//
//  Created by shunathon Owens on 11/24/25.
//

import SwiftUI

@main
struct AirPadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        NetworkManager.shared.tryAutoReconnectOnForeground()
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
