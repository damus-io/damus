//
//  Glow.swift
//  damus
//
//  Created by eric on 7/26/25.
//

import SwiftUI

struct Glow: ViewModifier {
    @State private var effect = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: effect ? 15 : 5)
                .animation(.easeOut(duration: 0.5).repeatForever(), value: effect)
                .onAppear {
                    effect.toggle()
                }

            content
        }
    }
}

extension View {
    func glow() -> some View {
        modifier(Glow())
    }
}
