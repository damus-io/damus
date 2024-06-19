//
//  ConfigView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//
import AVFoundation
import Kingfisher
import SwiftUI
import LocalAuthentication
import Combine

struct ConfigView: View {
    let state: DamusState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State var confirm_logout: Bool = false
    @State var delete_account_warning: Bool = false
    @State var confirm_delete_account: Bool = false
    @State var delete_text: String = ""

    @ObservedObject var settings: UserSettingsStore

    private let DELETE_KEYWORD = "DELETE"

    init(state: DamusState) {
        self.state = state
        _settings = ObservedObject(initialValue: state.settings)
    }

    func textColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Form {
                Section {
                    NavigationLink(value: Route.KeySettings(keypair: state.keypair)) {
                        IconLabel(NSLocalizedString("Keys", comment: "Settings section for managing keys"), img_name: "Key", color: .purple)
                    }

                    NavigationLink(value: Route.AppearanceSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Appearance and filters", comment: "Section header for text, appearance, and content filter settings"), img_name: "eye", color: .red)
                    }

                    NavigationLink(value: Route.SearchSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Search/Universe", comment: "Section header for search/universe settings"), img_name: "search", color: .red)
                    }

                    NavigationLink(value: Route.NotificationSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Notifications", comment: "Section header for Damus notifications"), img_name: "notification-bell-on", color: .blue)
                    }

                    NavigationLink(value: Route.ZapSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Zaps", comment: "Section header for zap settings"), img_name: "zap.fill", color: .orange)
                    }

                    NavigationLink(value: Route.TranslationSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Translation", comment: "Section header for text and appearance settings"), img_name: "globe", color: .green)
                    }
                    
                    NavigationLink(value: Route.ReactionsSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Reactions", comment: "Section header for reactions settings"), img_name: "shaka.fill", color: .purple)
                    }
                    
                    NavigationLink(value: Route.DeveloperSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("Developer", comment: "Section header for developer settings"), img_name: "magic-stick2.fill", color: DamusColors.adaptableBlack)
                    }
                    
                    NavigationLink(value: Route.FirstAidSettings(settings: settings)) {
                        IconLabel(NSLocalizedString("First Aid", comment: "Section header for first aid tools and settings"), img_name: "help2", color: .red)
                    }
                }

                Section(NSLocalizedString("Sign Out", comment: "Section title for signing out")) {
                    Button(action: {
                        if state.keypair.privkey == nil {
                            logout(state)
                        } else {
                            confirm_logout = true
                        }
                    }, label: {
                        Label(NSLocalizedString("Sign out", comment: "Sidebar menu label to sign out of the account."), image: "logout")
                            .foregroundColor(textColor())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    })
                }

                if state.is_privkey_user {
                    Section(header: Text("Permanently Delete Account", comment: "Section title for deleting the user")) {
                        Button(action: {
                            delete_account_warning = true
                        }, label: {
                            Label(NSLocalizedString("Delete Account", comment: "Button to delete the user's account."), image: "delete")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.red)
                        })
                    }
                }
                
                Section(NSLocalizedString("Version", comment: "Section title for displaying the version number of the Damus app.")) {
                    Text(verbatim: VersionInfo.version)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = VersionInfo.version
                            } label: {
                                Label(NSLocalizedString("Copy", comment: "Context menu option for copying the version of damus."), image: "copy2")
                            }
                        }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title for Settings view."))
        .navigationBarTitleDisplayMode(.large)
        .alert(NSLocalizedString("WARNING:\n\nTHIS WILL SIGN AN EVENT THAT DELETES THIS ACCOUNT.\n\nYOU WILL NO LONGER BE ABLE TO LOG INTO DAMUS USING THIS ACCOUNT KEY.\n\n ARE YOU SURE YOU WANT TO CONTINUE?", comment: "Alert for deleting the users account."), isPresented: $delete_account_warning) {

            Button(NSLocalizedString("Cancel", comment: "Cancel deleting the user."), role: .cancel) {
                delete_account_warning = false
            }
            Button(NSLocalizedString("Continue", comment: "Continue with deleting the user.")) {
                confirm_delete_account = true
            }
        }
        .alert(NSLocalizedString("Permanently Delete Account", comment: "Alert for deleting the users account."), isPresented: $confirm_delete_account) {
            TextField(String(format: NSLocalizedString("Type %@ to delete", comment: "Text field prompt asking user to type DELETE in all caps to confirm that they want to proceed with deleting their account."), DELETE_KEYWORD), text: $delete_text)
            Button(NSLocalizedString("Cancel", comment: "Cancel deleting the user."), role: .cancel) {
                confirm_delete_account = false
            }
            Button(NSLocalizedString("Delete", comment: "Button for deleting the users account."), role: .destructive) {
                guard let keypair = state.keypair.to_full(),
                      delete_text == DELETE_KEYWORD,
                      let ev = created_deleted_account_profile(keypair: keypair) else {
                    return
                }
                state.postbox.send(ev)
                logout(state)
            }
        }
        .alert(NSLocalizedString("Logout", comment: "Alert for logging out the user."), isPresented: $confirm_logout) {
            Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                confirm_logout = false
            }
            Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                logout(state)
            }
        } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }

}

struct ConfigView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConfigView(state: test_damus_state)
        }
    }
}


func handle_string_amount(new_value: String) -> Int? {
    let filtered = new_value.filter {
        $0.isNumber
    }

    if filtered == "" {
        return nil
    }

    guard let amt = NumberFormatter().number(from: filtered) as? Int else {
        return nil
    }

    return amt
}
