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
    DamusColors.purple,
    DamusColors.blue
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
            Image("plus")
                .font(.system(.title2))
                .foregroundColor(Color.white)
        }
    })
    .accessibilityLabel(NSLocalizedString("New Post", comment: "Accessibility label for new post button"))
    .accessibilityHint(NSLocalizedString("Double tap to compose a new note", comment: "Accessibility hint for new post button"))
    .keyboardShortcut("n", modifiers: [.command, .shift])
}

func PostButtonContainer(is_left_handed: Bool, action: @escaping () -> Void) -> some View {
    return VStack {
        Spacer()

        HStack {
            if is_left_handed != true {
                Spacer()
                
                PostButton(action: action)
            } else {
                PostButton(action: action)
                Spacer()
            }
        }
    }
}
