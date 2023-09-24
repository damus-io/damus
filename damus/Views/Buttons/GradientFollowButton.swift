//
//  GradientFollowButton.swift
//  damus
//
//  Created by klabo on 7/18/23.
//

import SwiftUI

struct GradientFollowButton: View {

    let target: FollowTarget
    let follows_you: Bool

    @State var follow_state: FollowState

    private let grayTextColor = Color(#colorLiteral(red: 0.1450980392, green: 0.1607843137, blue: 0.1764705882, alpha: 1))
    private let grayBorder = Color(#colorLiteral(red: 0.8666666667, green: 0.8823529412, blue: 0.8901960784, alpha: 1))

    var body: some View {

        Button(action: {
            follow_state = perform_follow_btn_action(follow_state, target: target)
        }) {
            Text(follow_btn_txt(follow_state, follows_you: follows_you))
                    .foregroundColor(follow_state == .unfollows ? .white : grayTextColor)
                    .font(.callout)
                    .fontWeight(.medium)
                    .padding([.top, .bottom], 10)
                    .padding([.leading, .trailing], 12)
                    .background(follow_state == .unfollows ? PinkGradient : GrayGradient)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(grayBorder, lineWidth: follow_state == .unfollows ? 0 : 1)
                    )
        }
        .onReceive(handle_notify(.followed)) { ref in
            guard target.follow_ref == ref else { return }
            self.follow_state = .follows
        }
        .onReceive(handle_notify(.unfollowed)) { ref in
            guard target.follow_ref == ref else { return }
            self.follow_state = .unfollows
        }
    }
}

struct GradientFollowButtonPreviews: View {
    let target: FollowTarget = .pubkey(.empty)
    var body: some View {
        VStack {
            Text(verbatim: "Unfollows")
            GradientFollowButton(target: target, follows_you: false, follow_state: .unfollows)

            Text(verbatim: "Following")
            GradientFollowButton(target: target, follows_you: false, follow_state: .following)

            Text(verbatim: "Follows")
            GradientFollowButton(target: target, follows_you: false, follow_state: .follows)

            Text(verbatim: "Follows")
            GradientFollowButton(target: target, follows_you: true, follow_state: .follows)

            Text(verbatim: "Unfollowing")
            GradientFollowButton(target: target, follows_you: false, follow_state: .unfollowing)
        }
    }
}

struct GradientButton_Previews: PreviewProvider {
    static var previews: some View {
        GradientFollowButtonPreviews()
    }
}
