//
//  FriendsButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-21.
//

import SwiftUI

struct FriendsButton: View {
    @Binding var filter: FriendFilter
    
    var body: some View {
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
                    .mask(Image("user-added")
                        .resizable()
                    ).frame(width: 28, height: 28)
            } else {
                Image("user-added")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FriendsButton_Previews: PreviewProvider {
    @State static var enabled: FriendFilter = .all
    
    static var previews: some View {
        FriendsButton(filter: $enabled)
    }
}
