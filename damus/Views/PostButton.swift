//
//  PostButton.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

func PostButton(action: @escaping () -> ()) -> some View {
    return Button(action: action, label: {
        Image(systemName: "plus")
            .font(.system(.title2))
            .foregroundColor(Color.white)
            .frame(width: 57, height: 57, alignment: .center)
            .background(Color.accentColor)
            .cornerRadius(38.5)
            .padding()
            .shadow(color: Color.black.opacity(0.3),
                    radius: 3,
                    x: 3,
                    y: 3)
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
    
