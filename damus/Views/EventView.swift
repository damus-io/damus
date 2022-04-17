//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI
import CachedAsyncImage

enum Highlight {
    case none
    case main
    case replied_to(String)

    var is_none: Bool {
        switch self {
        case .none: return true
        default: return false
        }
    }

    var is_replied_to: Bool {
        switch self {
        case .replied_to: return true
        default: return false
        }
    }
}

struct EventView: View {
    let event: NostrEvent
    let highlight: Highlight
    let has_action_bar: Bool

    @EnvironmentObject var profiles: Profiles

    var body: some View {
        let profile = profiles.lookup(id: event.pubkey)
        HStack {
            VStack {
                ProfilePicView(picture: profile?.picture, size: 64, highlight: highlight)

                Spacer()
            }

            VStack {
                HStack {
                    ProfileName(pubkey: event.pubkey, profile: profile)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    if event.is_reply {
                        Label("", systemImage: "arrowshape.turn.up.left")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if (event.pow ?? 0) >= 10 {
                        PowView(event.pow)
                    }
                }

                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Spacer()

                if has_action_bar {
                    EventActionBar(event: event)
                }

                Divider()
                    .padding([.top], 4)
            }
            .padding([.leading], 2)
        }
        .id(event.id)
        .frame(minHeight: PFP_SIZE)
        .padding([.bottom], 4)
    }
}


func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}
