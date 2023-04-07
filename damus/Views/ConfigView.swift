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
                    NavigationLink(destination: KeySettingsView(keypair: state.keypair)) {
                        IconLabel(NSLocalizedString("Keys", comment: "Settings section for managing keys"), img_name: "key.fill", color: .purple)
                    }
                    
                    NavigationLink(destination: AppearanceSettingsView(settings: settings)) {
                        IconLabel(NSLocalizedString("Appearance", comment: "Section header for text and appearance settings"), img_name: "textformat", color: .red)
                    }
                    
                    NavigationLink(destination: NotificationSettingsView(settings: settings)) {
                        IconLabel(NSLocalizedString("Local Notifications", comment: "Section header for damus local notifications user configuration"), img_name: "bell.fill", color: .blue)
                    }
                    
                    NavigationLink(destination: ZapSettingsView(pubkey: state.pubkey, settings: settings)) {
                        IconLabel(NSLocalizedString("Zaps", comment: "Section header for zap settings"), img_name: "bolt.fill", color: .orange)
                    }
                    
                    NavigationLink(destination: TranslationSettingsView(settings: settings)) {
                        IconLabel(NSLocalizedString("Translation", comment: "Section header for text and appearance settings"), img_name: "globe.americas.fill", color: .green)
                    }
                }
                

                Section(NSLocalizedString("Sign Out", comment: "Section title for signing out")) {
                    Button(action: {
                        if state.keypair.privkey == nil {
                            notify(.logout, ())
                        } else {
                            confirm_logout = true
                        }
                    }, label: {
                        Label(NSLocalizedString("Sign out", comment: "Sidebar menu label to sign out of the account."), systemImage: "pip.exit")
                            .foregroundColor(textColor())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    })
                }

                if state.is_privkey_user {
                    Section(NSLocalizedString("Permanently Delete Account", comment: "Section title for deleting the user")) {
                        Button(NSLocalizedString("Delete Account", comment: "Button to delete the user's account."), role: .destructive) {
                            delete_account_warning = true
                        }
                    }
                }

                if let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"], let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] {
                    Section(NSLocalizedString("Version", comment: "Section title for displaying the version number of the Damus app.")) {
                        Text(verbatim: "\(bundleShortVersion) (\(bundleVersion))")
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
                guard let full_kp = state.keypair.to_full() else {
                    return
                }
                
                guard delete_text == DELETE_KEYWORD else {
                    return
                }
                
                let ev = created_deleted_account_profile(keypair: full_kp)
                state.postbox.send(ev)
                notify(.logout, ())
            }
        }
        .alert(NSLocalizedString("Logout", comment: "Alert for logging out the user."), isPresented: $confirm_logout) {
            Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                confirm_logout = false
            }
            Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                notify(.logout, ())
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
            ConfigView(state: test_damus_state())
        }
    }
}


func handle_string_amount(new_value: String) -> Int? {
    let digits = Set("0123456789")
    let filtered = new_value.filter { digits.contains($0) }

    if filtered == "" {
        return nil
    }

    guard let amt = Int(filtered) else {
        return nil
    }
    
    return amt
}

func clear_kingfisher_cache() -> Void {
    KingfisherManager.shared.cache.clearMemoryCache()
    KingfisherManager.shared.cache.clearDiskCache()
    KingfisherManager.shared.cache.cleanExpiredDiskCache()
}
