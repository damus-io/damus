//
//  NIP05DomainPubkeysView.swift
//  damus
//
//  Created by Terry Yiu on 5/23/25.
//

import FaviconFinder
import Kingfisher
import SwiftUI

struct NIP05DomainPubkeysView: View {
    let damus_state: DamusState
    let domain: String
    let nip05_domain_favicon: FaviconURL?
    let pubkeys: [Pubkey]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(pubkeys, id: \.self) { pk in
                    FollowUserView(target: .pubkey(pk), damus_state: damus_state)
                }
            }
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    if let nip05_domain_favicon {
                        KFImage(nip05_domain_favicon.source)
                            .imageContext(.favicon, disable_animation: true)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .clipped()
                    }
                    Text(domain)
                        .font(.headline)
                }
            }
        }
    }
}

#Preview {
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    let pubkeys = [test_pubkey, test_pubkey_2]
    NIP05DomainPubkeysView(damus_state: test_damus_state, domain: "damus.io", nip05_domain_favicon: nip05_domain_favicon, pubkeys: pubkeys)
}
