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

/// Tracks the state of database compaction
fileprivate enum CompactionState {
    case idle
    case confirming
    case compacting
    case success
    case failed(String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
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
    @State fileprivate var compaction_state: CompactionState = .idle

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
                }

                // Compact Database Section
                Section(footer: Text("Compaction keeps all profiles and your own notes, removing everything else to free up space. The app will need to restart to apply.", comment: "Explanation of database compaction")) {
                    self.CompactDatabaseButton
                }
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
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
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

    var CompactDatabaseButton: some View {
        Button(action: {
            if case .idle = compaction_state {
                compaction_state = .confirming
            }
        }, label: {
            HStack(spacing: 6) {
                switch compaction_state {
                case .idle, .confirming:
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Compact Database", comment: "Button to compact the NostrDB database.")
                case .compacting:
                    ProgressView()
                    Text("Compacting...", comment: "Loading message indicating database compaction is in progress.")
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Compaction complete. Restart to apply.", comment: "Message indicating compaction succeeded.")
                case .failed(let msg):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                }
            }
        })
        .disabled(!compaction_state.isIdle)
        .alert(
            Text("Compact Database", comment: "Compact database confirmation title"),
            isPresented: Binding(
                get: { if case .confirming = compaction_state { return true } else { return false } },
                set: { if !$0 { compaction_state = .idle } }
            )
        ) {
            Button(NSLocalizedString("Compact", comment: "Confirm compact button"), role: .destructive) {
                compact_database()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                compaction_state = .idle
            }
        } message: {
            Text("This will remove all notes except your own and keep all profiles. The app will need to restart to apply the changes.", comment: "Compact database confirmation message")
        }
    }

    func compact_database() {
        compaction_state = .compacting

        let ndb = damus_state.ndb
        let pubkey = damus_state.pubkey

        Task.detached {
            guard let db_path = Ndb.db_path else {
                await MainActor.run { compaction_state = .failed("Could not find database path") }
                return
            }

            let compact_path = "\(db_path)/compact"
            let fm = FileManager.default

            // Create the compact output directory
            try? fm.createDirectory(atPath: compact_path, withIntermediateDirectories: true)

            do {
                let ok = try ndb.compact(output_path: compact_path, pubkeys: [pubkey])
                await MainActor.run {
                    if ok {
                        compaction_state = .success
                    } else {
                        compaction_state = .failed("Compaction failed")
                    }
                }
            } catch {
                await MainActor.run {
                    compaction_state = .failed("Compaction error: \(error.localizedDescription)")
                }
            }
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
                angle: .value("Size", category.size),
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
