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
                self.filter = .friends
            case .friends:
                self.filter = .all
            }
        }) {
            if filter == .friends {
                LINEAR_GRADIENT
                    .mask(Image(systemName: "person.2.fill")
                        .resizable()
                    ).frame(width: 30, height: 20)
            } else {
                Image(systemName: "person.2.fill")
                    .resizable()
                    .frame(width: 30, height: 20)
                    .foregroundColor(DamusColors.adaptableGrey)
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
