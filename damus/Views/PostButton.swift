//
//  PostButton.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

func PostButton(action: @escaping () -> ()) -> some View {
    return Button(action: action) {
        Label {
            Text("+")
        } icon: {
            Image("ic-add")
            .contentShape(Circle())
            .frame(width: 60, height: 60)
        }
        .labelStyle(IconOnlyLabelStyle())
    }
    //.padding()
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
