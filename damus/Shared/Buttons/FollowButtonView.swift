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
    var isReadOnly: Bool = false
    @State private var showReadOnlyAlert: Bool = false

    var body: some View {
        Button {
            if isReadOnly {
                showReadOnlyAlert = true
            } else {
                follow_state = perform_follow_btn_action(follow_state, target: target)
            }
        } label: {
            Text(verbatim: "\(follow_btn_txt(follow_state, follows_you: follows_you))")
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
        .onReceive(handle_notify(.followed)) { follow in
            guard case .pubkey(let pk) = follow,
                  pk == target.pubkey else { return }

            self.follow_state = .follows
        }
        .onReceive(handle_notify(.unfollowed)) { unfollow in
            guard case .pubkey(let pk) = unfollow,
                  pk == target.pubkey else { return }

            self.follow_state = .unfollows
        }
        .alert(
            NSLocalizedString("Read-Only Account", comment: "Alert title when read-only user tries to follow"),
            isPresented: $showReadOnlyAlert
        ) {
            Button(NSLocalizedString("OK", comment: "Button to dismiss read-only alert")) {
                showReadOnlyAlert = false
            }
        } message: {
            Text("Log in with your private key (nsec) to follow users.", comment: "Alert message explaining that private key is needed to follow")
        }
    }
    
    func filledTextColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    func emptyColor() -> Color {
        Color.black.opacity(0)
    }
    
    func borderColor() -> Color {
        colorScheme == .light ? DamusColors.darkGrey : DamusColors.lightGrey
    }
}

struct FollowButtonPreviews: View {
    let target: FollowTarget = .pubkey(test_pubkey)
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
        notify(.unfollow(target))
        return .following
    case .following:
        return .following
    case .unfollowing:
        return .following
    case .unfollows:
        notify(.follow(target))
        return .unfollowing
    }
}

