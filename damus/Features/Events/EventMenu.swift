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

    init(damus: DamusState, event: NostrEvent) {
        self.damus_state = damus
        self.event = event
    }

    var body: some View {
        EventMenuButton(damus_state: damus_state, event: event)
            .frame(width: 50, height: 35)
            .padding([.bottom], 4)
    }
}

/// UIKit-backed menu button that replaces the SwiftUI Menu overlay.
///
/// Using UIButton + UIDeferredMenuElement instead of SwiftUI Menu because:
/// 1. SwiftUI Menu eagerly evaluates its content builder on every row body,
///    creating deeply nested ZStack/Menu layout nodes that the layout engine
///    must recurse through for spacing computation (15ms+ per row).
/// 2. UIKit UIButton is an opaque leaf node — no recursive spacing traversal.
/// 3. UIDeferredMenuElement.uncached only builds menu items when tapped,
///    deferring ProfileModel allocation and menu construction to interaction time.
struct EventMenuButton: UIViewRepresentable {
    let damus_state: DamusState
    let event: NostrEvent

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(textStyle: .body)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .gray
        button.showsMenuAsPrimaryAction = true
        button.menu = buildDeferredMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.menu = buildDeferredMenu()
    }

    private func buildDeferredMenu() -> UIMenu {
        let ds = damus_state
        let ev = event
        return UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                completion(EventMenuButton.menuActions(damus_state: ds, event: ev))
            }
        ])
    }

    @MainActor
    static func menuActions(damus_state: DamusState, event: NostrEvent) -> [UIMenuElement] {
        let target_pubkey = event.pubkey
        let profileModel = ProfileModel(pubkey: target_pubkey, damus: damus_state)
        let isBookmarked = damus_state.bookmarks.isBookmarked(event)
        let isMutedThread = damus_state.mutelist_manager.is_event_muted(event)

        var actions: [UIMenuElement] = []

        actions.append(UIAction(
            title: NSLocalizedString("Copy text", comment: "Context menu option for copying the text from an note."),
            image: UIImage(named: "copy2")
        ) { _ in
            UIPasteboard.general.string = event.get_content(damus_state.keypair)
        })

        actions.append(UIAction(
            title: NSLocalizedString("Copy user public key", comment: "Context menu option for copying the ID of the user who created the note."),
            image: UIImage(named: "user")
        ) { _ in
            UIPasteboard.general.string = Bech32Object.encode(.nprofile(NProfile(author: target_pubkey, relays: profileModel.getCappedRelays())))
        })

        actions.append(UIAction(
            title: NSLocalizedString("Copy note ID", comment: "Context menu option for copying the ID of the note."),
            image: UIImage(named: "note-book")
        ) { _ in
            Task {
                let relays = await damus_state.nostrNetwork.relaysForEvent(event: event)
                let urls: [RelayURL]
                if !relays.isEmpty {
                    urls = relays.prefix(Constants.MAX_SHARE_RELAYS).map { $0 }
                } else {
                    urls = profileModel.getCappedRelays()
                }
                UIPasteboard.general.string = Bech32Object.encode(.nevent(NEvent(event: event, relays: urls)))
            }
        })

        if damus_state.settings.developer_mode {
            actions.append(UIAction(
                title: NSLocalizedString("Copy note JSON", comment: "Context menu option for copying the JSON text from the note."),
                image: UIImage(named: "code.on.square")
            ) { _ in
                UIPasteboard.general.string = event_to_json(ev: event)
            })
        }

        actions.append(UIAction(
            title: isBookmarked
                ? NSLocalizedString("Remove bookmark", comment: "Context menu option for removing a note bookmark.")
                : NSLocalizedString("Add bookmark", comment: "Context menu option for adding a note bookmark."),
            image: UIImage(named: isBookmarked ? "bookmark.fill" : "bookmark")
        ) { _ in
            damus_state.bookmarks.updateBookmark(event)
        })

        actions.append(UIAction(
            title: NSLocalizedString("Broadcast", comment: "Context menu option for broadcasting the user's note to all of the user's connected relay servers."),
            image: UIImage(named: "globe")
        ) { _ in
            notify(.broadcast(event))
        })

        if event.known_kind != .dm {
            actions.append(muteDurationMenu(
                title: isMutedThread
                    ? NSLocalizedString("Unmute conversation", comment: "Context menu option for unmuting a conversation.")
                    : NSLocalizedString("Mute conversation", comment: "Context menu option for muting a conversation."),
                image: UIImage(named: "mute")
            ) { duration in
                if let full_keypair = damus_state.keypair.to_full(),
                   let new_mutelist_ev = toggle_from_mutelist(keypair: full_keypair, prev: damus_state.mutelist_manager.event, to_toggle: .thread(event.thread_id(), duration?.date_from_now)) {
                    damus_state.mutelist_manager.set_mutelist(new_mutelist_ev)
                    Task { await damus_state.nostrNetwork.postbox.send(new_mutelist_ev) }
                }
            })
        }

        if damus_state.keypair.pubkey != target_pubkey && damus_state.keypair.privkey != nil {
            actions.append(UIAction(
                title: NSLocalizedString("Report", comment: "Context menu option for reporting content."),
                image: UIImage(named: "raising-hand"),
                attributes: .destructive
            ) { _ in
                notify(.report(.note(ReportNoteTarget(pubkey: target_pubkey, note_id: event.id))))
            })

            actions.append(muteDurationMenu(
                title: NSLocalizedString("Mute/Block user", comment: "Context menu option for muting/blocking users."),
                image: UIImage(named: "mute")
            ) { duration in
                notify(.mute(.user(target_pubkey, duration?.date_from_now)))
            })
        }

        return actions
    }

    private static func muteDurationMenu(title: String, image: UIImage?, action: @escaping (DamusDuration?) -> Void) -> UIMenu {
        let children = DamusDuration.allCases.map { duration in
            UIAction(title: duration.title) { _ in
                action(duration)
            }
        }
        return UIMenu(title: title, image: image, children: children)
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

    func event_relay_url_strings() async -> [RelayURL] {
        let relays = await damus_state.nostrNetwork.relaysForEvent(event: event)
        if !relays.isEmpty {
            return relays.prefix(Constants.MAX_SHARE_RELAYS).map { $0 }
        }

        return profileModel.getCappedRelays()
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
                Task { UIPasteboard.general.string = Bech32Object.encode(.nevent(NEvent(event: event, relays: await event_relay_url_strings()))) }
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
                        Task { await damus_state.nostrNetwork.postbox.send(new_mutelist_ev) }
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
            profileModel.findRelaysListener?.cancel()
        }
    }
}

