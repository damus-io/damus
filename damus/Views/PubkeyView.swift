//
//  PubkeyView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

struct PubkeyView: View {
    let pubkey: String
    let relay: String?
    
    var body: some View {
        let color: Color = id_to_color(pubkey)
        ZStack {
            Text("\(abbrev_pubkey(pubkey))", comment: "Abbreviated version of a nostr public key.")
                .foregroundColor(color)
        }
    }
}

func abbrev_pubkey(_ pubkey: String, amount: Int = 8) -> String {
    return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}

/*
struct PubkeyView_Previews: PreviewProvider {
    static var previews: some View {
        PubkeyView()
    }
}
 */
