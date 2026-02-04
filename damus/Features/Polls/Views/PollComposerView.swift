//
//  PollComposerView.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import SwiftUI

struct PollComposerView: View {
    @Binding var draft: PollDraft
    let onRemove: () -> Void

    @State private var isExpirationEnabled: Bool = false

    private var optionIndices: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: draft.options.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Poll", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                Button(action: onRemove) {
                    Text("Remove Poll", comment: "Button to remove the poll composer from the note.")
                }
                .buttonStyle(.borderless)
            }

            Picker("Poll Type", selection: $draft.pollType) {
                Text("Single Choice", comment: "Poll type option for single choice polls.")
                    .tag(PollType.singleChoice)
                Text("Multiple Choice", comment: "Poll type option for multiple choice polls.")
                    .tag(PollType.multipleChoice)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 8) {
                ForEach(draft.options) { option in
                    HStack {
                        TextField(
                            optionLabel(for: option.id),
                            text: binding(for: option.id)
                        )
                        .textFieldStyle(.roundedBorder)

                        if draft.options.count > PollDraft.minimumOptions {
                            Button {
                                removeOption(option.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if draft.options.count < PollDraft.maximumOptions {
                    Button {
                        draft.addOption()
                    } label: {
                        Label("Add Option", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $isExpirationEnabled.animation()) {
                    Text("Set expiration", comment: "Toggle to enable poll expiration.")
                }
                if isExpirationEnabled {
                    DatePicker(
                        "Poll ends",
                        selection: expirationBinding(),
                        in: Date().addingTimeInterval(60)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }
            }
        }
        .onAppear {
            isExpirationEnabled = draft.endsAt != nil
            draft.ensureMinimumOptions()
        }
        .onChange(of: isExpirationEnabled) { enabled in
            if enabled {
                if draft.endsAt == nil {
                    draft.endsAt = Date().addingTimeInterval(3600)
                }
            } else {
                draft.endsAt = nil
            }
        }
    }

    private func binding(for optionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                draft.options.first(where: { $0.id == optionID })?.text ?? ""
            },
            set: { newValue in
                if let index = draft.options.firstIndex(where: { $0.id == optionID }) {
                    draft.options[index].text = newValue
                }
            }
        )
    }

    private func optionLabel(for optionID: UUID) -> String {
        if let index = optionIndices[optionID] {
            return String(format: NSLocalizedString("Option %d", comment: "Label for a poll option field."), index)
        }
        return NSLocalizedString("Option", comment: "Fallback label for a poll option field.")
    }

    private func removeOption(_ optionID: UUID) {
        draft.removeOption(id: optionID)
    }

    private func expirationBinding() -> Binding<Date> {
        Binding<Date>(
            get: {
                draft.endsAt ?? Date().addingTimeInterval(3600)
            },
            set: { newValue in
                draft.endsAt = newValue
            }
        )
    }
}
