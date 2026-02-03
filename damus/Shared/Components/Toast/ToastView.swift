//
//  ToastView.swift
//  damus
//
//  Created by alltheseas on 2025-01-14.
//

import SwiftUI
import UIKit  // Required for UIAccessibility.post() on iOS 16 (see postAccessibilityAnnouncement)

/// A toast notification view that displays a message with an icon.
///
/// ToastView provides a visually consistent way to show brief feedback messages.
/// It supports swipe-to-dismiss gestures and adapts to both light and dark modes.
///
/// ## Design Notes
/// - Uses solid black background with white text for maximum contrast
/// - Ensures visibility over sheets, cards, and any overlay content
/// - Follows Apple HIG with 44pt minimum touch target
/// - Accessible via VoiceOver (posts announcement notification)
struct ToastView: View {
    let message: String
    let style: ToastStyle
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style.iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(style.color)

            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DamusColors.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 44) // Apple HIG minimum touch target
        .background(toastBackground)
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .onAppear {
            postAccessibilityAnnouncement(message)
        }
    }

    /// Posts a VoiceOver announcement for the toast message.
    ///
    /// - iOS 17+: Uses SwiftUI's `AccessibilityNotification.Announcement`
    /// - iOS 16: Falls back to UIKit's `UIAccessibility.post()` (requires `import UIKit`)
    private func postAccessibilityAnnouncement(_ message: String) {
        if #available(iOS 17.0, *) {
            AccessibilityNotification.Announcement(message).post()
        } else {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    /// Solid opaque background with maximum contrast.
    private var toastBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(DamusColors.black)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DamusColors.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
    }

    /// Swipe-up gesture to dismiss the toast.
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow upward drag
                guard value.translation.height < 0 else {
                    dragOffset = value.translation.height * 0.3 // Resist downward
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                // Return to original position if swipe threshold not met
                guard value.translation.height < -50 else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                    return
                }

                // Swipe threshold met - dismiss
                withAnimation(.easeOut(duration: 0.2)) {
                    dragOffset = -200
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onDismiss()
                }
            }
    }
}

/// View modifier that overlays a toast on the view.
struct ToastModifier: ViewModifier {
    @ObservedObject var manager: ToastManager

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            toastOverlay
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = manager.currentToast {
            GeometryReader { geometry in
                ToastView(
                    message: toast.message,
                    style: toast.style,
                    onDismiss: { manager.dismiss() }
                )
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds toast notification support to a view.
    ///
    /// - Parameter manager: The ToastManager that controls toast display.
    /// - Returns: A view with toast overlay capability.
    func toast(manager: ToastManager) -> some View {
        modifier(ToastModifier(manager: manager))
    }
}

// MARK: - Preview

#Preview("Success Toast") {
    ToastView(
        message: "Copied!",
        style: .success,
        onDismiss: {}
    )
    .padding()
}

#Preview("Info Toast") {
    ToastView(
        message: "Unfollowed @alice",
        style: .info,
        onDismiss: {}
    )
    .padding()
}

#Preview("Error Toast") {
    ToastView(
        message: "Failed to load content",
        style: .error,
        onDismiss: {}
    )
    .padding()
}
