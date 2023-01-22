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
    @State var follow_state: FollowState
    
    var body: some View {
        Button {
            follow_state = perform_follow_btn_action(follow_state, target: target)
        } label: {
            Text(follow_btn_txt(follow_state))
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
            Text("Unfollows", comment: "Text to indicate that the button next to it is in a state that will unfollow a profile when tapped.")
            FollowButtonView(target: target, follow_state: .unfollows)
            
            Text("Following", comment: "Text to indicate that the button next to it is in a state that indicates that it is in the process of following a profile.")
            FollowButtonView(target: target, follow_state: .following)
            
            Text("Follows", comment: "Text to indicate that button next to it is in a state that will follow a profile when tapped.")
            FollowButtonView(target: target, follow_state: .follows)
            
            Text("Unfollowing", comment: "Text to indicate that the button next to it is in  a state that indicates that it is in the process of unfollowing a profile.")
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

