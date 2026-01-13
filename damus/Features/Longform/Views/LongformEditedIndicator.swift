//
//  LongformEditedIndicator.swift
//  damus
//
//  Created for issue #3517 - Display longform article edit history
//

import SwiftUI

/// A view that displays an "Edited" indicator for longform articles that have been modified.
///
/// This indicator queries nostrdb for version history on appear and shows
/// "Edited" text if multiple versions exist. Tapping it shows the full
/// version history. The query runs asynchronously to avoid blocking the main thread.
struct LongformEditedIndicator: View {
    let state: DamusState
    let event: NostrEvent

    @State private var versionHistory: LongformVersionHistory?
    @State private var isLoading: Bool = true
    @State private var showingHistory: Bool = false

    var body: some View {
        content
            .onAppear {
                Task {
                    await checkForEdits()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let history = versionHistory, history.hasBeenEdited {
            Button {
                showingHistory = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.line")
                        .font(.caption2)
                    Text(NSLocalizedString("Edited", comment: "Indicator that a longform article has been edited"))
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.85))
                .cornerRadius(4)
            }
            .sheet(isPresented: $showingHistory) {
                LongformVersionHistoryView(state: state, history: history)
            }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// Check if this article has been edited by querying for multiple versions.
    private func checkForEdits() async {
        guard let history = await LongformVersionHistory.fetch(for: event, ndb: state.ndb) else {
            isLoading = false
            return
        }

        await MainActor.run {
            versionHistory = history
            isLoading = false
        }
    }
}
