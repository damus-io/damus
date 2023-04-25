//
//  ShareActionButton.swift
//  damus
//
//  Created by William Casarin on 2023-04-19.
//

import SwiftUI

struct ShareActionButton: View {
    let img: String
    let text: String
    let color: Color?
    let action: () -> ()
    
    init(img: String, text: String, col: Color?, action: @escaping () -> ()) {
        self.img = img
        self.text = text
        self.color = col
        self.action = action
    }
    
    init(img: String, text: String, action: @escaping () -> ()) {
        self.img = img
        self.text = text
        self.action = action
        self.color = nil
    }
    
    var col: Color {
        colorScheme == .light ? DamusColors.mediumGrey : DamusColors.white
    }
    
    @Environment(\.colorScheme) var colorScheme
        
    var body: some View {
        Button(action: action) {
            VStack() {
                Image(systemName: img)
                    .foregroundColor(col)
                    .font(.system(size: 23, weight: .bold))
                    .overlay {
                        Circle()
                            .stroke(col, lineWidth: 1)
                            .frame(width: 55.0, height: 55.0)
                    }
                    .frame(height: 25)
                Text(verbatim: text)
                    .foregroundColor(col)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
        }
    }
}

struct ShareActionButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareActionButton(img: "figure.flexibility", text: "Stretch", action: {})
    }
}
