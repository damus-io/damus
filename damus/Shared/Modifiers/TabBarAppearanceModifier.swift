//
//  TabBarAppearanceModifier.swift
//  damus
//

import SwiftUI

extension View {
    /// Lets the tab bar shrink into its minimized form as content scrolls down.
    ///
    /// This is the iOS 26 tab bar behaviour: the bar collapses to a compact pill
    /// when the user scrolls down into content and expands again on scroll up,
    /// so the timeline gets the full height while reading.
    ///
    /// `tabBarMinimizeBehavior(_:)` is iOS 26.0+, and `.onScrollDown` is
    /// additionally unavailable on macOS, tvOS, watchOS and visionOS — so the
    /// `#available` check is doing double duty here and also keeps the Catalyst
    /// target compiling. Apply it to the `TabView`, not to a tab's content.
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Gives content scrolling under the tab bar a soft scroll edge effect.
    ///
    /// The bottom edge of a timeline runs under a translucent tab bar, and the
    /// default `.automatic` effect renders a harder transition than the glass
    /// material wants. `.soft` gives the gradual fade that reads correctly
    /// beneath it.
    ///
    /// `scrollEdgeEffectStyle(_:for:)` is iOS 26.0+ and unavailable on visionOS.
    /// Note the style enum has only `.automatic`, `.hard` and `.soft` — there is
    /// no `.hidden` case; hiding an edge effect is the separate
    /// `scrollEdgeEffectHidden(_:for:)` API used by
    /// ``hideTopScrollEdgeEffect()``.
    @ViewBuilder
    func softBottomScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }
}
