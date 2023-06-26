//
//  EventMenu.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct EventMenuContext: View {
    let event: NostrEvent
    let keypair: Keypair
    let target_pubkey: String
    let bookmarks: BookmarksManager
    let muted_threads: MutedThreadsManager
    
    var body: some View {
        HStack {
            Menu {

                MenuItems(event: event, keypair: keypair, target_pubkey: target_pubkey, bookmarks: bookmarks, muted_threads: muted_threads)
                
            } label: {
                Label("", systemImage: "ellipsis")
                    .foregroundColor(Color.gray)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

struct MenuItems: View {
    let event: NostrEvent
    let keypair: Keypair
    let target_pubkey: String
    let bookmarks: BookmarksManager
    let muted_threads: MutedThreadsManager
    
    @State private var isBookmarked: Bool = false
    @State private var isMutedThread: Bool = false
    
    init(event: NostrEvent, keypair: Keypair, target_pubkey: String, bookmarks: BookmarksManager, muted_threads: MutedThreadsManager) {
        let bookmarked = bookmarks.isBookmarked(event)
        self._isBookmarked = State(initialValue: bookmarked)

        let muted_thread = muted_threads.isMutedThread(event, privkey: keypair.privkey)
        self._isMutedThread = State(initialValue: muted_thread)
        
        self.bookmarks = bookmarks
        self.muted_threads = muted_threads
        self.event = event
        self.keypair = keypair
        self.target_pubkey = target_pubkey
    }
    
    var body: some View {

        Group {
            Button {
                UIPasteboard.general.string = event.get_content(keypair.privkey)
            } label: {
                Label(NSLocalizedString("Copy text", comment: "Context menu option for copying the text from an note."), image: "copy2")
            }

            Button {
                UIPasteboard.general.string = bech32_pubkey(target_pubkey)
            } label: {
                Label(NSLocalizedString("Copy user public key", comment: "Context menu option for copying the ID of the user who created the note."), image: "user")
            }

            Button {
                UIPasteboard.general.string = bech32_note_id(event.id) ?? event.id
            } label: {
                Label(NSLocalizedString("Copy note ID", comment: "Context menu option for copying the ID of the note."), image: "note-book")
            }

            Button {
                UIPasteboard.general.string = event_to_json(ev: event)
            } label: {
                Label(NSLocalizedString("Copy note JSON", comment: "Context menu option for copying the JSON text from the note."), image: "code.on.square")
            }
            
            Button {
                self.bookmarks.updateBookmark(event)
                isBookmarked = self.bookmarks.isBookmarked(event)
            } label: {
                let imageName = isBookmarked ? "bookmark.fill" : "bookmark"
                let removeBookmarkString = NSLocalizedString("Remove bookmark", comment: "Context menu option for removing a note bookmark.")
                let addBookmarkString = NSLocalizedString("Add bookmark", comment: "Context menu option for adding a note bookmark.")
                Label(isBookmarked ? removeBookmarkString : addBookmarkString, image: imageName)
            }

            if event.known_kind != .dm {
                Button {
                    self.muted_threads.updateMutedThread(event)
                    let muted = self.muted_threads.isMutedThread(event, privkey: self.keypair.privkey)
                    isMutedThread = muted
                } label: {
                    let imageName = isMutedThread ? "mute" : "mute"
                    let unmuteThreadString = NSLocalizedString("Unmute conversation", comment: "Context menu option for unmuting a conversation.")
                    let muteThreadString = NSLocalizedString("Mute conversation", comment: "Context menu option for muting a conversation.")
                    Label(isMutedThread ? unmuteThreadString : muteThreadString, image: imageName)
                }
            }

            Button {
                NotificationCenter.default.post(name: .broadcast_event, object: event)
            } label: {
                Label(NSLocalizedString("Broadcast", comment: "Context menu option for broadcasting the user's note to all of the user's connected relay servers."), image: "globe")
            }
            
            // Only allow reporting if logged in with private key and the currently viewed profile is not the logged in profile.
            if keypair.pubkey != target_pubkey && keypair.privkey != nil {
                Button(role: .destructive) {
                    let target: ReportTarget = .note(ReportNoteTarget(pubkey: target_pubkey, note_id: event.id))
                    notify(.report, target)
                } label: {
                    Label(NSLocalizedString("Report", comment: "Context menu option for reporting content."), image: "raising-hand")
                }
                
                Button(role: .destructive) {
                    notify(.mute, target_pubkey)
                } label: {
                    Label(NSLocalizedString("Mute user", comment: "Context menu option for muting users."), image: "mute")
                }
            }
        }
    }
}

/*
struct EventMenu: UIViewRepresentable {
    
    typealias UIViewType = UIButton

    let saveAction = UIAction(title: "") { action in }
    let saveMenu = UIMenu(title: "", children: [
        UIAction(title: "First Menu Item", image: UIImage(systemName: "nameOfSFSymbol")) { action in
            //code action for menu item
        },
        UIAction(title: "First Menu Item", image: UIImage(systemName: "nameOfSFSymbol")) { action in
            //code action for menu item
        },
        UIAction(title: "First Menu Item", image: UIImage(systemName: "nameOfSFSymbol")) { action in
            //code action for menu item
        },
    ])

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        button.showsMenuAsPrimaryAction = true
        button.menu = saveMenu
        
        return button
    }
    
    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.setImage(UIImage(systemName: "plus"), for: .normal)
    }
}

struct EventMenu_Previews: PreviewProvider {
    static var previews: some View {
        EventMenu(event: test_event, privkey: nil, pubkey: test_event.pubkey)
    }
}

*/
