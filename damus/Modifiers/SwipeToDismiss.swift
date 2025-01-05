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
    
    let threshold_offset: CGFloat = 100.0
    let minimum_opacity: CGFloat = 0.1

    func body(content: Content) -> some View {
        content
            .offset(y: viewOffset.height)
            .animation(.interactiveSpring(), value: viewOffset)
            .opacity(max(min(1.0 - (abs(offset.height) / threshold_offset), 1.0), minimum_opacity))
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
                        if abs(offset.height) > threshold_offset {
                            onDismiss()
                        } else {
                            offset = .zero
                        }
                    }
            )
    }
}
