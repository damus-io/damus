//
//  PubkeyView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

func abbrev_pubkey(_ pubkey: String, amount: Int = 8) -> String {
    return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}
