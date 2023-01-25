//
//  SwipeToDismiss.swift
//  damus
//
//  Created by Joel Klabo on 1/18/23.
//

import SwiftUI

struct SwipeToDismissModifier: ViewModifier {
    let minDistance: CGFloat?
    var onDismiss: () -> Void
    @State private var offset: CGSize = .zero
    @GestureState private var viewOffset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .offset(y: viewOffset.height)
            .animation(.interactiveSpring(), value: viewOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: minDistance ?? 10)
                    .updating($viewOffset, body: { value, gestureState, transaction in
                        gestureState = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
                    })
                    .onChanged { gesture in
                        if gesture.translation.width < 50 {
                            offset = gesture.translation
                        }
                    }
                    .onEnded { _ in
                        if abs(offset.height) > 100 {
                            onDismiss()
                        } else {
                            offset = .zero
                        }
                    }
            )
    }
}
