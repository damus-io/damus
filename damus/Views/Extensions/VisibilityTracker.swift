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
    /// Watches for visibility changes.
    /// **Caution:** Detection mechanisms are not perfect, parameters may need fine tuning. Please refer to `VisibilityTracker` documentation for more details.
    func on_visibility_change(perform visibility_change_notifier: @escaping (Bool) -> Void, edge: Alignment = .center, method: VisibilityTracker.Method = .standard) -> some View {
        self.modifier(VisibilityTracker(visibility_change_notifier: visibility_change_notifier, edge: edge, method: method))
    }
}


/// Tracks visibility of a SwiftUI view.
/// Built mostly to track visibility states of video players around the app and help the video coordinator pick a video to focus on, but can be used for basically any other view
/// **Caution:** This is not a perfect tracker, please read and fine-tune parameters for your use case, especially `method`
struct VisibilityTracker: ViewModifier {
    let visibility_window: CGFloat = 0.6
    let visibility_change_notifier: (Bool) -> Void
    let edge: Alignment
    let method: Method
    
    init(visibility_change_notifier: @escaping (Bool) -> Void, edge: Alignment, method: Method) {
        self.visibility_change_notifier = visibility_change_notifier
        self.edge = edge
        self.method = method
    }
    
    @EnvironmentObject private var orientationTracker: OrientationTracker
    @State private var generic_visible: Bool = false {
        didSet {
            if oldValue == generic_visible { return }  // Save up computing resources if there were no changes
            self.visibility_change_notifier(self.is_visible)
        }
    }
    @State private var y_scroll_visible: Bool = false {
        didSet {
            switch self.method {
                case .standard:
                    if oldValue == y_scroll_visible { return }  // Save up computing resources if there were no changes
                    self.visibility_change_notifier(self.is_visible)
                case .no_y_scroll_detection:
                    return
            }
            
        }
    }
    var is_visible: Bool {
        switch method {
            case .standard:
                return generic_visible && y_scroll_visible
            case .no_y_scroll_detection:
                return generic_visible
        }
    }

    func body(content: Content) -> some View {
    content
      .overlay(
        GeometryReader { geo in
            let localFrame = geo.frame(in: .local)
            let centerY = globalCoordinate(localX: 0, localY: localFrame.midY, localGeometry: geo).y
            LazyVStack {
                Color.clear
                    // MARK: Detection functions
                    /// **Implementation note:** Even if the method calls for a "constant" visibility, we should compute the other visibility factors to have them up-to-date if the visibility tracking method changes.
                    .onAppear {
                        self.generic_visible = true
                        self.y_scroll_visible = self.compute_y_scroll_visible(centerY: centerY)
                    }
                    .onDisappear {
                        self.generic_visible = false
                    }
                    .onChange(of: centerY) { new_center_y in
                        if generic_visible == false { return }  // Don't bother calculating anything if this is not visible generically
                        self.y_scroll_visible = self.compute_y_scroll_visible(
                            centerY: new_center_y   // Compute the new Y scroll visibility using the newest value to avoid transient issues on device orientation changes
                        )
                    }
            }
        },
        alignment: edge)
    }
    
    private func compute_y_scroll_visible(centerY: CGFloat) -> Bool {
        let screen_center_y = orientationTracker.deviceMajorAxis / 2
        let screen_visibility_window_margin = orientationTracker.deviceMajorAxis * visibility_window / 2
        let isBelowTop = centerY > screen_center_y - screen_visibility_window_margin,
            isAboveBottom = centerY < screen_center_y + screen_visibility_window_margin
        return (isBelowTop && isAboveBottom)
    }
    
    /// The methods available for visibility detection.
    /// Unfortunately, there is currently no perfect visibility detection mechanism, so callers of `VisibilityTracker` should select a method that best suits the context of the view.
    enum Method: Equatable {
        /// Includes both a generic and Y coordinate based visibility detection.
        /// When this option is selected, the view is only deemed visible if both lazy view evaluators load it (when close enough to viewport), and the center Y coordinate is sufficiently in the center
        /// This is best for most view presentations, specially for scroll views.
        case standard
        /// Includes only a generic visibility detection based on a lazy view loader
        /// When this option is selected, the view is only deemed visible if the lazy view evaluators load it (which SwiftUI does when it is close enough to viewport), regardless of Y coordinate
        /// This is not suitable for scroll views or most presentations because it may trigger too early, leading to false positives. This is more suitable when the standard detection mechanism is triggering too many false negatives, and this is a more "static" view
        /// For example: when displaying an item in full screen mode where it is visible in a more stable, static form, and device orientation changes may cause transient visibility triggers
        case no_y_scroll_detection
    }
}
