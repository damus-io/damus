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
    @State var confirm_logout: Bool = false
    @State private var showQRCode = false
    
    @Environment(\.colorScheme) var colorScheme

    var sideBarWidth = min(UIScreen.main.bounds.size.width * 0.65, 400.0)
    let verticalSpacing: CGFloat = 20
    let padding: CGFloat = 30

    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }

    func textColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }

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

            NavigationLink(value: Route.Wallet(wallet: damus_state.wallet)) {
                navLabel(title: NSLocalizedString("Wallet", comment: "Sidebar menu label for Wallet view."), img: "wallet")
            }

            if damus_state.settings.enable_experimental_purple_api {
                NavigationLink(destination: DamusPurpleView(purple: damus_state.purple, keypair: damus_state.keypair)) {
                    HStack(spacing: 13) {
                        Image("nostr-hashtag")
                        Text("Purple")
                            .foregroundColor(DamusColors.purple)
                            .font(.title2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            NavigationLink(value: Route.MuteList(users: get_mutelist_users(damus_state.contacts.mutelist))) {
                navLabel(title: NSLocalizedString("Muted", comment: "Sidebar menu label for muted users view."), img: "mute")
            }

            NavigationLink(value: Route.RelayConfig) {
                navLabel(title: NSLocalizedString("Relays", comment: "Sidebar menu label for Relays view."), img: "world-relays")
            }

            NavigationLink(value: Route.Bookmarks) {
                navLabel(title: NSLocalizedString("Bookmarks", comment: "Sidebar menu label for Bookmarks view."), img: "bookmark")
            }

            Link(destination: URL(string: "https://store.damus.io/?ref=damus_ios_app")!) {
                navLabel(title: NSLocalizedString("Merch", comment: "Sidebar menu label for merch store link."), img: "basket")
            }

            NavigationLink(value: Route.Config) {
                navLabel(title: NSLocalizedString("Settings", comment: "Sidebar menu label for accessing the app settings"), img: "settings")
            }
        }
    }

    var TopProfile: some View {
        let profile_txn = damus_state.profiles.lookup(id: damus_state.pubkey)
        let profile = profile_txn.unsafeUnownedValue
        return VStack(alignment: .leading, spacing: verticalSpacing) {
            HStack {
                ProfilePicView(pubkey: damus_state.pubkey, size: 60, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)

                VStack(alignment: .leading) {
                    if let display_name = profile?.display_name {
                        Text(display_name)
                            .foregroundColor(textColor())
                            .font(.title)
                            .lineLimit(1)
                    }
                    if let name = profile?.name {
                        Text("@" + name)
                            .foregroundColor(DamusColors.mediumGrey)
                            .font(.body)
                            .lineLimit(1)
                    }
                }
            }

            navLabel(title: NSLocalizedString("Set Status", comment: "Sidebar menu label to set user status"), img: "add-reaction")
                .font(.title2)
                .foregroundColor(textColor())
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(.xSmall)
                .onTapGesture {
                    present_sheet(.user_status)
                }

            UserStatusView(status: damus_state.profiles.profile_data(damus_state.pubkey).status, show_general: true, show_music: true)
                .dynamicTypeSize(.xSmall)
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

            Divider()

            ScrollView {
                SidemenuItems(profile_model: profile_model, followers: followers)
                    .labelStyle(SideMenuLabelStyle())
                    .padding([.top, .bottom], verticalSpacing)
            }
        }
    }

    var content: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .top) {
                fillColor()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    MainSidemenu
                    .simultaneousGesture(TapGesture().onEnded {
                        isSidebarVisible = false
                    })

                    Divider()

                    HStack() {
                        Button(action: {
                            //ConfigView(state: damus_state)
                            if damus_state.keypair.privkey == nil {
                                notify(.logout)
                            } else {
                                confirm_logout = true
                            }
                        }, label: {
                            Label(NSLocalizedString("Sign out", comment: "Sidebar menu label to sign out of the account."), image: "logout")
                                .font(.title3)
                                .foregroundColor(textColor())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .dynamicTypeSize(.xSmall)
                        })

                        Spacer()

                        Button(action: {
                            showQRCode.toggle()
                        }, label: {
                            Image("qr-code")
                                .font(.title)
                                .foregroundColor(textColor())
                                .dynamicTypeSize(.xSmall)
                        }).fullScreenCover(isPresented: $showQRCode) {
                            QRCodeView(damus_state: damus_state, pubkey: damus_state.pubkey)
                        }
                    }
                    .padding(.top, verticalSpacing)
                }
                .padding(.top, -(padding / 2.0))
                .padding([.leading, .trailing, .bottom], padding)
            }
            .frame(width: sideBarWidth)
            .offset(x: isSidebarVisible ? 0 : -(sideBarWidth + padding))
            .animation(.default, value: isSidebarVisible)
            .alert("Logout", isPresented: $confirm_logout) {
                Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                    confirm_logout = false
                }
                Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                    notify(.logout)
                }
            } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
            }

            Spacer()
        }
    }

    func navLabel(title: String, img: String) -> some View {
        HStack {
            Image(img)
                .tint(DamusColors.adaptableBlack)
            
            Text(title)
                .font(.title2)
                .foregroundColor(textColor())
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(.xSmall)
        }
    }

    struct SideMenuLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .center, spacing: 8) {
                configuration.icon
                    .frame(width: 24, height: 24)
                    .aspectRatio(contentMode: .fit)
                configuration.title
            }
        }
    }
}

struct Previews_SideMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        SideMenuView(damus_state: ds, isSidebarVisible: .constant(true))
    }
}
