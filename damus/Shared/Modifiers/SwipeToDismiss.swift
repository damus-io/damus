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

/// Enables full-screen swipe-right gesture to navigate back, matching the UX pattern
/// used in X and Bluesky apps. More ergonomic than requiring users to reach the back button.
///
/// The gesture triggers navigation back when either:
/// - User drags beyond the distance threshold (100pt), OR
/// - User swipes with sufficient velocity (300pt/s)
struct SwipeToNavigateBackModifier: ViewModifier {
    @ObservedObject var navigationCoordinator: NavigationCoordinator

    @State private var dragOffset: CGFloat = 0

    /// Minimum drag distance required to trigger navigation back
    private let threshold: CGFloat = 100
    /// Minimum swipe velocity required to trigger navigation back
    private let velocityThreshold: CGFloat = 300
    private let screenWidth: CGFloat = UIScreen.main.bounds.width

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .animation(.interactiveSpring(), value: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { value in
                        // Only track right swipes (positive x translation)
                        guard value.translation.width > 0 else { return }
                        // Apply resistance factor for natural drag feel
                        dragOffset = value.translation.width * 0.7
                    }
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let velocity = value.predictedEndTranslation.width - value.translation.width

                        // Trigger navigation if drag exceeded threshold or velocity was high enough
                        guard horizontalAmount > threshold || velocity > velocityThreshold else {
                            // Snap back to original position
                            withAnimation(.interactiveSpring()) {
                                dragOffset = 0
                            }
                            return
                        }

                        // Animate view off-screen, then pop navigation
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = screenWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            navigationCoordinator.pop()
                            dragOffset = 0
                        }
                    }
            )
    }
}

extension View {
    /// Adds full-screen swipe-right gesture to navigate back to the previous view.
    func swipeToNavigateBack(navigationCoordinator: NavigationCoordinator) -> some View {
        self.modifier(SwipeToNavigateBackModifier(navigationCoordinator: navigationCoordinator))
    }
}
