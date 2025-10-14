//
//  MuteItemRow.swift
//  damus
//
//  Created by Claude Code
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

    private func updateTimeRemaining() {
        let expirationDate: Date? = {
            switch item {
            case .user(_, let date):
                return date
            case .hashtag(_, let date):
                return date
            case .word(_, let date):
                return date
            case .thread(_, let date):
                return date
            }
        }()

        guard let expirationDate = expirationDate else {
            timeRemaining = nil
            return
        }

        // Check if expired
        if expirationDate <= Date() {
            timeRemaining = NSLocalizedString("Expired", comment: "Label indicating a temporary mute has expired")
            return
        }

        timeRemaining = formatTimeRemaining(until: expirationDate)
    }

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

    private func startTimer() {
        // Update every minute for temporary mutes
        guard timeRemaining != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateTimeRemaining()
        }
    }

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
