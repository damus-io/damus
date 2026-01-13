//
//  TextDiff.swift
//  damus
//
//  Created for issue #3517 - Display longform article edit history
//

import Foundation

/// Represents a single change in a diff.
enum DiffChange: Equatable {
    case unchanged(String)
    case added(String)
    case removed(String)
}

/// A simple line-based diff algorithm using longest common subsequence (LCS).
///
/// This computes the differences between two texts at the line level,
/// identifying which lines were added, removed, or unchanged.
struct TextDiff {
    let changes: [DiffChange]

    /// Compute the diff between two texts.
    ///
    /// - Parameters:
    ///   - oldText: The original text
    ///   - newText: The modified text
    /// - Returns: A TextDiff containing the list of changes
    static func compute(oldText: String, newText: String) -> TextDiff {
        let oldLines = oldText.components(separatedBy: .newlines)
        let newLines = newText.components(separatedBy: .newlines)

        let changes = computeLCSDiff(oldLines: oldLines, newLines: newLines)
        return TextDiff(changes: changes)
    }

    /// Compute diff using LCS (Longest Common Subsequence) algorithm.
    private static func computeLCSDiff(oldLines: [String], newLines: [String]) -> [DiffChange] {
        let m = oldLines.count
        let n = newLines.count

        // Build LCS table
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if oldLines[i - 1] == newLines[j - 1] {
                    lcs[i][j] = lcs[i - 1][j - 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                }
            }
        }

        // Backtrack to find the diff
        var changes: [DiffChange] = []
        var i = m
        var j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                changes.append(.unchanged(oldLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
                changes.append(.added(newLines[j - 1]))
                j -= 1
            } else if i > 0 {
                changes.append(.removed(oldLines[i - 1]))
                i -= 1
            }
        }

        return changes.reversed()
    }

    /// Returns true if there are any actual changes (additions or removals).
    var hasChanges: Bool {
        changes.contains { change in
            switch change {
            case .unchanged:
                return false
            case .added, .removed:
                return true
            }
        }
    }

    /// Count of added lines.
    var addedCount: Int {
        changes.filter { if case .added = $0 { return true } else { return false } }.count
    }

    /// Count of removed lines.
    var removedCount: Int {
        changes.filter { if case .removed = $0 { return true } else { return false } }.count
    }
}
