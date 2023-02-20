//
//  FollowButtonView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowButtonView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    let target: FollowTarget
    let follows_you: Bool
    @State var follow_state: FollowState
    
    var body: some View {
        Button {
            follow_state = perform_follow_btn_action(follow_state, target: target)
        } label: {
            Text(follow_btn_txt(follow_state, follows_you: follows_you))
                .frame(width: 105, height: 30)
                //.padding(.vertical, 10)
                .font(.caption.weight(.bold))
                .foregroundColor(follow_state == .unfollows ? filledTextColor() : borderColor())
                .background(follow_state == .unfollows ?  fillColor() : emptyColor())
                .cornerRadius(20)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(follow_state == .unfollows ? .clear : borderColor(), lineWidth: 1)
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
    
    func filledTextColor() -> Color {
        colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
    }
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    func emptyColor() -> Color {
        Color.black.opacity(0)
    }
    
    func borderColor() -> Color {
        colorScheme == .light ? Color("DamusDarkGrey") : Color("DamusLightGrey")
    }
}

struct FollowButtonPreviews: View {
    let target: FollowTarget = .pubkey("")
    var body: some View {
        VStack {
            Text(verbatim: "Unfollows")
            FollowButtonView(target: target, follows_you: false, follow_state: .unfollows)
            
            Text(verbatim: "Following")
            FollowButtonView(target: target, follows_you: false, follow_state: .following)
           
            Text(verbatim: "Follows")
            FollowButtonView(target: target, follows_you: false, follow_state: .follows)
            
            Text(verbatim: "Follows")
            FollowButtonView(target: target, follows_you: true, follow_state: .follows)
            
            Text(verbatim: "Unfollowing")
            FollowButtonView(target: target, follows_you: false, follow_state: .unfollowing)
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

