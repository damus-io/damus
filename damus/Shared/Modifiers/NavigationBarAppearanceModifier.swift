//
//  NavigationBarAppearanceModifier.swift
//  damus
//

import SwiftUI

extension View {
    /// Keeps the navigation bar from changing appearance as content scrolls under it.
    ///
    /// The timelines draw their own header, so the system bar should stay
    /// transparent rather than picking up a material (and, on iOS 26, a scroll
    /// edge effect) the moment content reaches its edge.
    ///
    /// This used to be achieved by wrapping each timeline in a single-child
    /// `TabView(.page)`, which hid the scroll view from the navigation bar. A
    /// real tab bar needs that wrapper gone, so the suppression is explicit now.
    ///
    /// `toolbarBackground(_:for:)` is iOS 16+ and soft-deprecated
    /// (`deprecated: 100000.0`), so it is warning-free; its replacement
    /// `toolbarBackgroundVisibility(_:for:)` is iOS 18+ and would break the
    /// iOS 16 floor.
    func staticNavigationBarAppearance() -> some View {
        self
            .toolbarBackground(.hidden, for: .navigationBar)
            .hideTopScrollEdgeEffect()
    }

    /// Hides the top scroll edge effect on iOS 26+, leaving it unchanged on earlier versions.
    @ViewBuilder
    func hideTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
