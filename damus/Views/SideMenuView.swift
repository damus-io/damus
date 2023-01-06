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

    var sideBarWidth = UIScreen.main.bounds.size.width * 0.7
    var bgColor: Color =
          Color(.init(
                  red: 52 / 255,
                  green: 70 / 255,
                  blue: 182 / 255,
                  alpha: 1))
    
    var body: some View {
        if isSidebarVisible {
            ZStack {
                GeometryReader { _ in
                    EmptyView()
                }
                .background(.black.opacity(0.6))
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
                Color("DamusBlack")

                VStack(alignment: .leading, spacing: 20) {
                    let profile = damus_state.profiles.lookup(id: damus_state.pubkey)
                    
                    if let picture = damus_state.profiles.lookup(id: damus_state.pubkey)?.picture {
                        ProfilePicView(pubkey: damus_state.pubkey, size: 60, highlight: .none, profiles: damus_state.profiles, picture: picture)
                    } else {
                        Image(systemName: "person.fill")
                    }
                    if let display_name = profile?.display_name {
                        VStack(alignment: .leading) {
                            Text(display_name)
                                .foregroundColor(Color("DamusWhite"))
                                .font(.headline)
                            ProfileName(pubkey: damus_state.pubkey, profile: profile, prefix: "@", damus: damus_state, show_friend_confirmed: false)
                                .font(.callout)
                                .foregroundColor(.gray)
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
                    
                    NavigationLink(destination: ConfigView(state: damus_state)) {
                        Label("App Settings", systemImage: "xserve")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        //ConfigView(state: damus_state)
                        notify(.logout, ())
                    }, label: {
                        Label("Sign out", systemImage: "exit")
                            .font(.title3)
                            .foregroundColor(Color("DamusWhite"))
                    })
                }
                .padding(.top, 50)
                .padding(.bottom, 50)
                .padding(.horizontal, 20)
            }
            .frame(width: sideBarWidth)
            .offset(x: isSidebarVisible ? 0 : -sideBarWidth)
            .animation(.default, value: isSidebarVisible)

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
