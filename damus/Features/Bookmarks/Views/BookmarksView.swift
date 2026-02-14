//
//  BookmarksView.swift
//  damus
//
//  Created by Joel Klabo on 2/18/23.
//

import SwiftUI

struct BookmarksView: View {
    let state: DamusState
    private let bookmarksTitle = NSLocalizedString("Bookmarks", comment: "Title of bookmarks view")
    @State private var clearAllAlert: Bool = false
    
    @Environment(\.dismiss) var dismiss
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
                    Image("bookmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32.0, height: 32.0)
                    Text("You have no bookmarks yet, add them in the context menu", comment: "Text indicating that there are no bookmarks to be viewed")
                }
            } else {
                ScrollView {
                    InnerTimelineView(
                        events: EventHolder(events: bookmarks, incoming: []),
                        damus: state,
                        filter: ContentFilters.default_filters(damus_state: state).filter(ev:)
                    )
                }
                .padding(.bottom, 10 + tabHeight + getSafeAreaBottom())
            }
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(bookmarksTitle)
        .toolbar {
            if !bookmarks.isEmpty {
                Button(NSLocalizedString("Clear All", comment: "Button for clearing bookmarks data.")) {
                    clearAllAlert = true
                }
            }
        }
        .alert(NSLocalizedString("Are you sure you want to delete all of your bookmarks?", comment: "Alert for deleting all of the bookmarks."), isPresented: $clearAllAlert) {
            Button(NSLocalizedString("Cancel", comment: "Cancel deleting bookmarks."), role: .cancel) {
            }
            Button(NSLocalizedString("Continue", comment: "Continue with bookmarks.")) {
                manager.clearAll()
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
