//
//  FriendsButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-21.
//

import SwiftUI

struct FriendsButton: View {
    @Binding var enabled: Bool
    
    var body: some View {
        Button(action: {
            self.enabled.toggle()
        }) {
            if enabled {
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
    @State static var enabled: Bool = false
    
    static var previews: some View {
        FriendsButton(enabled: $enabled)
    }
}
