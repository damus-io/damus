//
//  UserView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct UserViewRow: View {
    let damus_state: DamusState
    let pubkey: String
    
    @State var navigating: Bool = false
    
    var body: some View {
        let dest = ProfileView(damus_state: damus_state, pubkey: pubkey)
        
        UserView(damus_state: damus_state, pubkey: pubkey)
            .contentShape(Rectangle())
            .background(
                NavigationLink(destination: dest, isActive: $navigating) {
                    EmptyView()
                }
            )
            .onTapGesture {
                navigating = true
            }
    }
}

struct UserView: View {
    let damus_state: DamusState
    let pubkey: String
    
    var body: some View {
        
        VStack {
            HStack {
                ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
            
                VStack(alignment: .leading) {
                    let profile = damus_state.profiles.lookup(id: pubkey)
                    ProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_nip5_domain: false)
                    if let about = profile?.about {
                        let blocks = parse_mentions(content: about, tags: [])
                        let about_string = render_blocks(blocks: blocks, profiles: damus_state.profiles).content.attributed
                        Text(about_string)
                            .lineLimit(3)
                            .font(.footnote)
                    }
                }
                
                Spacer()
            }
        }
    }
}

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        UserView(damus_state: test_damus_state(), pubkey: "pk")
    }
}
