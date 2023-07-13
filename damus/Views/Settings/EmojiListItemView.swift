//
//  EmojiListItemView.swift
//  damus
//
//  Created by Suhail Saqan on 7/16/23.
//

import SwiftUI

struct EmojiListItemView: View {
    @ObservedObject var settings: UserSettingsStore

    let emoji: String
    let recommended: Bool
    
    @Binding var showActionButtons: Bool
    
    var body: some View {
        Group {
            HStack {
                if showActionButtons {
                    if recommended {
                        AddButton()
                    } else {
                        RemoveButton()
                    }
                }
                
                Text(emoji)
            }
        }
        .swipeActions {
            if !recommended {
                RemoveButton()
                    .tint(.red)
            } else {
                AddButton()
                    .tint(.green)
            }
        }
        .contextMenu {
            CopyAction(emoji: emoji)
        }
    }
    
    func CopyAction(emoji: String) -> some View {
        Button {
            UIPasteboard.general.setValue(emoji, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy an emoji reaction"), image: "copy2")
        }
    }
        
    func RemoveButton() -> some View {
        Button(action: {
            if let index = settings.emoji_reactions.firstIndex(of: emoji) {
                settings.emoji_reactions.remove(at: index)
            }
        }) {
            Image(systemName: "minus.circle")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.red)
                .padding(.leading, 5)
        }
    }
    
    func AddButton() -> some View {
        Button(action: {
            settings.emoji_reactions.append(emoji)
        }) {
            Image(systemName: "plus.circle")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.green)
                .padding(.leading, 5)
        }
    }
}
