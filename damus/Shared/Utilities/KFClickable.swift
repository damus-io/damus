//
//  ClickableOverlay.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-09-20.
//

import SwiftUI

/// Applies a property that makes `KFAnimatedImage` clickable again on iOS 18+
fileprivate struct KFClickable: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
    }
}

extension View {
    /// Applies a property that makes `KFAnimatedImage` clickable again on iOS 18+
    func kfClickable() -> some View {
        return self.modifier(KFClickable())
    }
}
