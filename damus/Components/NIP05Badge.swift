//
//  NIP05Badge.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct NIP05Badge: View {
    let nip05: NIP05
    let pubkey: Pubkey
    let contacts: Contacts
    let show_domain: Bool
    let profiles: Profiles

    @Environment(\.openURL) var openURL
    
    init(nip05: NIP05, pubkey: Pubkey, contacts: Contacts, show_domain: Bool, profiles: Profiles) {
        self.nip05 = nip05
        self.pubkey = pubkey
        self.contacts = contacts
        self.show_domain = show_domain
        self.profiles = profiles
    }
    
    var nip05_color: Bool {
       return use_nip05_color(pubkey: pubkey, contacts: contacts)
    }
    
    var Seal: some View {
        Group {
            if nip05_color {
                LINEAR_GRADIENT
                    .mask(Image("verified.fill")
                        .resizable()
                    ).frame(width: 18, height: 18)
            } else if show_domain {
                Image("verified")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .nip05_colorized(gradient: nip05_color)
            }
        }
    }

    var username_matches_nip05: Bool {
        guard let profile = profiles.lookup(id: pubkey),
              let name = profile.name
        else {
            return false
        }

        return name.lowercased() == nip05.username.lowercased()
    }

    var nip05_string: String {
        if nip05.username == "_" || username_matches_nip05 {
            return nip05.host
        } else {
            return "\(nip05.username)@\(nip05.host)"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Seal

            if show_domain {
                Text(nip05_string)
                    .nip05_colorized(gradient: nip05_color)
                    .onTapGesture {
                        if let nip5url = nip05.siteUrl {
                            openURL(nip5url)
                        }
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

func use_nip05_color(pubkey: Pubkey, contacts: Contacts) -> Bool {
    return contacts.is_friend_or_self(pubkey) ? true : false
}

struct NIP05Badge_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
        VStack {
            NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, contacts: test_state.contacts, show_domain: true, profiles: test_state.profiles)

            NIP05Badge(nip05: NIP05(username: "_", host: "jb55.com"), pubkey: test_state.pubkey, contacts: test_state.contacts, show_domain: true, profiles: test_state.profiles)

            NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, contacts: test_state.contacts, show_domain: true, profiles: test_state.profiles)

            NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, contacts: Contacts(our_pubkey: test_pubkey), show_domain: true, profiles: test_state.profiles)
        }
    }
}

