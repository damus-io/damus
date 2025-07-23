//
//  ReactionsSettingsView.swift
//  damus
//
//  Created by Suhail Saqan on 7/3/23.
//

import SwiftUI
import EmojiPicker
import EmojiKit

struct ReactionsSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    let damus_state: DamusState
    @State private var isReactionsVisible: Bool = false

    @State private var selectedEmoji: Emoji? = nil

    var body: some View {
        Form {
            Section {
                Text(settings.default_emoji_reaction)
                    .onTapGesture {
                        isReactionsVisible = true
                    }
            } header: {
                Text("Select default emoji", comment: "Prompt selection of user's default emoji reaction")
            }
        }
        .navigationTitle(NSLocalizedString("Reactions", comment: "Title of emoji reactions view"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isReactionsVisible) {
            NavigationView {
                EmojiPickerView(selectedEmoji: $selectedEmoji, emojiProvider: damus_state.emoji_provider)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedEmoji) { newEmoji in
            guard let newEmoji else {
                return
            }
            settings.default_emoji_reaction = newEmoji.value
        }
    }
}

struct ReactionsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReactionsSettingsView(settings: UserSettingsStore(), damus_state: test_damus_state)
    }
}
