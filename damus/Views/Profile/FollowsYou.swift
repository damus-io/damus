//
//  FollowsYou.swift
//  damus
//
//  Created by William Casarin on 2023-02-07.
//

import SwiftUI

struct FollowsYou: View {
    @Environment(\.colorScheme) var colorScheme

    var fill_color: Color {
        colorScheme == .light ? Color("DamusLightGrey") : Color("DamusDarkGrey")
    }
    
    var body: some View {
        Text("Follows you")
            .padding([.leading, .trailing], 6.0)
            .padding([.top, .bottom], 2.0)
            .foregroundColor(.gray)
            .background {
                RoundedRectangle(cornerRadius: 5.0)
                    .foregroundColor(fill_color)
            }
            .font(.footnote)
    }
}

struct FollowsYou_Previews: PreviewProvider {
    static var previews: some View {
        FollowsYou()
    }
}
