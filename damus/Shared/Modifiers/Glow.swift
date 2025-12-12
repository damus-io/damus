//
//  Glow.swift
//  damus
//
//  Created by eric on 7/26/25.
//

import SwiftUI

struct Glow: ViewModifier {
    @State private var effect = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: reduceMotion ? 10 : (effect ? 15 : 5))
                .animation(reduceMotion ? .none : .easeOut(duration: 0.5).repeatForever(), value: effect)
                .onAppear {
                    if !reduceMotion {
                        effect.toggle()
                    }
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
