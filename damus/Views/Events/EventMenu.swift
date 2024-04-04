//
//  EventMenu.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct EventMenuContext: View {
    let damus_state: DamusState
    let event: NostrEvent
    let target_pubkey: Pubkey
    let profileModel : ProfileModel
    
    init(damus: DamusState, event: NostrEvent) {
        self.damus_state = damus
        self.event = event
        self.target_pubkey = event.pubkey
        self.profileModel = ProfileModel(pubkey: target_pubkey, damus: damus)
    }
    
    var body: some View {
        HStack {
            Label("", systemImage: "ellipsis")
                .foregroundColor(Color.gray)
                .contentShape(Circle())
                // Add our Menu button inside an overlay modifier to avoid affecting the rest of the layout around us.
                .overlay(
                    Menu {
                        MenuItems(damus_state: damus_state, event: event, target_pubkey: target_pubkey, profileModel: profileModel)
                    } label: {
                        Color.clear
                    }
                    // Hitbox frame size
                    .frame(width: 50, height: 35)
                )
        }
        .padding([.bottom], 4)
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

struct MenuItems: View {
    let damus_state: DamusState
    let event: NostrEvent
    let target_pubkey: Pubkey
    let profileModel: ProfileModel

    @State private var isBookmarked: Bool = false
    @State private var isMutedThread: Bool = false
    
    init(damus_state: DamusState, event: NostrEvent, target_pubkey: Pubkey, profileModel: ProfileModel) {
        let bookmarked = damus_state.bookmarks.isBookmarked(event)
        self._isBookmarked = State(initialValue: bookmarked)

        let muted_thread = damus_state.mutelist_manager.is_event_muted(event)
        self._isMutedThread = State(initialValue: muted_thread)
        
        self.damus_state = damus_state
        self.event = event
        self.target_pubkey = target_pubkey
        self.profileModel = profileModel
    }
    
    var body: some View {
        Group {
            Button {
                UIPasteboard.general.string = event.get_content(damus_state.keypair)
            } label: {
                Label(NSLocalizedString("Copy text", comment: "Context menu option for copying the text from an note."), image: "copy2")
            }

            Button {
                UIPasteboard.general.string = Bech32Object.encode(.nprofile(NProfile(author: target_pubkey, relays: profileModel.getCappedRelays())))
            } label: {
                Label(NSLocalizedString("Copy user public key", comment: "Context menu option for copying the ID of the user who created the note."), image: "user")
            }

            Button {
                UIPasteboard.general.string = event.id.bech32
            } label: {
                Label(NSLocalizedString("Copy note ID", comment: "Context menu option for copying the ID of the note."), image: "note-book")
            }

            if damus_state.settings.developer_mode {
                Button {
                    UIPasteboard.general.string = event_to_json(ev: event)
                } label: {
                    Label(NSLocalizedString("Copy note JSON", comment: "Context menu option for copying the JSON text from the note."), image: "code.on.square")
                }
            }
            
            Button {
                self.damus_state.bookmarks.updateBookmark(event)
                isBookmarked = self.damus_state.bookmarks.isBookmarked(event)
            } label: {
                let imageName = isBookmarked ? "bookmark.fill" : "bookmark"
                let removeBookmarkString = NSLocalizedString("Remove bookmark", comment: "Context menu option for removing a note bookmark.")
                let addBookmarkString = NSLocalizedString("Add bookmark", comment: "Context menu option for adding a note bookmark.")
                Label(isBookmarked ? removeBookmarkString : addBookmarkString, image: imageName)
            }

            Button {
                notify(.broadcast(event))
            } label: {
                Label(NSLocalizedString("Broadcast", comment: "Context menu option for broadcasting the user's note to all of the user's connected relay servers."), image: "globe")
            }
            // Mute thread - relocated to below Broadcast, as to move further away from Add Bookmark to prevent accidental muted threads
            if event.known_kind != .dm {
                MuteDurationMenu { duration in
                    if let full_keypair = self.damus_state.keypair.to_full(),
                       let new_mutelist_ev = toggle_from_mutelist(keypair: full_keypair, prev: damus_state.mutelist_manager.event, to_toggle: .thread(event.thread_id(), duration?.date_from_now)) {
                        damus_state.mutelist_manager.set_mutelist(new_mutelist_ev)
                        damus_state.nostrNetwork.postbox.send(new_mutelist_ev)
                    }
                    let muted = damus_state.mutelist_manager.is_event_muted(event)
                    isMutedThread = muted
                } label: {
                    let imageName = isMutedThread ? "mute" : "mute"
                    let unmuteThreadString = NSLocalizedString("Unmute conversation", comment: "Context menu option for unmuting a conversation.")
                    let muteThreadString = NSLocalizedString("Mute conversation", comment: "Context menu option for muting a conversation.")
                    Label(isMutedThread ? unmuteThreadString : muteThreadString, image: imageName)
                }
            }
            // Only allow reporting if logged in with private key and the currently viewed profile is not the logged in profile.
            if damus_state.keypair.pubkey != target_pubkey && damus_state.keypair.privkey != nil {
                Button(role: .destructive) {
                    notify(.report(.note(ReportNoteTarget(pubkey: target_pubkey, note_id: event.id))))
                } label: {
                    Label(NSLocalizedString("Report", comment: "Context menu option for reporting content."), image: "raising-hand")
                }
                
                MuteDurationMenu { duration in
                    notify(.mute(.user(target_pubkey, duration?.date_from_now)))
                } label: {
                    Label(NSLocalizedString("Mute/Block user", comment: "Context menu option for muting/blocking users."), image: "mute")
                }
            }
        }
        .onAppear() {
            profileModel.subscribeToFindRelays()
        }
        .onDisappear() {
            profileModel.unsubscribeFindRelays()
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
