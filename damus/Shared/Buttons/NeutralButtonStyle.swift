//
//  NeutralButtonStyle.swift
//  damus
//
//  Created by eric on 9/1/23.
//

import SwiftUI

enum NeutralButtonShape {
    case rounded, capsule, circle

    var style: NeutralButtonStyle {
        switch self {
        case .rounded:
            return NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 12)
        case .capsule:
            return NeutralButtonStyle(padding: EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15), cornerRadius: 20)
        case .circle:
            return NeutralButtonStyle(padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20), cornerRadius: 9999)
        }
    }
}

struct NeutralButtonStyle: ButtonStyle {
    let padding: EdgeInsets
    let cornerRadius: CGFloat
    let scaleEffect: CGFloat
    
    init(padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0), cornerRadius: CGFloat = 15, scaleEffect: CGFloat = 0.95) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.scaleEffect = scaleEffect
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(padding)
            .background(DamusColors.neutral1)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? scaleEffect : 1)
    }
}

struct NeutralButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            
            Button(action: {
                print("dynamic size")
            }) {
                Text(verbatim: "Dynamic Size")
                    .padding()
            }
            .buttonStyle(NeutralButtonStyle())
            
            Button(action: {
                print("infinite width")
            }) {
                HStack {
                    Text(verbatim: "Infinite Width")
                        .padding()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(NeutralButtonStyle())
            .padding()
            
            Button(String(stringLiteral: "Rounded Button"), action: {})
                .buttonStyle(NeutralButtonShape.rounded.style)
                .padding()

            Button(String(stringLiteral: "Capsule Button"), action: {})
                .buttonStyle(NeutralButtonShape.capsule.style)
                .padding()

            Button(action: {}, label: {Image("messages")})
                .buttonStyle(NeutralButtonShape.circle.style)
        }
    }
}
