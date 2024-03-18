//
//  VisibilityTracker.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-03-18.
// 
//  Based on code examples shown in this article: https://medium.com/@jackvanderpump/how-to-detect-is-an-element-is-visible-in-swiftui-9ff58ca72339

import Foundation
import SwiftUI

extension View {
    func on_visibility_change(perform visibility_change_notifier: @escaping (Bool) -> Void, edge: Alignment = .center) -> some View {
        self.modifier(VisibilityTracker(visibility_change_notifier: visibility_change_notifier, edge: edge))
    }
}

struct VisibilityTracker: ViewModifier {
    let visibility_change_notifier: (Bool) -> Void
    let edge: Alignment

    func body(content: Content) -> some View {
    content
      .overlay(
        LazyVStack {
          Color.clear
            .onAppear {
                visibility_change_notifier(true)
            }
            .onDisappear {
                visibility_change_notifier(false)
            }
        },
        alignment: edge)
    }
}
