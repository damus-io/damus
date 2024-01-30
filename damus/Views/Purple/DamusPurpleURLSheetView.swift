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
        switch self.purple_url.variant {
            case .verify_npub(let checkout_id):
                DamusPurpleVerifyNpubView(damus_state: damus_state, checkout_id: checkout_id)
            case .welcome(_):
                // Forcibly pass the dismiss environment object,
                // because SwiftUI has a weird quirk that makes the `dismiss` Environment object unavailable in deeply nested views
                // this problem only exists in real devices.
                DamusPurpleNewUserOnboardingView(damus_state: damus_state, dismiss: _dismiss)
            case .landing:
                DamusPurpleView(damus_state: damus_state)
        }
    }
}

struct DamusPurpleURLSheetView_Previews: PreviewProvider {
    static var previews: some View {
        DamusPurpleURLSheetView(damus_state: test_damus_state, purple_url: .init(is_staging: false, variant: .verify_npub(checkout_id: "123")))
    }
}

