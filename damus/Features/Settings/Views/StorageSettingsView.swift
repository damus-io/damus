//
//  StorageSettingsView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-02-20.
//

import SwiftUI
import Charts

fileprivate let CACHE_CLEAR_BUTTON_RESET_TIME_IN_SECONDS: Double = 60
fileprivate let MINIMUM_CACHE_CLEAR_BUTTON_DELAY_IN_SECONDS: Double = 1

/// A simple type to keep track of the cache clearing state
fileprivate enum CacheClearingState {
    case not_cleared
    case clearing
    case cleared
}

/// A simple type to keep track of a user-initiated prune.
///
/// A prune takes minutes on a real database, so the button spends most of its
/// life in `.pruning` and the view must stay usable throughout.
fileprivate enum ManualPruneState: Equatable {
    case idle
    case pruning
    /// Finished, with what to show for it.
    case finished(ManualPruneMessage)
}

/// What the button shows once a prune has finished.
fileprivate struct ManualPruneMessage: Equatable {
    let text: String

    /// Whether the button stays tappable.
    ///
    /// `false` only once a pruned copy is staged, when the sole remaining step
    /// is a restart. Everything else — no budget set, no room on the volume —
    /// is something the user can go and fix, so the button has to still be
    /// there when they come back to it.
    let canRetry: Bool

    /// Whether this wants the user's attention rather than reporting success.
    let isProblem: Bool
}

/// Storage category for display in list and chart
struct StorageCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let size: UInt64
    
    var range: Range<Double> {
        return 0..<Double(size)
    }
}

