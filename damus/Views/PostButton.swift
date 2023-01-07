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
        Image(systemName: "plus")
            .font(.system(.title2))
            .foregroundColor(Color.white)
            .frame(width: BUTTON_SIZE, height: BUTTON_SIZE, alignment: .center)
            .background(LINEAR_GRADIENT)
            .cornerRadius(38.5)
            .padding()
            .shadow(color: Color.black.opacity(0.3),
                    radius: 3,
                    x: 3,
                    y: 3)
    })
    .keyboardShortcut("n", modifiers: [.command, .shift])
}

func PostButtonContainer(action: @escaping () -> Void) -> some View {
    // if left_handed is true, put the post button on the left side
    @StateObject var user_settings = UserSettingsStore()  // initialize user_settings
    let is_left_handed = user_settings.left_handed.self
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
