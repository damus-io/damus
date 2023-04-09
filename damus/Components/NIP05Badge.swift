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
    
    var nip05_color: Bool {
       return use_nip05_color(pubkey: pubkey, contacts: contacts)
    }
    
    var Seal: some View {
        Group {
            if nip05_color {
                LINEAR_GRADIENT
                    .mask(Image(systemName: "checkmark.seal.fill")
                        .resizable()
                    ).frame(width: 14, height: 14)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Seal
            
            if show_domain {
                if clickable {
                    Text(nip05.host)
                        .nip05_colorized(gradient: nip05_color)
                        .onTapGesture {
                            if let nip5url = nip05.siteUrl {
                                openURL(nip5url)
                            }
                        }
                } else {
                    Text(nip05.host)
                        .foregroundColor(.gray)
                }
            }
        }

    }
}

extension View {
    func nip05_colorized(gradient: Bool) -> some View {
        if gradient {
            return AnyView(self.foregroundStyle(LINEAR_GRADIENT))
        } else {
            return AnyView(self.foregroundColor(.gray))
        }
        
    }
}

func use_nip05_color(pubkey: String, contacts: Contacts) -> Bool {
    return contacts.is_friend_or_self(pubkey) ? true : false
}

struct NIP05Badge_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
        NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, contacts: test_state.contacts, show_domain: true, clickable: false)
    }
}

