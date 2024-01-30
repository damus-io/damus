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
    }
}

#Preview {
    DamusPurpleNewUserOnboardingView(damus_state: test_damus_state)
}
