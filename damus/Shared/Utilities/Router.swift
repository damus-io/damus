//
//  Router.swift
//  damus
//
//  Created by Scott Penrose on 5/7/23.
//

import FaviconFinder
import SwiftUI
import DamusWallet

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
    case StorageSettings(settings: UserSettingsStore)
    case NostrDBStorageDetail(stats: StorageStats)
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
    case OrangeWalletWelcome
    case OrangeWalletSetup
    case OrangeWalletKeyCustodyConfirmation
    case OrangeWalletBackupToICloud
    case OrangeWalletManualBackup
    case OrangeWalletSeedWordsQuiz
    case OrangeWalletSetupComplete
    case OrangeWalletReceive(ReceiveFlowContext)
    case OrangeWalletReceiveAmountEntry(ReceiveFlowContext)
    case OrangeWalletReceiveConfirmation(ReceiveFlowContext)
    case OrangeWalletSendScan(SendFlowContext)
    case OrangeWalletSendAmountEntry(SendFlowContext)
    case OrangeWalletSendReview(SendFlowContext)
    case OrangeWalletSendConfirmation(SendFlowContext)

    @MainActor
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
            DeveloperSettingsView(settings: settings, damus_state: damusState)
        case .FirstAidSettings(settings: let settings):
            FirstAidSettingsView(damus_state: damusState, settings: settings)
        case .StorageSettings(settings: let settings):
            StorageSettingsView(damus_state: damusState, settings: settings)
        case .NostrDBStorageDetail(stats: let stats):
            NostrDBDetailView(damus_state: damusState, settings: damusState.settings, stats: stats)
        case .Thread(let thread):
            ChatroomThreadView(damus: damusState, thread: thread)
            //ThreadView(state: damusState, thread: thread)
        case .LoadableNostrEvent(let note_reference):
            LoadableNostrEventView(state: damusState, note_reference: note_reference)
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
        case .NDBSearch(let results, let query):
            NDBSearchView(damus_state: damusState, results: results, searchQuery: query)
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
            LoadScript(pool: RelayPool(ndb: damusState.ndb, keypair: damusState.keypair), model: load_model)
        case .NIP05DomainEvents(let events, let nip05_domain_favicon):
            NIP05DomainTimelineView(damus_state: damusState, model: events, nip05_domain_favicon: nip05_domain_favicon)
        case .NIP05DomainPubkeys(let domain, let nip05_domain_favicon, let pubkeys):
            NIP05DomainPubkeysView(damus_state: damusState, domain: domain, nip05_domain_favicon: nip05_domain_favicon, pubkeys: pubkeys)
        case .FollowPack(let followPack, let followPackModel, let blur_imgs):
            FollowPackView(state: damusState, ev: followPack, model: followPackModel, blur_imgs: blur_imgs)
        case .LiveEvents(let model):
            LiveStreamHomeView(damus_state: damusState, model: model)
        case .LiveEvent(let liveEvent, let liveEventModel):
            LiveStreamView(state: damusState, ev: liveEvent, model: liveEventModel)
        case .OrangeWalletWelcome:
            let model = HomeView.ViewModel.init(
                navigationCoordinator: navigationCoordinator,
                walletProvider: damusState.orangeWallet,
                priceManager: navigationCoordinator.bitcoinPriceManager
            )
            HomeView(model: model)
        case .OrangeWalletSetup:
            let model = CreateNewWalletView.ViewModel.init(navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet)
            CreateNewWalletView(model: model)
        case .OrangeWalletKeyCustodyConfirmation:
            let model = KeyCustodyConfirmationView.ViewModel.init(navigationCoordinator: navigationCoordinator)
            KeyCustodyConfirmationView(viewModel: model)
        case .OrangeWalletBackupToICloud:
            let model = BackupToICloudView.ViewModel.init(navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet)
            BackupToICloudView(model: model)
        case .OrangeWalletManualBackup:
            let model = ManualBackupView.ViewModel.init(navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet)
            ManualBackupView(model: model)
        case .OrangeWalletSeedWordsQuiz:
            let model = SeedWordsQuizView.ViewModel.init(navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet)
            SeedWordsQuizView(model: model)
        case .OrangeWalletSetupComplete:
            let model = SetupCompleteView.ViewModel.init(navigationCoordinator: navigationCoordinator)
            SetupCompleteView(model: model)
        case .OrangeWalletReceive(let receiveFlowContext):
            let model = ReceiveView.ViewModel.init(
                flow: receiveFlowContext,
                navigationCoordinator: navigationCoordinator,
                walletProvider: damusState.orangeWallet,
                priceManager: navigationCoordinator.bitcoinPriceManager
            )
            ReceiveView(model: model)
        case .OrangeWalletReceiveAmountEntry(let receiveFlowContext):
            let model = ReceiveAmountEntryView.ViewModel(
                flow: receiveFlowContext,
                navigationCoordinator: navigationCoordinator,
                amountModel: AmountInputModel.make(priceManager: navigationCoordinator.bitcoinPriceManager)
            )
            ReceiveAmountEntryView(model: model)
        case .OrangeWalletReceiveConfirmation(let receiveFlowContext):
            let model = ReceiveConfirmationView.ViewModel(
                flow: receiveFlowContext,
                navigationCoordinator: navigationCoordinator
            )
            ReceiveConfirmationView(model: model)
        case .OrangeWalletSendScan(let sendFlowContext):
            SendScanView(model: .init(flow: sendFlowContext, navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet, priceManager: navigationCoordinator.bitcoinPriceManager))
        case .OrangeWalletSendAmountEntry(let sendFlowContext):
            SendAmountEntryView(model: .init(
                flow: sendFlowContext,
                navigationCoordinator: navigationCoordinator,
                amountModel: AmountInputModel.make(priceManager: navigationCoordinator.bitcoinPriceManager)
            ))
        case .OrangeWalletSendReview(let sendFlowContext):
            SendReviewView(model: .init(flow: sendFlowContext, navigationCoordinator: navigationCoordinator, walletProvider: damusState.orangeWallet, priceManager: navigationCoordinator.bitcoinPriceManager))
        case .OrangeWalletSendConfirmation(let sendFlowContext):
            SendConfirmationView(model: .init(flow: sendFlowContext, navigationCoordinator: navigationCoordinator))
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
        case .StorageSettings:
            hasher.combine("storageSettings")
        case .NostrDBStorageDetail(let stats):
            hasher.combine("nostrDBStorageDetail")
            hasher.combine(stats)
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
        case .OrangeWalletWelcome:
            hasher.combine("orangeWalletWelcome")
        case .OrangeWalletSetup:
            hasher.combine("orangeWalletSetup")
        case .OrangeWalletKeyCustodyConfirmation:
            hasher.combine("orangeWalletKeyCustodyConfirmation")
        case .OrangeWalletBackupToICloud:
            hasher.combine("orangeWalletBackupToICloud")
        case .OrangeWalletManualBackup:
            hasher.combine("orangeWalletManualBackup")
        case .OrangeWalletSeedWordsQuiz:
            hasher.combine("orangeWalletSeedWordsQuiz")
        case .OrangeWalletSetupComplete:
            hasher.combine("orangeWalletSetupComplete")
        case .OrangeWalletReceive:
            hasher.combine("orangeWalletReceive")
        case .OrangeWalletReceiveAmountEntry:
            hasher.combine("orangeWalletReceiveAmountEntry")
        case .OrangeWalletReceiveConfirmation:
            hasher.combine("orangeWalletReceiveConfirmation")
        case .OrangeWalletSendScan:
            hasher.combine("orangeWalletSendScan")
        case .OrangeWalletSendAmountEntry:
            hasher.combine("orangeWalletSendAmountEntry")
        case .OrangeWalletSendReview:
            hasher.combine("orangeWalletSendReview")
        case .OrangeWalletSendConfirmation:
            hasher.combine("orangeWalletSendConfirmation")
        }
    }
}

