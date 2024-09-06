//
//  Router.swift
//  damus
//
//  Created by Scott Penrose on 5/7/23.
//

import SwiftUI

enum Route: Hashable {
    case ProfileByKey(pubkey: Pubkey)
    case Profile(profile: ProfileModel, followers: FollowersModel)
    case Followers(followers: FollowersModel)
    case Relay(relay: RelayURL, showActionButtons: Binding<Bool>)
    case RelayDetail(relay: RelayURL, metadata: RelayMetadata?)
    case Following(following: FollowingModel)
    case MuteList
    case RelayConfig
    case Script(script: ScriptModel)
    case Bookmarks
    case Config
    case EditMetadata
    case DMChat(dms: DirectMessageModel)
    case UserRelays(relays: [RelayURL])
    case KeySettings(keypair: Keypair)
    case AppearanceSettings(settings: UserSettingsStore)
    case NotificationSettings(settings: UserSettingsStore)
    case ZapSettings(settings: UserSettingsStore)
    case TranslationSettings(settings: UserSettingsStore)
    case ReactionsSettings(settings: UserSettingsStore)
    case SearchSettings(settings: UserSettingsStore)
    case DeveloperSettings(settings: UserSettingsStore)
    case FirstAidSettings(settings: UserSettingsStore)
    case Thread(thread: ThreadModel)
    case ThreadFromReference(note_reference: LoadableThreadModel.NoteReference)
    case Reposts(reposts: EventsModel)
    case QuoteReposts(quotes: EventsModel)
    case Reactions(reactions: EventsModel)
    case Zaps(target: ZapTarget)
    case Search(search: SearchModel)
    case NDBSearch(results:  Binding<[NostrEvent]>)
    case EULA
    case Login
    case CreateAccount
    case SaveKeys(account: CreateAccountModel)
    case Wallet(wallet: WalletModel)
    case WalletScanner(result: Binding<WalletScanResult>)
    case FollowersYouKnow(friendedFollowers: [Pubkey], followers: FollowersModel)

    @ViewBuilder
    func view(navigationCoordinator: NavigationCoordinator, damusState: DamusState) -> some View {
        switch self {
        case .ProfileByKey(let pubkey):
            ProfileView(damus_state: damusState, pubkey: pubkey)
        case .Profile(let profile, let followers):
            ProfileView(damus_state: damusState, profile: profile, followers: followers)
        case .Followers(let followers):
            FollowersView(damus_state: damusState, followers: followers)
        case .Relay(let relay, let showActionButtons):
            RelayView(state: damusState, relay: relay, showActionButtons: showActionButtons, recommended: false)
        case .RelayDetail(let relay, let metadata):
            RelayDetailView(state: damusState, relay: relay, nip11: metadata)
        case .Following(let following):
            FollowingView(damus_state: damusState, following: following)
        case .MuteList:
            MutelistView(damus_state: damusState)
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
            AppearanceSettingsView(damus_state: damusState, settings: settings)
        case .NotificationSettings(let settings):
            NotificationSettingsView(damus_state: damusState, settings: settings)
        case .ZapSettings(let settings):
            ZapSettingsView(settings: settings)
        case .TranslationSettings(let settings):
            TranslationSettingsView(settings: settings, damus_state: damusState)
        case .ReactionsSettings(let settings):
            ReactionsSettingsView(settings: settings, damus_state: damusState)
        case .SearchSettings(let settings):
            SearchSettingsView(settings: settings)
        case .DeveloperSettings(let settings):
            DeveloperSettingsView(settings: settings)
        case .FirstAidSettings(settings: let settings):
            FirstAidSettingsView(damus_state: damusState, settings: settings)
        case .Thread(let thread):
            ChatroomThreadView(damus: damusState, thread: thread)
            //ThreadView(state: damusState, thread: thread)
        case .ThreadFromReference(let note_reference):
            LoadableThreadView(state: damusState, note_reference: note_reference)
        case .Reposts(let reposts):
            RepostsView(damus_state: damusState, model: reposts)
        case .QuoteReposts(let quote_reposts):
            QuoteRepostsView(damus_state: damusState, model: quote_reposts)
        case .Reactions(let reactions):
            ReactionsView(damus_state: damusState, model: reactions)
        case .Zaps(let target):
            ZapsView(state: damusState, target: target)
        case .Search(let search):
            SearchView(appstate: damusState, search: search)
        case .NDBSearch(let results):
            NDBSearchView(damus_state: damusState, results: results)
        case .EULA:
            EULAView(nav: navigationCoordinator)
        case .Login:
            LoginView(nav: navigationCoordinator)
        case .CreateAccount:
            CreateAccountView(nav: navigationCoordinator)
        case .SaveKeys(let account):
            SaveKeysView(account: account)
        case .Wallet(let walletModel):
            WalletView(damus_state: damusState, model: walletModel)
        case .WalletScanner(let walletScanResult):
            WalletScannerView(result: walletScanResult)
        case .FollowersYouKnow(let friendedFollowers, let followers):
            FollowersYouKnowView(damus_state: damusState, friended_followers: friendedFollowers, followers: followers)
        case .Script(let load_model):
            LoadScript(pool: damusState.pool, model: load_model)
        }
    }

