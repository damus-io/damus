//
//  EventProfileName.swift
//  damus
//
//  Created by William Casarin on 2023-03-14.
//

import SwiftUI

/// Profile Name used when displaying an event in the timeline
@MainActor
struct EventProfileName: View {
    var damus_state: DamusState
    let pubkey: Pubkey

    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    @State var donation: Int?
    @State var purple_account: DamusPurple.Account?
    @State var profile: Profile?

    let size: EventViewKind

    init(pubkey: Pubkey, damus: DamusState, size: EventViewKind) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.size = size
        self.purple_account = nil

        // Initialize with safe defaults; async task will populate from cache
        self._profile = State(initialValue: nil)
        self._display_name = State(initialValue: nil)
        self._donation = State(initialValue: nil)
        self._nip05 = State(initialValue: nil)
    }
    
    var friend_type: FriendType? {
        return get_friend_type(contacts: damus_state.contacts, pubkey: self.pubkey)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
    
    func current_display_name(_ profile: Profile?) -> DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    func onlyzapper(_ profile: Profile?) -> Bool {
        guard let profile else {
            return false
        }
        
        return profile.reactions == false
    }
    
    func supporter_percentage() -> Int? {
        guard let donation, donation > 0
        else {
            return nil
        }
        
        return donation
    }

    var body: some View {
        HStack(spacing: 2) {
            switch current_display_name(profile) {
            case .one(let one):
                Text(one)
                    .font(.body.weight(.bold))
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    .fontWeight(.bold)
                
            case .both(username: let username, displayName: let displayName):
                    HStack(spacing: 6) {
                        Text(verbatim: displayName)
                            .font(.body.weight(.bold))
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                            .fontWeight(.bold)
                        
                        Text(verbatim: "@\(username)")
                            .foregroundColor(.gray)
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    }
            }
            
            /*
            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: false, clickable: false)
            }
             */
            
            if size != .small {
                if let frend = friend_type {
                    FriendIcon(friend: frend)
                }
                
                if onlyzapper(profile) {
                    Image("zap-hashtag")
                        .frame(width: 14, height: 14)
                }
                
                SupporterBadge(percent: self.supporter_percentage(), purple_account: self.purple_account, style: .compact)
            }
        }
        .task {
            // Load cached profile off main thread to avoid blocking UI
            let pubkey = self.pubkey
            let ndb = damus_state.ndb

            let cachedProfile = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let profile = try? ndb.lookup_profile_and_copy(pubkey)
                    continuation.resume(returning: profile)
                }
            }

            // Check if view disappeared during async work
            if Task.isCancelled { return }

            if let cachedProfile {
                self.profile = cachedProfile
                self.display_name = Profile.displayName(profile: cachedProfile, pubkey: pubkey)
                self.donation = cachedProfile.damus_donation
            }

            // profiles.is_validated must run on MainActor (not Sendable)
            self.nip05 = damus_state.profiles.is_validated(pubkey)
        }
        .task {
            for await profile in await damus_state.nostrNetwork.profilesManager.streamProfile(pubkey: pubkey) {
                self.profile = profile

                let display_name = Profile.displayName(profile: profile, pubkey: pubkey)
                if display_name != self.display_name {
                    self.display_name = display_name
                }

                let nip05 = damus_state.profiles.is_validated(pubkey)

                if self.nip05 != nip05 {
                    self.nip05 = nip05
                }

                if self.donation != profile.damus_donation {
                    donation = profile.damus_donation
                }
            }
        }
        .task {
            if damus_state.purple.enable_purple {
                self.purple_account = try? await damus_state.purple.get_maybe_cached_account(pubkey: pubkey)
            }
        }
    }
}


struct EventProfileName_Previews: PreviewProvider {
    static var previews: some View {
        EventProfileName(pubkey: test_note.pubkey, damus: test_damus_state, size: .normal)
    }
}
