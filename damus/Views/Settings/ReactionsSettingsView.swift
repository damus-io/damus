//
//  ReactionsSettingsView.swift
//  damus
//
//  Created by Suhail Saqan on 7/3/23.
//

import SwiftUI
import Combine

struct ReactionsSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    
    @State var new_emoji: String = ""
    @State private var showActionButtons = false
    
    @Environment(\.dismiss) var dismiss
    
    var recommended: [String] {
        return getMissingRecommendedEmojis(added: settings.emoji_reactions)
    }
    
    var body: some View {
        Form {
            Section {
                AddEmojiView(emoji: $new_emoji)
            } header: {
                Text(NSLocalizedString("Add Emoji", comment: "Label for section for adding an emoji to the reactions list."))
                    .font(.system(size: 18, weight: .heavy))
                    .padding(.bottom, 5)
            } footer: {
                HStack {
                    Spacer()
                    if !new_emoji.isEmpty {
                        Button(NSLocalizedString("Cancel", comment: "Button to cancel out of view adding user inputted emoji.")) {
                            new_emoji = ""
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 80, height: 30)
                        .foregroundColor(.white)
                        .background(LINEAR_GRADIENT)
                        .clipShape(Capsule())
                        .padding(EdgeInsets(top: 15, leading: 0, bottom: 0, trailing: 0))
                        
                        Button(NSLocalizedString("Add", comment: "Button to confirm adding user inputted emoji.")) {
                            if isValidEmoji(new_emoji) {
                                settings.emoji_reactions.append(new_emoji)
                                new_emoji = ""
                            }
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 80, height: 30)
                        .foregroundColor(.white)
                        .background(LINEAR_GRADIENT)
                        .clipShape(Capsule())
                        .padding(EdgeInsets(top: 15, leading: 0, bottom: 0, trailing: 0))
                    }
                }
            }
            
            Picker(NSLocalizedString("Select default emoji", comment: "Prompt selection of user's default emoji reaction"),
                   selection: $settings.default_emoji_reaction) {
                ForEach(settings.emoji_reactions, id: \.self) { emoji in
                    Text(emoji)
                }
            }
            
            Section {
                List {
                    ForEach(Array(zip(settings.emoji_reactions, 1...)), id: \.1) { tup in
                        EmojiListItemView(settings: settings, emoji: tup.0, recommended: false, showActionButtons: $showActionButtons)
                    }
                    .onMove(perform: showActionButtons ? move: nil)
                }
            } header: {
                Text("Emoji Reactions", comment: "Section title for emoji reactions that are currently added.")
                    .font(.system(size: 18, weight: .heavy))
                    .padding(.bottom, 5)
            }
            
            if recommended.count > 0 {
                Section {
                    List(Array(zip(recommended, 1...)), id: \.1) { tup in
                        EmojiListItemView(settings: settings, emoji: tup.0, recommended: true, showActionButtons: $showActionButtons)
                    }
                } header: {
                    Text("Recommended Emojis", comment: "Section title for recommend emojis")
                        .font(.system(size: 18, weight: .heavy))
                        .padding(.bottom, 5)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Reactions", comment: "Title of emoji reactions view"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if showActionButtons {
                Button("Done") {
                    showActionButtons.toggle()
                }
            } else {
                Button("Edit") {
                    showActionButtons.toggle()
                }
            }
        }
    }
    
    private func move(from: IndexSet, to: Int) {
        settings.emoji_reactions.move(fromOffsets: from, toOffset: to)
    }
    
    // Returns the emojis that are in the recommended list but the user has not added yet
    func getMissingRecommendedEmojis(added: [String], recommended: [String] = default_emoji_reactions) -> [String] {
        let addedSet = Set(added)
        let missingEmojis = recommended.filter { !addedSet.contains($0) }
        return missingEmojis
    }
}

/// From: https://stackoverflow.com/a/39425959
extension Character {
    /// A simple emoji is one scalar and presented to the user as an Emoji
    var isSimpleEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }

    /// Checks if the scalars will be merged into an emoji
    var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }

    var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}

extension String {
    var isSingleEmoji: Bool { count == 1 && containsEmoji }

    var containsEmoji: Bool { contains { $0.isEmoji } }

    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }

    var emojiString: String { emojis.map { String($0) }.reduce("", +) }

    var emojis: [Character] { filter { $0.isEmoji } }

    var emojiScalars: [UnicodeScalar] { filter { $0.isEmoji }.flatMap { $0.unicodeScalars } }
}

func isValidEmoji(_ string: String) -> Bool {
    return string.isSingleEmoji
}

struct ReactionsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReactionsSettingsView(settings: UserSettingsStore())
    }
}
