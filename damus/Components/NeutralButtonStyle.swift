//
//  NeutralButtonStyle.swift
//  damus
//
//  Created by eric on 9/1/23.
//

import SwiftUI

struct NeutralButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .background(DamusColors.neutral1)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct NeutralCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .padding(20)
            .background(DamusColors.neutral1)
            .cornerRadius(9999)
            .overlay(
                RoundedRectangle(cornerRadius: 9999)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
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
        }
    }
}
