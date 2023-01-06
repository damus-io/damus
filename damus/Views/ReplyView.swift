//
//  ReplyView.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import SwiftUI

func all_referenced_pubkeys(_ ev: NostrEvent) -> [ReferencedId] {
    var keys = ev.referenced_pubkeys
    let ref = ReferencedId(ref_id: ev.pubkey, relay_id: nil, key: "p")
    keys.insert(ref, at: 0)
    return keys
}

struct ReplyView: View {
    let replying_to: NostrEvent
    let damus: DamusState
    
    var body: some View {
        VStack {
            Text("Replying to:")
            HStack(alignment: .top) {
                let names = all_referenced_pubkeys(replying_to)
                    .map { pubkey in
                        let pk = pubkey.ref_id
                        let prof = damus.profiles.lookup(id: pk)
                        return Profile.displayName(profile: prof, pubkey: pk)
                    }
                    .joined(separator: ", ")
                Text(names)
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            ScrollView {
                EventView(event: replying_to, highlight: .none, has_action_bar: false, damus: damus, show_friend_icon: true)                
            }
            PostView(replying_to: replying_to, references: gather_reply_ids(our_pubkey: damus.pubkey, from: replying_to))
        }
        .padding()
        
    }
    
    
}

struct ReplyView_Previews: PreviewProvider {
    static var previews: some View {
        ReplyView(replying_to: NostrEvent(content: "hi", pubkey: "pubkey"), damus: test_damus_state())
    }
}
