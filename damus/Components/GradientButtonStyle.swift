//
//  GradientButtonStyle.swift
//  damus
//
//  Created by eric on 5/20/23.
//

import SwiftUI

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .padding()
            .foregroundColor(Color.white)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(PinkGradient.gradient)
            }
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
    }
}


struct GradientButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Button("Dynamic Size", action: {
                print("dynamic size")
            })
            .buttonStyle(GradientButtonStyle())
            
            
            Button(action: {
                print("infinite width")
            }) {
                HStack {
                    Text("Infinite Width")
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding()
        }
    }
}
