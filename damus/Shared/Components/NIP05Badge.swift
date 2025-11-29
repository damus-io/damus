//
//  NIP05Badge.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import FaviconFinder
import Kingfisher
import SwiftUI

struct NIP05Badge: View {
    let nip05: NIP05
    let pubkey: Pubkey
    let damus_state: DamusState
    let show_domain: Bool
    let nip05_domain_favicon: FaviconURL?

    init(nip05: NIP05, pubkey: Pubkey, damus_state: DamusState, show_domain: Bool, nip05_domain_favicon: FaviconURL?) {
        self.nip05 = nip05
        self.pubkey = pubkey
        self.damus_state = damus_state
        self.show_domain = show_domain
        self.nip05_domain_favicon = nip05_domain_favicon
    }
    
    var nip05_color: Bool {
        return use_nip05_color(pubkey: pubkey, contacts: damus_state.contacts)
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

    var domainBadge: some View {
        Group {
            if let nip05_domain_favicon {
                KFImage(nip05_domain_favicon.source)
                    .imageContext(.favicon, disable_animation: true)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipped()
            } else {
                EmptyView()
            }
        }
    }

    var username_matches_nip05: Bool {
        guard let name = damus_state.profiles.lookup(id: pubkey)?.name
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

            Group {
                if show_domain {
                    Text(nip05_string)
                        .nip05_colorized(gradient: nip05_color)
                }

                if nip05_domain_favicon != nil {
                    domainBadge
                }
            }
            .onTapGesture {
                damus_state.nav.push(route: Route.NIP05DomainEvents(events: NIP05DomainEventsModel(state: damus_state, domain: nip05.host), nip05_domain_favicon: nip05_domain_favicon))
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
        let test_state = test_damus_state
        VStack {
            NIP05Badge(nip05: NIP05(username: "jb55", host: "jb55.com"), pubkey: test_state.pubkey, damus_state: test_state, show_domain: true, nip05_domain_favicon: nil)

            NIP05Badge(nip05: NIP05(username: "_", host: "jb55.com"), pubkey: test_state.pubkey, damus_state: test_state, show_domain: true, nip05_domain_favicon: nil)
        }
    }
}

