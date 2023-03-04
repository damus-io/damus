//
//  BookmarksView.swift
//  damus
//
//  Created by Joel Klabo on 2/18/23.
//

import SwiftUI

struct BookmarksView: View {
    let state: DamusState
    private let noneFilter: (NostrEvent) -> Bool = { _ in true }
    private let bookmarksTitle = NSLocalizedString("Bookmarks", comment: "Title of bookmarks view")
    
    @ObservedObject var manager: BookmarksManager

    init(state: DamusState) {
        self.state = state
        self._manager = ObservedObject(initialValue: state.bookmarks)
    }
    
    var bookmarks: [NostrEvent] {
        manager.bookmarks
    }
        
    var body: some View {
        Group {
            if bookmarks.isEmpty {
                VStack {
                    Image(systemName: "bookmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32.0, height: 32.0)
                    Text(NSLocalizedString("You have no bookmarks yet, add them in the context menu", comment: "Text indicating that there are no bookmarks to be viewed"))
                }
            } else {
                ScrollView {
                    InnerTimelineView(events: EventHolder(events: bookmarks, incoming: []), damus: state, show_friend_icon: true, filter: noneFilter)

                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(bookmarksTitle)
        .toolbar {
            if !bookmarks.isEmpty {
                Button(NSLocalizedString("Clear All", comment: "Button for clearing bookmarks data.")) {
                    manager.clearAll()
                }
            }
        }
    }
}

/*
struct BookmarksView_Previews: PreviewProvider {
 static var previews: some View {
    BookmarksView()
 }
}
 */
