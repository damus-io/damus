//
//  ReactionsSettingsView.swift
//  damus
//
//  Created by Suhail Saqan on 7/3/23.
//

import SwiftUI
import MCEmojiPicker

struct ReactionsSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    @State private var isReactionsVisible: Bool = false

    var body: some View {
        Form {
            Section {
                Text(settings.default_emoji_reaction)
                    .emojiPicker(
                        isPresented: $isReactionsVisible,
                        selectedEmoji: $settings.default_emoji_reaction,
                        arrowDirection: .up,
                        isDismissAfterChoosing: true
                    )
                    .onTapGesture {
                        isReactionsVisible = true
                    }
            } header: {
                Text("Select default emoji", comment: "Prompt selection of user's default emoji reaction")
            }
        }
        .navigationTitle(NSLocalizedString("Reactions", comment: "Title of emoji reactions view"))
        .navigationBarTitleDisplayMode(.large)
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
