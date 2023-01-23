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

    init(event: NostrEvent, has_action_bar: Bool, damus: DamusState) {
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
        return Group {
            if event.known_kind == .boost, let inner_ev = event.inner_event {
                VStack(alignment: .leading) {
                    let prof_model = ProfileModel(pubkey: event.pubkey, damus: damus)
                    let follow_model = FollowersModel(damus_state: damus, target: event.pubkey)
                    let prof = damus.profiles.lookup(id: event.pubkey)
                    let booster_profile = ProfileView(damus_state: damus, profile: prof_model, followers: follow_model)
                    
                    NavigationLink(destination: booster_profile) {
                        Reposted(damus: damus, pubkey: event.pubkey, profile: prof)
                    }
                    .buttonStyle(PlainButtonStyle())
                    TextEvent(inner_ev, pubkey: inner_ev.pubkey, booster_pubkey: event.pubkey)
                        .padding([.top], 1)
                }
            } else {
                TextEvent(event, pubkey: pubkey)
                    .padding([.top], 6)
            }
        }
    }

    func TextEvent(_ event: NostrEvent, pubkey: String, booster_pubkey: String? = nil) -> some View {
        let content = event.get_content(damus.keypair.privkey)
        
        return HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)
        
            VStack {
                let pmodel = ProfileModel(pubkey: pubkey, damus: damus)
                let pv = ProfileView(damus_state: damus, profile: pmodel, followers: FollowersModel(damus_state: damus, target: pubkey))
                
                NavigationLink(destination: pv) {
                    ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus.profiles)
                }
                
                Spacer()
            }

            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    EventProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true, size: .normal)
                    
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                }
                
                EventBody(damus_state: damus, event: event, size: .normal)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                }
                
                if has_action_bar {
                    Rectangle().frame(height: 2).opacity(0)
                    
                    let bar = make_actionbar_model(ev: event, damus: damus)
                    
                    EventActionBar(damus_state: damus, event: event, bar: bar)
                        .padding([.top], 4)
                }

                Divider()
                    .padding([.top], 4)
            }
            .padding([.leading], 2)
        }
        .contentShape(Rectangle())
        .background(event_validity_color(event.validity))
        .id(event.id)
        .frame(maxWidth: .infinity, minHeight: PFP_SIZE)
        .padding([.bottom], 2)
        .event_context_menu(event, pubkey: pubkey, privkey: damus.keypair.privkey)
    }
}

// blame the porn bots for this code
func should_show_images(contacts: Contacts, ev: NostrEvent, our_pubkey: String, booster_pubkey: String? = nil) -> Bool {
    if ev.pubkey == our_pubkey {
        return true
    }
    if contacts.is_in_friendosphere(ev.pubkey) {
        return true
    }
    if let boost_key = booster_pubkey, contacts.is_in_friendosphere(boost_key) {
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
    
    func event_context_menu(_ event: NostrEvent, pubkey: String, privkey: String?) -> some View {
        return self.contextMenu {
            Button {
                UIPasteboard.general.string = event.get_content(privkey)
            } label: {
                Label(NSLocalizedString("Copy Text", comment: "Context menu option for copying the text from an note."), systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = bech32_pubkey(pubkey) ?? pubkey
            } label: {
                Label(NSLocalizedString("Copy User ID", comment: "Context menu option for copying the ID of the user who created the note."), systemImage: "person")
            }

            Button {
                UIPasteboard.general.string = bech32_note_id(event.id) ?? event.id
            } label: {
                Label(NSLocalizedString("Copy Note ID", comment: "Context menu option for copying the ID of the note."), systemImage: "note.text")
            }

            Button {
                UIPasteboard.general.string = event_to_json(ev: event)
            } label: {
                Label(NSLocalizedString("Copy Note JSON", comment: "Context menu option for copying the JSON text from the note."), systemImage: "j.square.on.square")
            }

            Button {
                NotificationCenter.default.post(name: .broadcast_event, object: event)
            } label: {
                Label(NSLocalizedString("Broadcast", comment: "Context menu option for broadcasting the user's note to all of the user's connected relay servers."), systemImage: "globe")
            }
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


func reply_desc(profiles: Profiles, event: NostrEvent) -> String {
    let desc = make_reply_description(event.tags)
    let pubkeys = desc.pubkeys
    let n = desc.others

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Reply to self", comment: "Label to indicate that the user is replying to themself.")
    }

    let names: [String] = pubkeys.map {
        let prof = profiles.lookup(id: $0)
        return Profile.displayName(profile: prof, pubkey: $0)
    }

    if names.count == 2 {
        if n > 2 {
            let othersCount = n - pubkeys.count
            return String(format: NSLocalizedString("replying_to_two_and_others", comment: "Label to indicate that the user is replying to 2 users and others."), names[0], names[1], othersCount)
        }
        return String(format: NSLocalizedString("Replying to %@ & %@", comment: "Label to indicate that the user is replying to 2 users."), names[0], names[1])
    }

    let othersCount = n - pubkeys.count
    return String(format: NSLocalizedString("replying_to_one_and_others", comment: "Label to indicate that the user is replying to 1 user and others."), names[0], othersCount)
}



func make_actionbar_model(ev: NostrEvent, damus: DamusState) -> ActionBarModel {
    let likes = damus.likes.counts[ev.id]
    let boosts = damus.boosts.counts[ev.id]
    let tips = damus.tips.tips[ev.id]
    let our_like = damus.likes.our_events[ev.id]
    let our_boost = damus.boosts.our_events[ev.id]
    let our_tip = damus.tips.our_tips[ev.id]

    return ActionBarModel(likes: likes ?? 0,
                          boosts: boosts ?? 0,
                          tips: tips ?? 0,
                          our_like: our_like,
                          our_boost: our_boost,
                          our_tip: our_tip
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
                event: test_event,
                has_action_bar: true,
                damus: test_damus_state()
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
