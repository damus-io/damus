//
//  GradientButtonStyle.swift
//  damus
//
//  Created by eric on 5/20/23.
//

import SwiftUI

struct GradientButtonStyle: ButtonStyle {
    let padding: CGFloat

    init(padding: CGFloat = 16.0) {
        self.padding = padding
    }

    func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .padding(padding)
            .foregroundColor(Color.white)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(PinkGradient)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}


struct GradientButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Button(action: {
                print("dynamic size")
            }) {
                Text(verbatim: "Dynamic Size")
            }
            .buttonStyle(GradientButtonStyle())
            
            
            Button(action: {
                print("infinite width")
            }) {
                HStack {
                    Text(verbatim: "Infinite Width")
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding()
        }
    }
}
