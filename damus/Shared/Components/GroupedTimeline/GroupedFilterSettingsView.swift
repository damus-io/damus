//
//  GroupedFilterSettingsView.swift
//  damus
//
//  Created by alltheseas on 2025-12-08.
//

import SwiftUI

/// Settings for grouped feed filtering (fevela-style).
/// Used by both NIP-05 domain feeds and the home timeline.
class GroupedFilterSettings: ObservableObject {
    @Published var enableGroupedMode: Bool
    @Published var timeRange: GroupedTimeRange = .day
    @Published var includeReplies: Bool = false
    @Published var hideShortNotes: Bool = false
    @Published var filteredWords: String = ""
    @Published var maxNotesPerUser: Int? = nil  // nil means disabled

    static let maxNotesOptions: [Int?] = [nil, 3, 5, 10, 20]

    /// The default value passed at init, used by `reset()` to restore per-screen defaults.
    private let defaultGroupedMode: Bool

    /// - Parameter enableGroupedMode: Initial grouped mode state. NIP-05 domain views pass `true`; home timeline defaults to `false`.
    init(enableGroupedMode: Bool = false) {
        self.defaultGroupedMode = enableGroupedMode
        self.enableGroupedMode = enableGroupedMode
    }

    func reset() {
        enableGroupedMode = defaultGroupedMode
        timeRange = .day
        includeReplies = false
        hideShortNotes = false
        filteredWords = ""
        maxNotesPerUser = nil
    }
}

/// Filter settings view that appears when tapping on grouped mode.
struct GroupedFilterSettingsView: View {
    @ObservedObject var settings: GroupedFilterSettings
    @Environment(\.dismiss) var dismiss
    let onApply: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $settings.enableGroupedMode) {
                        Text("Enable grouped notes mode", comment: "Toggle to enable grouping notes by author")
                    }
                    .tint(DamusColors.purple)
                }

                Section {
                    HStack {
                        Text("Show me a summary for single users of what happened in the last", comment: "Label for time range picker")
                        Spacer()
                    }

                    Picker("Time Range", selection: $settings.timeRange) {
                        ForEach(GroupedTimeRange.allCases, id: \.self) { range in
                            Text(range.displayTitle).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                }

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

                Section {
                    Text("Filter out notes with these words (comma separated):", comment: "Label for word filter input")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. nostr, bitcoin, gm", text: $settings.filteredWords)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    Text("Filter out users who have published more than X notes in the timeframe:", comment: "Label for max notes filter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Max Notes", selection: $settings.maxNotesPerUser) {
                        Text("Disabled", comment: "Option to disable max notes filter").tag(nil as Int?)
                        ForEach(GroupedFilterSettings.maxNotesOptions.compactMap({ $0 }), id: \.self) { count in
                            Text("\(count)").tag(count as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }

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

#Preview {
    GroupedFilterSettingsView(settings: GroupedFilterSettings()) {
        print("Applied!")
    }
}
