//
//  OnboardingSession.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import Foundation

/// Tracks whether the user is mid-onboarding/login to avoid unexpected account flips.
@MainActor
final class OnboardingSession: ObservableObject {
    static let shared = OnboardingSession()

    @Published var isOnboarding: Bool = false

    func begin() {
        isOnboarding = true
    }

    func end() {
        isOnboarding = false
    }
}
