//
//  TrustedNetworkButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-21.
//

import SwiftUI

struct TrustedNetworkButton: View {
    @Binding var filter: FriendFilter

    @State private var shouldShowTip = false
    @State private var debounceTask: Task<Void, Never>?

    let tip = TrustedNetworkButtonTip()

    var MainButton: some View {
        Button(action: {
            switch self.filter {
            case .all:
                self.filter = .friends_of_friends
            case .friends_of_friends:
                self.filter = .all
            }
        }) {
            if filter == .friends_of_friends {
                LINEAR_GRADIENT
                    .mask(Image(systemName: "network.badge.shield.half.filled")
                        .resizable()
                    ).frame(width: 26, height: 26)
            } else {
                Image(systemName: "network.slash")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        Group {
            if shouldShowTip {
                MainButton
                    .popupTip(tip)
            } else {
                MainButton
            }
        }
        .onAppear {
            // There is a race condition where if components on the view are still rendering,
            // the tip popover is rendered incorrectly with text still animated in movement,
            // and in the wrong place or missing.
            // There is another race condition where if navigates between tabs too quickly,
            // it could inadvertently cause the popover tip to show in full screen, even though
            // the backing view has disappeared.
            // Adding a delay gives time for the view rendering to complete before showing the tip
            // and mitigates these race conditions.
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                shouldShowTip = true
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            shouldShowTip = false
        }
    }
}

struct TrustedNetworkButton_Previews: PreviewProvider {
    @State static var enabled: FriendFilter = .all
    
    static var previews: some View {
        TrustedNetworkButton(filter: $enabled)
    }
}
