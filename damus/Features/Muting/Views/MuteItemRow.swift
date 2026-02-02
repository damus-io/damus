//
//  MuteItemRow.swift
//  damus
//
//  Created by alltheseas
//

import SwiftUI

/// Displays a mute item with an optional expiration indicator
struct MuteItemRow<Content: View>: View {
    let item: MuteItem
    @ViewBuilder let content: () -> Content

    @State private var timeRemaining: String?
    @State private var timer: Timer?

    var body: some View {
        HStack {
            content()

            Spacer()

            if let timeRemaining = timeRemaining {
                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            updateTimeRemaining()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    /// The localized string shown when a mute has expired.
    private static let expiredString = NSLocalizedString("Expired", comment: "Label indicating a temporary mute has expired")

    /// Updates the time remaining string based on the item's expiration date.
    /// Sets `timeRemaining` to nil for permanent mutes, "Expired" for expired mutes,
    /// or a formatted time string for active temporary mutes.
    /// Stops the timer when transitioning to expired state.
    private func updateTimeRemaining() {
        guard let expirationDate = item.expirationDate else {
            timeRemaining = nil
            return
        }

        // Check if expired
        if expirationDate <= Date() {
            timeRemaining = Self.expiredString
            // Stop timer when mute expires - no need to keep updating
            stopTimer()
            return
        }

        timeRemaining = formatTimeRemaining(until: expirationDate)
    }

    /// Formats the time interval until the given date as a human-readable string.
    /// - Parameter date: The expiration date to format time remaining for.
    /// - Returns: A localized string like "2d 5h", "3h 30m", "45m", or "30s".
    private func formatTimeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSince(Date())

        if interval < 0 {
            return NSLocalizedString("Expired", comment: "Label indicating a temporary mute has expired")
        }

        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            let remainingHours = hours % 24
            if remainingHours > 0 {
                return String(format: NSLocalizedString("%dd %dh", comment: "Time remaining format: days and hours"), days, remainingHours)
            }
            return String(format: NSLocalizedString("%dd", comment: "Time remaining format: days only"), days)
        } else if hours > 0 {
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return String(format: NSLocalizedString("%dh %dm", comment: "Time remaining format: hours and minutes"), hours, remainingMinutes)
            }
            return String(format: NSLocalizedString("%dh", comment: "Time remaining format: hours only"), hours)
        } else if minutes > 0 {
            return String(format: NSLocalizedString("%dm", comment: "Time remaining format: minutes only"), minutes)
        } else {
            return String(format: NSLocalizedString("%ds", comment: "Time remaining format: seconds only"), seconds)
        }
    }

    /// Starts a timer that updates the time remaining display every minute.
    /// Only starts if the item has an active temporary mute (non-nil, non-expired timeRemaining) and no timer exists.
    /// Uses `.common` run loop mode to ensure timer fires during scrolling.
    private func startTimer() {
        guard let remaining = timeRemaining,
              remaining != Self.expiredString,
              timer == nil else { return }

        let newTimer = Timer(timeInterval: 60, repeats: true) { _ in
            updateTimeRemaining()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Stops and invalidates the timer when the view disappears.
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    List {
        MuteItemRow(item: .hashtag(Hashtag(hashtag: "test"), Calendar.current.date(byAdding: .hour, value: 2, to: Date()))) {
            Text("#test")
        }

        MuteItemRow(item: .hashtag(Hashtag(hashtag: "permanent"), nil)) {
            Text("#permanent")
        }

        MuteItemRow(item: .user(test_pubkey, Calendar.current.date(byAdding: .day, value: 1, to: Date()))) {
            Text("User")
        }
    }
}
