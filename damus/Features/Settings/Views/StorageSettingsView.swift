//
//  StorageSettingsView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-02-20.
//

import SwiftUI
import Charts

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
            
            // Event Kinds breakdown
            let sortedKindStats = details.kindStats
                .filter { $0.totalSize > 0 }
                .sorted { $0.totalSize > $1.totalSize }
            
            if !sortedKindStats.isEmpty {
                text += "\nEvent Kinds:\n"
                
                for kindStat in sortedKindStats {
                    let percentage = stats.nostrdbSize > 0 ? Double(kindStat.totalSize) / Double(stats.nostrdbSize) * 100.0 : 0.0
                    let kindNamePadded = localizedNostrDBKindName(kindStat.kind).padding(toLength: 25, withPad: " ", startingAt: 0)
                    let sizePadded = StorageStatsManager.formatBytes(kindStat.totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
                    text += "\(kindNamePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
                    text += "  Count: \(kindStat.count), Keys: \(StorageStatsManager.formatBytes(kindStat.keySize)), Values: \(StorageStatsManager.formatBytes(kindStat.valueSize))\n"
                }
            }
            
            // Indices
            if details.indicesSize > 0 {
                let percentage = stats.nostrdbSize > 0 ? Double(details.indicesSize) / Double(stats.nostrdbSize) * 100.0 : 0.0
                text += "\n"
                let titlePadded = "Indices".padding(toLength: 25, withPad: " ", startingAt: 0)
                let sizePadded = StorageStatsManager.formatBytes(details.indicesSize).padding(toLength: 12, withPad: " ", startingAt: 0)
                text += "\(titlePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
            }
            
            // Other
            if details.otherSize > 0 {
                let percentage = stats.nostrdbSize > 0 ? Double(details.otherSize) / Double(stats.nostrdbSize) * 100.0 : 0.0
                let titlePadded = "Other Data".padding(toLength: 25, withPad: " ", startingAt: 0)
                let sizePadded = StorageStatsManager.formatBytes(details.otherSize).padding(toLength: 12, withPad: " ", startingAt: 0)
                text += "\(titlePadded) \(sizePadded) (\(String(format: "%.1f", percentage))%)\n"
            }
            
            text += "\n" + String(repeating: "-", count: 50) + "\n"
            let nostrdbTitlePadded = "NostrDB Total".padding(toLength: 25, withPad: " ", startingAt: 0)
            let nostrdbSizePadded = StorageStatsManager.formatBytes(stats.nostrdbSize).padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(nostrdbTitlePadded) \(nostrdbSizePadded)\n"
        }
        
        return text
    }
    
    /// Get localized display name for a NostrDB kind (helper for export)
    /// - Parameter kind: The kind name
    /// - Returns: Localized display name
    private func localizedNostrDBKindName(_ kind: String) -> String {
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
