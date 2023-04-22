//
//  FriendIcon.swift
//  damus
//
//  Created by William Casarin on 2023-04-20.
//

import SwiftUI

struct FriendIcon: View {
    let friend: FriendType
    
    var body: some View {
        Group {
            switch friend {
            case .friend:
                LINEAR_GRADIENT
                    .mask(Image(systemName: "person.fill.checkmark")
                        .resizable()
                    ).frame(width: 20, height: 14)
            case .fof:
                Image(systemName: "person.fill.and.arrow.left.and.arrow.right")
                    .resizable()
                    .frame(width: 21, height: 14)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct FriendIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FriendIcon(friend: .friend)
            
            FriendIcon(friend: .fof)
        }
    }
}
