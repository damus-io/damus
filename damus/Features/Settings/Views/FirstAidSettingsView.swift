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
    @State var contactListInitiallyPresent: Bool = true
    @State var relayListInitiallyPresent: Bool = true
    
    var body: some View {
        Form {
            if !contactListInitiallyPresent {
                ItemResetSection(
                    damus_state: self.damus_state,
                    settings: self.settings,
                    itemName: NSLocalizedString("Contact list", comment: "Section title for Contact list first aid tools"),
                    hintMessage: NSLocalizedString(
                        "No contact list was found. You might experience issues using the app. If you suspect you have permanently lost your contact list (or if you never had one), you can fix this by resetting it",
                        comment: "Section footer for Contact list first aid tools"
                    ),
                    resetButtonLabel: NSLocalizedString("Reset contact list", comment: "Button to reset contact list."),
                    warningMessage: NSLocalizedString(
                        "WARNING:\n\nThis will reset your contact list, including the list of everyone you follow and potentially the list of all relays you usually connect to. ONLY PROCEED IF YOU ARE SURE YOU HAVE LOST YOUR CONTACT LIST BEYOND RECOVERABILITY.",
                        comment: "Alert for resetting the user's contact list."),
                    successMessage: NSLocalizedString("Contact list has been reset", comment: "Message indicating that the contact list was successfully reset."),
                    performOperation: {
                        try await self.resetContactList()
                    }
                )
            }
            
            if !relayListInitiallyPresent {
                ItemResetSection(
                    damus_state: self.damus_state,
                    settings: self.settings,
                    itemName: NSLocalizedString("Relay list", comment: "Section title for Relay list first aid tools"),
                    hintMessage: NSLocalizedString(
                        "No relay list was found. You might experience issues using the app. If you suspect you have permanently lost your relay list (or if you never had one), you can fix this by resetting it",
                        comment: "Section footer for relay list first aid tools"
                    ),
                    resetButtonLabel: NSLocalizedString("Repair relay list", comment: "Button to repair relay list."),
                    warningMessage: NSLocalizedString("WARNING:\n\nThis will attempt to repair your relay list based on other information we have. You may lose any relays you have added manually. Only proceed if you have lost your relay list beyond recoverability or if you are ok with losing any manually added relays.", comment: "Alert for repairing the user's relay list."),
                    successMessage: NSLocalizedString("Relay list has been repaired", comment: "Message indicating that the relay list was successfully repaired."),
                    performOperation: {
                        try await self.resetRelayList()
                    }
                )
            }
            
            if contactListInitiallyPresent && contactListInitiallyPresent {
                Text("We did not detect any issues that we can automatically fix for you. If you are having issues, please contact Damus support: [support@damus.io](mailto:support@damus.io)", comment: "Message indicating that no First Aid actions are available.")
            }
        }
        .navigationTitle(NSLocalizedString("First Aid", comment: "Navigation title for first aid settings and tools"))
        .onAppear {
            self.contactListInitiallyPresent = damus_state.contacts.event != nil
            self.relayListInitiallyPresent = damus_state.nostrNetwork.userRelayList.getUserCurrentRelayList() != nil
        }
    }
    
    func resetContactList() async throws {
        guard let new_contact_list_event = make_first_contact_event(keypair: damus_state.keypair) else {
            throw FirstAidError.cannotMakeFirstContactEvent
        }
        damus_state.nostrNetwork.send(event: new_contact_list_event)
        damus_state.settings.latest_contact_event_id_hex = new_contact_list_event.id.hex()
    }
    
    func resetRelayList() async throws {
        let bestEffortRelayList = damus_state.nostrNetwork.userRelayList.getBestEffortRelayList()
        try damus_state.nostrNetwork.userRelayList.set(userRelayList: bestEffortRelayList)
    }
    
    enum FirstAidError: Error {
        case cannotMakeFirstContactEvent
    }
}

extension FirstAidSettingsView {
    struct ItemResetSection: View {
        let damus_state: DamusState
        @ObservedObject var settings: UserSettingsStore
        @State var reset_item_state: ItemResetState = .not_started
        
        let itemName: String
        let hintMessage: String
        let resetButtonLabel: String
        let warningMessage: String
        let successMessage: String
        var performOperation: () async throws -> Void
        
        enum ItemResetState: Equatable {
            case not_started
            case confirming_with_user
            case error(String)
            case in_progress
            case completed
        }
        
        var body: some View {
            Section(
                header: Text(itemName),
                footer: Text(hintMessage)
            ) {
                Button(action: {
                    reset_item_state = .confirming_with_user
                }, label: {
                    HStack(spacing: 6) {
                        switch reset_item_state {
                        case .not_started, .error:
                            Label(resetButtonLabel, image: "broom")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.red)
                        case .confirming_with_user, .in_progress:
                            ProgressView()
                            Text(NSLocalizedString("In progress…", comment: "Loading message indicating that a first aid operation is in progress."))
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(successMessage)
                        }
                    }
                })
                .disabled(reset_item_state == .in_progress || reset_item_state == .completed)
                
                if case let .error(error_message) = reset_item_state {
                    Text(error_message)
                        .foregroundStyle(.red)
                }
            }
            .alert(warningMessage, isPresented: Binding(get: { reset_item_state == .confirming_with_user }, set: { _ in return })
            ) {
                Button(NSLocalizedString("Cancel", comment: "Cancel the user-requested operation."), role: .cancel) {
                    reset_item_state = .not_started
                }
                Button(NSLocalizedString("Continue", comment: "Continue with the user-requested operation.")) {
                    Task {
                        do {
                            try await performOperation()
                            reset_item_state = .completed
                        }
                        catch {
                            reset_item_state = .error(NSLocalizedString("An unexpected error happened while trying to perform this action. Please contact support.", comment: "Error message for a failed reset/repair operation"))
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    FirstAidSettingsView(damus_state: test_damus_state, settings: test_damus_state.settings)
}
