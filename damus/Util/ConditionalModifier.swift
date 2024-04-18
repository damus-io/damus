//
//  ConditionalModifier.swift
//  damus
//
//  Created by KernelKind on 2/2/24.
//

import SwiftUI

struct ConditionalModifier: ViewModifier {
    let modification: (AnyView) -> AnyView

    func body(content: Content) -> some View {
        modification(AnyView(content))
    }
}

extension View {
    func conditionalModifier(modification: @escaping (AnyView) -> AnyView) -> some View {
        self.modifier(ConditionalModifier(modification: modification))
    }
}

