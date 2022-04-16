//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI
import CachedAsyncImage

struct EventView: View {
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
                    if (event.pow ?? 0) >= 10 {
                        PowView(event.pow)
                    }
                }
                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                EventActionBar(event: event)

                Divider()
                    .padding([.top], 4)
            }
        }
        .frame(minHeight: PFP_SIZE)
        .padding([.bottom], 4)
    }
}


func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}
