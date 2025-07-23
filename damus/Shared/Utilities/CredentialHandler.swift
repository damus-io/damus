//
//  CredentialHandler.swift
//  damus
//
//  Created by Bryan Montz on 4/26/23.
//

import Foundation
import AuthenticationServices

final class CredentialHandler: NSObject, ASAuthorizationControllerDelegate {
    
    func check_credentials() {
        let requests: [ASAuthorizationRequest] = [ASAuthorizationPasswordProvider().createRequest()]
        let authorizationController = ASAuthorizationController(authorizationRequests: requests)
        authorizationController.delegate = self
        authorizationController.performRequests()
    }
    
    func save_credential(pubkey: Pubkey, privkey: Privkey) {
        let pub = pubkey.npub
        let priv = privkey.nsec

        SecAddSharedWebCredential("damus.io" as CFString, pub as CFString, priv as CFString, { error in
            if let error {
                print("⚠️ An error occurred while saving credentials: \(error)")
            }
        })
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASPasswordCredential,
              let parsedKey = parse_key(cred.password) else {
            return
        }
        
        Task {
            switch parsedKey {
            case .pub, .priv:
                try? await process_login(parsedKey, is_pubkey: false)
            default:
                break
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("⚠️ Warning: authentication failed with error: \(error)")
    }
}
