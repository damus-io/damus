//
//  FollowsYou.swift
//  damus
//
//  Created by William Casarin on 2023-02-07.
//

import SwiftUI

struct FollowsYou: View {
    
    var body: some View {
        Text("Follows you", comment: "Text to indicate that a user is following your profile.")
            .padding([.leading, .trailing], 6.0)
            .padding([.top, .bottom], 2.0)
            .foregroundColor(.gray)
            .background {
                RoundedRectangle(cornerRadius: 5.0)
                    .foregroundColor(DamusColors.adaptableGrey)
            }
            .font(.footnote)
    }
}

struct FollowsYou_Previews: PreviewProvider {
    static var previews: some View {
        FollowsYou()
    }
}
