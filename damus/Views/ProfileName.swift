//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

func get_friend_icon(contacts: Contacts, pubkey: String, show_confirmed: Bool) -> String? {
    if !show_confirmed {
        return nil
    }
    
    if contacts.is_friend_or_self(pubkey) {
        return "person.fill.checkmark"
    }
    
    if contacts.is_friend_of_friend(pubkey) {
        return "person.fill.and.arrow.left.and.arrow.right"
    }
    
    return nil
}

struct ProfileName: View {
    let damus_state: DamusState
    let pubkey: String
    let profile: Profile?
    let prefix: String
    
    let show_friend_confirmed: Bool
    
    @State var display_name: String?
    @State var nip05: NIP05?
    @State private var isNIP05HostVisible = false
    
    @Environment(\.colorScheme) var colorScheme
    
    init(pubkey: String, profile: Profile?, damus: DamusState, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.show_friend_confirmed = show_friend_confirmed
        self.damus_state = damus
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, damus: DamusState, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.damus_state = damus
        self.show_friend_confirmed = show_friend_confirmed
    }
    
    var friend_icon: String? {
        return get_friend_icon(contacts: damus_state.contacts, pubkey: pubkey, show_confirmed: show_friend_confirmed)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
    
    var nip05_colorgradient: LinearGradient {
        return get_nip05_colorgradient(pubkey: pubkey, contacts: damus_state.contacts)
    }
    
    var nip05_color: Color {
        return get_nip05_color(pubkey: pubkey, contacts: damus_state.contacts)
    }
    
    func nip05fillColor() -> Color {
        colorScheme == .light ? .accentColor : .accentColor
    }
    
    var body: some View {
        
        HStack(spacing: 2) {
            
            Text(prefix + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)
            
            if let nip05 = current_nip05 {
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(nip05fillColor())
                        .frame(width: isNIP05HostVisible ? 150 : 0, height: 15)
                        .animation(.default, value: isNIP05HostVisible)
                        .scaledToFit()
                        .clipped()
                        .padding(.leading, 20)
                        .overlay(
                            Text(nip05.host)
                                .font(.caption2)
                                .padding(.leading, 20)
                                .foregroundColor(Color("DamusDarkGrey"))
                                .scaledToFit()
                                .clipped()
                            )
                    
                    nip05_colorgradient.mask(
                        Image(systemName: "checkmark.seal.fill")
                            .contentShape(Circle())
                            .frame(width: 50, height: 50)
                    )
                    .shadow(color: Color("DamusBlack"), radius: 1, x: 1, y: 1)
                    .frame(width: 50, height: 50)
                    .onTapGesture {
                        //withAnimation {
                        //    self.isNIPCollapsed.toggle()
                        //}
                        isNIP05HostVisible.toggle()
                    }
                }
            }
        }
        .onReceive(handle_notify(.profile_updated)) { notif in
            let update = notif.object as! ProfileUpdate
            if update.pubkey != pubkey {
                return
            }
            display_name = Profile.displayName(profile: update.profile, pubkey: pubkey)
            nip05 = damus_state.profiles.is_validated(pubkey)
        }
    }
}

/// Profile Name used when displaying an event in the timeline
struct EventProfileName: View {
    let damus_state: DamusState
    let pubkey: String
    let profile: Profile?
    let prefix: String
    
    let show_friend_confirmed: Bool
    
    @State var display_name: String?
    @State var nip05: NIP05?
    
    let size: EventViewKind
    
    init(pubkey: String, profile: Profile?, damus: DamusState, show_friend_confirmed: Bool, size: EventViewKind = .normal) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, damus: DamusState, show_friend_confirmed: Bool, size: EventViewKind = .normal) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
    }
    
    var friend_icon: String? {
        return get_friend_icon(contacts: damus_state.contacts, pubkey: pubkey, show_confirmed: show_friend_confirmed)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
    
    var nip05_colorgradient: LinearGradient {
        return get_nip05_colorgradient(pubkey: pubkey, contacts: damus_state.contacts)
    }
   
    var body: some View {
        HStack(spacing: 2) {
            if let real_name = profile?.display_name {
                Text(real_name)
                    .font(.body.weight(.bold))
                    .padding([.trailing], 2)
                
                Text("@" + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .foregroundColor(.gray)
                    .font(eventviewsize_to_font(size))
            } else {
                Text(String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .font(eventviewsize_to_font(size))
                    .fontWeight(.bold)
            }
            
            if let _ = current_nip05 {
                nip05_colorgradient.mask(
                    Image(systemName: "checkmark.seal.fill")
                        .contentShape(Circle())
                        .frame(width: 24, height: 24)
                )
                .contentShape(Circle())
                .frame(width: 24, height: 24)
                /*
                nip05_colorgradient.mask(
                    Image(systemName: "checkmark.seal.fill")
                        .contentShape(Circle())
                        .frame(width: 24, height: 24)
                )
                .contentShape(Circle())
                .frame(width: 24, height: 24)
                 */
            }
            
            if let frend = friend_icon, current_nip05 == nil {
                Label("", systemImage: frend)
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
        }
        .onReceive(handle_notify(.profile_updated)) { notif in
            let update = notif.object as! ProfileUpdate
            if update.pubkey != pubkey {
                return
            }
            display_name = Profile.displayName(profile: update.profile, pubkey: pubkey)
            nip05 = damus_state.profiles.is_validated(pubkey)
        }
    }
}

func get_nip05_color(pubkey: String, contacts: Contacts) -> Color {
    return contacts.is_friend_or_self(pubkey) ? .accentColor : Color("DamusMediumGrey")
}

func get_nip05_colorgradient(pubkey: String, contacts: Contacts) -> LinearGradient {
    return contacts.is_friend_or_self(pubkey) ?
        LinearGradient(gradient: Gradient(colors: [
            Color("DamusPurple"),
            Color("DamusBlue")
        ]), startPoint: .topTrailing, endPoint: .bottomTrailing)
     :
        LinearGradient(gradient: Gradient(colors: [
            Color("DamusMediumGrey"),
            Color("DamusLightGrey")
        ]), startPoint: .topTrailing, endPoint: .bottomTrailing)
}
