//
//  TabBarAppearanceModifier.swift
//  damus
//

import SwiftUI

/// Whether the timeline filter selector lives in the tab view's bottom glass
/// accessory rather than in a ``CustomPicker`` at the top of the tab.
///
/// The accessory is iOS 26-only (see
/// ``SwiftUI/View/timelineFilterAccessory(_:)``), so pre-26 the top picker stays
/// the only selector. From iOS 26 on the accessory owns the job and the tab roots
/// drop their picker, so the same filter is never offered in two places at once.
///
/// Tab roots branch on this rather than writing an `#available` of their own,
/// which keeps the version check next to the modifier it belongs to.
var timelineFilterLivesInTabViewAccessory: Bool {
    if #available(iOS 26.0, *) {
        return true
    }
    return false
}

extension View {
    /// Lets the tab bar shrink into its minimized form as content scrolls down.
    ///
    /// This is the iOS 26 tab bar behaviour: the bar collapses to a compact pill
    /// when the user scrolls down into content, so the timeline gets the full
    /// height while reading.
    ///
    /// `tabBarMinimizeBehavior(_:)` is iOS 26.0+, and `.onScrollDown` is
    /// additionally unavailable on macOS, tvOS, watchOS and visionOS — so the
    /// `#available` check is doing double duty here and also keeps the Catalyst
    /// target compiling. Apply it to the `TabView`, not to a tab's content.
    ///
    /// ## Known limitation: it restores at the top, not on scrolling up
    ///
    /// The name `.onScrollDown` implies the bar comes back when you scroll up
    /// again. It does not. On iOS 26.5 the bar restores only once the scroll
    /// view reaches the very top; scrolling upward mid-timeline leaves it
    /// minimized, so the way back to a full bar is to scroll to the top or tap a
    /// tab button.
    ///
    /// This was confirmed on a real device, and it is not something damus is
    /// doing: it reproduces with a bare `ScrollView { LazyVStack { ... } }` in a
    /// plain `TabView`, with none of this file's modifiers applied and no
    /// `tabViewBottomAccessory` present. It is not affected by
    /// ``softBottomScrollEdgeEffect()``, by
    /// ``SwiftUI/View/staticNavigationBarAppearance()``, or by the timeline's own
    /// scroll-offset machinery. Accepted as-is rather than worked around — see
    /// headway:damus-ios/spread-faith-month for the full investigation.
    ///
    /// Whether the iOS 18 `Tab {}` API behaves differently from `.tabItem` here
    /// is **not** established: the bare-`ScrollView` reproduction used
    /// `.tabItem`, so it says nothing either way, and the one `Tab {}` arm that
    /// was tried was measured with the invalid zero-velocity gesture described
    /// below. Note the floor makes this academic for now — `Tab {}` is iOS 18+
    /// against a 16 floor, and gating it by availability would give the
    /// `TabView` two identities, which discards every tab's navigation stack on
    /// each tab change.
    ///
    /// One trap if you go measuring this yourself: the tab bar's accessibility
    /// frame is identical whether expanded or minimized, so it is not a probe.
    /// `app.tabBars.firstMatch.buttons.count` is — 4 expanded, 1 minimized. And
    /// drive the scroll with `swipeUp(velocity: .fast)`, not
    /// `press(forDuration:thenDragTo:)`, which ends at zero velocity and fails
    /// to restore the bar in *every* configuration, manufacturing false
    /// negatives that look like clean refutations.
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

    /// Hangs the timeline filter selector off the bottom of the tab view, in a
    /// Liquid Glass accessory beside the tab bar.
    ///
    /// `tabViewBottomAccessory(content:)` is iOS 26.0+ and additionally
    /// unavailable on macOS, tvOS, watchOS and visionOS, so pre-26 (and on
    /// Catalyst) this is a no-op and the tab roots keep their top
    /// ``CustomPicker`` instead — see ``timelineFilterLivesInTabViewAccessory``.
    ///
    /// The search tab has no filter and passes `nil`, which has to switch the
    /// accessory off rather than just draw nothing in it: the glass capsule is
    /// the system's, not ours, so empty content still leaves an empty pill
    /// hovering over the timeline. That is what the `isEnabled:` overload is for,
    /// and it is iOS 26.1+ — hence the nested check. On 26.0 exactly we fall back
    /// to the always-on accessory and the search tab shows that empty capsule; it
    /// is cosmetic, and the alternative (raising the floor to 26.1) would cost
    /// the accessory on every 26.0 device.
    ///
    /// Note what is deliberately *not* done here: applying the modifier only for
    /// the tabs that have a filter. A condition that changes as the user switches
    /// tabs gives the `TabView` two identities, and SwiftUI would throw away
    /// every tab's navigation stack on each change. The modifier is always
    /// applied; only its content and enablement vary.
    ///
    /// Apply it to the `TabView`, not to a tab's content.
    @ViewBuilder
    func timelineFilterAccessory(_ filter: TimelineFilterSelection?) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: filter != nil) {
                if let filter {
                    TimelineFilterAccessory(filter: filter)
                }
            }
        } else if #available(iOS 26.0, *) {
            self.tabViewBottomAccessory {
                if let filter {
                    TimelineFilterAccessory(filter: filter)
                }
            }
        } else {
            self
        }
    }
}
