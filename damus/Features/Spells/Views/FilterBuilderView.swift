//
//  FilterBuilderView.swift
//  damus
//
//  Visual filter builder for creating custom spell feeds from UI controls.
//

import SwiftUI

/// A form-based view for creating custom spell feeds.
///
/// Allows users to select event kinds, author scope, time range, and other
/// NIP-A7 filter parameters, then save the result as a new feed tab.
struct FilterBuilderView: View {
    @StateObject private var model = FilterBuilderModel()
    @Environment(\.dismiss) private var dismiss
    let onSave: (SavedSpellFeed) -> Void

    var body: some View {
        NavigationView {
            Form {
                nameSection
                kindSection
                authorSection
                timeSection
                filtersSection
                previewSection
            }
            .navigationTitle(NSLocalizedString("New Feed", comment: "Title for the filter builder view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "Save button")) {
                        save()
                    }
                    .disabled(!model.isValid)
                }
            }
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        Section(header: Text("Feed Name", comment: "Section header for feed name")) {
            TextField(
                NSLocalizedString("e.g. Tech Notes", comment: "Placeholder for feed name"),
                text: $model.feedName
            )
            TextField(
                NSLocalizedString("Description (optional)", comment: "Placeholder for feed description"),
                text: $model.feedDescription
            )
        }
    }

    // MARK: - Kinds

    private var kindSection: some View {
        Section(
            header: Text("Event Kinds", comment: "Section header for kind selection"),
            footer: Text("Select which types of events to include in this feed.", comment: "Footer for kind section")
        ) {
            ForEach(KindPreset.presets) { preset in
                KindToggleRow(
                    preset: preset,
                    isSelected: model.selectedKinds.contains(preset.kind),
                    onToggle: { selected in
                        if selected {
                            model.selectedKinds.insert(preset.kind)
                        } else {
                            model.selectedKinds.remove(preset.kind)
                        }
                    }
                )
            }

            HStack {
                Text("Custom kind:", comment: "Label for custom kind number input")
                    .foregroundColor(.secondary)
                TextField(
                    NSLocalizedString("e.g. 30023", comment: "Placeholder for custom kind number"),
                    text: $model.customKindText
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Authors

    private var authorSection: some View {
        Section(header: Text("Authors", comment: "Section header for author filter")) {
            Picker(
                NSLocalizedString("Show events from", comment: "Author scope picker label"),
                selection: $model.authorScope
            ) {
                Text("Anyone", comment: "Author scope: no filter").tag(AuthorScope.anyone)
                Text("People I follow", comment: "Author scope: contacts").tag(AuthorScope.contacts)
                Text("Only me", comment: "Author scope: self").tag(AuthorScope.me)
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        Section(header: Text("Time Range", comment: "Section header for time range")) {
            Picker(
                NSLocalizedString("Show events from the last", comment: "Time range picker label"),
                selection: $model.sincePreset
            ) {
                Text("No limit", comment: "No time restriction").tag("")
                ForEach(TimePreset.presets) { preset in
                    Text(preset.label).tag(preset.tag)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Filters

    private var filtersSection: some View {
        Section(header: Text("Additional Filters", comment: "Section header for additional filters")) {
            HStack {
                Text("Search:", comment: "Label for search filter")
                    .foregroundColor(.secondary)
                TextField(
                    NSLocalizedString("e.g. bitcoin", comment: "Placeholder for search text"),
                    text: $model.searchText
                )
                .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Hashtag:", comment: "Label for hashtag filter")
                    .foregroundColor(.secondary)
                TextField(
                    NSLocalizedString("e.g. nostr", comment: "Placeholder for hashtag"),
                    text: $model.hashtagText
                )
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section(
            header: Text("Preview", comment: "Section header for tag preview"),
            footer: Text("This is what the spell event tags will look like.", comment: "Footer for preview section")
        ) {
            let tags = model.buildTags()
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.joined(separator: ", "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let feed = model.buildSavedFeed() else { return }
        onSave(feed)
        dismiss()
    }
}

// MARK: - Kind Toggle Row

/// A row with a toggle for selecting an event kind.
private struct KindToggleRow: View {
    let preset: KindPreset
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack {
                Text(preset.label)
                    .foregroundColor(.primary)
                Spacer()
                Text("kind:\(preset.kind)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DamusColors.purple : .secondary)
            }
        }
    }
}
