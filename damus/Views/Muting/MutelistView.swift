//
//  MutelistView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct MutelistView: View {
    let damus_state: DamusState
    @State var mutelist_items: Set<MuteItem> = Set<MuteItem>()
    @State var show_add_muteitem: Bool = false

    func RemoveAction(item: MuteItem) -> some View {
        Button {
            guard let mutelist = damus_state.contacts.mutelist,
                  let keypair = damus_state.keypair.to_full(),
                  let new_ev = remove_from_mutelist(keypair: keypair,
                                                    prev: mutelist,
                                                    to_remove: item)
            else {
                return
            }

            damus_state.contacts.set_mutelist(new_ev)
            damus_state.postbox.send(new_ev)
            mutelist_items = new_ev.mute_list ?? Set<MuteItem>()
        } label: {
            Label(NSLocalizedString("Delete", comment: "Button to remove a user from their mutelist."), image: "delete")
        }
        .tint(.red)
    }


    var body: some View {
        List {
            Section(NSLocalizedString("Users", comment: "Section header title for a list of muted users.")) {
                ForEach(mutelist_items.users, id: \.self) { pubkey in
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
            Section(NSLocalizedString("Hashtags", comment: "Section header title for a list of hashtags that are muted.")) {
                ForEach(mutelist_items.hashtags, id: \.hashtag) { hashtag in
                    Text("#\(hashtag.hashtag)")
                     .id(hashtag.hashtag)
                     .swipeActions {
                         RemoveAction(item: .hashtag(hashtag, nil))
                     }
                     .onTapGesture {
                         damus_state.nav.push(route: Route.Search(search: SearchModel.init(state: damus_state, search: NostrFilter(hashtag: [hashtag.hashtag]))))
                     }
                }
            }
            Section(NSLocalizedString("Words", comment: "Section header title for a list of words that are muted.")) {
                ForEach(mutelist_items.words, id: \.self) { word in
                    Text("\(word)")
                     .id(word)
                     .swipeActions {
                         RemoveAction(item: .word(word, nil))
                     }
                }
            }
            Section(NSLocalizedString("Threads", comment: "Section header title for a list of threads that are muted.")) {
                ForEach(mutelist_items.threads, id: \.self) { note_id in
                    if let event = damus_state.events.lookup(note_id) {
                        EventView(damus: damus_state, event: event)
                         .id(note_id.hex())
                         .swipeActions {
                             RemoveAction(item: .thread(note_id, nil))
                         }
                    } else {
                        Text(NSLocalizedString("Error retrieving muted event", comment: "Text for an item that application failed to retrieve the muted event for."))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Muted", comment: "Navigation title of view to see list of muted users & phrases."))
        .onAppear {
            mutelist_items = damus_state.contacts.mutelist?.mute_list ?? Set<MuteItem>()
        }
        .onReceive(handle_notify(.new_mutes)) { new_mutes in
            mutelist_items = mutelist_items.union(new_mutes)
        }
        .onReceive(handle_notify(.new_unmutes)) { new_unmutes in
            mutelist_items = mutelist_items.subtracting(new_unmutes)
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
            if #available(iOS 16.0, *) {
                AddMuteItemView(state: damus_state)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                AddMuteItemView(state: damus_state)
            }
        }
    }
}

struct MutelistView_Previews: PreviewProvider {
    static var previews: some View {
        MutelistView(damus_state: test_damus_state, mutelist_items: Set([
            .user(test_note.pubkey, nil),
            .hashtag(Hashtag(hashtag: "test"), nil),
            .word("test", nil),
            .thread(test_note.id, nil)
        ]))
    }
}
