//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

enum EventViewKind {
    case small
    case normal
    case selected
}

func eventviewsize_to_font(_ size: EventViewKind) -> Font {
    switch size {
    case .small:
        return .body
    case .normal:
        return .body
    case .selected:
        return .custom("selected", size: 21.0)
    }
}



struct EventView: View {
    let event: NostrEvent
    let has_action_bar: Bool
    let damus: DamusState
    let pubkey: String

    @EnvironmentObject var action_bar: ActionBarModel

    init(damus: DamusState, event: NostrEvent, has_action_bar: Bool) {
        self.event = event
        self.has_action_bar = has_action_bar
        self.damus = damus
        self.pubkey = event.pubkey
    }

    init(damus: DamusState, event: NostrEvent) {
        self.event = event
        self.has_action_bar = false
        self.damus = damus
        self.pubkey = event.pubkey
    }

    init(damus: DamusState, event: NostrEvent, pubkey: String) {
        self.event = event
        self.has_action_bar = false
        self.damus = damus
        self.pubkey = pubkey
    }

    var body: some View {
        VStack {
            if event.known_kind == .boost {
                if let inner_ev = event.inner_event {
                    VStack(alignment: .leading) {
                        let prof_model = ProfileModel(pubkey: event.pubkey, damus: damus)
                        let follow_model = FollowersModel(damus_state: damus, target: event.pubkey)
                        let prof = damus.profiles.lookup(id: event.pubkey)
                        let booster_profile = ProfileView(damus_state: damus, profile: prof_model, followers: follow_model)
                        
                        NavigationLink(destination: booster_profile) {
                            Reposted(damus: damus, pubkey: event.pubkey, profile: prof)
                        }
                        .buttonStyle(PlainButtonStyle())
                        TextEvent(damus: damus, event: inner_ev, pubkey: inner_ev.pubkey, has_action_bar: has_action_bar, booster_pubkey: event.pubkey)
                            .padding([.top], 1)
                    }
                } else {
                    EmptyView()
                }
            } else if event.known_kind == .zap {
                if let zap = damus.zaps.zaps[event.id] {
                    ZapEvent(damus: damus, zap: zap)
                } else {
                    EmptyView()
                }
            } else {
                TextEvent(damus: damus, event: event, pubkey: pubkey, has_action_bar: has_action_bar, booster_pubkey: nil)
                    .padding([.top], 6)
            }
            
            Divider()
                .padding([.top], 4)
        }
    }
}

// blame the porn bots for this code
func should_show_images(contacts: Contacts, ev: NostrEvent, our_pubkey: String, booster_pubkey: String? = nil) -> Bool {
    if ev.pubkey == our_pubkey {
        return true
    }

    let remote_image_policy: RemoteImagePolicy = RemoteImagePolicy(rawValue: UserDefaults.standard.string(forKey: "remote_image_policy") ?? "") ?? .friendsOfFriends
    if remote_image_policy == .everyone ||
       remote_image_policy == .friendsOnly && contacts.is_friend(ev.pubkey) ||
       remote_image_policy == .friendsOfFriends && contacts.is_in_friendosphere(ev.pubkey) {
        return true
    }

    if let boost_key = booster_pubkey, contacts.is_in_friendosphere(boost_key) && remote_image_policy != .restricted {
        return true
    }
    
    return false
}

func event_validity_color(_ validation: ValidationResult) -> some View {
    Group {
        switch validation {
        case .ok:
            EmptyView()
        case .bad_id:
            Color.orange.opacity(0.4)
        case .bad_sig:
            Color.red.opacity(0.4)
        }
    }
}

extension View {
    func pubkey_context_menu(bech32_pubkey: String) -> some View {
        return self.contextMenu {
            Button {
                    UIPasteboard.general.string = bech32_pubkey
            } label: {
                Label(NSLocalizedString("Copy Account ID", comment: "Context menu option for copying the ID of the account that created the note."), systemImage: "doc.on.doc")
            }
        }
    }
    
    func event_context_menu(_ event: NostrEvent, keypair: Keypair, target_pubkey: String) -> some View {
        return self.contextMenu {
            EventMenuContext(event: event, keypair: keypair, target_pubkey: target_pubkey)
        }

    }
}

func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}

func format_date(_ created_at: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(created_at))
    let dateFormatter = DateFormatter()
    dateFormatter.timeStyle = .short
    dateFormatter.dateStyle = .short
    return dateFormatter.string(from: date)
}



func make_actionbar_model(ev: NostrEvent, damus: DamusState) -> ActionBarModel {
    let likes = damus.likes.counts[ev.id]
    let boosts = damus.boosts.counts[ev.id]
    let zaps = damus.zaps.event_counts[ev.id]
    let zap_total = damus.zaps.event_totals[ev.id]
    let our_like = damus.likes.our_events[ev.id]
    let our_boost = damus.boosts.our_events[ev.id]
    let our_zap = damus.zaps.our_zaps[ev.id]

    return ActionBarModel(likes: likes ?? 0,
                          boosts: boosts ?? 0,
                          zaps: zaps ?? 0,
                          zap_total: zap_total ?? 0,
                          our_like: our_like,
                          our_boost: our_boost,
                          our_zap: our_zap?.first
    )
}


struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            /*
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .small)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .normal)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .big)
            
             */
            EventView(
                damus: test_damus_state(),
                event: test_event,
                has_action_bar: true
            )
        }
        .padding()
    }
}

let test_event =
        NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
