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
    @State private var searchText: String = ""

    @ObservedObject var settings: UserSettingsStore
    
    // String constants
    private let DELETE_KEYWORD = "DELETE"
    private let accountsTitle = NSLocalizedString("Accounts", comment: "Settings section for managing accounts")
    private let keysTitle = NSLocalizedString("Keys", comment: "Settings section for managing keys")
    private let appearanceTitle = NSLocalizedString("Appearance and filters", comment: "Section header for text, appearance, and content filter settings")
    private let searchUniverseTitle = NSLocalizedString("Search / Universe", comment: "Section header for search/universe settings")
    private let notificationsTitle = NSLocalizedString("Notifications", comment: "Section header for Damus notifications")
    private let zapsTitle = NSLocalizedString("Zaps", comment: "Section header for zap settings")
    private let translationTitle = NSLocalizedString("Translation", comment: "Section header for text and appearance settings")
    private let reactionsTitle = NSLocalizedString("Reactions", comment: "Section header for reactions settings")
    private let developerTitle = NSLocalizedString("Developer", comment: "Section header for developer settings")
    private let firstAidTitle = NSLocalizedString("First Aid", comment: "Section header for first aid tools and settings")
    private let signOutTitle = NSLocalizedString("Sign out", comment: "Sidebar menu label to sign out of the account.")
    private let deleteAccountTitle = NSLocalizedString("Delete Account", comment: "Button to delete the user's account.")
    private let versionTitle = NSLocalizedString("Version", comment: "Section title for displaying the version number of the Damus app.")
    private let copyString = NSLocalizedString("Copy", comment: "Context menu option for copying the version of damus.")
    
    init(state: DamusState) {
        self.state = state
        _settings = ObservedObject(initialValue: state.settings)
    }

    func textColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    func showSettingsButton(title : String)->Bool{
        return searchText.isEmpty || title.lowercased().contains(searchText.lowercased())
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Form {
                Section {
                    // Accounts
                    if showSettingsButton(title: accountsTitle) {
                        NavigationLink(value: Route.ManageAccountsSettings) {
                            IconLabel(accountsTitle, img_name: "user", color: .blue)
                        }
                    }
                    // Keys
                    if showSettingsButton(title: keysTitle){
                        NavigationLink(value:Route.KeySettings(keypair: state.keypair)){
                            IconLabel(keysTitle,img_name:"Key",color:.purple)
                        }
                    }
                    // Appearance and filters
                    if showSettingsButton(title: appearanceTitle){
                        NavigationLink(value:Route.AppearanceSettings(settings: settings)){
                            IconLabel(appearanceTitle,img_name:"eye",color:.red)
                        }
                    }
                    // Search/Universe
                    if showSettingsButton(title: searchUniverseTitle){
                        NavigationLink(value: Route.SearchSettings(settings: settings)){
                            IconLabel(searchUniverseTitle,img_name:"search",color:.red)
                        }
                    }

                    //Notifications
                    if showSettingsButton(title: notificationsTitle){
                        NavigationLink(value: Route.NotificationSettings(settings: settings)){
                            IconLabel(notificationsTitle,img_name:"notification-bell-on",color:.blue)
                        }
                    }
                    //Zaps
                    if showSettingsButton(title: zapsTitle){
                        NavigationLink(value: Route.ZapSettings(settings: settings)){
                            IconLabel(zapsTitle,img_name:"zap.fill",color:.orange)
                        }
                    }
                    //Translation
                    if showSettingsButton(title: translationTitle){
                        NavigationLink(value: Route.TranslationSettings(settings: settings)){
                            IconLabel(translationTitle,img_name:"globe",color:.green)
                        }
                    }
                    //Reactions
                    if showSettingsButton(title: reactionsTitle){
                        NavigationLink(value: Route.ReactionsSettings(settings: settings)){
                            IconLabel(reactionsTitle,img_name:"shaka.fill",color:.purple)
                        }
                    }
                    //Developer
                    if showSettingsButton(title: developerTitle){
                        NavigationLink(value: Route.DeveloperSettings(settings: settings)){
                            IconLabel(developerTitle,img_name:"magic-stick2.fill",color:DamusColors.adaptableBlack)
                        }
                    }
                    //First Aid
                    if showSettingsButton(title: firstAidTitle){
                        NavigationLink(value: Route.FirstAidSettings(settings: settings)){
                            IconLabel(firstAidTitle,img_name:"help2",color: .red)
                        }
                    }
                }
                //Sign out Section
                if showSettingsButton(title: signOutTitle){
                    Section(signOutTitle){
                        Button(action: {
                            if state.keypair.privkey == nil {
                                logout(state)
                            } else {
                                confirm_logout = true
                            }
                        }, label: {
                            Label(signOutTitle, image: "logout")
                                .foregroundColor(textColor())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        })
                    }
                }
                // Delete Account
                if showSettingsButton(title: deleteAccountTitle){
                    if state.is_privkey_user {
                        Section(header: Text("Permanently Delete Account", comment: "Section title for deleting the user")) {
                            Button(action: {
                                delete_account_warning = true
                            }, label: {
                                Label(deleteAccountTitle, image: "delete")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundColor(.red)
                            })
                        }
                    }
                }
                // Version info
                if showSettingsButton(title: versionTitle) {
                    Section(
                        header: Text(versionTitle),
                        footer: Text("").padding(.bottom, tabHeight + getSafeAreaBottom())
                    ) {
                        Text(verbatim: VersionInfo.version)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = VersionInfo.version
                                } label: {
                                    Label(copyString, image: "copy2")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title for Settings view."))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: NSLocalizedString("Search within settings", comment: "Text to prompt the user to search settings."))
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
                Task {
                    await state.nostrNetwork.postbox.send(ev)
                    logout(state)
                }
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
            if KeyStorageSettings.mode == .localOnly {
                Text("Your key is stored locally only. Make sure you have backed up your nsec key before logging out, or you will lose access to this account.", comment: "Reminder message for local-only storage when logging out.")
            } else {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
            }
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
