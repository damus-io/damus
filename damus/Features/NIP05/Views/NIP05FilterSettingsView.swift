//
//  NIP05FilterSettingsView.swift
//  damus
//
//  Created by alltheseas on 2025-12-08.
//

import SwiftUI

/// Settings for NIP-05 domain feed filtering (fevela-style)
class NIP05FilterSettings: ObservableObject {
    @Published var enableGroupedMode: Bool = true
    @Published var timeRange: NIP05TimeRange = .day
    @Published var compactView: Bool = true
    @Published var showLastNotePreview: Bool = true
    @Published var includeReplies: Bool = false
    @Published var hideShortNotes: Bool = false
    @Published var filteredWords: String = ""
    @Published var maxNotesPerUser: Int? = nil  // nil means disabled

    static let maxNotesOptions: [Int?] = [nil, 3, 5, 10, 20]

    func reset() {
        enableGroupedMode = true
        timeRange = .day
        compactView = true
        showLastNotePreview = true
        includeReplies = false
        hideShortNotes = false
        filteredWords = ""
        maxNotesPerUser = nil
    }
}

/// Filter settings view that appears when tapping on grouped mode
struct NIP05FilterSettingsView: View {
    @ObservedObject var settings: NIP05FilterSettings
    @Environment(\.dismiss) var dismiss
    let onApply: () -> Void

    var body: some View {
        NavigationView {
            Form {
                // Grouped mode toggle
                Section {
                    Toggle(isOn: $settings.enableGroupedMode) {
                        Text("Enable grouped notes mode", comment: "Toggle to enable grouping notes by author")
                    }
                    .tint(DamusColors.purple)
                }

                // Time range
                Section {
                    HStack {
                        Text("Show me a summary for single users of what happened in the last", comment: "Label for time range picker")
                        Spacer()
                    }

                    Picker("Time Range", selection: $settings.timeRange) {
                        ForEach(NIP05TimeRange.allCases, id: \.self) { range in
                            Text(range.displayTitle).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // View options (only when grouped mode is enabled)
                if settings.enableGroupedMode {
                    Section {
                        Toggle(isOn: $settings.compactView) {
                            Text("Compact view: show only authors", comment: "Toggle for compact author-only view")
                        }
                        .tint(DamusColors.purple)

                        Toggle(isOn: $settings.showLastNotePreview) {
                            Text("Show preview of the last note", comment: "Toggle to show preview of most recent note")
                        }
                        .tint(DamusColors.purple)
                    }
                }

                // Content filters
                Section {
                    Toggle(isOn: $settings.includeReplies) {
                        Text("Include replies", comment: "Toggle to include reply notes in feed")
                    }
                    .tint(DamusColors.purple)

                    Toggle(isOn: $settings.hideShortNotes) {
                        Text("Hide (too) short notes", comment: "Toggle to hide very short notes")
                    }
                    .tint(DamusColors.purple)
                }

                // Word filter
                Section {
                    Text("Filter out notes with these words (comma separated):", comment: "Label for word filter input")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. nostr, bitcoin, gm", text: $settings.filteredWords)
                        .textFieldStyle(.roundedBorder)
                }

                // Max notes per user
                Section {
                    Text("Filter out users who have published more than X notes in the timeframe:", comment: "Label for max notes filter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Max Notes", selection: $settings.maxNotesPerUser) {
                        Text("Disabled", comment: "Option to disable max notes filter").tag(nil as Int?)
                        ForEach(NIP05FilterSettings.maxNotesOptions.compactMap({ $0 }), id: \.self) { count in
                            Text("\(count)").tag(count as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Reset and Apply buttons
                Section {
                    HStack {
                        Button {
                            settings.reset()
                        } label: {
                            Text("Reset", comment: "Button to reset filter settings to defaults")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onApply()
                            dismiss()
                        } label: {
                            Text("Apply", comment: "Button to apply filter settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DamusColors.purple)
                    }
                }
            }
            .navigationTitle(Text("Filter Settings", comment: "Navigation title for filter settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// Add display title to NIP05TimeRange
extension NIP05TimeRange {
    var displayTitle: String {
        switch self {
        case .day:
            return NSLocalizedString("24 Hours", comment: "Time range option for last 24 hours")
        case .week:
            return NSLocalizedString("7 Days", comment: "Time range option for last 7 days")
        }
    }
}

#Preview {
    NIP05FilterSettingsView(settings: NIP05FilterSettings()) {
        print("Applied!")
    }
}
