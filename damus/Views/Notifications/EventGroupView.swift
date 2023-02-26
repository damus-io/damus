//
//  RepostGroupView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI


enum EventGroupType {
    case repost(EventGroup)
    case reaction(EventGroup)
    case zap(ZapGroup)
    case profile_zap(ZapGroup)
    
    var events: [NostrEvent] {
        switch self {
        case .repost(let grp):
            return grp.events
        case .reaction(let grp):
            return grp.events
        case .zap(let zapgrp):
            return zapgrp.zap_requests()
        case .profile_zap(let zapgrp):
            return zapgrp.zap_requests()
        }
    }
}

enum ReactingTo {
    case your_post
    case tagged_in
    case your_profile
}

func determine_reacting_to(our_pubkey: String, ev: NostrEvent?) -> ReactingTo {
    guard let ev else {
        return .your_profile
    }
    
    if ev.pubkey == our_pubkey {
        return .your_post
    }
    
    return .tagged_in
}

func determine_reacting_to_text(_ r: ReactingTo) -> String {
    switch r {
    case .tagged_in:
        return "a post you were tagged in"
    case .your_post:
        return "your post"
    case .your_profile:
        return "your profile"
    }
}

func event_author_name(profiles: Profiles, _ ev: NostrEvent) -> String {
    let alice_pk = ev.pubkey
    let alice_prof = profiles.lookup(id: alice_pk)
    return Profile.displayName(profile: alice_prof, pubkey: alice_pk)
}

func reacting_to_text(profiles: Profiles, our_pubkey: String, group: EventGroupType, ev: NostrEvent?) -> String {
    let verb = reacting_to_verb(group: group)
    
    let reacting_to = determine_reacting_to(our_pubkey: our_pubkey, ev: ev)
    let target = determine_reacting_to_text(reacting_to)
    
    if group.events.count == 1 {
        let ev = group.events.first!
        let profile = profiles.lookup(id: ev.pubkey)
        let display_name = Profile.displayName(profile: profile, pubkey: ev.pubkey)
        return String(format: "%@ is %@ %@", display_name, verb, target)
    }
    
    if group.events.count == 2 {
        let alice_name = event_author_name(profiles: profiles, group.events[0])
        let bob_name = event_author_name(profiles: profiles, group.events[1])
        
        return String(format: "%@ and %@ are %@ %@", alice_name, bob_name, verb, target)
    }
    
    if group.events.count > 2 {
        let alice_name = event_author_name(profiles: profiles, group.events.first!)
        let count = group.events.count - 1
        
        return String(format: "%@ and %d other people are %@ %@", alice_name, count, verb, target)
    }
    
    return "??"
}

func reacting_to_verb(group: EventGroupType) -> String {
    switch group {
    case .reaction:
        return "reacting to"
    case .repost:
        return "reposting"
    case .zap: fallthrough
    case .profile_zap:
        return "zapping"
    }
}

struct EventGroupView: View {
    let state: DamusState
    let event: NostrEvent?
    let group: EventGroupType
    
    var GroupDescription: some View {
        Text(reacting_to_text(profiles: state.profiles, our_pubkey: state.pubkey, group: group, ev: event))
    }
    
    func ZapIcon(_ zapgrp: ZapGroup) -> some View {
        let fmt = format_msats_abbrev(zapgrp.msat_total)
        return VStack(alignment: .center) {
            Image(systemName: "bolt.fill")
                .foregroundColor(.orange)
            Text("\(fmt)")
                .foregroundColor(Color.orange)
        }
    }
    
    var GroupIcon: some View {
        Group {
            switch group {
            case .repost:
                Image(systemName: "arrow.2.squarepath")
                    .foregroundColor(Color("DamusGreen"))
            case .reaction:
                Image("shaka-full")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.accentColor)
            case .profile_zap(let zapgrp):
                ZapIcon(zapgrp)
            case .zap(let zapgrp):
                ZapIcon(zapgrp)
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            GroupIcon
                .frame(width: PFP_SIZE + 10)
            
            VStack(alignment: .leading) {
                ProfilePicturesView(state: state, events: group.events)
                
                GroupDescription
                
                if let event {
                    NavigationLink(destination: BuildThreadV2View(damus: state, event_id: event.id)) {
                        Text(event.content)
                            .padding([.top], 1)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding([.top], 6)
    }
}

let test_encoded_post = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"
let test_repost = NostrEvent(id: "", content: test_encoded_post, pubkey: "", kind: 6, tags: [], createdAt: 1)
let test_reposts = [test_repost, test_repost]
let test_event_group = EventGroup(events: test_reposts)

struct EventGroupView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            EventGroupView(state: test_damus_state(), event: test_event, group: .repost(test_event_group))
                .frame(height: 200)
                .padding()
            
            EventGroupView(state: test_damus_state(), event: test_event, group: .reaction(test_event_group))
                .frame(height: 200)
                .padding()
        }
    }
    
}

