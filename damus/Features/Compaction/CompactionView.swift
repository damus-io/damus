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

    /// The current state of the startup compaction flow.
    enum CompactionState {
        case idle
        case compacting(progress: Double, stepTitle: String, stepDetail: String, showsLargeDatabaseWarning: Bool)
        case failed(error: String)
        case complete

        /// The initial visible state shown when compaction begins.
        /// - Parameter showsLargeDatabaseWarning: Whether the loading UI should explain that a large database may take longer to compact.
        static func initialCompactingState(showsLargeDatabaseWarning: Bool) -> CompactionState {
            return .compacting(
                progress: 0.05,
                stepTitle: NSLocalizedString("Preparing database compaction", comment: "Initial title shown during database compaction"),
                stepDetail: NSLocalizedString("Checking the database and getting everything ready.", comment: "Initial detail shown during database compaction"),
                showsLargeDatabaseWarning: showsLargeDatabaseWarning
            )
        }
    }

    @State private var compactionState: CompactionState = .idle
    @State private var hasStartedCompactionFlow: Bool = false

    var body: some View {
        Group {
            switch compactionState {
            case .complete:
                ContentView(keypair: keypair, appDelegate: appDelegate)

            case .idle:
                CompactionLoadingView(
                    state: .compacting(
                        progress: 0.0,
                        stepTitle: NSLocalizedString("Preparing database compaction", comment: "Title shown before database compaction starts"),
                        stepDetail: NSLocalizedString("Checking whether database optimization is needed.", comment: "Detail shown before database compaction starts"),
                        showsLargeDatabaseWarning: false
                    ),
                    continueAfterError: continueAfterError
                )

            case .compacting, .failed:
                CompactionLoadingView(
                    state: compactionState,
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
            compactionState = .complete
            return
        }

        let showsLargeDatabaseWarning = Ndb.db_path.map({ Ndb.is_large_database(path: $0) }) ?? false
        compactionState = CompactionState.initialCompactingState(showsLargeDatabaseWarning: showsLargeDatabaseWarning)

        Task.detached(priority: .userInitiated) {
            do {
                try Ndb.compact_if_needed(
                    progress: { progress in
                        Task { @MainActor in
                            compactionState = .compacting(
                                progress: progress.fractionCompleted,
                                stepTitle: progress.step.title,
                                stepDetail: progress.step.detail,
                                showsLargeDatabaseWarning: showsLargeDatabaseWarning
                            )
                        }
                    }
                )

                await MainActor.run {
                    compactionState = .complete
                }
            } catch {
                await MainActor.run {
                    compactionState = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    /// Continues to the main content after the user acknowledges a compaction error.
    private func continueAfterError() {
        compactionState = .complete
    }
}

/// A loading view displayed during database compaction.
///
/// Shows a spinner and informative text to the user while the compaction process runs.
/// If compaction fails, it shows the error and requires explicit acknowledgement before continuing.
struct CompactionLoadingView: View {
    let state: CompactionView.CompactionState
    let continueAfterError: () -> Void

    /// A percentage label for the current compaction progress.
    private var progressPercentageText: String? {
        guard case .compacting(let progress, _, _, _) = state else { return nil }

        let percentage = Int((progress * 100).rounded())
        return String(
            format: NSLocalizedString("%d%% complete", comment: "Accessibility and status label showing database compaction progress percentage"),
            percentage
        )
    }
    
    /// Whether the current loading state should show the large-database warning.
    private var showsLargeDatabaseWarning: Bool {
        guard case .compacting(_, _, _, let showsLargeDatabaseWarning) = state else { return false }
        return showsLargeDatabaseWarning
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    Image("icon")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                    Text("Optimizing Database", comment: "Title shown during database compaction")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.primary)

                    if let progressPercentageText {
                        Text(progressPercentageText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }

                switch state {
                case .idle, .complete:
                    EmptyView()

                case .compacting(let progress, let stepTitle, let stepDetail, _):
                    VStack(spacing: 20) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .scaleEffect(x: 1, y: 1.4, anchor: .center)
                        
                        VStack(alignment: .leading, spacing: 14) {
                            Text(stepTitle)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(stepDetail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            

                        }
                        .padding(20)
                        .frame(maxWidth: 420, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )

                        Label(
                            showsLargeDatabaseWarning
                            ? NSLocalizedString("Your database is very large, so this optimization may take a few minutes. This is usually a one-time catch-up cost, and future optimizations should be faster once the database has been compacted. Please keep the app open.", comment: "Subtitle shown during long-running compaction when the database is large")
                            : NSLocalizedString("This can take several seconds. Please keep the app open.", comment: "Subtitle shown during long-running database compaction"),
                            systemImage: "clock"
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    }

                case .failed(let error):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 42))
                            .foregroundColor(.orange)

                        VStack(spacing: 8) {
                            Text("Compaction Warning", comment: "Title shown when database compaction encounters an error")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Text("The app can continue, but some storage may not have been freed.", comment: "Message shown when compaction fails but app can continue after acknowledgement")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: continueAfterError) {
                            Text("Continue", comment: "Button title used to continue into the app after acknowledging a compaction error")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: 420)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
    }
}

#Preview {
    CompactionLoadingView(
        state: CompactionView.CompactionState.compacting(
            progress: 0.55,
            stepTitle: "Creating compacted snapshot",
            stepDetail: "Copying data into a smaller optimized database file. This is usually the longest step.",
            showsLargeDatabaseWarning: false
        ),
        continueAfterError: {}
    )
}

#Preview("Large database warning") {
    CompactionLoadingView(
        state: CompactionView.CompactionState.compacting(
            progress: 0.55,
            stepTitle: "Creating compacted snapshot",
            stepDetail: "Copying data into a smaller optimized database file. This is usually the longest step.",
            showsLargeDatabaseWarning: true
        ),
        continueAfterError: {}
    )
}

#Preview("With Error") {
    CompactionLoadingView(
        state: CompactionView.CompactionState.failed(error: "Failed to compact database"),
        continueAfterError: {}
    )
}
