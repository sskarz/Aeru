//
//  RAGSearchLLMApp.swift
//  RAGSearchLLM
//
//  Created by Sanskar Thapa on 7/15/25.
//

import SwiftUI

@main
struct AeruApp: App {
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                AeruView()
                
                if showOnboarding {
                    OnboardingView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showOnboarding)
            .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                withAnimation {
                    showOnboarding = false
                }
            }
        }
    }
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}