class NavigationCoordinator: ObservableObject {
    @MainActor let bitcoinPriceManager: BitcoinPriceManager
    @Published var path = [Route]()

    @MainActor
    init(bitcoinPriceManager: BitcoinPriceManager? = nil) {
        self.bitcoinPriceManager = bitcoinPriceManager ?? BitcoinPriceManager()
    }

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

extension NavigationCoordinator: WalletNavigationCoordinator {
    func push(route: DamusWallet.WalletRoute) {
        self.push(route: route.toDamusRoute())
    }
    
    func pop() {
        self.path.removeLast()
    }
    
    func popTo(route: DamusWallet.WalletRoute) {
        let damusRoute = route.toDamusRoute()
        if let index = path.lastIndex(where: { $0 == damusRoute }) {
            path = Array(path[...index])
        }
    }
    
    func currentRoute() -> DamusWallet.WalletRoute? {
        self.path.last?.toWalletRoute()
    }
}

extension Route {
    func toWalletRoute() -> WalletRoute? {
        switch self {
        case .ProfileByKey(pubkey: let pubkey):
            return nil
        case .Profile(profile: let profile, followers: _):
            return nil
        case .Followers(followers: _):
            return nil
        case .Relay(relay: let relay, showActionButtons: let showActionButtons):
            return nil
        case .RelayDetail(relay: let relay, metadata: let metadata):
            return nil
        case .Following(following: let following):
            return nil
        case .MuteList:
            return nil
        case .RelayConfig:
            return nil
        case .Script(script: let script):
            return nil
        case .Bookmarks:
            return nil
        case .Config:
            return nil
        case .EditMetadata:
            return nil
        case .DMChat(dms: let dms):
            return nil
        case .UserRelays(relays: let relays):
            return nil
        case .KeySettings(keypair: let keypair):
            return nil
        case .AppearanceSettings(settings: let settings):
            return nil
        case .NotificationSettings(settings: let settings):
            return nil
        case .ZapSettings(settings: let settings):
            return nil
        case .TranslationSettings(settings: let settings):
            return nil
        case .ReactionsSettings(settings: let settings):
            return nil
        case .SearchSettings(settings: let settings):
            return nil
        case .DeveloperSettings(settings: let settings):
            return nil
        case .FirstAidSettings(settings: let settings):
            return nil
        case .StorageSettings(settings: let settings):
            return nil
        case .NostrDBStorageDetail(stats: let stats):
            return nil
        case .Thread(thread: let thread):
            return nil
        case .LoadableNostrEvent(note_reference: let note_reference):
            return nil
        case .Reposts(reposts: let reposts):
            return nil
        case .QuoteReposts(quotes: let quotes):
            return nil
        case .Reactions(reactions: let reactions):
            return nil
        case .Zaps(target: let target):
            return nil
        case .Search(search: let search):
            return nil
        case .NDBSearch(results: let results, query: let query):
            return nil
        case .EULA:
            return nil
        case .Login:
            return nil
        case .CreateAccount:
            return nil
        case .SaveKeys(account: let account):
            return nil
        case .Wallet(wallet: let wallet):
            return nil
        case .WalletScanner(result: let result):
            return nil
        case .FollowersYouKnow(friendedFollowers: let friendedFollowers, followers: _):
            return nil
        case .NIP05DomainEvents(events: let events, nip05_domain_favicon: let nip05_domain_favicon):
            return nil
        case .NIP05DomainPubkeys(domain: let domain, nip05_domain_favicon: let nip05_domain_favicon, pubkeys: let pubkeys):
            return nil
        case .FollowPack(followPack: let followPack, model: _, blur_imgs: _):
            return nil
        case .LiveEvents(model: _):
            return nil
        case .LiveEvent(LiveEvent: let LiveEvent, model: _):
            return nil
        case .OrangeWalletWelcome:
            return .home
        case .OrangeWalletSetup:
            return .createNewWallet
        case .OrangeWalletKeyCustodyConfirmation:
            return .keyCustodyConfirmation
        case .OrangeWalletBackupToICloud:
            return .backupToICloud
        case .OrangeWalletManualBackup:
            return .manualBackup
        case .OrangeWalletSeedWordsQuiz:
            return .seedWordsQuiz
        case .OrangeWalletSetupComplete:
            return .setupComplete
        case .OrangeWalletReceive(let receiveFlowContext):
            return .receive(receiveFlowContext)
        case .OrangeWalletReceiveAmountEntry(let receiveFlowContext):
            return .receiveAmountEntry(receiveFlowContext)
        case .OrangeWalletReceiveConfirmation(let receiveFlowContext):
            return .receiveConfirmation(receiveFlowContext)
        case .OrangeWalletSendScan(let sendFlowContext):
            return .sendScan(sendFlowContext)
        case .OrangeWalletSendAmountEntry(let sendFlowContext):
            return .sendAmountEntry(sendFlowContext)
        case .OrangeWalletSendReview(let sendFlowContext):
            return .sendReview(sendFlowContext)
        case .OrangeWalletSendConfirmation(let sendFlowContext):
            return .sendConfirmation(sendFlowContext)
        }
    }
}

extension DamusWallet.WalletRoute {
    func toDamusRoute() -> Route {
        switch self {
        case .home:
            .OrangeWalletWelcome
        case .createNewWallet:
            .OrangeWalletSetup
        case .keyCustodyConfirmation:
            .OrangeWalletKeyCustodyConfirmation
        case .backupOptions:
            .OrangeWalletWelcome
        case .backupToICloud:
            .OrangeWalletBackupToICloud
        case .manualBackup:
            .OrangeWalletManualBackup
        case .seedWordsQuiz:
            .OrangeWalletSeedWordsQuiz
        case .setupComplete:
            .OrangeWalletSetupComplete
        case .recoverWallet:
            .OrangeWalletWelcome
        case .walletSettings:
            .OrangeWalletWelcome
        case .receive(let receiveContext):
            .OrangeWalletReceive(receiveContext)
        case .receiveAmountEntry(let receiveContext):
            .OrangeWalletReceiveAmountEntry(receiveContext)
        case .receiveConfirmation(let receiveContext):
            .OrangeWalletReceiveConfirmation(receiveContext)
        case .sendScan(let sendContext):
            .OrangeWalletSendScan(sendContext)
        case .sendAmountEntry(let sendContext):
            .OrangeWalletSendAmountEntry(sendContext)
        case .sendReview(let sendContext):
            .OrangeWalletSendReview(sendContext)
        case .sendConfirmation(let sendContext):
            .OrangeWalletSendConfirmation(sendContext)
        }
    }
}
