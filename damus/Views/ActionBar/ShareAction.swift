//
//  ShareAction.swift
//  damus
//
//  Created by eric on 3/8/23.
//

import SwiftUI

struct ShareAction: View {
    let event: NostrEvent
    let bookmarks: BookmarksManager
    @State private var isBookmarked: Bool = false

    @Binding var show_share_sheet: Bool
    @Binding var show_share_action: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    init(event: NostrEvent, bookmarks: BookmarksManager, show_share_sheet: Binding<Bool>, show_share_action: Binding<Bool>) {
        let bookmarked = bookmarks.isBookmarked(event)
        self._isBookmarked = State(initialValue: bookmarked)
        
        self.bookmarks = bookmarks
        self.event = event
        self._show_share_sheet = show_share_sheet
        self._show_share_action = show_share_action
    }
    
    var body: some View {
        
        let col = colorScheme == .light ? DamusColors.mediumGrey : DamusColors.white
        
        VStack {
            Text("Share Note", comment: "Title text to indicate that the buttons below are meant to be used to share a note with others.")
                .padding()
                .font(.system(size: 17, weight: .bold))
            
            Spacer()

            HStack(alignment: .top, spacing: 25) {
                
                ShareActionButton(img: "link", text: NSLocalizedString("Copy Link", comment: "Button to copy link to note"), col: col) {
                    show_share_action = false
                    UIPasteboard.general.string = "https://damus.io/" + (bech32_note_id(event.id) ?? event.id)
                }
                
                let bookmarkImg = isBookmarked ? "bookmark.slash" : "bookmark"
                let bookmarkTxt = isBookmarked ? NSLocalizedString("Remove Bookmark", comment: "Button text to remove bookmark from a note.") : NSLocalizedString("Add Bookmark", comment: "Button text to add bookmark to a note.")
                let boomarkCol = isBookmarked ? Color(.red) : col
                ShareActionButton(img: bookmarkImg, text: bookmarkTxt, col: boomarkCol) {
                    show_share_action = false
                    self.bookmarks.updateBookmark(event)
                    isBookmarked = self.bookmarks.isBookmarked(event)
                }
                
                ShareActionButton(img: "globe", text: NSLocalizedString("Broadcast", comment: "Button to broadcast note to all your relays"), col: col) {
                    show_share_action = false
                    NotificationCenter.default.post(name: .broadcast_event, object: event)
                }
                
                ShareActionButton(img: "square.and.arrow.up", text: NSLocalizedString("Share Via...", comment: "Button to present iOS share sheet"), col: col) {
                    show_share_action = false
                    show_share_sheet = true
                }
                
            }
            
            Spacer()
            
            HStack {
                
                Button(action: {
                    show_share_action = false
                }) {
                    Text(NSLocalizedString("Cancel", comment: "Button to cancel a repost."))
                    .frame(minWidth: 300, maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .center)
                    .foregroundColor(colorScheme == .light ? DamusColors.black : DamusColors.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(colorScheme == .light ? DamusColors.mediumGrey : DamusColors.white, lineWidth: 1)
                    }
                    .padding(EdgeInsets(top: 10, leading: 50, bottom: 25, trailing: 50))
                }
            }
        }
    }
}

func ShareActionButton(img: String, text: String, col: Color, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        VStack() {
            Image(systemName: img)
                .foregroundColor(col)
                .font(.system(size: 23, weight: .bold))
                .overlay {
                    Circle()
                        .stroke(col, lineWidth: 1)
                        .frame(width: 55.0, height: 55.0)
                }
                .frame(height: 25)
            Text(verbatim: text)
                .foregroundColor(col)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.top)
        }
    }

}
