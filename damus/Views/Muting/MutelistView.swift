//
//  MutelistView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct MutelistView: View {
    let damus_state: DamusState
    @State var users: [String]
    
    func RemoveAction(pubkey: String) -> some View {
        Button {
            guard let mutelist = damus_state.contacts.mutelist else {
                return
            }
            
            guard let keypair = damus_state.keypair.to_full() else {
                return
            }
            
            guard let new_ev = remove_from_mutelist(keypair: keypair, prev: mutelist, to_remove: pubkey) else {
                return
            }
            
            damus_state.contacts.set_mutelist(new_ev)
            damus_state.postbox.send(new_ev)
            users = get_mutelist_users(new_ev)
        } label: {
            Label(NSLocalizedString("Delete", comment: "Button to remove a user from their mutelist."), image: "delete")
        }
        .tint(.red)
    }

    
    var body: some View {
        List(users, id: \.self) { pubkey in
            UserViewRow(damus_state: damus_state, pubkey: pubkey)
                .id(pubkey)
                .swipeActions {
                    RemoveAction(pubkey: pubkey)
                }
                .onTapGesture {
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                }
        }
        .navigationTitle(NSLocalizedString("Muted Users", comment: "Navigation title of view to see list of muted users."))
        .onAppear {
            users = get_mutelist_users(damus_state.contacts.mutelist) 
        }
    }
}


func get_mutelist_users(_ mlist: NostrEvent?) -> [String] {
    guard let mutelist = mlist else {
        return []
    }
    
    return mutelist.tags.reduce(into: Array<String>()) { pks, tag in
        if tag.count >= 2 && tag[0] == "p" {
            pks.append(tag[1])
        }
    }
}

struct MutelistView_Previews: PreviewProvider {
    static var previews: some View {
        MutelistView(damus_state: test_damus_state(), users: [test_event.pubkey, test_event.pubkey+"hi"])
    }
}
