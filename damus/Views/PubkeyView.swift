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
            Text("\(abbrev_pubkey(pubkey))")
                .foregroundColor(color)
        }
    }
}

func abbrev_pubkey(_ pubkey: String) -> String {
    return pubkey.prefix(4) + ":" + pubkey.suffix(4)
}

/*
struct PubkeyView_Previews: PreviewProvider {
    static var previews: some View {
        PubkeyView()
    }
}
 */
