//
//  AddEmojiView.swift
//  damus
//
//  Created by Suhail Saqan on 7/16/23.
//

import SwiftUI

struct AddEmojiView: View {
    @Binding var emoji: String
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack{
                TextField(NSLocalizedString("⚡", comment: "Placeholder example for an emoji reaction"), text: $emoji)
                    .padding(2)
                    .padding(.leading, 25)
                    .opacity(emoji == "" ? 0.5 : 1)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .onChange(of: emoji) { newEmoji in
                        if let lastEmoji = newEmoji.last.map(String.init), isValidEmoji(lastEmoji) {
                            self.emoji = lastEmoji
                        } else {
                            self.emoji = ""
                        }
                    }
                
                Label("", image: "close-circle")
                    .foregroundColor(.accentColor)
                    .padding(.trailing, -25.0)
                    .opacity((emoji == "") ? 0.0 : 1.0)
                    .onTapGesture {
                        self.emoji = ""
                    }
            }
            
            Label("", image: "copy2")
                .padding(.leading, -10)
                .onTapGesture {
                    if let pastedEmoji = UIPasteboard.general.string {
                        self.emoji = pastedEmoji
                    }
                }
        }
    }
}
