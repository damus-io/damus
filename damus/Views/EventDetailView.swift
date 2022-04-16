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

            VStack {
                HStack {
                    ProfileName(pubkey: event.pubkey, profile: profile)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    Spacer()
                    PowView(event.pow)
                }
                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .padding([.bottom], 10)

                EventActionBar(event: event)

                Spacer()
            }
        }
        .padding()
    }
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailView(event: NostrEvent(content: "Hello", pubkey: "Guy"), profile: nil)
    }
}
