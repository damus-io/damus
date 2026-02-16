//
//  HumanReadableErrors.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-05.
//

import Foundation

extension WalletConnect.FullWalletResponse.InitializationError {
    var humanReadableError: ErrorView.UserPresentableError? {
        switch self {
        case .incorrectAuthorPubkey:
            nil    // Anyone can send a response event with an incorrect author pubkey, it is not really an "error". We should silently ignore it.
        case .missingRequestIdReference:
            .init(
                user_visible_description: NSLocalizedString("Wallet provider returned an invalid response.", comment: "Error description shown to the user when a response from the wallet provider is invalid"),
                tip: NSLocalizedString("Please copy the technical info and send it to our support team.", comment: "Tip on how to resolve issue when wallet returns an invalid response"),
                technical_info: "Wallet response does not make a reference to any request; No request ID `e` tag was found."
            )
        case .failedToDecodeJSON(let error):
            .init(
                user_visible_description: NSLocalizedString("Wallet provider returned a response that we do not understand.", comment: "Error description shown to the user when a response from the wallet provider contains data the app does not understand"),
                tip: NSLocalizedString("Please copy the technical info and send it to our support team.", comment: "Tip on how to resolve issue when wallet returns an invalid response"),
                technical_info: "Failed to decode NWC Wallet response JSON. Error: \(error)"
            )
        case .failedToDecrypt(let error):
            .init(
                user_visible_description: NSLocalizedString("Wallet provider returned a response that we could not decrypt.", comment: "Error description shown to the user when a response from the wallet provider contains data the app could not decrypt."),
                tip: NSLocalizedString("Please copy the technical info and send it to our support team.", comment: "Tip on how to resolve issue when wallet returns an invalid response"),
                technical_info: "Failed to decrypt NWC Wallet response. Error: \(error)"
            )
        }
    }
}

extension WalletConnect.WalletResponseErr {
    var humanReadableError: ErrorView.UserPresentableError? {
        guard let code = self.code else {
            return .init(
                user_visible_description: String(format: NSLocalizedString("Your connected wallet raised an unknown error. Message: %@", comment: "Human readable error description for unknown error"), self.message ?? NSLocalizedString("Empty error message", comment: "A human readable placeholder to indicate that the error message is empty")),
                tip: NSLocalizedString("Please contact the developer of your wallet provider for help.", comment: "Human readable error description for an unknown error raised by a wallet provider."),
                technical_info: "NWC wallet provider returned an error response without a valid reason code. Message: \(self.message ?? "Empty error message")"
            )
        }
        switch code {
        case .rateLimited:
            return .init(
                user_visible_description: NSLocalizedString("Your wallet is temporarily being rate limited.", comment: "Error description for rate limit error"),
                tip: NSLocalizedString("Wait a few moments, and then try again.", comment: "Tip for rate limit error"),
                technical_info: "Wallet returned a rate limit error with message: \(self.message ?? "No further details provided")"
            )
        case .notImplemented:
            return .init(
                user_visible_description: NSLocalizedString("This feature is not implemented by your wallet.", comment: "Error description for not implemented feature"),
                tip: NSLocalizedString("Please check for updates or contact your wallet provider.", comment: "Tip for not implemented error"),
                technical_info: "Wallet reported a not implemented error. Message: \(self.message ?? "No further details provided")"
            )
        case .insufficientBalance:
            return .init(
                user_visible_description: NSLocalizedString("Your wallet does not have sufficient balance for this transaction.", comment: "Error description for insufficient balance"),
                tip: NSLocalizedString("Please deposit more funds and try again.", comment: "Tip for insufficient balance errors"),
                technical_info: "Wallet returned an insufficient balance error. Message: \(self.message ?? "No further details provided")"
            )
        case .quotaExceeded:
            return .init(
                user_visible_description: NSLocalizedString("Your transaction quota has been exceeded.", comment: "Error description for quota exceeded"),
                tip: NSLocalizedString("Wait for the quota to reset, or configure your wallet provider to allow a higher limit.", comment: "Tip for quota exceeded"),
                technical_info: "Wallet reported a quota exceeded error. Message: \(self.message ?? "No further details provided")"
            )
        case .restricted:
            return .init(
                user_visible_description: NSLocalizedString("This operation is restricted by your wallet.", comment: "Error description for restricted operation"),
                tip: NSLocalizedString("Check your account permissions or contact support.", comment: "Tip for restricted operation"),
                technical_info: "Wallet returned a restricted error. Message: \(self.message ?? "No further details provided")"
            )
        case .unauthorized:
            return .init(
                user_visible_description: NSLocalizedString("You are not authorized to perform this action with your wallet.", comment: "Error description for unauthorized access"),
                tip: NSLocalizedString("Please verify your credentials or permissions.", comment: "Tip for unauthorized access"),
                technical_info: "Wallet returned an unauthorized error. Message: \(self.message ?? "No further details provided")"
            )
        case .internalError:
            return .init(
                user_visible_description: NSLocalizedString("An internal error occurred in your wallet.", comment: "Error description for an internal error"),
                tip: NSLocalizedString("Try restarting your wallet or contacting support if the problem persists.", comment: "Tip for internal error"),
                technical_info: "Wallet reported an internal error. Message: \(self.message ?? "No further details provided")"
            )
        case .other:
            return .init(
                user_visible_description: NSLocalizedString("An unspecified error occurred in your wallet.", comment: "Error description for an unspecified error"),
                tip: NSLocalizedString("Please try again or contact your wallet provider for further assistance.", comment: "Tip for unspecified error"),
                technical_info: "Wallet returned an error: \(self.message ?? "No further details provided")"
            )
        }
    }
}