/// Settings view displaying storage usage statistics for Damus data stores
struct StorageSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss
    
    @State private var stats: StorageStats?
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var selectedAngle: Double?
    @State private var showShareSheet: Bool = false
    @State private var exportText: String?
    @State private var isPreparingExport: Bool = false
    @State fileprivate var cache_clearing_state: CacheClearingState = .not_cleared
    @State var showing_cache_clear_alert: Bool = false
    @State fileprivate var manual_prune_state: ManualPruneState = .idle
    @State var showing_prune_alert: Bool = false
    @State fileprivate var space_budget: NdbSpaceBudget = Ndb.get_space_budget()
    
    /// Storage categories with cumulative ranges for angle selection (iOS 17+)
    private var categoryRanges: [(category: String, range: Range<Double>)] {
        guard let stats = stats else { return [] }
        return StorageStatsViewHelper.computeCategoryRanges(for: categories)
    }
    
    /// Selected storage category based on pie chart interaction (iOS 17+)
    private var selectedCategory: StorageCategory? {
        guard let selectedAngle = selectedAngle else { return nil }
        
        if let selectedIndex = categoryRanges.firstIndex(where: { $0.range.contains(selectedAngle) }) {
            return categories[selectedIndex]
        }
        
        return nil
    }
    
    /// All storage categories for display (top-level view)
    private var categories: [StorageCategory] {
        guard let stats = stats else { return [] }
        
        return [
            StorageCategory(
                id: "nostrdb",
                title: NSLocalizedString("NostrDB", comment: "Label for main NostrDB database"),
                icon: "internaldrive.fill",
                color: .blue,
                size: stats.nostrdbSize
            ),
            StorageCategory(
                id: "snapshot",
                title: NSLocalizedString("Snapshot Database", comment: "Label for snapshot database"),
                icon: "doc.on.doc.fill",
                color: .purple,
                size: stats.snapshotSize
            ),
            StorageCategory(
                id: "cache",
                title: NSLocalizedString("Image Cache", comment: "Label for Kingfisher image cache"),
                icon: "photo.fill",
                color: .orange,
                size: stats.imageCacheSize
            )
        ]
    }
    
    var body: some View {
        Form {
            // Chart Section (iOS 17+ only)
            if let stats = stats {
                if #available(iOS 17.0, *) {
                    Section {
                        StoragePieChart(
                            categories: categories,
                            selectedAngle: $selectedAngle,
                            selectedCategory: selectedCategory,
                            totalSize: stats.totalSize
                        )
                        .frame(height: 300)
                        .padding(.vertical)
                    }
                }
                
                // Categories List
                Section {
                    ForEach(categories) { category in
                        if category.id == "nostrdb", stats.nostrdbDetails != nil {
                            // NostrDB is drillable when we have detailed stats
                            NavigationLink(value: Route.NostrDBStorageDetail(stats: stats)) {
                                if #available(iOS 17.0, *) {
                                    StorageCategoryRow(
                                        category: category,
                                        percentage: stats.percentage(for: category.size),
                                        isSelected: selectedCategory?.id == category.id
                                    )
                                } else {
                                    StorageCategoryRow(
                                        category: category,
                                        percentage: stats.percentage(for: category.size),
                                        isSelected: false
                                    )
                                }
                            }
                        } else {
                            // Other categories are not drillable
                            if #available(iOS 17.0, *) {
                                StorageCategoryRow(
                                    category: category,
                                    percentage: stats.percentage(for: category.size),
                                    isSelected: selectedCategory?.id == category.id
                                )
                            } else {
                                StorageCategoryRow(
                                    category: category,
                                    percentage: stats.percentage(for: category.size),
                                    isSelected: false
                                )
                            }
                        }
                    }
                }
                
                // Total at bottom
                Section {
                    HStack {
                        Text("Total Storage", comment: "Label for total storage used")
                            .font(.headline)
                        Spacer()
                        Text(StorageStatsManager.formatBytes(stats.totalSize))
                            .foregroundColor(.secondary)
                            .font(.headline)
                    }
                }
                
                // Clear Cache Section
                Section {
                    self.ClearCacheButton
                    self.FreeUpSpaceButton
                }

                // Space budget Section
                self.SpaceBudgetSection
            }
            
            // Loading state
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            
            // Error state
            if let error = error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .padding(.bottom, 50)
        .navigationTitle(NSLocalizedString("Storage", comment: "Navigation title for storage settings"))
        .toolbar {
            if stats != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await prepareExport() } }) {
                        if isPreparingExport {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isPreparingExport)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportText = exportText {
                TextShareSheet(activityItems: [exportText])
            }
        }
        .refreshable {
            await loadStorageStatsAsync()
        }
        .onAppear {
            if stats == nil {
                loadStorageStats()
            }
            // A copy staged by an earlier session — or by this screen before the
            // user navigated away — is waiting for the next launch, and saying
            // so is more useful than offering to redo the work.
            if let message = Self.pending_prune_message(), manual_prune_state == .idle {
                manual_prune_state = .finished(message)
            }
        }
    }
    
    /// Prepare export text on background thread before showing share sheet
    @concurrent
    private func prepareExport() async {
        // Capture all relevant @State in one MainActor.run
        let (shouldProceed, statsSnapshot): (Bool, StorageStats?) = await MainActor.run {
            let hasStats = stats != nil
            let notAlreadyPreparing = !isPreparingExport
            if hasStats && notAlreadyPreparing {
                isPreparingExport = true
                return (true, stats)
            } else {
                return (false, nil)
            }
        }
        guard shouldProceed, let statsSnapshot else { return }

        // Format text on background thread using shared helper
        let text = await StorageStatsViewHelper.formatStorageStatsAsText(statsSnapshot)

        // Update UI on main thread
        await MainActor.run {
            self.exportText = text
            self.isPreparingExport = false
            self.showShareSheet = true
        }
    }
    
    /// Load storage statistics on a background thread (for onAppear)
    private func loadStorageStats() {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        Task {
            await loadStorageStatsAsync()
        }
    }
    
    /// Load storage statistics asynchronously (for refreshable)
    @concurrent
    private func loadStorageStatsAsync() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let calculatedStats = try await StorageStatsViewHelper.loadStorageStatsAsync(ndb: damus_state.ndb)
            await MainActor.run {
                self.stats = calculatedStats
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = String(format: NSLocalizedString("Failed to calculate storage: %@", comment: "Error message when storage calculation fails"), error.localizedDescription)
                self.isLoading = false
            }
        }
    }
    
    /// Clear cache button action with loading state management
    func clear_cache_button_action() {
        cache_clearing_state = .clearing
        
        let group = DispatchGroup()
        
        group.enter()
        DamusCacheManager.shared.clear_cache(damus_state: self.damus_state, completion: {
            group.leave()
        })
        
        // Make clear cache button take at least a second or so to avoid issues with labor perception bias (https://growth.design/case-studies/labor-perception-bias)
        group.enter()
        DispatchQueue.main.asyncAfter(deadline: .now() + MINIMUM_CACHE_CLEAR_BUTTON_DELAY_IN_SECONDS) {
            group.leave()
        }
        
        group.notify(queue: .main) {
            cache_clearing_state = .cleared
            
            // Refresh storage stats after clearing cache
            loadStorageStats()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + CACHE_CLEAR_BUTTON_RESET_TIME_IN_SECONDS) {
                cache_clearing_state = .not_cleared
            }
        }
    }
    
    /// Clear cache button view with confirmation dialog
    var ClearCacheButton: some View {
        Button(action: { self.showing_cache_clear_alert = true }, label: {
            HStack(spacing: 6) {
                switch cache_clearing_state {
                    case .not_cleared:
                        Text("Clear Cache", comment: "Button to clear image cache.")
                    case .clearing:
                        ProgressView()
                        Text("Clearing Cache", comment: "Loading message indicating that the cache is being cleared.")
                    case .cleared:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Cache has been cleared", comment: "Message indicating that the cache was successfully cleared.")
                }
            }
        })
        .disabled(self.cache_clearing_state != .not_cleared)
        .alert(isPresented: $showing_cache_clear_alert) {
            Alert(title: Text("Confirmation", comment: "Confirmation dialog title"),
                  message: Text("Are you sure you want to clear the cache? This will free space, but images may take longer to load again.", comment: "Message explaining what it means to clear the cache, asking if user wants to proceed."),
                  primaryButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                      self.clear_cache_button_action()
                  },
                  secondaryButton: .cancel())
        }
    }

    /// Section that caps how much space the database may take up.
    ///
    /// The budget is purely what triggers a background prune: once `data.mdb`
    /// grows past it, damus clears the cache down to the notes it cannot get
    /// back — the user's own, and everyone's profiles — and the timeline refills
    /// from relays. So the database lands far under the budget rather than near
    /// it, and crossing the budget again is what triggers the next prune.
    var SpaceBudgetSection: some View {
        Section(
            header: Text("Database Size Limit", comment: "Section header for the setting capping how much space the database may use"),
            footer: SpaceBudgetCaption
        ) {
            Picker(
                NSLocalizedString("Maximum database size", comment: "Setting label for choosing how much space the database may use"),
                selection: $space_budget
            ) {
                ForEach(NdbSpaceBudget.allCases, id: \.self) { option in
                    Text(option.text_description()).tag(option)
                }
            }
            .onChange(of: space_budget) { newBudget in
                Ndb.set_space_budget(newBudget)
            }

            HStack {
                Text("Current size", comment: "Label for how much space the database is using right now")
                Spacer()
                Text(currentDatabaseSizeDescription)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Caption displayed below the space budget picker, describing what the
    /// selected budget will do.
    private var SpaceBudgetCaption: some View {
        Group {
            if space_budget == .unlimited {
                Text("The database is never trimmed, and will keep growing as you use Damus.", comment: "Caption shown when the database size is not capped")
            } else {
                Text("When the database grows past this size, Damus clears out cached notes in the background and downloads them again as you browse. Your own notes and everyone\u{2019}s profiles are always kept.", comment: "Caption explaining what happens when the database grows past the size limit")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    /// How much space `data.mdb` takes up right now.
    private var currentDatabaseSizeDescription: String {
        guard let path = Ndb.db_path, let size = Ndb.database_file_size(path: path) else {
            return NSLocalizedString("Unknown", comment: "Placeholder shown when the size of the database cannot be determined")
        }
        return StorageStatsManager.formatBytes(size)
    }

    /// Shown once a pruned copy is staged and only a restart is left, when there
    /// is no measuring how much smaller it is.
    fileprivate static let restart_to_apply_message = ManualPruneMessage(
        text: NSLocalizedString(
            "Space will be freed the next time you open Damus.",
            comment: "Message indicating that a pruned database copy is ready and will be applied on the next app launch."
        ),
        canRetry: false,
        isProblem: false
    )

    /// Shown when a prune staged a copy no smaller than the database it came
    /// from.
    ///
    /// Not a failure: a database already down to profiles and the user's own
    /// notes prunes to roughly itself, and there is genuinely nothing left to
    /// free. Quoting the figure anyway — "Frees up 0 bytes" — would read as one.
    fileprivate static let nothing_to_free_message = ManualPruneMessage(
        text: NSLocalizedString(
            "Your database is already as small as it can get.",
            comment: "Message shown when trimming the database would not free up any meaningful amount of space."
        ),
        canRetry: false,
        isProblem: false
    )

    /// Says how much smaller a staged copy is than the database in use.
    ///
    /// Future tense throughout, and deliberately so. The prune wrote a second
    /// database beside the live one and has not touched the live one, so nothing
    /// is free yet — the volume has *less* room until the swap at the next
    /// launch. A message in the past tense would be contradicted by the very
    /// storage figures on this screen.
    ///
    /// - Parameter saving: What the swap will save, or `nil` if the staged copy
    ///   could not be measured.
    fileprivate static func staged_message(saving: NdbPruneSaving?) -> ManualPruneMessage {
        guard let saving else { return restart_to_apply_message }
        guard !saving.isNegligible else { return nothing_to_free_message }

        let format = NSLocalizedString(
            "Frees up %@ the next time you open Damus.",
            comment: "Message saying how much space a staged pruned database copy will free up once it is applied at the next app launch."
        )
        return ManualPruneMessage(
            text: String(format: format, StorageStatsManager.formatBytes(saving.savedBytes)),
            canRetry: false,
            isProblem: false
        )
    }

    /// The message for a copy already staged and waiting, if there is one.
    ///
    /// Measured here rather than remembered from the prune that staged it: the
    /// copy usually outlives the screen, and often the process.
    fileprivate static func pending_prune_message() -> ManualPruneMessage? {
        guard let pending = Ndb.get_pending_prune() else { return nil }
        let saving = Ndb.db_path
            .flatMap({ Ndb.database_file_size(path: $0) })
            .flatMap({ NdbPruneSaving(sizeBefore: $0, stagedPath: pending.path) })
        return staged_message(saving: saving)
    }

    /// Whether the button can be pressed right now.
    fileprivate var manual_prune_is_available: Bool {
        switch manual_prune_state {
        case .idle: return true
        case .pruning: return false
        case .finished(let message): return message.canRetry
        }
    }

    /// Free-up-space button view with confirmation dialog.
    ///
    /// Clears the cache right now, instead of waiting for the database to grow
    /// past the size limit on its own. The work happens on a background queue
    /// against a copy — the database stays usable and this screen stays
    /// interactive throughout — and the copy is swapped in at the next launch,
    /// which is why the success message asks for nothing but patience.
    var FreeUpSpaceButton: some View {
        Button(action: { self.showing_prune_alert = true }, label: {
            HStack(spacing: 6) {
                switch manual_prune_state {
                    case .idle:
                        Text("Free Up Space Now", comment: "Button to trim the NostrDB database down to the size limit immediately.")
                    case .pruning:
                        ProgressView()
                        Text("Freeing up space\u{2026} This can take a few minutes.", comment: "Loading message indicating that the database is being trimmed in the background.")
                    case .finished(let message):
                        Image(systemName: message.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(message.isProblem ? .orange : .green)
                            .accessibilityHidden(true)
                        Text(message.text)
                }
            }
        })
        // Left enabled without a budget on purpose: a greyed-out button explains
        // nothing, and the outcome message says exactly what to do instead —
        // which only helps if the user can then come back and press it.
        .disabled(!self.manual_prune_is_available)
        .alert(isPresented: $showing_prune_alert) {
            Alert(
                title: Text("Free Up Space", comment: "Confirmation dialog title for trimming the database"),
                message: Text("This clears out cached notes, keeping your own notes and everyone\u{2019}s profiles. The rest is downloaded again as you browse. It runs in the background and takes effect the next time you open Damus. Proceed?", comment: "Message explaining what freeing up space does and when it takes effect."),
                primaryButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                    self.free_up_space_button_action()
                },
                secondaryButton: .cancel()
            )
        }
    }

    /// Kicks off a user-initiated prune and reports what it did.
    ///
    /// Deliberately fire-and-forget: the prune outlives this screen easily, and
    /// the actor keeps running it whether or not anyone is watching. If the user
    /// navigates away the result is simply not shown — reopening the screen
    /// picks up the staged copy in `onAppear`.
    fileprivate func free_up_space_button_action() {
        manual_prune_state = .pruning

        Task {
            let message: ManualPruneMessage
            do {
                message = Self.describe(outcome: try await damus_state.pruneManager.pruneNow())
            } catch {
                Log.error("Manual prune failed: %@", for: .storage, String(describing: error))
                DamusSentry.captureSentryError(error) { scope in
                    scope.setContext(value: ["operation": "manual_prune"], key: "storage")
                    // `ndb_prune` writes the real cause to stderr, which is gone
                    // by the time anyone reads the report. `NdbPruneError`
                    // carries it instead — the failing phase, the LMDB rc and
                    // how far the copy got — so a field failure is diagnosable
                    // from the report alone.
                    if let pruneError = error as? NdbPruneError {
                        scope.setContext(value: pruneError.reportContext, key: "ndb_prune")
                    }
                }
                message = ManualPruneMessage(
                    text: String(
                        format: NSLocalizedString("Could not free up space: %@", comment: "Error message shown when a user-initiated database trim fails"),
                        error.localizedDescription
                    ),
                    canRetry: true,
                    isProblem: true
                )
            }

            await MainActor.run {
                manual_prune_state = .finished(message)
                loadStorageStats()
            }
        }
    }

    /// Turns a prune outcome into the one line the button has room for.
    fileprivate static func describe(outcome: ManualPruneOutcome) -> ManualPruneMessage {
        switch outcome {
        case .staged(let saving):
            return staged_message(saving: saving)
        case .alreadyStaged(let saving):
            return staged_message(saving: saving)
        case .alreadyRunning:
            return ManualPruneMessage(
                text: NSLocalizedString("Already freeing up space in the background.", comment: "Message shown when a database trim was already running"),
                canRetry: true,
                isProblem: false
            )
        case .noBudget:
            return ManualPruneMessage(
                text: NSLocalizedString("Set a database size limit first.", comment: "Message shown when a database trim was requested with no size limit set"),
                canRetry: true,
                isProblem: true
            )
        case .notEnoughFreeSpace(let neededBytes, let availableBytes):
            let format = NSLocalizedString("Not enough free space: %@ needed, %@ available.", comment: "Message shown when there is not enough disk space to trim the database")
            return ManualPruneMessage(
                text: String(format: format,
                             StorageStatsManager.formatBytes(neededBytes),
                             StorageStatsManager.formatBytes(availableBytes)),
                canRetry: true,
                isProblem: true
            )
        case .noDatabase:
            return ManualPruneMessage(
                text: NSLocalizedString("No database to free up space in.", comment: "Message shown when a database trim was requested but there is no database"),
                canRetry: true,
                isProblem: true
            )
        }
    }
}

/// Pie chart displaying storage usage distribution (iOS 17+)
@available(iOS 17.0, *)
struct StoragePieChart: View {
    let categories: [StorageCategory]
    @Binding var selectedAngle: Double?
    let selectedCategory: StorageCategory?
    let totalSize: UInt64
    
    var body: some View {
        Chart(categories) { category in
            SectorMark(
                angle: .value(NSLocalizedString("Size", comment: "Label for size in disk storage chart"), category.size),
                innerRadius: .ratio(0.618),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(category.color)
            .opacity(selectedCategory == nil || selectedCategory?.id == category.id ? 1.0 : 0.5)
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { chartProxy in
            GeometryReader { geometry in
                if let anchor = chartProxy.plotFrame {
                    let frame = geometry[anchor]
                    centerLabel
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    /// Center label showing selected category or total
    private var centerLabel: some View {
        VStack(spacing: 4) {
            if let selected = selectedCategory {
                Image(systemName: selected.icon)
                    .font(.title2)
                    .foregroundColor(selected.color)
                Text(selected.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(StorageStatsManager.formatBytes(selected.size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Total", comment: "Label for total storage in pie chart center")
                    .font(.headline)
                Text(StorageStatsManager.formatBytes(totalSize))
                    .font(.title2)
                    .bold()
            }
        }
        .frame(maxWidth: 120)
    }
}

/// Row displaying a storage category with icon, name, size, and percentage
struct StorageCategoryRow: View {
    let category: StorageCategory
    let percentage: Double
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundColor(category.color)
                .frame(width: 24)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.body)
                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(StorageStatsManager.formatBytes(category.size))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(isSelected ? 1.0 : 0.9)
    }
}

/// Text-based ShareSheet wrapper for SwiftUI
struct TextShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview
#Preview("Storage Settings") {
    NavigationStack {
        StorageSettingsView(
            damus_state: test_damus_state,
            settings: test_damus_state.settings
        )
    }
}
