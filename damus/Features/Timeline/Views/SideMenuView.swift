//
//  SideMenuView.swift
//  damus
//
//  Created by Ben Weeks on 1/6/23.
//  Ref: https://blog.logrocket.com/create-custom-collapsible-sidebar-swiftui/

import SwiftUI

@MainActor
struct SideMenuView: View {
    let damus_state: DamusState
    @Binding var isSidebarVisible: Bool
    @Binding var selected: Timeline
    @State var confirm_logout: Bool = false
    @State private var showQRCode = false

    var sideBarWidth = min(UIScreen.main.bounds.size.width * 0.65, 400.0)
    let verticalSpacing: CGFloat = 25
    let padding: CGFloat = 30

    var body: some View {
        ZStack {
            GeometryReader { _ in
                EmptyView()
            }
            .background(DamusColors.darkGrey.opacity(0.6))
            .opacity(isSidebarVisible ? 1 : 0)
            .animation(.default, value: isSidebarVisible)
            .onTapGesture {
                isSidebarVisible.toggle()
            }

            content
        }
    }

    func SidemenuItems(profile_model: ProfileModel, followers: FollowersModel) -> some View {
        return VStack(spacing: verticalSpacing) {
            NavigationLink(value: Route.Profile(profile: profile_model, followers: followers)) {
                navLabel(title: NSLocalizedString("Profile", comment: "Sidebar menu label for Profile view."), img: "user")
            }
            .accessibilityIdentifier(AppAccessibilityIdentifiers.side_menu_profile_button.rawValue)

            NavigationLink(value: Route.Wallet(wallet: damus_state.wallet)) {
                navLabel(title: NSLocalizedString("Wallet", comment: "Sidebar menu label for Wallet view."), img: "wallet")
            }

            if damus_state.purple.enable_purple {
                NavigationLink(destination: DamusPurpleView(damus_state: damus_state)) {
                    HStack(spacing: 23) {
                        Image("nostr-hashtag")
                        Text("Purple")
                            .foregroundColor(DamusColors.purple)
                            .font(.title2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            NavigationLink(value: Route.MuteList) {
                navLabel(title: NSLocalizedString("Muted", comment: "Sidebar menu label for muted users view."), img: "mute")
            }

            NavigationLink(value: Route.RelayConfig) {
                navLabel(title: NSLocalizedString("Relays", comment: "Sidebar menu label for Relays view."), img: "world-relays")
            }

            NavigationLink(value: Route.Bookmarks) {
                navLabel(title: NSLocalizedString("Bookmarks", comment: "Sidebar menu label for Bookmarks view."), img: "bookmark")
            }

            Link(destination: URL(string: "https://store.damus.io/?ref=damus_ios_app")!) {
                navLabel(title: NSLocalizedString("Merch", comment: "Sidebar menu label for merch store link."), img: "shop")
            }

            NavigationLink(value: Route.Config) {
                navLabel(title: NSLocalizedString("Settings", comment: "Sidebar menu label for accessing the app settings"), img: "settings")
            }
            
            Button(action: {
                if damus_state.keypair.privkey == nil {
                    logout(damus_state)
                } else {
                    confirm_logout = true
                }
            }, label: {
                navLabel(title: NSLocalizedString("Logout", comment: "Sidebar menu label to sign out of the account."), img: "logout")
            })
            .accessibilityIdentifier(AppAccessibilityIdentifiers.side_menu_logout_button.rawValue)
        }
    }

    var TopProfile: some View {
        var name: String? = nil
        var display_name: String? = nil

        do {
            let profile_txn = damus_state.ndb.lookup_profile(damus_state.pubkey, txn_name: "top_profile")
            let profile = profile_txn?.unsafeUnownedValue?.profile
            name = profile?.name
            display_name = profile?.display_name
        }

        return VStack(alignment: .leading) {
            HStack(spacing: 10) {
                
                ProfilePicView(pubkey: damus_state.pubkey, size: 50, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)
                
                Spacer()
                
                Button(action: {
                    present_sheet(.user_status)
                    isSidebarVisible = false
                }, label: {
                    Image("add-reaction")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(5)
                        .foregroundColor(DamusColors.adaptableBlack)
                        .background {
                            Circle()
                                .foregroundColor(DamusColors.neutral3)
                        }
                })
                
                Button(action: {
                    showQRCode.toggle()
                    isSidebarVisible = false
                }, label: {
                    Image("qr-code")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(5)
                        .foregroundColor(DamusColors.adaptableBlack)
                        .background {
                            Circle()
                                .foregroundColor(DamusColors.neutral3)
                        }
                }).damus_full_screen_cover($showQRCode, damus_state: damus_state) {
                    QRCodeView(damus_state: damus_state, pubkey: damus_state.pubkey)
                }
            }
            
            VStack(alignment: .leading) {
                
                if let display_name {
                    Text(display_name)
                        .font(.title2.weight(.bold))
                        .foregroundColor(DamusColors.adaptableBlack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dynamicTypeSize(.xSmall)
                        .lineLimit(1)
                }
                if let name {
                    if !name.isEmpty {
                        Text(verbatim: "@" + name)
                            .foregroundColor(DamusColors.mediumGrey)
                            .font(.body)
                            .lineLimit(1)
                    }
                }
                
                PubkeyView(pubkey: damus_state.pubkey, sidemenu: true)
                    .pubkey_context_menu(pubkey: damus_state.pubkey)
                    .simultaneousGesture(TapGesture().onEnded{
                        isSidebarVisible = true
                    })
            }
        }
    }

    var MainSidemenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            let followers = FollowersModel(damus_state: damus_state, target: damus_state.pubkey)
            let profile_model = ProfileModel(pubkey: damus_state.pubkey, damus: damus_state)

            NavigationLink(value: Route.Profile(profile: profile_model, followers: followers), label: {
                TopProfile
                    .padding(.bottom, verticalSpacing)
            })
            .simultaneousGesture(TapGesture().onEnded {
                isSidebarVisible = false
            })

            ScrollView {
                SidemenuItems(profile_model: profile_model, followers: followers)
                    .simultaneousGesture(TapGesture().onEnded {
                        isSidebarVisible = false
                    })
            }
            .scrollIndicators(.hidden)
        }
    }

    var content: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .top) {
                DamusColors.adaptableWhite
                    .ignoresSafeArea()

                MainSidemenu
                    .padding([.leading, .trailing], padding)
            }
            .frame(width: sideBarWidth)
            .offset(x: isSidebarVisible ? 0 : -(sideBarWidth + padding))
            .animation(.default, value: isSidebarVisible)
            .alert("Logout", isPresented: $confirm_logout) {
                Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                    confirm_logout = false
                }
                Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                    logout(damus_state)
                }
                .accessibilityIdentifier(AppAccessibilityIdentifiers.side_menu_logout_confirm_button.rawValue)
            } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
            }

            Spacer()
        }
    }

    func navLabel(title: String, img: String) -> some View {
        HStack(spacing: 20) {
            Image(img)
                .tint(DamusColors.adaptableBlack)
            
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(DamusColors.adaptableBlack)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(.xSmall)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

struct Previews_SideMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        SideMenuView(damus_state: ds, isSidebarVisible: .constant(true), selected: .constant(.home))
    }
}
