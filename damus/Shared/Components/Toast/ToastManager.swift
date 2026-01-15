//
//  ToastManager.swift
//  damus
//
//  Created by alltheseas on 2025-01-14.
//

import SwiftUI

/// Style variants for toast notifications.
///
/// Each style provides appropriate colors and icons for different feedback scenarios.
enum ToastStyle {
    case success
    case info
    case warning
    case error

    /// The SF Symbol name for this toast style.
    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    /// The primary color for this toast style.
    var color: Color {
        switch self {
        case .success: return DamusColors.success
        case .info: return DamusColors.blue
        case .warning: return DamusColors.warning
        case .error: return DamusColors.danger
        }
    }
}

/// A single toast message to be displayed.
struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let message: String
    let style: ToastStyle
    let duration: TimeInterval

    /// Creates a new toast message.
    ///
    /// - Parameters:
    ///   - message: The localized message to display.
    ///   - style: The visual style of the toast. Defaults to `.success`.
    ///   - duration: How long to display the toast in seconds. Defaults to 3 seconds.
    init(message: String, style: ToastStyle = .success, duration: TimeInterval = 3.0) {
        self.id = UUID()
        self.message = message
        self.style = style
        self.duration = duration
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages the display of toast notifications throughout the app.
///
/// ToastManager is an ObservableObject that should be passed through the environment
/// or stored as a StateObject at the app's root level. It handles queuing and
/// auto-dismissal of toast messages.
///
/// ## Usage
/// ```swift
/// // Show a toast
/// toastManager.show("Copied!", style: .success)
///
/// // In the view hierarchy
/// .environmentObject(toastManager)
/// ```
@MainActor
final class ToastManager: ObservableObject {
    /// Shared instance for use from global functions.
    /// Prefer using the environment object when available in views.
    static let shared = ToastManager()

    /// The currently displayed toast, if any.
    @Published private(set) var currentToast: ToastMessage?

    /// Queue of pending toasts.
    private var queue: [ToastMessage] = []

    /// Task handling auto-dismissal.
    private var dismissTask: Task<Void, Never>?

    /// Shows a toast message.
    ///
    /// If a toast is currently showing, the new toast is queued and will display
    /// after the current one dismisses.
    ///
    /// - Parameters:
    ///   - message: The localized message to display.
    ///   - style: The visual style. Defaults to `.success`.
    ///   - duration: Display duration in seconds. Defaults to 3 seconds.
    func show(_ message: String, style: ToastStyle = .success, duration: TimeInterval = 3.0) {
        let toast = ToastMessage(message: message, style: style, duration: duration)

        guard currentToast == nil else {
            queue.append(toast)
            return
        }

        displayToast(toast)
    }

    /// Dismisses the current toast immediately.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }

        showNextIfQueued()
    }

    /// Displays a toast and schedules auto-dismissal.
    private func displayToast(_ toast: ToastMessage) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToast = toast
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Shows the next queued toast if available.
    private func showNextIfQueued() {
        guard !queue.isEmpty else { return }

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s gap between toasts
            guard !Task.isCancelled else { return }
            guard currentToast == nil else { return } // Another toast was shown during the gap

            let next = queue.removeFirst()
            displayToast(next)
        }
    }
}

// MARK: - Convenience Extensions

extension ToastManager {
    /// Shows a "Copied!" toast with success style.
    func showCopied() {
        show(NSLocalizedString("Copied!", comment: "Toast message when content is copied to clipboard"), style: .success)
    }

    /// Shows a "Followed" toast with success style.
    ///
    /// - Parameter name: The display name of the followed user.
    func showFollowed(_ name: String) {
        let format = NSLocalizedString("Followed %@", comment: "Toast message when following a user")
        show(String(format: format, name), style: .success)
    }

    /// Shows an "Unfollowed" toast with info style.
    ///
    /// - Parameter name: The display name of the unfollowed user.
    func showUnfollowed(_ name: String) {
        let format = NSLocalizedString("Unfollowed %@", comment: "Toast message when unfollowing a user")
        show(String(format: format, name), style: .info)
    }

    /// Shows a "Bookmarked" toast.
    func showBookmarked() {
        show(NSLocalizedString("Added to bookmarks", comment: "Toast message when adding a bookmark"), style: .success)
    }

    /// Shows a "Removed from bookmarks" toast.
    func showUnbookmarked() {
        show(NSLocalizedString("Removed from bookmarks", comment: "Toast message when removing a bookmark"), style: .info)
    }

    /// Shows a "Profile updated" toast.
    func showProfileUpdated() {
        show(NSLocalizedString("Profile updated", comment: "Toast message when profile is saved"), style: .success)
    }

    /// Shows a "Relay added" toast.
    func showRelayAdded() {
        show(NSLocalizedString("Relay added", comment: "Toast message when a relay is added"), style: .success)
    }

    /// Shows a "Relay removed" toast.
    func showRelayRemoved() {
        show(NSLocalizedString("Relay removed", comment: "Toast message when a relay is removed"), style: .info)
    }

    /// Shows a "Muted" toast.
    ///
    /// - Parameter name: The display name of the muted user or item.
    func showMuted(_ name: String) {
        let format = NSLocalizedString("Muted %@", comment: "Toast message when muting a user")
        show(String(format: format, name), style: .success)
    }

    /// Shows an "Unmuted" toast.
    ///
    /// - Parameter name: The display name of the unmuted user or item.
    func showUnmuted(_ name: String) {
        let format = NSLocalizedString("Unmuted %@", comment: "Toast message when unmuting a user")
        show(String(format: format, name), style: .info)
    }

    /// Shows a "Thread muted" toast.
    func showThreadMuted() {
        show(NSLocalizedString("Thread muted", comment: "Toast message when muting a thread"), style: .success)
    }

    /// Shows a "Thread unmuted" toast.
    func showThreadUnmuted() {
        show(NSLocalizedString("Thread unmuted", comment: "Toast message when unmuting a thread"), style: .info)
    }

    /// Shows a "Reposted" toast.
    func showReposted() {
        show(NSLocalizedString("Reposted", comment: "Toast message when reposting a note"), style: .success)
    }

    /// Shows a "Note posted" toast.
    func showNotePosted() {
        show(NSLocalizedString("Note posted", comment: "Toast message when a note is published"), style: .success)
    }

    /// Shows a "Zap sent" toast.
    ///
    /// - Parameter msats: The zap amount in millisats.
    func showZapSent(_ msats: Int64) {
        let format = NSLocalizedString("Zap sent for %@ sats", comment: "Toast message when sending a zap")
        show(String(format: format, format_msats_abbrev(msats)), style: .success)
    }

    /// Shows an error toast.
    ///
    /// - Parameter message: The error message to display.
    func showError(_ message: String) {
        show(message, style: .error, duration: 4.0)
    }
}
