//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct EventDetailView: View {
    let event: NostrEvent
    let profile: Profile?

    var body: some View {
        HStack {
            VStack {
                ProfilePicView(picture: profile?.picture, size: 64)

                Spacer()
            }
        }
    }
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailView(event: NostrEvent(content: "Hello", pubkey: "Guy"), profile: nil)
    }
}
