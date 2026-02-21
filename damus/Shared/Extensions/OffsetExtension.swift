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

    private class Storage {
        var currentOffset: CGFloat = 0
        var previousOffset: CGFloat = 0
    }

    @State private var storage = Storage()

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader{proxy in
                    let minY = proxy.frame(in: .named("scroll")).minY
                    Color.clear
                        .preference(key: OffsetKey.self, value: minY)
                        .onPreferenceChange(OffsetKey.self) { value in
                            storage.previousOffset = storage.currentOffset
                            storage.currentOffset = value
                            onChange(storage.previousOffset, storage.currentOffset)
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
