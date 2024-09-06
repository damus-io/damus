//
//  ErrorView.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-01-08.
//

import SwiftUI

/// A generic user-presentable error view
///
/// Use this to handle and display errors to the user when it does not make sense to create a custom error view.
/// This includes good error handling UX practices, such as:
/// - Clear description
/// - Actionable advice for the user on what to do next.
/// - One-click support contact options
struct ErrorView: View {
    let damus_state: DamusState?
    let error: UserPresentableError
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Oops!", comment: "Heading for an error screen")
                .font(.title)
                .bold()
                .padding(.bottom, 10)
                .accessibilityHeading(.h1)
            Text(error.user_visible_description)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                    Text("Advice", comment: "Heading for some advice text to help the user with an error")
                        .font(.headline)
                        .accessibilityHeading(.h3)
                }
                Text(error.tip)
            }
            .padding()
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(10)
            .padding(.vertical, 30)
            
            Spacer()
            
            if let damus_state, damus_state.is_privkey_user {
                Button(action: {
                    damus_state.nav.push(route: .DMChat(dms: .init(our_pubkey: damus_state.keypair.pubkey, pubkey: Constants.SUPPORT_PUBKEY)))
                    dismiss()
                }, label: {
                    Text("Contact support via DMs", comment: "Button label to contact support from an error screen")
                })
                .padding(.vertical, 20)
            }
            Text("Contact support via email at [support@damus.io](mailto:support@damus.io)", comment: "Text to contact support via email")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .padding(.top, 20)
    }
    
    /// An error that is displayed to the user, and can be sent to the Developers as well.
    struct UserPresentableError {
        /// The description of the error to be shown to the user
        ///
        /// **Requirements:**
        /// - This should not be technical. It should use accessible language
        /// - Should be localized
        /// - It should try to explain the user what happened, and — if possible — why.
        let user_visible_description: String
        
        /// Helpful tip/advice to the user, to help them overcome the error
        ///
        /// **Requirements:**
        /// - Should provide actionable advice to the user
        /// - This should not be overly technical
        /// - Should be localized
        /// - Should NOT include support contact (The view that will display this will already include support contact options)
        ///
        /// **Implementation notes:**
        /// - This is NOT an optional value, because part of good UX is making sure error messages are actionable, which is something that is often forgotten. It's not uncommon for error messages to be written in vague, technical, and/or unactionable terms, but this is when the user needs help the most. And so this field is made mandatory to force developers to write actionable content to the user
        let tip: String
        
        /// Technical information about the error, which will be sendable to developers
        ///
        /// Note: This is still unutilized, but this will be used in the future.
        ///
        /// **Requirements**
        /// - Should never include any sensitive info
        /// - Should be in English. The developers are the main audience.
        /// - Should include helping info, such as context in which the error happens.
        /// - Should be technical
        let technical_info: String?
        
    }
}



#Preview {
    ErrorView(
        damus_state: test_damus_state,
        error: .init(
            user_visible_description: "We are still too early",
            tip: "Stay humble, keep building, stack sats",
            technical_info: nil
        )
    )
}
