//
//  LoginView+AccountFlow.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import Foundation

extension LoginView {
    @MainActor
    func login(parsed: ParsedKey, save: Bool) async {
        do {
            let keypair = try await process_login(parsed, is_pubkey: is_pubkey, shouldSaveKey: save)
            if !save {
                // Set transient active session so the app recognizes us as logged in
                AccountsStore.shared.setActiveTransient(keypair)
                OnboardingSession.shared.end()
                notify(.login(keypair))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
