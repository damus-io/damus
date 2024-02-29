//
//  DamusPurpleNewUserOnboardingView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-29.
//

import SwiftUI

struct DamusPurpleNewUserOnboardingView: View {
    var damus_state: DamusState
    @State var current_page: Int = 0
    @Environment(\.dismiss) var dismiss
    
    func next_page() {
        current_page += 1
    }

    var body: some View {
        NavigationView {
            TabView(selection: $current_page) {
                DamusPurpleWelcomeView(next_page: {
                    self.next_page()
                })
                    .tag(0)
                
                DamusPurpleTranslationSetupView(damus_state: damus_state, next_page: {
                    dismiss()
                })
                .tag(1)
            }
            .ignoresSafeArea()  // Necessary to avoid weird white edges
        }
        .task {
            guard let account = try? await damus_state.purple.fetch_account(pubkey: damus_state.pubkey), account.active else {
                return
            }
            // Let's mark onboarding as "shown"
            damus_state.purple.onboarding_status.onboarding_was_shown = true
            // Let's notify other views across SwiftUI to update our user's Purple status.
            notify(.purple_account_update(account))
        }
    }
}

#Preview {
    DamusPurpleNewUserOnboardingView(damus_state: test_damus_state)
}
