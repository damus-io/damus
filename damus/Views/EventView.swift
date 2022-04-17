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
    let highlighted: Bool
    
    @EnvironmentObject var profiles: Profiles

    var body: some View {
        let profile = profiles.lookup(id: event.pubkey)
        HStack {
            VStack {
                ProfilePicView(picture: profile?.picture, size: 64, highlighted: highlighted)

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
                    .textSelection(.enabled)

                Spacer()

                EventActionBar(event: event, profiles: profiles)

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
