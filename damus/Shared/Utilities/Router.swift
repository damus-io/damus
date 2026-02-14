//
//  Router.swift
//  damus
//
//  Created by Scott Penrose on 5/7/23.
//

import FaviconFinder
import SwiftUI

enum Route: Hashable {
    case ProfileByKey(pubkey: Pubkey)
    case Profile(profile: ProfileModel, followers: FollowersModel)
    case Followers(followers: FollowersModel)
    case Relay(relay: RelayURL, showActionButtons: Binding<Bool>)
    case RelayDetail(relay: RelayURL, metadata: RelayMetadata?)
    case Following(contacts: NostrEvent)
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
    case LoadableNostrEvent(note_reference: LoadableNostrEventViewModel.NoteReference)
    case Reposts(reposts: EventsModel)
    case QuoteReposts(quotes: EventsModel)
    case Reactions(reactions: EventsModel)
    case Zaps(target: ZapTarget)
    case Search(search: SearchModel)
    case NDBSearch(results:  Binding<[NostrEvent]>, query: String)
    case EULA
    case Login
    case CreateAccount
    case SaveKeys(account: CreateAccountModel)
    case Wallet(wallet: WalletModel)
    case WalletScanner(result: Binding<WalletScanResult>)
    case FollowersYouKnow(friendedFollowers: [Pubkey], followers: FollowersModel)
    case NIP05DomainEvents(events: NIP05DomainEventsModel, nip05_domain_favicon: FaviconURL?)
    case NIP05DomainPubkeys(domain: String, nip05_domain_favicon: FaviconURL?, pubkeys: [Pubkey])
    case FollowPack(followPack: NostrEvent, model: FollowPackModel, blur_imgs: Bool)
    case LiveEvents(model: LiveEventModel)
    case LiveEvent(LiveEvent: NostrEvent, model: LiveEventModel)

