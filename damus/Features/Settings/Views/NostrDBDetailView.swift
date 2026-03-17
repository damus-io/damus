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
        return StorageStatsViewHelper.computeCategoryRanges(for: detailedCategories)
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
                id: dbStat.database.id,
                title: dbStat.database.displayName,
                icon: dbStat.database.icon,
                color: dbStat.database.color,
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
        .padding(.bottom, 50)
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
        // Atomically check/export all needed @State on MainActor
        let (shouldProceed, statsSnapshot): (Bool, StorageStats?) = await MainActor.run {
            let hasDetails = stats.nostrdbDetails != nil
            let notAlreadyPreparing = !isPreparingExport
            if hasDetails && notAlreadyPreparing {
                isPreparingExport = true
                return (true, stats)
            } else {
                return (false, nil)
            }
        }
        guard shouldProceed, let statsSnapshot else { return }

        // Format text off-main
        let text = await StorageStatsViewHelper.formatNostrDBStatsAsText(statsSnapshot)

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
                        NdbDatabaseStats(database: .other, keySize: 0, valueSize: 2000000000),
                        NdbDatabaseStats(database: .note, keySize: 50000, valueSize: 200000),
                        NdbDatabaseStats(database: .noteBlocks, keySize: 100000, valueSize: 50000),
                        NdbDatabaseStats(database: .profile, keySize: 25000, valueSize: 100000),
                        NdbDatabaseStats(database: .noteId, keySize: 75000, valueSize: 75000)
                    ]
                ),
                nostrdbSize: 2500000000,
                snapshotSize: 100000,
                imageCacheSize: 5000000,
                videoCacheSize: 0,
                otherSize: 0
            )
        )
    }
}
