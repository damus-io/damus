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
    
    /// Detailed categories showing per-kind breakdown plus indices and other
    private var detailedCategories: [StorageCategory] {
        guard let details = stats.nostrdbDetails else { return [] }
        
        var result: [StorageCategory] = []
        
        // Per-kind categories - sorted by size descending, filtered to only show non-zero
        let sortedKindStats = details.kindStats
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
        
        for kindStat in sortedKindStats {
            result.append(StorageCategory(
                id: "kind_\(kindStat.kind)",
                title: localizedKindName(kindStat.kind),
                icon: iconForKind(kindStat.kind),
                color: colorForKind(kindStat.kind),
                size: kindStat.totalSize
            ))
        }
        
        // Indices category - only if non-zero
        if details.indicesSize > 0 {
            result.append(StorageCategory(
                id: "indices",
                title: NSLocalizedString("Indices", comment: "Label for database indices"),
                icon: "list.bullet.indent",
                color: .gray,
                size: details.indicesSize
            ))
        }
        
        // Other databases - only if non-zero
        if details.otherSize > 0 {
            result.append(StorageCategory(
                id: "other_dbs",
                title: NSLocalizedString("Other Data", comment: "Label for other database storage"),
                icon: "square.grid.2x2",
                color: .secondary,
                size: details.otherSize
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
    
    /// Get localized display name for a kind
    private func localizedKindName(_ kind: String) -> String {
        switch kind.lowercased() {
        case "profile":
            return NSLocalizedString("Profile", comment: "Label for profile kind")
        case "text":
            return NSLocalizedString("Text Notes", comment: "Label for text note kind")
        case "contacts":
            return NSLocalizedString("Contacts", comment: "Label for contacts kind")
        case "dm":
            return NSLocalizedString("Direct Messages", comment: "Label for DM kind")
        case "reaction":
            return NSLocalizedString("Reactions", comment: "Label for reaction kind")
        case "repost":
            return NSLocalizedString("Reposts", comment: "Label for repost kind")
        case "zap", "zap_request":
            return NSLocalizedString("Zaps", comment: "Label for zap kind")
        case "longform":
            return NSLocalizedString("Long-form", comment: "Label for longform kind")
        case "status":
            return NSLocalizedString("Status", comment: "Label for status kind")
        case "list":
            return NSLocalizedString("Lists", comment: "Label for list kind")
        case "delete":
            return NSLocalizedString("Deletions", comment: "Label for delete kind")
        case "http_auth":
            return NSLocalizedString("HTTP Auth", comment: "Label for HTTP auth kind")
        case "nwc_request", "nwc_response":
            return NSLocalizedString("Wallet Connect", comment: "Label for NWC kind")
        case "other":
            return NSLocalizedString("Other Kinds", comment: "Label for other event kinds")
        default:
            // Capitalize first letter for unknown kinds
            return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }
    
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
        
        // Event Kinds breakdown
        let sortedKindStats = details.kindStats
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
        
        if !sortedKindStats.isEmpty {
            text += "Event Kinds:\n"
            text += String(repeating: "-", count: 50) + "\n"
            
            for kindStat in sortedKindStats {
                let percentage = Self.percentageOfNostrDB(for: kindStat.totalSize, nostrdbSize: stats.nostrdbSize)
                let kindNamePadded = Self.localizedKindName(kindStat.kind).padding(toLength: 25, withPad: " ", startingAt: 0)
                let sizePadded = StorageStatsManager.formatBytes(kindStat.totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
                text += "\(kindNamePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
                text += "  Count: \(kindStat.count), Keys: \(StorageStatsManager.formatBytes(kindStat.keySize)), Values: \(StorageStatsManager.formatBytes(kindStat.valueSize))\n"
            }
            text += "\n"
        }
        
        // Indices
        if details.indicesSize > 0 {
            let percentage = Self.percentageOfNostrDB(for: details.indicesSize, nostrdbSize: stats.nostrdbSize)
            let titlePadded = "Indices".padding(toLength: 25, withPad: " ", startingAt: 0)
            let sizePadded = StorageStatsManager.formatBytes(details.indicesSize).padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(titlePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
        }
        
        // Other
        if details.otherSize > 0 {
            let percentage = Self.percentageOfNostrDB(for: details.otherSize, nostrdbSize: stats.nostrdbSize)
            let titlePadded = "Other Data".padding(toLength: 25, withPad: " ", startingAt: 0)
            let sizePadded = StorageStatsManager.formatBytes(details.otherSize).padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(titlePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
        }
        
        text += String(repeating: "-", count: 50) + "\n"
        let totalTitlePadded = "NostrDB Total".padding(toLength: 25, withPad: " ", startingAt: 0)
        let totalSizePadded = StorageStatsManager.formatBytes(stats.nostrdbSize).padding(toLength: 12, withPad: " ", startingAt: 0)
        text += "\(totalTitlePadded) \(totalSizePadded)\n"
        
        return text
    }
    
    /// Calculate percentage of NostrDB size (static helper)
    /// - Parameters:
    ///   - size: The size to calculate percentage for
    ///   - nostrdbSize: Total NostrDB size
    /// - Returns: Percentage as a double
    private static func percentageOfNostrDB(for size: UInt64, nostrdbSize: UInt64) -> Double {
        guard nostrdbSize > 0 else { return 0.0 }
        return Double(size) / Double(nostrdbSize) * 100.0
    }
    
    /// Get localized display name for a kind (static helper)
    /// - Parameter kind: The kind name
    /// - Returns: Localized display name
    private static func localizedKindName(_ kind: String) -> String {
        switch kind.lowercased() {
        case "profile":
            return NSLocalizedString("Profile", comment: "Label for profile kind")
        case "text":
            return NSLocalizedString("Text Notes", comment: "Label for text note kind")
        case "contacts":
            return NSLocalizedString("Contacts", comment: "Label for contacts kind")
        case "dm":
            return NSLocalizedString("Direct Messages", comment: "Label for DM kind")
        case "reaction":
            return NSLocalizedString("Reactions", comment: "Label for reaction kind")
        case "repost":
            return NSLocalizedString("Reposts", comment: "Label for repost kind")
        case "zap", "zap_request":
            return NSLocalizedString("Zaps", comment: "Label for zap kind")
        case "longform":
            return NSLocalizedString("Long-form", comment: "Label for longform kind")
        case "status":
            return NSLocalizedString("Status", comment: "Label for status kind")
        case "list":
            return NSLocalizedString("Lists", comment: "Label for list kind")
        case "delete":
            return NSLocalizedString("Deletions", comment: "Label for delete kind")
        case "http_auth":
            return NSLocalizedString("HTTP Auth", comment: "Label for HTTP auth kind")
        case "nwc_request", "nwc_response":
            return NSLocalizedString("Wallet Connect", comment: "Label for NWC kind")
        case "other":
            return NSLocalizedString("Other Kinds", comment: "Label for other event kinds")
        default:
            // Capitalize first letter for unknown kinds
            return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }
    
    /// Get icon for a specific kind
    private func iconForKind(_ kind: String) -> String {
        switch kind.lowercased() {
        case "profile": return "person.circle.fill"
        case "text": return "text.bubble.fill"
        case "contacts": return "person.2.fill"
        case "dm": return "envelope.fill"
        case "reaction": return "heart.fill"
        case "repost": return "arrow.2.squarepath"
        case "zap", "zap_request": return "bolt.fill"
        case "longform": return "doc.text.fill"
        case "status": return "bubble.left.fill"
        case "list": return "list.bullet"
        case "delete": return "trash.fill"
        case "http_auth": return "key.fill"
        case "nwc_request", "nwc_response": return "wallet.pass.fill"
        default: return "doc.fill"
        }
    }
    
    /// Get color for a specific kind
    private func colorForKind(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "profile": return .blue
        case "text": return .green
        case "contacts": return .cyan
        case "dm": return .pink
        case "reaction": return .red
        case "repost": return .teal
        case "zap", "zap_request": return .yellow
        case "longform": return .indigo
        case "status": return .mint
        case "list": return .purple
        case "delete": return .orange
        case "http_auth": return .brown
        case "nwc_request", "nwc_response": return .blue
        default: return .gray
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
                    kindStats: [
                        NdbKindStats(kind: "text", count: 1000, keySize: 50000, valueSize: 200000),
                        NdbKindStats(kind: "profile", count: 500, keySize: 25000, valueSize: 100000),
                        NdbKindStats(kind: "reaction", count: 2000, keySize: 100000, valueSize: 50000)
                    ],
                    indicesSize: 150000,
                    otherSize: 50000
                ),
                nostrdbSize: 725000,
                snapshotSize: 100000,
                imageCacheSize: 5000000
            )
        )
    }
}
