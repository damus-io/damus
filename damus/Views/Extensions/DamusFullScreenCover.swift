//
//  DamusFullScreenCover.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-10-25.
//

import SwiftUI


// MARK: - Private view modifier implementations of DamusFullScreenCover

/// This implements a full screen cover made for use in Damus.
/// This was created as a way to facilitate video coordination throughout the app, by handling the necessary logic — without requiring any special handling in the usages of video player views.
///
/// In the future this could be used to faciliate other full screen logic as well.
///
/// # Features
///
/// This has the following features:
/// 1. It automatically tells the video coordinator about full screen mode changes, so that the video coordinator always knows if the app is in normal mode or in full screen mode for video coordination
/// 2. It automatically sets the `view_layer_context`, which is consumed by video player views, allowing those views to communicate about their layer position to the video coordinator
fileprivate struct DamusFullScreenCover<FullScreenContent: View, T: Identifiable & Equatable>: ViewModifier {
    /// The `damus_state`, where we can access the video coordinator
    let damus_state: DamusState
    /// The item to be presented full screen
    @Binding var item: T?
    /// The view to be presented full screen
    let full_screen_content: (T) -> FullScreenContent
    
    func body(content: Content) -> some View {
        content
            .environment(\.view_layer_context, .normal_layer)  // Let the views under content know they are NOT in a full screen environment
            .onChange(of: item, perform: { newValue in
                // Inform the video coordinator whether we are in full screen mode or not.
                damus_state.video.set_full_screen_mode(newValue != nil)
            })
            .fullScreenCover(item: $item, content: { item in
                full_screen_content(item)
                    .environment(\.view_layer_context, .full_screen_layer)  // Let the views under full screen content know they are in a full screen environment
                    // Another observer for full screen presentation is needed here because in some cases the underlying view (`body::content`) may have been deinitialized and no longer listen to changes
                    // One such example is when the underlying navigation stack navigates away from a source view at the same time it opens the full screen view
                    // Therefore, when the full screen view is dismissed, this content will disappear, and we should notify the video coordinator.
                    .onDisappear {
                        damus_state.video.set_full_screen_mode(false)
                    }
            })
    }
}

/// A convenience view modifier that provides a different interface than `DamusFullScreenCover`, but is otherwise identical to it.
fileprivate struct DamusFullScreenCoverWithoutItem<FullScreenContent: View>: ViewModifier {
    let damus_state: DamusState
    @Binding var is_presented: Bool
    let full_screen_content: () -> FullScreenContent
    private let fake_item: FakeItem = FakeItem()
    private var binding_item: Binding<FakeItem?> {
        return Binding(
            get: { is_presented ? self.fake_item : nil },
            set: { is_presented = $0 != nil ? true : false }
        )
    }
    
    func body(content: Content) -> some View {
        content
            .damus_full_screen_cover(self.binding_item, damus_state: damus_state, content: { _ in full_screen_content() })
    }
    
    private struct FakeItem: Identifiable, Equatable {
        let id: Int = 1
    }
}


// MARK: - Environment variable definitions

extension EnvironmentValues {
    @Entry var view_layer_context: ViewLayerContext? = nil
}


/// Context about the layer a view finds itself in
/// This communicates to a view (e.g. a video player) context about whether it is being displayed inside a full screen layer, or a normal layer
enum ViewLayerContext {
    /// This is used for items placed in a scroll view, such as on a timeline or a thread view.
    case normal_layer
    /// This is used for video players being displayed full screen
    case full_screen_layer
}


// MARK: - View extension interfaces to access Damus' full screen cover

extension View {
    
    /// A full screen cover to be used throughout Damus, containing extra functionality that helps with app coordination, and is meant to replace `.fullScreenCover`
    ///
    /// ## Usage notes
    ///
    /// This is the preferred method of doing a full screen cover. This is preferred over `.fullScreenCover` because it helps with certain coordination elements:
    ///
    /// 1. It automatically informs the video coordinator if the app is in full screen or not
    /// 2. It provides contextual information that any child view can pickup to introspect whether or not they are in a full screen layer. This can be picked up via the `\.view_layer_context` environment variable
    ///
    /// **CAUTION:**
    /// If you are planning to use this from a view that is presented on a timeline or lazy stack, please use `present(full_screen_item: FullScreenItem)` instead to avoid your full screen view to abruptly disappear.
    /// Please read the documentation for `present(full_screen_item: FullScreenItem)` for more details.
    ///
    /// - Parameters:
    ///   - is_presented: whether to show the full screen cover
    ///   - damus_state: The state of the app
    ///   - content: The view to show full screen
    /// - Returns: the modified view
    func damus_full_screen_cover<Content: View>(_ is_presented: Binding<Bool>, damus_state: DamusState, @ViewBuilder content: @escaping () -> Content) -> some View {
        return self.modifier(DamusFullScreenCoverWithoutItem(damus_state: damus_state, is_presented: is_presented, full_screen_content: content))
    }
    
    /// A full screen cover to be used throughout Damus, containing extra functionality that helps with app coordination, and is meant to replace `.fullScreenCover`
    /// 
    /// ## Usage notes
    /// 
    /// This is the preferred method of doing a full screen cover. This is preferred over `.fullScreenCover` because it helps with certain coordination elements:
    /// 
    /// 1. It automatically informs the video coordinator if the app is in full screen or not
    /// 2. It provides contextual information that any child view can pickup to introspect whether or not they are in a full screen layer. This can be picked up via the `\.view_layer_context` environment variable
    ///
    /// **CAUTION:**
    /// If you are planning to use this from a view that is presented on a timeline or lazy stack, please use `present(full_screen_item: FullScreenItem)` instead to avoid your full screen view to abruptly disappear.
    /// Please read the documentation for `present(full_screen_item: FullScreenItem)` for more details.
    ///
    ///
    /// - Parameters:
    ///   - item: The item to be displayed full screen, or `nil` if full screen should be dismissed.
    ///   - damus_state: The state of the app
    ///   - content: The view to render `item`
    /// - Returns: the modified view
    func damus_full_screen_cover<Content: View, T: Identifiable & Equatable>(_ item: Binding<T?>, damus_state: DamusState, @ViewBuilder content: @escaping (T) -> Content) -> some View {
        return self.modifier(DamusFullScreenCover(damus_state: damus_state, item: item, full_screen_content: content))
    }
}
