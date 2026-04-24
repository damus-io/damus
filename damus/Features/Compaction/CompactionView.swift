//
//  CompactionView.swift
//  damus
//

import SwiftUI

/// A view that handles database compaction on a background thread before showing the main content.
///
/// This view sits between `MainView` and `ContentView` to prevent the app from being killed by
/// the watchdog due to long-running compaction operations blocking the main thread during startup.
///
/// ## Implementation
///
/// When compaction is needed, this view:
/// 1. Shows a loading screen with progress information
/// 2. Performs the compaction on a background thread
/// 3. Transitions to `ContentView` once compaction completes
/// 4. Requires explicit user acknowledgement before continuing if compaction fails
///
/// The compaction process is performed before `Ndb` is opened for normal use, ensuring the
/// database is in a consistent state before the main app logic begins.
struct CompactionView: View {
    let keypair: Keypair
    let appDelegate: AppDelegate?

    @State private var isCompacting: Bool = false
    @State private var compactionComplete: Bool = false
    @State private var compactionError: String? = nil
    @State private var hasStartedCompactionFlow: Bool = false

    var body: some View {
        Group {
            if compactionComplete {
                ContentView(keypair: keypair, appDelegate: appDelegate)
            } else {
                CompactionLoadingView(
                    isCompacting: isCompacting,
                    error: compactionError,
                    continueAfterError: continueAfterError
                )
            }
        }
        .onAppear {
            guard !hasStartedCompactionFlow else { return }
            hasStartedCompactionFlow = true
            performCompactionIfNeeded()
        }
    }

    /// Checks if compaction is needed and performs it on a background thread.
    ///
    /// This function:
    /// - Schedules auto-compaction based on the configured interval
    /// - Checks if compaction was previously requested
    /// - If compaction is needed, performs it on a background thread with a loading UI
    /// - If no compaction is needed, immediately transitions to the main content
    private func performCompactionIfNeeded() {
        Ndb.schedule_auto_compact_if_needed()

        let needsCompaction = UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key)
        guard needsCompaction else {
            compactionComplete = true
            return
        }

        isCompacting = true

        Task.detached(priority: .userInitiated) {
            do {
                try Ndb.compact_if_needed()

                await MainActor.run {
                    isCompacting = false
                    compactionComplete = true
                }
            } catch {
                await MainActor.run {
                    isCompacting = false
                    compactionError = error.localizedDescription
                }
            }
        }
    }

    /// Continues to the main content after the user acknowledges a compaction error.
    private func continueAfterError() {
        compactionComplete = true
    }
}

/// A loading view displayed during database compaction.
///
/// Shows a spinner and informative text to the user while the compaction process runs.
/// If compaction fails, it shows the error and requires explicit acknowledgement before continuing.
struct CompactionLoadingView: View {
    let isCompacting: Bool
    let error: String?
    let continueAfterError: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("icon")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)

                if isCompacting {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()

                    Text("Optimizing Database", comment: "Title shown during database compaction")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("This may take a moment…", comment: "Subtitle shown during database compaction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("Compaction Warning", comment: "Title shown when database compaction encounters an error")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Text("The app can continue, but some storage may not have been freed.", comment: "Message shown when compaction fails but app can continue after acknowledgement")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: continueAfterError) {
                            Text("Continue", comment: "Button title used to continue into the app after acknowledging a compaction error")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                        .padding(.horizontal)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    CompactionLoadingView(
        isCompacting: true,
        error: nil,
        continueAfterError: {}
    )
}

#Preview("With Error") {
    CompactionLoadingView(
        isCompacting: false,
        error: "Failed to compact database",
        continueAfterError: {}
    )
}