//
//  PostButton.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

let BUTTON_SIZE: CGFloat = 60
let LINEAR_GRADIENT = LinearGradient(gradient: Gradient(colors: [
    Color("DamusPurple"),
    Color("DamusBlue")
]), startPoint: .topTrailing, endPoint: .bottomTrailing)

func PostButton(action: @escaping () -> ()) -> some View {

    return Button(action: action, label: {
        ZStack(alignment: .center) {
            Circle()
                .stroke(LINEAR_GRADIENT, lineWidth: 2)
                .frame(width: BUTTON_SIZE, height: BUTTON_SIZE)
                .rotationEffect(.degrees(45))
                 
            Circle()
                .fill(LINEAR_GRADIENT)
                .frame(width: BUTTON_SIZE - 8, height: BUTTON_SIZE - 8)
                .rotationEffect(.degrees(45))

            Text("+")
                .font(.system(.largeTitle))
                .foregroundColor(Color.white)
                .padding(.bottom, 7)
                .frame(width: BUTTON_SIZE, height: BUTTON_SIZE)
        }
    })
    .padding()
    .shadow(color: Color.black.opacity(0.3),
            radius: 3,
            x: 3,
            y: 3)
    .keyboardShortcut("n", modifiers: [.command, .shift])
}

func PostButtonContainer(action: @escaping () -> ()) -> some View {
    return VStack {
        Spacer()

        HStack {
            Spacer()
            PostButton(action: action)
        }
    }
}
