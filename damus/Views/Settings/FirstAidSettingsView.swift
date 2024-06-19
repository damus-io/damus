//
//  FirstAidSettingsView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-04-19.
//

import SwiftUI

struct FirstAidSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @State var reset_contact_list_state: ContactListResetState = .not_started
    
    enum ContactListResetState: Equatable {
        case not_started
        case confirming_with_user
        case error(String)
        case in_progress
        case completed
    }
    
    
    var body: some View {
        Form {
            if damus_state.contacts.event == nil {
                Section(
                    header: Text(NSLocalizedString("Contact list (Follows + Relay list)", comment: "Section title for Contact list first aid tools")),
                    footer: Text(NSLocalizedString("No contact list was found. You might experience issues using the app. If you suspect you have permanently lost your contact list (or if you never had one), you can fix this by resetting it", comment: "Section footer for Contact list first aid tools"))
                ) {
                    Button(action: {
                        reset_contact_list_state = .confirming_with_user
                    }, label: {
                        HStack(spacing: 6) {
                            switch reset_contact_list_state {
                                case .not_started, .error:
                                    Label(NSLocalizedString("Reset contact list", comment: "Button to reset contact list."), image: "broom")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(.red)
                                case .confirming_with_user, .in_progress:
                                    ProgressView()
                                    Text(NSLocalizedString("In progress…", comment: "Loading message indicating that a contact list reset operation is in progress."))
                                case .completed:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(NSLocalizedString("Contact list has been reset", comment: "Message indicating that the contact list was successfully reset."))
                            }
                        }
                    })
                    .disabled(reset_contact_list_state == .in_progress || reset_contact_list_state == .completed)
                    
                    if case let .error(error_message) = reset_contact_list_state {
                        Text(error_message)
                            .foregroundStyle(.red)
                    }
                }
                .alert(NSLocalizedString("WARNING:\n\nThis will reset your contact list, including the list of everyone you follow and the list of all relays you usually connect to. ONLY PROCEED IF YOU ARE SURE YOU HAVE LOST YOUR CONTACT LIST BEYOND RECOVERABILITY.", comment: "Alert for resetting the user's contact list."),
                       isPresented: Binding(get: { reset_contact_list_state == .confirming_with_user }, set: { _ in return })
                       ) {
                           Button(NSLocalizedString("Cancel", comment: "Cancel resetting the contact list."), role: .cancel) {
                               reset_contact_list_state = .not_started
                           }
                           Button(NSLocalizedString("Continue", comment: "Continue with resetting the contact list.")) {
                               guard let new_contact_list_event = make_first_contact_event(keypair: damus_state.keypair) else {
                                   reset_contact_list_state = .error(NSLocalizedString("An unexpected error happened while trying to create the new contact list. Please contact support.", comment: "Error message for a failed contact list reset operation"))
                                   return
                               }
                               damus_state.pool.send(.event(new_contact_list_event))
                               reset_contact_list_state = .completed
                           }
                       }
            }
            
            if damus_state.contacts.event != nil {
                Text("We did not detect any issues that we can automatically fix for you. If you are having issues, please contact Damus support: [support@damus.io](mailto:support@damus.io)", comment: "Message indicating that no First Aid actions are available.")
            }
        }
        .navigationTitle(NSLocalizedString("First Aid", comment: "Navigation title for first aid settings and tools"))
    }
}

#Preview {
    FirstAidSettingsView(damus_state: test_damus_state, settings: test_damus_state.settings)
}
