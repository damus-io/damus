//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

enum Highlight {
    case none
    case main
    case reply
    case custom(Color, Float)

    var is_main: Bool {
        if case .main = self {
            return true
        }
        return false
    }
    
    var is_none: Bool {
        if case .none = self {
            return true
        }
        return false
    }

    var is_replied_to: Bool {
        switch self {
        case .reply: return true
        default: return false
        }
    }
}

struct EventView: View {
    let event: NostrEvent
    let highlight: Highlight
    let has_action_bar: Bool
    let pool: RelayPool

    @EnvironmentObject var profiles: Profiles
    @EnvironmentObject var action_bar: ActionBarModel
    
    var body: some View {
        let profile = profiles.lookup(id: event.pubkey)
        HStack {
            VStack {
                let pv = ProfileView(pool: pool, profile: ProfileModel(pubkey: event.pubkey, pool: pool))
                    .environmentObject(profiles)
                
                NavigationLink(destination: pv) {
                    ProfilePicView(picture: profile?.picture, size: PFP_SIZE!, highlight: highlight)
                }

                Spacer()
            }

            VStack {
                HStack {
                    ProfileName(pubkey: event.pubkey, profile: profile)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    Spacer()
                }
                
                if event.is_reply {
                    Text("\(reply_desc(profiles: profiles, event: event))")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Spacer()

                if has_action_bar {
                    EventActionBar(event: event)
                        .environmentObject(profiles)
                }

                Divider()
                    .padding([.top], 4)
            }
            .padding([.leading], 2)
        }
        .contentShape(Rectangle())
        .id(event.id)
        .frame(minHeight: PFP_SIZE)
        .padding([.bottom], 4)
        .contextMenu {
            Button {
                UIPasteboard.general.string = event.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button {
                UIPasteboard.general.string = event.id
            } label: {
                Label("Copy ID", systemImage: "tag")
            }
            
            Button {
                NotificationCenter.default.post(name: .broadcast_event, object: event)
            } label: {
                Label("Broadcast", systemImage: "globe")
            }
        }
    }
}


func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}

func reply_desc(profiles: Profiles, event: NostrEvent) -> String {
    let (pubkeys, n) = event.reply_description
    if pubkeys.count == 0 {
        return "Reply to self"
    }
    
    let names: [String] = pubkeys.map {
        let prof = profiles.lookup(id: $0)
        return Profile.displayName(profile: prof, pubkey: $0)
    }
    
    if names.count == 2 {
        if n > 2 {
            let and_other = reply_others_desc(n: n, n_pubkeys: pubkeys.count)
            return "Replying to \(names[0]), \(names[1])\(and_other)"
        }
        return "Replying to \(names[0]) & \(names[1])"
    }
    
    let and_other = reply_others_desc(n: n, n_pubkeys: pubkeys.count)
    return "Replying to \(names[0])\(and_other)"
}

func reply_others_desc(n: Int, n_pubkeys: Int) -> String {
    let other = n - n_pubkeys
    let plural = other == 1 ? "" : "s"
    return n > 1 ? " & \(other) other\(plural)" : ""
}


