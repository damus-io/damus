//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct EventDetailView: View {
    let event: NostrEvent

    var body: some View {
        Text("EventDetailView")
    }
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailView(event: NostrEvent(content: "Hello", pubkey: "Guy"))
    }
}