    static func == (lhs: Route, rhs: Route) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .ProfileByKey(let pubkey):
            hasher.combine("profilebykey")
            hasher.combine(pubkey.id.bytes)
        case .Profile(let profile, _):
            hasher.combine("profile")
            hasher.combine(profile.pubkey.id.bytes)
        case .Followers:
            hasher.combine("followers")
        case .Relay(let relay, _):
            hasher.combine("relay")
            hasher.combine(relay)
        case .RelayDetail(let relay, _):
            hasher.combine("relayDetail")
            hasher.combine(relay)
        case .Following:
            hasher.combine("following")
        case .MuteList:
            hasher.combine("muteList")
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
        case .AppearanceSettings:
            hasher.combine("appearanceSettings")
        case .NotificationSettings:
            hasher.combine("notificationSettings")
        case .ZapSettings:
            hasher.combine("zapSettings")
        case .TranslationSettings:
            hasher.combine("translationSettings")
        case .ReactionsSettings:
            hasher.combine("reactionsSettings")
        case .SearchSettings:
            hasher.combine("searchSettings")
        case .DeveloperSettings:
            hasher.combine("developerSettings")
        case .FirstAidSettings:
            hasher.combine("firstAidSettings")
        case .Thread(let threadModel):
            hasher.combine("thread")
            hasher.combine(threadModel.event.id)
        case .ThreadFromReference(note_reference: let note_reference):
            hasher.combine("thread_from_reference")
            hasher.combine(note_reference)
        case .Reposts(let reposts):
            hasher.combine("reposts")
            hasher.combine(reposts.target)
        case .QuoteReposts(let evs_model):
            hasher.combine("quote_reposts")
            hasher.combine(evs_model.events.events.count)
        case .Zaps(let target):
            hasher.combine("zaps")
            hasher.combine(target.id)
            hasher.combine(target.pubkey)
        case .Reactions(let reactions):
            hasher.combine("reactions")
            hasher.combine(reactions.target)
        case .Search(let search):
            hasher.combine("search")
            hasher.combine(search.search)
        case .NDBSearch(let results):
            hasher.combine("results")
        case .EULA:
            hasher.combine("eula")
        case .Login:
            hasher.combine("login")
        case .CreateAccount:
            hasher.combine("createAccount")
        case .SaveKeys(let account):
            hasher.combine("saveKeys")
            hasher.combine(account.pubkey)
        case .Wallet:
            hasher.combine("wallet")
        case .WalletScanner:
            hasher.combine("walletScanner")
        case .FollowersYouKnow(let friendedFollowers, let followers):
            hasher.combine("followersYouKnow")
            hasher.combine(friendedFollowers)
            hasher.combine(followers.sub_id)
        case .Script(let model):
            hasher.combine("script")
            hasher.combine(model.data.count)
        }
    }
}

class NavigationCoordinator: ObservableObject {
    @Published var path = [Route]()

    func push(route: Route) {
        guard route != path.last else {
            return
        }
        path.append(route)
    }
    
    func isAtRoot() -> Bool {
        return path.count == 0
    }

    func popToRoot() {
        path = []
    }
}
