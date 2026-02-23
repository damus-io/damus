//
//  NostrDBDetailView.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-02-23.
//

import SwiftUI
import Charts

/// Detail view displaying NostrDB storage breakdown by kind, indices, and other categories
struct NostrDBDetailView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    let initialStats: StorageStats
    
    @State private var stats: StorageStats
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var selectedAngle: Double?
    @State private var showShareSheet: Bool = false
    @State private var exportText: String?
    @State private var isPreparingExport: Bool = false
    @Environment(\.dismiss) var dismiss
    
    init(damus_state: DamusState, settings: UserSettingsStore, stats: StorageStats) {
        self.damus_state = damus_state
        self.settings = settings
        self.initialStats = stats
        self._stats = State(initialValue: stats)
    }
    
    /// Storage categories with cumulative ranges for angle selection (iOS 17+)
    private var categoryRanges: [(category: String, range: Range<Double>)] {
        guard stats.nostrdbDetails != nil else { return [] }
        
        var total: UInt64 = 0
        return detailedCategories.map { category in
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
            return detailedCategories[selectedIndex]
        }
        
        return nil
    }
    
    /// Detailed categories showing per-database breakdown
    private var detailedCategories: [StorageCategory] {
        guard let details = stats.nostrdbDetails else { return [] }
        
        var result: [StorageCategory] = []
        
        // Per-database categories (sorted by size descending in getStats)
        for dbStat in details.databaseStats {
            result.append(StorageCategory(
                id: "db_\(dbStat.database)",
                title: dbStat.database,
                icon: iconForDatabase(dbStat.database),
                color: colorForDatabase(dbStat.database),
                size: dbStat.totalSize
            ))
        }
        
        return result
    }
    
    var body: some View {
        Form {
            // Chart Section (iOS 17+ only)
            if stats.nostrdbDetails != nil {
                if #available(iOS 17.0, *) {
                    Section {
                        StoragePieChart(
                            categories: detailedCategories,
                            selectedAngle: $selectedAngle,
                            selectedCategory: selectedCategory,
                            totalSize: stats.nostrdbDetails?.totalSize ?? stats.nostrdbSize
                        )
                        .frame(height: 300)
                        .padding(.vertical)
                    }
                }
                
                // Detailed Categories List
                Section {
                    ForEach(detailedCategories) { category in
                        if #available(iOS 17.0, *) {
                            StorageCategoryRow(
                                category: category,
                                percentage: percentageOfNostrDB(for: category.size),
                                isSelected: selectedCategory?.id == category.id
                            )
                        } else {
                            StorageCategoryRow(
                                category: category,
                                percentage: percentageOfNostrDB(for: category.size),
                                isSelected: false
                            )
                        }
                    }
                }
                
                // NostrDB Total
                Section {
                    HStack {
                        Text("NostrDB Total", comment: "Label for total NostrDB storage")
                            .font(.headline)
                        Spacer()
                        Text(StorageStatsManager.formatBytes(stats.nostrdbSize))
                            .foregroundColor(.secondary)
                            .font(.headline)
                    }
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
        .navigationTitle(NSLocalizedString("NostrDB Details", comment: "Navigation title for NostrDB detail view"))
        .toolbar {
            if stats.nostrdbDetails != nil {
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
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
    
    /// Prepare export text on background thread before showing share sheet
    @concurrent
    private func prepareExport() async {
        guard stats.nostrdbDetails != nil, !isPreparingExport else { return }
        
        await MainActor.run {
            isPreparingExport = true
        }
        
        // Capture stats to avoid MainActor isolation issues
        let statsSnapshot = stats
        
        // Format text on background thread
        let text = await formatNostrDBStatsAsText(statsSnapshot)
        
        // Update UI on main thread
        await MainActor.run {
            self.exportText = text
            self.isPreparingExport = false
            self.showShareSheet = true
        }
    }
    
    /// Calculate percentage of NostrDB size
    private func percentageOfNostrDB(for size: UInt64) -> Double {
        guard stats.nostrdbSize > 0 else { return 0.0 }
        return Double(size) / Double(stats.nostrdbSize) * 100.0
    }
    
    /// Load storage statistics asynchronously (for refreshable)
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
    
    // MARK: - Helper Functions
    
    /// Format NostrDB statistics as exportable text
    /// - Parameter stats: The storage statistics containing NostrDB details
    /// - Returns: Formatted text representation of NostrDB stats breakdown
    @concurrent
    private func formatNostrDBStatsAsText(_ stats: StorageStats) async -> String {
        guard let details = stats.nostrdbDetails else {
            return "NostrDB details not available"
        }
        
        var text = "Damus NostrDB Detailed Statistics\n"
        text += "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        // Per-database breakdown (sorted by size, already done in getStats)
        if !details.databaseStats.isEmpty {
            text += "Databases:\n"
            text += String(repeating: "-", count: 50) + "\n"
            
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
            text += "\n"
        }
        
        text += String(repeating: "-", count: 50) + "\n"
        let totalTitlePadded = "NostrDB Total".padding(toLength: 30, withPad: " ", startingAt: 0)
        let totalSizePadded = StorageStatsManager.formatBytes(details.totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
        text += "\(totalTitlePadded) \(totalSizePadded)\n"
        
        return text
    }
    
    /// Get icon for a specific database
    private func iconForDatabase(_ database: String) -> String {
        if database.contains("Notes (NDB_DB_NOTE)") {
            return "text.bubble.fill"
        } else if database.contains("Profiles (NDB_DB_PROFILE)") {
            return "person.circle.fill"
        } else if database.contains("Metadata") {
            return "info.circle.fill"
        } else if database.contains("Note Blocks") {
            return "square.stack.3d.up.fill"
        } else if database.contains("Index") || database.contains("Search") {
            return "list.bullet.indent"
        } else if database.contains("Relay") {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "internaldrive.fill"
        }
    }
    
    /// Get color for a specific database
    private func colorForDatabase(_ database: String) -> Color {
        if database.contains("Notes (NDB_DB_NOTE)") {
            return .green
        } else if database.contains("Profiles (NDB_DB_PROFILE)") {
            return .blue
        } else if database.contains("Note Blocks") {
            return .purple
        } else if database.contains("Metadata") {
            return .orange
        } else if database.contains("Index") || database.contains("Search") {
            return .gray
        } else if database.contains("Relay") {
            return .cyan
        } else {
            return .secondary
        }
    }
}

// MARK: - Preview
#Preview("NostrDB Detail") {
    NavigationStack {
        NostrDBDetailView(
            damus_state: test_damus_state,
            settings: test_damus_state.settings,
            stats: StorageStats(
                nostrdbDetails: NdbStats(
                    databaseStats: [
                        NdbDatabaseStats(database: "Other Data", keySize: 0, valueSize: 2000000000),
                        NdbDatabaseStats(database: "Notes (NDB_DB_NOTE)", keySize: 50000, valueSize: 200000),
                        NdbDatabaseStats(database: "Note Blocks", keySize: 100000, valueSize: 50000),
                        NdbDatabaseStats(database: "Profiles (NDB_DB_PROFILE)", keySize: 25000, valueSize: 100000),
                        NdbDatabaseStats(database: "Note ID Index", keySize: 75000, valueSize: 75000)
                    ]
                ),
                nostrdbSize: 2500000000,
                snapshotSize: 100000,
                imageCacheSize: 5000000
            )
        )
    }
}
