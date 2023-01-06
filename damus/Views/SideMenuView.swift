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
    @StateObject var user_settings = UserSettingsStore()
    
    @Environment(\.colorScheme) var colorScheme
    
    var sideBarWidth = UIScreen.main.bounds.size.width * 0.7
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
    }
    
    func textColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    var body: some View {
        if isSidebarVisible {
            ZStack {
                GeometryReader { _ in
                    EmptyView()
                }
                .background(.gray.opacity(0.6))
                .opacity(isSidebarVisible ? 1 : 0)
                .animation(.easeInOut.delay(0.2), value: isSidebarVisible)
                .onTapGesture {
                    isSidebarVisible.toggle()
                }
                content
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
    
    var content: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .top) {
                fillColor()

                VStack(alignment: .leading, spacing: 20) {
                    let profile = damus_state.profiles.lookup(id: damus_state.pubkey)
                    
                    if let picture = damus_state.profiles.lookup(id: damus_state.pubkey)?.picture {
                        ProfilePicView(pubkey: damus_state.pubkey, size: 60, highlight: .none, profiles: damus_state.profiles, picture: picture)
                    } else {
                        Image(systemName: "person.fill")
                    }
                    VStack(alignment: .leading) {
                        if let display_name = profile?.display_name {
                            Text(display_name)
                                .foregroundColor(textColor())
                                .font(.title)
                        }
                        if let name = profile?.name {
                            Text("@" + name)
                                .foregroundColor(Color("DamusMediumGrey"))
                                .font(.body)
                        }
                    }
                    
                    Divider()
                    
                    //NavigationView {
                    let followers = FollowersModel(damus_state: damus_state, target: damus_state.pubkey)
                    let profile_model = ProfileModel(pubkey: damus_state.pubkey, damus: damus_state)
                        
                    NavigationLink(destination: ProfileView(damus_state: damus_state, profile: profile_model, followers: followers)
                    ) {
                        Label("Profile", systemImage: "person")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    NavigationLink(destination: EmptyView()) {
                        Label("Relays", systemImage: "gear")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    NavigationLink(destination: ConfigView(state: damus_state).environmentObject(user_settings)) {
                        Label("App Settings", systemImage: "xserve")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        //ConfigView(state: damus_state)
                        confirm_logout = true
                    }, label: {
                        Label("Sign out", systemImage: "pip.exit")
                            .font(.title3)
                            .foregroundColor(textColor())
                    })
                }
                .padding(.top, 50)
                .padding(.bottom, 50)
                .padding(.leading, 40)
            }
            .frame(width: sideBarWidth)
            .offset(x: isSidebarVisible ? 0 : -sideBarWidth)
            .animation(.default, value: isSidebarVisible)
            .alert("Logout", isPresented: $confirm_logout) {
                Button("Cancel") {
                    confirm_logout = false
                }
                Button("Logout") {
                    notify(.logout, ())
                }
            } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account")
            }

            Spacer()
        }
    }
}

struct Previews_SideMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        SideMenuView(damus_state: ds, isSidebarVisible: .constant(true))
    }
}
