//
//  ToolbarItemModifier.swift
//  damus
//

import SwiftUI

/// Extension that adds the `.hideToolbarBackground()` modifier to toolbar content.
///
/// This modifier conditionally applies `.sharedBackgroundVisibility(.hidden)` on iOS 26+,
/// eliminating the need for duplicated `if #available(iOS 26.0, *)` checks throughout the codebase.
///
/// - Usage:
///   ```swift
///   .toolbar {
///       ToolbarItem(placement: .navigationBarLeading) {
///           Button("Action") { }
///       }
///       .hideToolbarBackground()
///   }
///   ```
@available(iOS 15.0, *)
extension ToolbarContent {
    /// Hides the toolbar background on iOS 26+, leaving it unchanged on earlier versions.
    ///
    /// Apply this modifier to `ToolbarItem` views to suppress the shared background
    /// visibility introduced in iOS 26 without duplicating version checks.
    func hideToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            return self.sharedBackgroundVisibility(.hidden)
        } else {
            return self
        }
    }
}
