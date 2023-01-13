//
//  NIP05Badge.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct NIP05Badge: View {
    let nip05: NIP05
    let pubkey: String
    let contacts: Contacts
    let show_domain: Bool
    let clickable: Bool
    
    @Environment(\.openURL) var openURL
    
    init (nip05: NIP05, pubkey: String, contacts: Contacts, show_domain: Bool, clickable: Bool) {
        self.nip05 = nip05
        self.pubkey = pubkey
        self.contacts = contacts
        self.show_domain = show_domain
        self.clickable = clickable
    }
    
    var nip05_color: Color {
       return get_nip05_color(pubkey: pubkey, contacts: contacts)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundColor(nip05_color)
            if show_domain {
                if clickable {
                    Text(nip05.host)
                        .foregroundColor(nip05_color)
                        .onTapGesture {
                            if let nip5url = nip05.siteUrl {
                                openURL(nip5url)
                            }
                        }
                } else {
                    Text(nip05.host)
                        .foregroundColor(nip05_color)
                }
            }
        }

    }
}

func get_nip05_color(pubkey: String, contacts: Contacts) -> Color {
    return contacts.is_friend_or_self(pubkey) ? .accentColor : .gray
}

struct NIP05Badge_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
        NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, contacts: test_state.contacts, show_domain: true, clickable: false)
    }
}

