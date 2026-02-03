//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import FaviconFinder
import SwiftUI

enum FriendType {
    case friend
    case fof

    var priority: Int {
        switch self {
        case .friend: return 2
        case .fof: return 1
        }
    }
}

@MainActor
func get_friend_type(contacts: Contacts, pubkey: Pubkey) -> FriendType? {
    if contacts.is_friend_or_self(pubkey) {
        return .friend
    }
    
    if contacts.is_friend_of_friend(pubkey) {
        return .fof
    }
    
    return nil
}

struct ProfileName: View {
    let damus_state: DamusState
    let pubkey: Pubkey
    let prefix: String
    
    let show_nip5_domain: Bool
    private let supporterBadgeStyle: SupporterBadge.Style
    
    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    @State var donation: Int?
    @State var purple_account: DamusPurple.Account?
    @State var nip05_domain_favicon: FaviconURL?
    @State var profile: Profile?

    init(pubkey: Pubkey, prefix: String = "", damus: DamusState, show_nip5_domain: Bool = true, supporterBadgeStyle: SupporterBadge.Style = .compact) {
        self.pubkey = pubkey
        self.prefix = prefix
        self.damus_state = damus
        self.show_nip5_domain = show_nip5_domain
        self.supporterBadgeStyle = supporterBadgeStyle
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

    @MainActor
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }

    func current_display_name(profile: Profile?) -> DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    func name_choice(profile: Profile?) -> String {
        let displayName = current_display_name(profile: profile)
        let untruncatedName = prefix == "@" ? displayName.username : displayName.displayName
        return untruncatedName.truncate(maxLength: 50)
    }
    
    func onlyzapper(profile: Profile?) -> Bool {
        guard let profile else {
            return false
        }
        
        return profile.reactions == false
    }
    
    func supporter(profile: Profile?) -> Int? {
        guard let profile,
              let donation = profile.damus_donation,
              donation > 0
        else {
            return nil
        }
        
        return donation
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: "\(prefix)\(name_choice(profile: profile))")
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)

            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, damus_state: damus_state, show_domain: show_nip5_domain, nip05_domain_favicon: nip05_domain_favicon)
            }

            if let friend = friend_type, current_nip05 == nil {
                FriendIcon(friend: friend)
            }

            if onlyzapper(profile: profile) {
                Image("zap-hashtag")
                    .frame(width: 14, height: 14)
            }

            SupporterBadge(percent: supporter(profile: profile), purple_account: self.purple_account, style: supporterBadgeStyle)


        }
        .task {
            if damus_state.purple.enable_purple {
                self.purple_account = try? await damus_state.purple.get_maybe_cached_account(pubkey: pubkey)
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
            let cachedNip05 = damus_state.profiles.is_validated(pubkey)
            self.nip05 = cachedNip05

            // Load favicon after nip05 is set to avoid race condition
            if let domain = cachedNip05?.host {
                self.nip05_domain_favicon = try? await damus_state.favicon_cache.lookup(domain)
                    .largest()
            }
        }
        .task {
            for await profile in await damus_state.nostrNetwork.profilesManager.streamProfile(pubkey: pubkey) {
                handle_profile_update(profile: profile)
            }
        }
    }

    @MainActor
    func handle_profile_update(profile: Profile) {
        self.profile = profile

        let display_name = Profile.displayName(profile: profile, pubkey: pubkey)
        if self.display_name != display_name {
            self.display_name = display_name
        }

        let nip05 = damus_state.profiles.is_validated(pubkey)
        if nip05 != self.nip05 {
            self.nip05 = nip05

            if let domain = nip05?.host {
                Task {
                    let favicon = try? await damus_state.favicon_cache.lookup(domain)
                        .filter {
                            if let size = $0.size {
                                return size.width <= 128 && size.height <= 128
                            } else {
                                return true
                            }
                        }
                        .largest()

                    await MainActor.run {
                        self.nip05_domain_favicon = favicon
                    }
                }
            }
        }

        if donation != profile.damus_donation {
            donation = profile.damus_donation
        }
    }
}

struct ProfileName_Previews: PreviewProvider {
    static var previews: some View {
        ProfileName(pubkey: test_damus_state.pubkey, damus: test_damus_state)
    }
}
