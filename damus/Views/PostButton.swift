//
//  PostButton.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

let BUTTON_SIZE = 57.0
let LINEAR_GRADIENT = LinearGradient(gradient: Gradient(colors: [
    Color("DamusPurple"),
    Color("DamusBlue")
]), startPoint: .topTrailing, endPoint: .bottomTrailing)

func PostButton(action: @escaping () -> ()) -> some View {
    return Button(action: action, label: {
        ZStack(alignment: .center) {
            Circle()
                .fill(LINEAR_GRADIENT)
                .frame(width: BUTTON_SIZE, height: BUTTON_SIZE, alignment: .center)
                .rotationEffect(.degrees(20))
                .padding()
                .shadow(color: Color.black.opacity(0.3),
                        radius: 3,
                        x: 3,
                        y: 3)
            Image(systemName: "plus")
                .font(.system(.title2))
                .foregroundColor(Color.white)
        }
    })
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
    
