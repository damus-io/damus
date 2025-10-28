//
//  MutelistView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct MutelistView: View {
    let damus_state: DamusState
    @State var show_add_muteitem: Bool = false

    @State var users: [MuteItem] = []
    @State var hashtags: [MuteItem] = []
    @State var threads: [MuteItem] = []
    @State var words: [MuteItem] = []
    
    @State var new_text: String = ""

    func RemoveAction(item: MuteItem) -> some View {
        Button {
            guard let mutelist = damus_state.mutelist_manager.event,
                  let keypair = damus_state.keypair.to_full(),
                  let new_ev = remove_from_mutelist(keypair: keypair,
                                                    prev: mutelist,
                                                    to_remove: item)
            else {
                return
            }

            damus_state.mutelist_manager.set_mutelist(new_ev)
            damus_state.settings.latest_mutelist_event_id_hex = new_ev.id.hex()
            Task {
                await damus_state.nostrNetwork.postbox.send(new_ev)
                updateMuteItems()
            }
        } label: {
            Label(NSLocalizedString("Delete", comment: "Button to remove a user from their mutelist."), image: "delete")
        }
        .tint(.red)
    }

    func updateMuteItems() {
        users = Array(damus_state.mutelist_manager.users)
        hashtags = Array(damus_state.mutelist_manager.hashtags)
        threads = Array(damus_state.mutelist_manager.threads)
        words = Array(damus_state.mutelist_manager.words)
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Hashtags", comment: "Section header title for a list of hashtags that are muted.")) {
                ForEach(hashtags, id: \.self) { item in
                    if case let MuteItem.hashtag(hashtag, _) = item {
                        Text(verbatim: "#\(hashtag.hashtag)")
                            .id(hashtag.hashtag)
                            .swipeActions {
                                RemoveAction(item: .hashtag(hashtag, nil))
                            }
                            .onTapGesture {
                                damus_state.nav.push(route: Route.Search(search: SearchModel.init(state: damus_state, search: NostrFilter(hashtag: [hashtag.hashtag]))))
                            }
                    }
                }
            }
            Section(NSLocalizedString("Words", comment: "Section header title for a list of words that are muted.")) {
                ForEach(words, id: \.self) { item in
                    if case let MuteItem.word(word, _) = item {
                        Text(word)
                            .id(word)
                            .swipeActions {
                                RemoveAction(item: .word(word, nil))
                            }
                    }
                }
            }
            Section(NSLocalizedString("Threads", comment: "Section header title for a list of threads that are muted.")) {
                ForEach(threads, id: \.self) { item in
                    if case let MuteItem.thread(note_id, _) = item {
                        if let event = damus_state.events.lookup(note_id) {
                            EventView(damus: damus_state, event: event)
                                .id(note_id.hex())
                                .swipeActions {
                                    RemoveAction(item: .thread(note_id, nil))
                                }
                        } else {
                            Text("Error retrieving muted event", comment: "Text for an item that application failed to retrieve the muted event for.")
                        }
                    }
                }
            }
            Section(
                header: Text(NSLocalizedString("Users", comment: "Section header title for a list of muted users.")),
                footer: Text("").padding(.bottom, 10 + tabHeight + getSafeAreaBottom())
            ) {
                ForEach(users, id: \.self) { user in
                    if case let MuteItem.user(pubkey, _) = user {
                        UserViewRow(damus_state: damus_state, pubkey: pubkey)
                            .id(pubkey)
                            .swipeActions {
                                RemoveAction(item: .user(pubkey, nil))
                            }
                            .onTapGesture {
                                damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                            }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Muted", comment: "Navigation title of view to see list of muted users & phrases."))
        .onAppear {
            updateMuteItems()
        }
        .onReceive(handle_notify(.new_mutes)) { new_mutes in
            updateMuteItems()
        }
        .onReceive(handle_notify(.new_unmutes)) { new_unmutes in
            updateMuteItems()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    self.show_add_muteitem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $show_add_muteitem, onDismiss: { self.show_add_muteitem = false }) {
            AddMuteItemView(state: damus_state, new_text: $new_text)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}

struct MutelistView_Previews: PreviewProvider {
    static var previews: some View {
        MutelistView(damus_state: test_damus_state)
    }
}
