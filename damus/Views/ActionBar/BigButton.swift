//
//  BigButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-19.
//

import SwiftUI

struct BigButton: View {
    let text: String
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme
    
    init(_ text: String, action: @escaping () -> ()) {
        self.text = text
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            Text(text)
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .center)
                .foregroundColor(colorScheme == .light ? DamusColors.black : DamusColors.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(colorScheme == .light ? DamusColors.black : DamusColors.white, lineWidth: 2)
                }
                .padding(EdgeInsets(top: 10, leading: 50, bottom: 25, trailing: 50))
        }
    }
}

struct BigButton_Previews: PreviewProvider {
    static var previews: some View {
        BigButton("Cancel", action: {})
    }
}
