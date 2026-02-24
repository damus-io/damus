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
    @State private var showing_compact_db_alert: Bool = false
    @State private var showing_compaction_requested_alert: Bool = false
    
    /// Storage categories with cumulative ranges for angle selection (iOS 17+)
    private var categoryRanges: [(category: String, range: Range<Double>)] {
        guard let stats = stats else { return [] }
        
        var total: UInt64 = 0
        return categories.map { category in
            let newTotal = total + category.size
            let result = (category: category.id, range: Double(total)..<Double(newTotal))
            total = newTotal
            return result
        }
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
                Section {
                    self.CompactDatabaseButton
                } header: {
                    Text("Database Compaction", comment: "Header for database compaction section")
                } footer: {
                    Text("Compacts your database to keep only your own posts and all profiles. This can significantly reduce storage usage but will remove other people's posts from your local database. Your data will remain on relays.", comment: "Footer explaining database compaction feature")
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
        .alert(isPresented: $showing_compaction_requested_alert) {
            Alert(
                title: Text("Compaction Requested", comment: "Alert title when compaction is requested"),
                message: Text("The database will be compacted on next app launch. Please restart the app now.", comment: "Alert message explaining app needs to restart for compaction"),
                primaryButton: .default(Text("Restart Now", comment: "Button to restart the app")) {
                    // Request app restart
                    exit(0)
                },
                secondaryButton: .cancel(Text("Later", comment: "Button to defer action"))
            )
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
        guard stats != nil, !isPreparingExport else { return }
        
        await MainActor.run {
            isPreparingExport = true
        }
        
        // Capture stats to avoid MainActor isolation issues
        guard let statsSnapshot = stats else {
            await MainActor.run {
                isPreparingExport = false
            }
            return
        }
        
        // Format text on background thread
        let text = await formatStorageStatsAsText(statsSnapshot)
        
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
            let calculatedStats = try await StorageStatsManager.shared.calculateStorageStats(ndb: damus_state.ndb)
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
    
    /// Compact database button view with confirmation dialog
    var CompactDatabaseButton: some View {
        Button(action: { self.showing_compact_db_alert = true }, label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                Text("Compact Database", comment: "Button to compact the database to save storage space.")
            }
        })
        .alert(isPresented: $showing_compact_db_alert) {
            Alert(
                title: Text("Compact Database?", comment: "Confirmation dialog title for database compaction"),
                message: Text("This will create a new compact database containing only your posts and all profiles. Other people's posts will be removed from your local database but remain on relays. The app will restart when complete. This may take a few minutes.", comment: "Explanation of database compaction process"),
                primaryButton: .default(Text("Compact", comment: "Button label to proceed with database compaction")) {
                    self.compact_database_action()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    /// Request database compaction
    func compact_database_action() {
        Task {
            await damus_state.compactionManager.requestCompaction()
            
            // Show alert that app will restart
            await MainActor.run {
                showing_compaction_requested_alert = true
            }
        }
    }
    
    /// Format storage statistics as exportable text
    /// - Parameter stats: The storage statistics to format
    /// - Returns: Formatted text representation of storage stats
    @concurrent
    private func formatStorageStatsAsText(_ stats: StorageStats) async -> String {
        // Build categories list
        let categories = [
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
        
        var text = "Damus Storage Statistics\n"
        text += "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        // Top-level Categories
        text += "Storage Breakdown:\n"
        text += String(repeating: "-", count: 50) + "\n"
        
        for category in categories {
            let percentage = stats.percentage(for: category.size)
            let titlePadded = category.title.padding(toLength: 25, withPad: " ", startingAt: 0)
            let sizePadded = StorageStatsManager.formatBytes(category.size).padding(toLength: 10, withPad: " ", startingAt: 0)
            text += "\(titlePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
        }
        
        text += String(repeating: "-", count: 50) + "\n"
        let totalTitlePadded = "Total Storage".padding(toLength: 25, withPad: " ", startingAt: 0)
        let totalSizePadded = StorageStatsManager.formatBytes(stats.totalSize).padding(toLength: 10, withPad: " ", startingAt: 0)
        text += "\(totalTitlePadded) \(totalSizePadded)\n\n"
        
        // Add NostrDB detailed breakdown if available
        if let details = stats.nostrdbDetails {
            text += String(repeating: "=", count: 50) + "\n\n"
            text += "NostrDB Detailed Breakdown:\n"
            text += String(repeating: "-", count: 50) + "\n"
            
            // Per-database breakdown (sorted by size, already done in getStats)
            if !details.databaseStats.isEmpty {
                text += "\nDatabases:\n"
                
                for dbStat in details.databaseStats {
                    let percentage = details.totalSize > 0 ? Double(dbStat.totalSize) / Double(details.totalSize) * 100.0 : 0.0
                    let dbNamePadded = dbStat.database.padding(toLength: 30, withPad: " ", startingAt: 0)
                    let sizePadded = StorageStatsManager.formatBytes(dbStat.totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
                    text += "\(dbNamePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
                    
                    // Only show keys/values breakdown if both exist
                    if dbStat.keySize > 0 && dbStat.valueSize > 0 {
                        text += "  Keys: \(StorageStatsManager.formatBytes(dbStat.keySize)), Values: \(StorageStatsManager.formatBytes(dbStat.valueSize))\n"
                    }
                }
            }
            
            text += "\n" + String(repeating: "-", count: 50) + "\n"
            let nostrdbTitlePadded = "NostrDB Total".padding(toLength: 30, withPad: " ", startingAt: 0)
            let nostrdbSizePadded = StorageStatsManager.formatBytes(details.totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(nostrdbTitlePadded) \(nostrdbSizePadded)\n"
        }
        
        return text
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
