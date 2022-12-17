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
        Text("+")
            .font(.system(.largeTitle))
            .frame(width: 57, height: 50)
            .foregroundColor(Color.white)
            .padding(.bottom, 7)
    })
    .background(Color.blue)
    .cornerRadius(38.5)
    .padding(.bottom)
    .shadow(color: Color.black.opacity(0.3),
            radius: 3,
            x: 3,
            y: 3)
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
    
