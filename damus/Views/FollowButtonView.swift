//
//  FollowButtonView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowButtonView: View {
    let target: FollowTarget
    @State var follow_state: FollowState
    
    var body: some View {
        Button {
            follow_state = perform_follow_btn_action(follow_state, target: target)
        } label: {
            Text(follow_btn_txt(follow_state))
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .font(.caption.weight(.bold))
                .foregroundColor(follow_state == .unfollows ? .white : .black)
                .background(follow_state == .unfollows ?  .black : .white)
                .cornerRadius(20)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(follow_state == .unfollows ? .white : .gray, lineWidth: 1)
                }
        }
        .onReceive(handle_notify(.followed)) { notif in
            let pk = notif.object as! String
            if pk != target.pubkey {
                return
            }
            
            self.follow_state = .follows
        }
        .onReceive(handle_notify(.unfollowed)) { notif in
            let pk = notif.object as! String
            if pk != target.pubkey {
                return
            }
            
            self.follow_state = .unfollows
        }
    }
}

struct FollowButtonPreviews: View {
    let target: FollowTarget = .pubkey("")
    var body: some View {
        VStack {
            Text("Unfollows")
            FollowButtonView(target: target, follow_state: .unfollows)
            
            Text("Following")
            FollowButtonView(target: target, follow_state: .following)
            
            Text("Follows")
            FollowButtonView(target: target, follow_state: .follows)
            
            Text("Unfollowing")
            FollowButtonView(target: target, follow_state: .unfollowing)
        }
    }
}

struct FollowButtonView_Previews: PreviewProvider {
    static var previews: some View {
        FollowButtonPreviews()
    }
}

func perform_follow_btn_action(_ fs: FollowState, target: FollowTarget) -> FollowState {
    switch fs {
    case .follows:
        notify(.unfollow, target)
        return .following
    case .following:
        return .following
    case .unfollowing:
        return .following
    case .unfollows:
        notify(.follow, target)
        return .unfollowing
    }
}

