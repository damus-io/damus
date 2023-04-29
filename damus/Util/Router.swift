//
//  Router.swift
//  damus
//
//  Created by Scott Penrose on 5/7/23.
//

import SwiftUI

enum Route: Hashable {
    case Profile(damusSate: DamusState, profile: ProfileModel, followers: FollowersModel)
    case Followers(damusState: DamusState, environmentObject: FollowersModel)
    case Relay(damusState: DamusState, relay: String, showActionButtons: Binding<Bool>)
    case Following(damusState: DamusState, following: FollowingModel)
    case MuteList(damusState: DamusState, users: [String])
    case RelayConfig(damusState: DamusState)
    case Bookmarks(damusState: DamusState)
    case Config(damusState: DamusState)
    case EditMetadata(damusState: DamusState)
    case DMChat(damusState: DamusState, dms: DirectMessageModel)
    case UserRelays(damusState: DamusState, relays: [String])

    @ViewBuilder
    func view(navigationCordinator: NavigationCoordinator) -> some View {
        switch self {
        case .Profile (let damusState, let profile, let followers):
            ProfileView(damus_state: damusState, profile: profile, followers: followers)
        case .Followers (let damusState, let environmentObject):
            FollowersView(damus_state: damusState)
                .environmentObject(environmentObject)
        case .Relay (let damusState, let relay, let showActionButtons):
            RelayView(state: damusState, relay: relay, showActionButtons: showActionButtons)
        case .Following(let damusState, let following):
            FollowingView(damus_state: damusState, following: following)
        case .MuteList(let damusState, let users):
            MutelistView(damus_state: damusState, users: users)
        case .RelayConfig(let damusState):
            RelayConfigView(state: damusState)
        case .Bookmarks(let damusState):
            BookmarksView(state: damusState)
        case .Config(let damusState):
            ConfigView(state: damusState)
        case .EditMetadata(let damusState):
            EditMetadataView(damus_state: damusState)
        case .DMChat(let damusState, let dms):
            DMChatView(damus_state: damusState, dms: dms)
        case .UserRelays(let damusState, let relays):
            UserRelaysView(state: damusState, relays: relays)
        }
    }

    static func == (lhs: Route, rhs: Route) -> Bool {
        switch (lhs, rhs) {
        case (.Profile (_, let lhs_profile, _), .Profile(_, let rhs_profile, _)):
            return lhs_profile == rhs_profile
        case (.Followers (_, _), .Followers (_, _)):
            return true
        case (.Relay (_, let lhs_relay, _), .Relay (_, let rhs_relay, _)):
            return lhs_relay == rhs_relay
        case (.Following(_, _), .Following(_, _)):
            return true
        case (.MuteList(_, let lhs_users), .MuteList(_, let rhs_users)):
            return lhs_users == rhs_users
        case (.RelayConfig(_), .RelayConfig(_)):
            return true
        case (.Bookmarks(_), .Bookmarks(_)):
            return true
        case (.Config(_), .Config(_)):
            return true
        case (.EditMetadata(_), .EditMetadata(_)):
            return true
        case (.DMChat(_, let lhs_dms), .DMChat(_, let rhs_dms)):
            return lhs_dms.our_pubkey == rhs_dms.our_pubkey
        case (.UserRelays(_, let lhs_relays), .UserRelays(_, let rhs_relays)):
            return lhs_relays == rhs_relays
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .Profile(_, let profile, _):
            hasher.combine(profile.pubkey)
        case .Followers(_, _):
            hasher.combine("followers")
        case .Relay(_, let relay, _):
            hasher.combine(relay)
        case .Following(_, _):
            hasher.combine("following")
        case .MuteList(_, let users):
            hasher.combine(users)
        case .RelayConfig(_):
            hasher.combine("relayConfig")
        case .Bookmarks(_):
            hasher.combine("bookmarks")
        case .Config(_):
            hasher.combine("config")
        case .EditMetadata(_):
            hasher.combine("editMetadata")
        case .DMChat(_, let dms):
            hasher.combine(dms.our_pubkey)
        case .UserRelays(_, let relays):
            hasher.combine(relays)
        }
    }
}

class NavigationCoordinator: ObservableObject {
    @Published var path = [Route]()

    func popToRoot() {
        path = []
    }
}
