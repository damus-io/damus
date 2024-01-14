//
//  DamusPurpleURLSheetView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-13.
//

import Foundation

import SwiftUI

struct DamusPurpleURLSheetView: View {
    @Environment(\.dismiss) var dismiss
    let damus_state: DamusState
    let purple_url: DamusPurpleURL
    
    var body: some View {
        switch self.purple_url {
            case .verify_npub(let checkout_id):
                DamusPurpleVerifyNpubView(damus_state: damus_state, checkout_id: checkout_id)
            case .welcome(_):
                DamusPurpleWelcomeView()
            case .landing:
                DamusPurpleView(damus_state: damus_state)
        }
    }
}

struct DamusPurpleURLSheetView_Previews: PreviewProvider {
    static var previews: some View {
        DamusPurpleURLSheetView(damus_state: test_damus_state, purple_url: .verify_npub(checkout_id: "123"))
    }
}

