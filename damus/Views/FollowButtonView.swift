//
//  FollowButtonView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowButtonView: View {
    let pubkey: String
    @State var follow_state: FollowState
    
    var body: some View {
        Button("\(follow_btn_txt(follow_state))") {
            follow_state = perform_follow_btn_action(follow_state, target: pubkey)
        }
        .buttonStyle(.bordered)
        .onReceive(handle_notify(.followed)) { notif in
            let pk = notif.object as! String
            if pk != pubkey {
                return
            }
            
            self.follow_state = .follows
        }
        .onReceive(handle_notify(.unfollowed)) { notif in
            let pk = notif.object as! String
            if pk != pubkey {
                return
            }
            
            self.follow_state = .unfollows
        }
    }
}

    /*
struct FollowButtonView_Previews: PreviewProvider {
    static var previews: some View {
        FollowButtonView()
    }
}
     */
