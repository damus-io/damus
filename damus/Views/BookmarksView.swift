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
    
    @State private var bookmarkEvents: [NostrEvent] = []

    init(state: DamusState) {
        self.state = state
    }
        
    var body: some View {
        Group {
            if bookmarkEvents.isEmpty {
                VStack {
                    Image(systemName: "bookmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32.0, height: 32.0)
                    Text(NSLocalizedString("You have no bookmarks yet, add them in the context menu", comment: "Text indicating that there are no bookmarks to be viewed"))
                }
                .task {
                    bookmarkEvents = BookmarksManager(pubkey: state.pubkey).bookmarks.compactMap { bookmark_json in
                        event_from_json(dat: bookmark_json)
                    }
                }
            } else {
                ScrollView {
                    InnerTimelineView(events: $bookmarkEvents, damus: state, show_friend_icon: true, filter: noneFilter)

                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(bookmarksTitle)
    }
}

//struct BookmarksView_Previews: PreviewProvider {
//    static var previews: some View {
//        BookmarksView()
//    }
//}
