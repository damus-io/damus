//
//  OffsetExtension.swift
//  damus
//
//  Created by eric on 9/6/24.
//

import SwiftUI

enum SwipeDirection {
    case up
    case down
    case none
}

extension View {
    @ViewBuilder
    func offsetY(completion: @escaping (CGFloat, CGFloat)->())->some View {
        self
            .modifier(OffsetHelper(onChange: completion))
    }
    
    func safeArea() -> UIEdgeInsets {
        guard let scene = this_app.connectedScenes.first as? UIWindowScene else{return .zero}
        guard let safeArea = scene.windows.first?.safeAreaInsets else{return .zero}
        return safeArea
    }
}

struct OffsetHelper: ViewModifier{
    var onChange: (CGFloat,CGFloat)->()
    @State var currentOffset: CGFloat = 0
    @State var previousOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader{proxy in
                    let minY = proxy.frame(in: .named("scroll")).minY
                    Color.clear
                        .preference(key: OffsetKey.self, value: minY)
                        .onPreferenceChange(OffsetKey.self) { value in
                            previousOffset = currentOffset
                            currentOffset = value
                            onChange(previousOffset,currentOffset)
                        }
                }
            }
    }
}

struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HeaderBoundsKey: PreferenceKey{
    static var defaultValue: Anchor<CGRect>?
    
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue()
    }
}

func getSafeAreaTop()->CGFloat{
    guard let scene = this_app.connectedScenes.first as? UIWindowScene else{return .zero}
    guard let topSafeArea = scene.windows.first?.safeAreaInsets.top else{return .zero}
    return topSafeArea
}

func getSafeAreaBottom()->CGFloat{
    guard let scene = this_app.connectedScenes.first as? UIWindowScene else{return .zero}
    guard let bottomSafeArea = scene.windows.first?.safeAreaInsets.bottom else{return .zero}
    return bottomSafeArea
}

/// The scroll-driven offset that hides and reveals the home timeline's chrome.
///
/// This is a reference type rather than a `@State` value because `TimelineView`'s scroll
/// callback writes it on every frame. Held as plain state it invalidated every view between
/// its owner and the header, so the whole header subtree — including the timeline switcher's
/// `Menu` — was reconstructed per frame even though none of its *content* depends on the offset.
///
/// Owners keep it in `@State`, which stores the reference without subscribing to it. Only the
/// small `ViewModifier`s below observe it, so a write re-runs the placement and leaves the
/// already-built views it wraps alone. Keep it an `ObservableObject` for that reason: `@State`
/// *does* track an `@Observable` type, which would put the per-frame invalidation right back.
@MainActor
final class HeaderOffsetModel: ObservableObject {
    @Published var offset: CGFloat = 0

    /// Scratch state for the scroll callback. Deliberately not `@Published` — it changes only
    /// when the scroll direction flips, and nothing draws from it.
    var shiftOffset: CGFloat = 0
    var lastOffset: CGFloat = 0
    var direction: SwipeDirection = .none
}

/// Applies the header's scroll-driven hide/reveal placement without rebuilding the header.
///
/// The offset is read inside a `ViewModifier` body, where `content` is a placeholder for the
/// already-built subtree, so a scroll frame re-runs only this placement.
struct HeaderOffsetPlacement: ViewModifier {
    @ObservedObject var model: HeaderOffsetModel
    let headerHeight: CGFloat

    func body(content: Content) -> some View {
        let offset = model.offset
        return content
            .offset(y: -offset < headerHeight ? offset : (offset < 0 ? offset : 0))
            .opacity(1.0 - (abs(offset / 100.0)))
    }
}

/// Fades chrome in step with the header's scroll-driven offset, without rebuilding it.
struct HeaderOffsetFade: ViewModifier {
    @ObservedObject var model: HeaderOffsetModel
    let base: CGFloat

    func body(content: Content) -> some View {
        content.opacity(base + abs(1.25 - (abs(model.offset / 100.0))))
    }
}

extension View {
    /// See ``HeaderOffsetPlacement``.
    func headerOffsetPlacement(_ model: HeaderOffsetModel, headerHeight: CGFloat) -> some View {
        modifier(HeaderOffsetPlacement(model: model, headerHeight: headerHeight))
    }

    /// See ``HeaderOffsetFade``.
    func headerOffsetFade(_ model: HeaderOffsetModel, base: CGFloat) -> some View {
        modifier(HeaderOffsetFade(model: model, base: base))
    }
}
