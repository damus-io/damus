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
    /// Watches for visibility changes. Does not detect occlusion
    /// 
    /// ## Usage notes
    /// 
    /// 1. Detection mechanisms are not perfect, parameters may need fine tuning. Please refer to `VisibilityTracker` documentation for more details.
    /// 2. This does **not** detect if the view has been occluded. There are currently no known mechanisms to do that.
    ///   If occlusion tracking is needed for your usage, consider using layout knowledge/introspection of the different layers that make up the view, and using that information for your logic.
    ///   For example, when dealing with items on a normal view, and a full screen cover, write your logic based on explicit information about which views are in the full screen layer.
    ///   Read about `present(full_screen_item: FullScreenItem)`, `damus_full_screen_cover`, and the `.view_layer_context` environment variable.
    ///
    /// - Parameters:
    ///   - visibility_change_notifier: Function to call once visibility changes
    ///   - edge: Edge for the visibility overlay sensor
    ///   - method: The method to use for visibility tracking. Refer to `VisibilityTracker` documentation for more details.
    /// - Returns: A modified view.
    func on_visibility_change(perform visibility_change_notifier: @escaping (Bool) -> Void, edge: Alignment = .center, method: VisibilityTracker.Method = .standard) -> some View {
        self.modifier(VisibilityTracker(visibility_change_notifier: visibility_change_notifier, edge: edge, method: method))
    }
}


/// Tracks visibility of a SwiftUI view.
/// Built mostly to track visibility states of video players around the app and help the video coordinator pick a video to focus on, but can be used for basically any other view
/// **Caution:** This is not a perfect tracker, please read and fine-tune parameters for your use case, especially `method`
struct VisibilityTracker: ViewModifier {
    let visibility_window: CGFloat = 0.8
    let visibility_change_notifier: (Bool) -> Void
    let edge: Alignment
    let method: Method
    
    init(visibility_change_notifier: @escaping (Bool) -> Void, edge: Alignment, method: Method) {
        self.visibility_change_notifier = visibility_change_notifier
        self.edge = edge
        self.method = method
    }
    
    @EnvironmentObject private var orientationTracker: OrientationTracker
    /// Holds information about whether the view is "generically" visible, meaning whether it would have been loaded on a lazy stack.
    @State private var generic_visible: Bool = false {
        didSet {
            if oldValue == generic_visible { return }  // Save up computing resources if there were no changes
            self.visibility_change_notifier(self.is_visible)
        }
    }
    /// Whether the view is visible by checking if its Y position is within a range of the user's screen
    @State private var y_scroll_visible: Bool = false {
        didSet {
            switch self.method {
                case .standard:
                    if oldValue == y_scroll_visible { return }  // Save up computing resources if there were no changes
                    self.visibility_change_notifier(self.is_visible)
                case .no_y_scroll_detection:
                    return  // Don't cause re-renders if the visibility method does not use this
            }
        }
    }
    /// Whether view is "visible"
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
                        // MARK: Detection triggers
                        .onAppear {
                            self.generic_visible = true
                            self.y_scroll_visible = self.compute_y_scroll_visible(centerY: centerY)
                        }
                        .onDisappear {
                            self.generic_visible = false
                        }
                        .onChange(of: centerY) { new_center_y in
                            if generic_visible == false { return }  // Don't bother calculating anything if this is not visible generically, to save up computing resources
                            self.y_scroll_visible = self.compute_y_scroll_visible(
                                centerY: new_center_y   // Compute the new Y scroll visibility using the newest value to avoid transient issues on device orientation changes
                            )
                        }
                }
            },
            alignment: edge)
    }
    
    /// Computes whether the view is "visible" in a range of the screen given its Y position
    private func compute_y_scroll_visible(centerY: CGFloat) -> Bool {
        let screen_center_y: CGFloat = orientationTracker.deviceMajorAxis / 2
        let screen_visibility_window_margin: CGFloat = orientationTracker.deviceMajorAxis * visibility_window / 2
        let isBelowTop = centerY > screen_center_y - screen_visibility_window_margin
        let isAboveBottom = centerY < screen_center_y + screen_visibility_window_margin
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
