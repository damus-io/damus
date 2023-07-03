//
//  Router.swift
//  damus
//
//  Created by Scott Penrose on 5/7/23.
//

import SwiftUI

enum Route: Hashable {
    case ProfileByKey(pubkey: String)
    case Profile(profile: ProfileModel, followers: FollowersModel)
    case Followers(followers: FollowersModel)
    case Relay(relay: String, showActionButtons: Binding<Bool>)
    case RelayDetail(relay: String, metadata: RelayMetadata)
    case Following(following: FollowingModel)
    case MuteList(users: [String])
    case RelayConfig
    case Bookmarks
    case Config
    case EditMetadata
    case DMChat(dms: DirectMessageModel)
    case UserRelays(relays: [String])
    case KeySettings(keypair: Keypair)
    case AppearanceSettings(settings: UserSettingsStore)
    case NotificationSettings(settings: UserSettingsStore)
    case ZapSettings(settings: UserSettingsStore)
    case TranslationSettings(settings: UserSettingsStore)
    case SearchSettings(settings: UserSettingsStore)
    case Thread(thread: ThreadModel)
    case Reposts(reposts: RepostsModel)
    case Reactions(reactions: ReactionsModel)
    case Zaps(target: ZapTarget)
    case Search(search: SearchModel)
    case EULA
    case Login
    case CreateAccount
    case SaveKeys(account: CreateAccountModel)
    case Wallet(wallet: WalletModel)
    case WalletScanner(result: Binding<WalletScanResult>)
    case FollowersYouKnow(friendedFollowers: [String], followers: FollowersModel)

    @ViewBuilder
    func view(navigationCordinator: NavigationCoordinator, damusState: DamusState) -> some View {
        switch self {
        case .ProfileByKey(let pubkey):
            ProfileView(damus_state: damusState, pubkey: pubkey)
        case .Profile(let profile, let followers):
            ProfileView(damus_state: damusState, profile: profile, followers: followers)
        case .Followers(let followers):
            FollowersView(damus_state: damusState, followers: followers)
        case .Relay(let relay, let showActionButtons):
            RelayView(state: damusState, relay: relay, showActionButtons: showActionButtons)
        case .RelayDetail(let relay, let metadata):
            RelayDetailView(state: damusState, relay: relay, nip11: metadata)
        case .Following(let following):
            FollowingView(damus_state: damusState, following: following)
        case .MuteList(let users):
            MutelistView(damus_state: damusState, users: users)
        case .RelayConfig:
            RelayConfigView(state: damusState)
        case .Bookmarks:
            BookmarksView(state: damusState)
        case .Config:
            ConfigView(state: damusState)
        case .EditMetadata:
            EditMetadataView(damus_state: damusState)
        case .DMChat(let dms):
            DMChatView(damus_state: damusState, dms: dms)
        case .UserRelays(let relays):
            UserRelaysView(state: damusState, relays: relays)
        case .KeySettings(let keypair):
            KeySettingsView(keypair: keypair)
        case .AppearanceSettings(let settings):
            AppearanceSettingsView(settings: settings)
        case .NotificationSettings(let settings):
            NotificationSettingsView(settings: settings)
        case .ZapSettings(let settings):
            ZapSettingsView(settings: settings)
        case .TranslationSettings(let settings):
            TranslationSettingsView(settings: settings)
        case .SearchSettings(let settings):
            SearchSettingsView(settings: settings)
        case .Thread(let thread):
            ThreadView(state: damusState, thread: thread)
        case .Reposts(let reposts):
            RepostsView(damus_state: damusState, model: reposts)
        case .Reactions(let reactions):
            ReactionsView(damus_state: damusState, model: reactions)
        case .Zaps(let target):
            ZapsView(state: damusState, target: target)
        case .Search(let search):
            SearchView(appstate: damusState, search: search)
        case .EULA:
            EULAView(nav: navigationCordinator)
        case .Login:
            LoginView(nav: navigationCordinator)
        case .CreateAccount:
            CreateAccountView(nav: navigationCordinator)
        case .SaveKeys(let account):
            SaveKeysView(account: account)
        case .Wallet(let walletModel):
            WalletView(damus_state: damusState, model: walletModel)
        case .WalletScanner(let walletScanResult):
            WalletScannerView(result: walletScanResult)
        case .FollowersYouKnow(let friendedFollowers, let followers):
            FollowersYouKnowView(damus_state: damusState, friended_followers: friendedFollowers, followers: followers)
        }
    }

