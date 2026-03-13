//
//  StorageStatsViewHelper.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-02-25.
//

import Foundation
import SwiftUI

/// Shared helper functions for storage statistics views
/// Consolidates common logic between StorageSettingsView and NostrDBDetailView
enum StorageStatsViewHelper {
    
    // MARK: - Category Ranges
    
    /// Computes cumulative ranges for angle selection in pie charts (iOS 17+)
    /// - Parameter categories: Array of storage categories
    /// - Returns: Array of tuples containing category ID and cumulative range
    static func computeCategoryRanges(for categories: [StorageCategory]) -> [(category: String, range: Range<Double>)] {
        var total: UInt64 = 0
        return categories.map { category in
            let newTotal = total + category.size
            let result = (category: category.id, range: Double(total)..<Double(newTotal))
            total = newTotal
            return result
        }
    }
    
    // MARK: - Storage Stats Loading
    
    /// Load storage statistics asynchronously
    /// - Parameter ndb: The NostrDB instance
    /// - Returns: Calculated storage statistics
    /// - Throws: Error if storage calculation fails
    @concurrent
    static func loadStorageStatsAsync(ndb: Ndb) async throws -> StorageStats {
        return try await StorageStatsManager.shared.calculateStorageStats(ndb: ndb)
    }
    
    // MARK: - Export Preparation
    
    /// Prepare export text for storage statistics on background thread
    /// - Parameters:
    ///   - stats: The storage statistics to export
    ///   - formatter: Closure that formats the stats into text
    /// - Returns: Formatted text ready for export
    @concurrent
    static func prepareExportText(
        stats: StorageStats,
        formatter: @escaping @concurrent (StorageStats) async -> String
    ) async -> String {
        return await formatter(stats)
    }
    
    // MARK: - Text Formatting
    
    /// Format storage statistics as exportable text
    /// - Parameter stats: The storage statistics to format
    /// - Returns: Formatted text representation of storage stats
    @concurrent
    static func formatStorageStatsAsText(_ stats: StorageStats) async -> String {
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
            text += await formatNostrDBDetails(details: details)
        }
        
        // Full container file listing for debugging orphaned files
        text += await formatContainerFileBreakdown()
        
        return text
    }
    
    /// Format NostrDB statistics as exportable text
    /// - Parameter stats: The storage statistics containing NostrDB details
    /// - Returns: Formatted text representation of NostrDB stats breakdown
    @concurrent
    static func formatNostrDBStatsAsText(_ stats: StorageStats) async -> String {
        guard let details = stats.nostrdbDetails else {
            return "NostrDB details not available"
        }
        
        var text = "Damus NostrDB Detailed Statistics\n"
        text += "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        text += await formatNostrDBDetails(details: details)
        
        return text
    }
    
    // MARK: - Private Helpers
    
    /// Format NostrDB details section
    /// - Parameter details: The NostrDB statistics details
    /// - Returns: Formatted text representation of NostrDB details
    @concurrent
    private static func formatNostrDBDetails(details: NdbStats) async -> String {
        var text = String(repeating: "=", count: 50) + "\n\n"
        text += "NostrDB Detailed Breakdown:\n"
        text += String(repeating: "-", count: 50) + "\n"
        
        // Per-database breakdown (sorted by size, already done in getStats)
        if !details.databaseStats.isEmpty {
            text += "\nDatabases:\n"
            
            for dbStat in details.databaseStats {
                let percentage = details.totalSize > 0 ? Double(dbStat.totalSize) / Double(details.totalSize) * 100.0 : 0.0
                let dbNamePadded = dbStat.database.displayName.padding(toLength: 30, withPad: " ", startingAt: 0)
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
        
        return text
    }
    
    /// Enumerate all files in the app sandbox and shared app group container and format them as text.
    ///
    /// Files are sorted by size descending so the largest contributors appear first,
    /// making orphaned or unexpectedly large files easy to identify.
    ///
    /// - Returns: Formatted text listing every file with its size and relative path.
    @concurrent
    private static func formatContainerFileBreakdown() async -> String {
        let entries = StorageStatsManager.shared.containerFileBreakdown()
        
        var text = String(repeating: "=", count: 50) + "\n\n"
        text += "Full Container File Breakdown:\n"
        text += String(repeating: "-", count: 50) + "\n"
        
        if entries.isEmpty {
            text += "(no files found)\n"
        } else {
            var totalSize: UInt64 = 0
            for entry in entries {
                let sizePadded = StorageStatsManager.formatBytes(entry.size).padding(toLength: 12, withPad: " ", startingAt: 0)
                text += "[\(entry.containerLabel)] \(sizePadded)  \(entry.relativePath)\n"
                totalSize += entry.size
            }
            text += String(repeating: "-", count: 50) + "\n"
            let totalTitlePadded = "Total (all files)".padding(toLength: 25, withPad: " ", startingAt: 0)
            let totalSizePadded = StorageStatsManager.formatBytes(totalSize).padding(toLength: 12, withPad: " ", startingAt: 0)
            text += "\(totalTitlePadded) \(totalSizePadded)\n"
        }
        
        return text
    }
}