    // AnyView is intentional here: a 44-case @ViewBuilder switch creates 44
    // levels of nested _ConditionalContent that SwiftUI must evaluate on every
    // navigation push. AnyView flattens this to a single type. Navigation
    // destinations are created once per push (not per frame), so the usual
    // AnyView diffing penalty does not apply.
    func view(navigationCoordinator: NavigationCoordinator, damusState: DamusState) -> AnyView {
        switch self {
        case .ProfileByKey(let pubkey):
            AnyView(ProfileView(damus_state: damusState, pubkey: pubkey))
        case .Profile(let profile, let followers):
            AnyView(ProfileView(damus_state: damusState, profile: profile, followers: followers))
        case .Followers(let followers):
            AnyView(FollowersView(damus_state: damusState, followers: followers))
        case .Relay(let relay, let showActionButtons):
            AnyView(RelayView(state: damusState, relay: relay, showActionButtons: showActionButtons, recommended: false))
        case .RelayDetail(let relay, let metadata):
            AnyView(RelayDetailView(state: damusState, relay: relay, nip11: metadata))
        case .Following(let contacts):
            AnyView(FollowingView(damus_state: damusState, following: FollowingModel(damus_state: damusState, contacts: Array(contacts.referenced_pubkeys), hashtags: Array(contacts.referenced_hashtags))))
        case .MuteList:
            AnyView(MutelistView(damus_state: damusState))
        case .RelayConfig:
            AnyView(RelayConfigView(state: damusState))
        case .Bookmarks:
            AnyView(BookmarksView(state: damusState))
        case .Config:
            AnyView(ConfigView(state: damusState))
        case .EditMetadata:
            AnyView(EditMetadataView(damus_state: damusState))
        case .DMChat(let dms):
            AnyView(DMChatView(damus_state: damusState, dms: dms))
        case .UserRelays(let relays):
            AnyView(UserRelaysView(state: damusState, relays: relays))
        case .KeySettings(let keypair):
            AnyView(KeySettingsView(keypair: keypair))
        case .AppearanceSettings(let settings):
            AnyView(AppearanceSettingsView(damus_state: damusState, settings: settings))
        case .NotificationSettings(let settings):
            AnyView(NotificationSettingsView(damus_state: damusState, settings: settings))
        case .ZapSettings(let settings):
            AnyView(ZapSettingsView(settings: settings))
        case .TranslationSettings(let settings):
            AnyView(TranslationSettingsView(settings: settings, damus_state: damusState))
        case .ReactionsSettings(let settings):
            AnyView(ReactionsSettingsView(settings: settings, damus_state: damusState))
        case .SearchSettings(let settings):
            AnyView(SearchSettingsView(settings: settings))
        case .DeveloperSettings(let settings):
            AnyView(DeveloperSettingsView(settings: settings, damus_state: damusState))
        case .FirstAidSettings(settings: let settings):
            AnyView(FirstAidSettingsView(damus_state: damusState, settings: settings))
        case .Thread(let thread):
            AnyView(ChatroomThreadView(damus: damusState, thread: thread))
        case .LoadableNostrEvent(let note_reference):
            AnyView(LoadableNostrEventView(state: damusState, note_reference: note_reference))
        case .Reposts(let reposts):
            AnyView(RepostsView(damus_state: damusState, model: reposts))
        case .QuoteReposts(let quote_reposts):
            AnyView(QuoteRepostsView(damus_state: damusState, model: quote_reposts))
        case .Reactions(let reactions):
            AnyView(ReactionsView(damus_state: damusState, model: reactions))
        case .Zaps(let target):
            AnyView(ZapsView(state: damusState, target: target))
        case .Search(let search):
            AnyView(SearchView(appstate: damusState, search: search))
        case .NDBSearch(let results, let query):
            AnyView(NDBSearchView(damus_state: damusState, results: results, searchQuery: query))
        case .EULA:
            AnyView(EULAView(nav: navigationCoordinator))
        case .Login:
            AnyView(LoginView(nav: navigationCoordinator))
        case .CreateAccount:
            AnyView(CreateAccountView(nav: navigationCoordinator))
        case .SaveKeys(let account):
            AnyView(SaveKeysView(account: account))
        case .Wallet(let walletModel):
            AnyView(WalletView(damus_state: damusState, model: walletModel))
        case .WalletScanner(let walletScanResult):
            AnyView(WalletScannerView(result: walletScanResult))
        case .FollowersYouKnow(let friendedFollowers, let followers):
            AnyView(FollowersYouKnowView(damus_state: damusState, friended_followers: friendedFollowers, followers: followers))
        case .Script(let load_model):
            AnyView(LoadScript(pool: RelayPool(ndb: damusState.ndb, keypair: damusState.keypair), model: load_model))
        case .NIP05DomainEvents(let events, let nip05_domain_favicon):
            AnyView(NIP05DomainTimelineView(damus_state: damusState, model: events, nip05_domain_favicon: nip05_domain_favicon))
        case .NIP05DomainPubkeys(let domain, let nip05_domain_favicon, let pubkeys):
            AnyView(NIP05DomainPubkeysView(damus_state: damusState, domain: domain, nip05_domain_favicon: nip05_domain_favicon, pubkeys: pubkeys))
        case .FollowPack(let followPack, let followPackModel, let blur_imgs):
            AnyView(FollowPackView(state: damusState, ev: followPack, model: followPackModel, blur_imgs: blur_imgs))
        case .LiveEvents(let model):
            AnyView(LiveStreamHomeView(damus_state: damusState, model: model))
        case .LiveEvent(let liveEvent, let liveEventModel):
            AnyView(LiveStreamView(state: damusState, ev: liveEvent, model: liveEventModel))
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
        case .Following(let contacts):
            hasher.combine("following")
            hasher.combine(contacts.id)
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
            hasher.combine(threadModel.original_event.id)
        case .LoadableNostrEvent(note_reference: let note_reference):
            hasher.combine("loadable_nostr_event")
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
        case .NDBSearch(_, let query):
            hasher.combine("results")
            hasher.combine(query)
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
        case .Script(let model):
            hasher.combine("script")
            hasher.combine(model.data.count)
        case .NIP05DomainEvents(let events, _):
            hasher.combine("nip05DomainEvents")
            hasher.combine(events.domain)
        case .NIP05DomainPubkeys(let domain, _, _):
            hasher.combine("nip05DomainPubkeys")
            hasher.combine(domain)
        case .FollowPack(let followPack, let followPackModel, let blur_imgs):
            hasher.combine("followPack")
            hasher.combine(followPack.id)
        case .LiveEvents(let model):
            hasher.combine("liveEvents")
        case .LiveEvent(let liveEvent, let liveEventModel):
            hasher.combine("liveEvent")
            hasher.combine(liveEvent.id)
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