    static func == (lhs: Route, rhs: Route) -> Bool {
        switch (lhs, rhs) {
        case (.ProfileByKey (let lhs_pubkey), .ProfileByKey(let rhs_pubkey)):
            return lhs_pubkey == rhs_pubkey
        case (.Profile (let lhs_profile, _), .Profile(let rhs_profile, _)):
            return lhs_profile == rhs_profile
        case (.Followers (_), .Followers (_)):
            return true
        case (.Relay (let lhs_relay, _), .Relay (let rhs_relay, _)):
            return lhs_relay == rhs_relay
        case (.RelayDetail(let lhs_relay, _), .RelayDetail(let rhs_relay, _)):
            return lhs_relay == rhs_relay
        case (.Following(_), .Following(_)):
            return true
        case (.MuteList(let lhs_users), .MuteList(let rhs_users)):
            return lhs_users == rhs_users
        case (.RelayConfig, .RelayConfig):
            return true
        case (.Bookmarks, .Bookmarks):
            return true
        case (.Config, .Config):
            return true
        case (.EditMetadata, .EditMetadata):
            return true
        case (.DMChat(let lhs_dms), .DMChat(let rhs_dms)):
            return lhs_dms.our_pubkey == rhs_dms.our_pubkey
        case (.UserRelays(let lhs_relays), .UserRelays(let rhs_relays)):
            return lhs_relays == rhs_relays
        case (.KeySettings(let lhs_keypair), .KeySettings(let rhs_keypair)):
            return lhs_keypair.pubkey == rhs_keypair.pubkey
        case (.AppearanceSettings(_), .AppearanceSettings(_)):
            return true
        case (.NotificationSettings(_), .NotificationSettings(_)):
            return true
        case (.ZapSettings(_), .ZapSettings(_)):
            return true
        case (.TranslationSettings(_), .TranslationSettings(_)):
            return true
        case (.SearchSettings(_), .SearchSettings(_)):
            return true
        case (.Thread(let lhs_threadModel), .Thread(thread: let rhs_threadModel)):
            return lhs_threadModel.event.id == rhs_threadModel.event.id
        case (.Reposts(let lhs_reposts), .Reposts(let rhs_reposts)):
            return lhs_reposts.target == rhs_reposts.target
        case (.Reactions(let lhs_reactions), .Reactions(let rhs_reactions)):
            return lhs_reactions.target == rhs_reactions.target
        case (.Zaps(let lhs_target), .Zaps(let rhs_target)):
            return lhs_target == rhs_target
        case (.Search(let lhs_search), .Search(let rhs_search)):
            return lhs_search.sub_id == rhs_search.sub_id && lhs_search.profiles_subid == rhs_search.profiles_subid
        case (.EULA, .EULA):
            return true
        case (.Login, .Login):
            return true
        case (.CreateAccount, .CreateAccount):
            return true
        case (.SaveKeys(let lhs_account), .SaveKeys(let rhs_account)):
            return lhs_account.pubkey == rhs_account.pubkey
        case (.Wallet(_), .Wallet(_)):
            return true
        case (.WalletScanner(_), .WalletScanner(_)):
            return true
        case (.FollowersYouKnow(_, _), .FollowersYouKnow(_, _)):
            return true
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .ProfileByKey(let pubkey):
            hasher.combine("profilebykey")
            hasher.combine(pubkey)
        case .Profile(let profile, _):
            hasher.combine("profile")
            hasher.combine(profile.pubkey)
        case .Followers(_):
            hasher.combine("followers")
        case .Relay(let relay, _):
            hasher.combine("relay")
            hasher.combine(relay)
        case .RelayDetail(let relay, _):
            hasher.combine("relayDetail")
            hasher.combine(relay)
        case .Following(_):
            hasher.combine("following")
        case .MuteList(let users):
            hasher.combine("muteList")
            hasher.combine(users)
        case .RelayConfig:
            hasher.combine("relayConfig")
        case .Bookmarks:
            hasher.combine("bookmarks")
        case .Config:
            hasher.combine("config")
        case .EditMetadata:
            hasher.combine("editMetadata")
        case .DMChat(let dms):
            hasher.combine("dms")
            hasher.combine(dms.our_pubkey)
        case .UserRelays(let relays):
            hasher.combine("userRelays")
            hasher.combine(relays)
        case .KeySettings(let keypair):
            hasher.combine("keySettings")
            hasher.combine(keypair.pubkey)
        case .AppearanceSettings(_):
            hasher.combine("appearanceSettings")
        case .NotificationSettings(_):
            hasher.combine("notificationSettings")
        case .ZapSettings(_):
            hasher.combine("zapSettings")
        case .TranslationSettings(_):
            hasher.combine("translationSettings")
        case .SearchSettings(_):
            hasher.combine("searchSettings")
        case .Thread(let threadModel):
            hasher.combine("thread")
            hasher.combine(threadModel.event.id)
        case .Reposts(let reposts):
            hasher.combine("reposts")
            hasher.combine(reposts.target)
        case .Zaps(let target):
            hasher.combine("zaps")
            hasher.combine(target.id)
            hasher.combine(target.pubkey)
        case .Reactions(let reactions):
            hasher.combine("reactions")
            hasher.combine(reactions.target)
        case .Search(let search):
            hasher.combine("search")
            hasher.combine(search.sub_id)
            hasher.combine(search.profiles_subid)
        case .EULA:
            hasher.combine("eula")
        case .Login:
            hasher.combine("login")
        case .CreateAccount:
            hasher.combine("createAccount")
        case .SaveKeys(let account):
            hasher.combine("saveKeys")
            hasher.combine(account.pubkey)
        case .Wallet(_):
            hasher.combine("wallet")
        case .WalletScanner(_):
            hasher.combine("walletScanner")
        case .FollowersYouKnow(let friendedFollowers, let followers):
            hasher.combine("followersYouKnow")
            hasher.combine(friendedFollowers)
            hasher.combine(followers.sub_id)
        }
    }
}

class NavigationCoordinator: ObservableObject {
    @Published var path = [Route]()

    func push(route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path = []
    }
}
