//
//  UserRelayListErrors.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-27.
//

import Foundation

extension NostrNetworkManager.UserRelayListManager {
    /// Models an error that may occur when performing operations that change the user's relay list.
    ///
    /// Callers to functions that throw this error SHOULD handle them in order to provide a better user experience.
    enum UpdateError: Error {
        /// The user is not authorized to change relay list, usually because the private key is missing.
        case notAuthorizedToChangeRelayList
        /// An error occurred when forming the relay list Nostr event.
        case cannotFormRelayListEvent
        /// Cannot add item to the relay list because the relay is already present in the list.
        case relayAlreadyExists
        /// Cannot update the relay list because we do not have the user's previous relay list.
        ///
        /// Implementers must be careful not to overwrite the user's existing relay list if it exists somewhere else.
        case noInitialRelayList
        /// Cannot remove or update a specific relay because it is not on the relay list
        case noSuchRelay
        
        /// Convert `RelayPool.RelayError` into `UserRelayListUpdateError`
        static func from(_ relayPoolError: RelayPool.RelayError) -> Self {
            switch relayPoolError {
            case .RelayAlreadyExists: return .relayAlreadyExists
            }
        }
        
        var humanReadableError: ErrorView.UserPresentableError {
            switch self {
            case .notAuthorizedToChangeRelayList:
                ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("You do not have permission to alter this relay list.", comment: "Human readable error description"),
                    tip: NSLocalizedString("Please make sure you have logged-in with your private key.", comment: "Human readable tip for error"),
                    technical_info: nil
                )
            case .cannotFormRelayListEvent:
                ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("There was a problem creating the relay list event.", comment: "Human readable error description"),
                    tip: NSLocalizedString("Please try again later or contact support if the issue persists.", comment: "Human readable tip for error"),
                    technical_info: "Failed forming Nostr event for the relay list update."
                )
            case .relayAlreadyExists:
                ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("This relay is already in your list.", comment: "Human readable tip for error"),
                    tip: NSLocalizedString("Check the address and/or the relay list.", comment: "Human readable tip for error"),
                    technical_info: nil
                )
            case .noInitialRelayList:
                ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("No initial relay list available to update.", comment: "Human readable error description"),
                    tip: NSLocalizedString("Please go to Settings > First Aid > Repair relay list, or contact support.", comment: "Human readable tip for error"),
                    technical_info: "Missing initial relay list data for reference during update."
                )
            case .noSuchRelay:
                ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("The specified relay that you are trying to udpate was not found in your relay list.", comment: "Human readable error description"),
                    tip: NSLocalizedString("This is an unexpected error, please contact support.", comment: "Human readable tip for error"),
                    technical_info: nil
                )
            }
        }
    }
    
    enum LoadingError: Error {
        case relayListParseError
        
        var humanReadableError: ErrorView.UserPresentableError {
            switch self {
            case .relayListParseError:
                return ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("Your relay list appears to be broken, so we cannot connect you to your Nostr network.", comment: "Human readable error description for a failure to parse the relay list due to a bad relay list"),
                    tip: NSLocalizedString("Please contact support for further help.", comment: "Human readable tips for what to do for a failure to find the relay list"),
                    technical_info: "Relay list could not be parsed."
                )
            }
        }
    }
}
