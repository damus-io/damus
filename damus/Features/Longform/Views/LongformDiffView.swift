//
//  LongformDiffView.swift
//  damus
//
//  Created for issue #3517 - Display longform article edit history
//

import SwiftUI

/// A view showing the diff between two versions of a longform article.
///
/// Displays additions in green and removals in red, with unchanged lines
/// shown in the default text color.
struct LongformDiffView: View {
    let oldVersion: NostrEvent
    let newVersion: NostrEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var diff: TextDiff {
        let oldContent = oldVersion.content
        let newContent = newVersion.content
        return TextDiff.compute(oldText: oldContent, newText: newContent)
    }

    private var oldDate: String {
        formatDate(oldVersion.created_at)
    }

    private var newDate: String {
        formatDate(newVersion.created_at)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Summary header
                    DiffSummaryHeader(diff: diff, oldDate: oldDate, newDate: newDate)
                        .padding()

                    Divider()

                    // Diff content
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.changes.enumerated()), id: \.offset) { _, change in
                            DiffLineView(change: change, colorScheme: colorScheme)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(NSLocalizedString("Changes", comment: "Title for diff view showing changes between article versions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "Button to dismiss diff view")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ timestamp: UInt32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Header showing a summary of the changes.
private struct DiffSummaryHeader: View {
    let diff: TextDiff
    let oldDate: String
    let newDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("Comparing versions", comment: "Header for diff comparison"))
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                Label(oldDate, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label(newDate, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("+\(diff.addedCount)")
                        .font(.caption.monospaced())
                        .foregroundColor(.green)
                    Text(NSLocalizedString("added", comment: "Label for number of lines added"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text("-\(diff.removedCount)")
                        .font(.caption.monospaced())
                        .foregroundColor(.red)
                    Text(NSLocalizedString("removed", comment: "Label for number of lines removed"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// A single line in the diff view.
private struct DiffLineView: View {
    let change: DiffChange
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Line prefix
            Text(prefix)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(prefixColor)
                .frame(width: 20, alignment: .center)

            // Line content
            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch change {
        case .unchanged:
            return " "
        case .added:
            return "+"
        case .removed:
            return "-"
        }
    }

    private var content: String {
        switch change {
        case .unchanged(let text), .added(let text), .removed(let text):
            return text.isEmpty ? " " : text
        }
    }

    private var prefixColor: Color {
        switch change {
        case .unchanged:
            return .secondary
        case .added:
            return .green
        case .removed:
            return .red
        }
    }

    private var textColor: Color {
        switch change {
        case .unchanged:
            return .primary
        case .added:
            return colorScheme == .dark ? .green : .green.opacity(0.8)
        case .removed:
            return colorScheme == .dark ? .red : .red.opacity(0.8)
        }
    }

    private var backgroundColor: Color {
        switch change {
        case .unchanged:
            return .clear
        case .added:
            return .green.opacity(0.1)
        case .removed:
            return .red.opacity(0.1)
        }
    }
}
