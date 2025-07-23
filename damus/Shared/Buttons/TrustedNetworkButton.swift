//
//  TrustedNetworkButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-21.
//

import SwiftUI

struct TrustedNetworkButton: View {
    @Binding var filter: FriendFilter
    var action: (@MainActor () -> Void)? = nil

    var MainButton: some View {
        Button(action: {
            switch self.filter {
            case .all:
                self.filter = .friends_of_friends
            case .friends_of_friends:
                self.filter = .all
            }

            if let action {
                action()
            }
        }) {
            if filter == .friends_of_friends {
                LINEAR_GRADIENT
                    .mask(Image(systemName: "network.badge.shield.half.filled")
                        .frame(width: 24, height: 24)
                    )
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "network.slash")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        MainButton
    }
}

struct TrustedNetworkButton_Previews: PreviewProvider {
    @State static var enabled: FriendFilter = .all

    static var previews: some View {
        TrustedNetworkButton(filter: $enabled)
    }
}
