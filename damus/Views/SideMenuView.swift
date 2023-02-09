//
//  SideMenuView.swift
//  damus
//
//  Created by Ben Weeks on 1/6/23.
//  Ref: https://blog.logrocket.com/create-custom-collapsible-sidebar-swiftui/

import SwiftUI

struct SideMenuView: View {
    let damus_state: DamusState
    @Binding var isSidebarVisible: Bool
    @State var confirm_logout: Bool = false
    
    @State private var showQRCode = false
    
    @Environment(\.colorScheme) var colorScheme
    
    var sideBarWidth = min(UIScreen.main.bounds.size.width * 0.65, 400.0)
    let verticalSpacing: CGFloat = 20
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
    }
    
    func textColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    var body: some View {
        ZStack {
            GeometryReader { _ in
                EmptyView()
            }
            .background(Color("DamusDarkGrey").opacity(0.6))
            .opacity(isSidebarVisible ? 1 : 0)
            .animation(.default, value: isSidebarVisible)
            .onTapGesture {
                isSidebarVisible.toggle()
            }
            content
        }
    }
    
    var content: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .top) {
                fillColor()
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 0) {
                    
                    VStack(alignment: .leading, spacing: 0) {
                        let profile = damus_state.profiles.lookup(id: damus_state.pubkey)
                        let followers = FollowersModel(damus_state: damus_state, target: damus_state.pubkey)
                        let profile_model = ProfileModel(pubkey: damus_state.pubkey, damus: damus_state)
                        
                        NavigationLink(destination: ProfileView(damus_state: damus_state, profile: profile_model, followers: followers)) {
                            
                            HStack {
                                ProfilePicView(pubkey: damus_state.pubkey, size: 60, highlight: .none, profiles: damus_state.profiles)
                                
                                VStack(alignment: .leading) {
                                    if let display_name = profile?.display_name {
                                        Text(display_name)
                                            .foregroundColor(textColor())
                                            .font(.title)
                                            .lineLimit(1)
                                    }
                                    if let name = profile?.name {
                                        Text("@" + name)
                                            .foregroundColor(Color("DamusMediumGrey"))
                                            .font(.body)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.bottom, verticalSpacing)
                        }
                        
                        Divider()
                        
                        ScrollView {
                            VStack(spacing: verticalSpacing) {
                                NavigationLink(destination: ProfileView(damus_state: damus_state, profile: profile_model, followers: followers)) {
                                    navLabel(title: NSLocalizedString("Profile", comment: "Sidebar menu label for Profile view."), systemImage: "person")
                                }
                                
                                /*
                                NavigationLink(destination: EmptyView()) {
                                    navLabel(title: NSLocalizedString("Wallet", comment: "Sidebar menu label for Wallet view."), systemImage: "bolt")
                                }
                                */
                                 
                                NavigationLink(destination: MutelistView(damus_state: damus_state, users: get_mutelist_users(damus_state.contacts.mutelist) )) {
                                    navLabel(title: NSLocalizedString("Blocked", comment: "Sidebar menu label for Profile view."), systemImage: "exclamationmark.octagon")
                                }
                                
                                NavigationLink(destination: RelayConfigView(state: damus_state)) {
                                    navLabel(title: NSLocalizedString("Relays", comment: "Sidebar menu label for Relays view."), systemImage: "network")
                                }
                                
                                NavigationLink(destination: ConfigView(state: damus_state)) {
                                    navLabel(title: NSLocalizedString("Settings", comment: "Sidebar menu label for accessing the app settings"), systemImage: "gear")
                                }
                            }
                            .padding([.top, .bottom], verticalSpacing)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isSidebarVisible = false
                    })
                    
                    Divider()
                    
                    HStack() {
                        Button(action: {
                            //ConfigView(state: damus_state)
                            if damus_state.keypair.privkey == nil {
                                notify(.logout, ())
                            } else {
                                confirm_logout = true
                            }
                        }, label: {
                            Label(NSLocalizedString("Sign out", comment: "Sidebar menu label to sign out of the account."), systemImage: "pip.exit")
                                .font(.title3)
                                .foregroundColor(textColor())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        })
                        
                        Spacer()
                        
                        Button(action: {
                            showQRCode.toggle()
                        }, label: {
                            Label(NSLocalizedString("", comment: "Sidebar menu label for accessing QRCode view"), systemImage: "qrcode")
                                .font(.title)
                                .foregroundColor(textColor())
                        }).fullScreenCover(isPresented: $showQRCode) {
                            QRCodeView(damus_state: damus_state)
                        }
                    }
                    .padding(.top, verticalSpacing)
                }
                .padding(.top, -15)
                .padding([.leading, .trailing, .bottom], 30)
            }
            .frame(width: sideBarWidth)
            .offset(x: isSidebarVisible ? 0 : -sideBarWidth)
            .animation(.default, value: isSidebarVisible)
            .alert("Logout", isPresented: $confirm_logout) {
                Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                    confirm_logout = false
                }
                Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                    notify(.logout, ())
                }
            } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
            }

            Spacer()
        }
    }
    
    
    @ViewBuilder
    func navLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2)
            .foregroundColor(textColor())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Previews_SideMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        SideMenuView(damus_state: ds, isSidebarVisible: .constant(true))
    }
}
