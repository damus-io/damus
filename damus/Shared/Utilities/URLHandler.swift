//
//  URLHandler.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-09-06.
//

import Foundation

/// Parses URLs into actions within the app.
///
/// ## Implementation notes
///
/// - This exists so that we can separate the logic of parsing the URL and the actual action within the app. That makes the code more readable, testable, and extensible
struct DamusURLHandler {
    /// Parses a URL, handles any needed actions within damus state, and returns the view to be opened in the app
    ///
    /// Side effects: May mutate `damus_state` in some circumstances
    ///
    /// - Parameters:
    ///   - damus_state: The Damus state. May be mutated as part of this function
    ///   - url: The URL to be opened
    /// - Returns: A view to be shown to the user
    static func handle_opening_url_and_compute_view_action(damus_state: DamusState, url: URL) async -> ContentView.ViewOpenAction {
        let parsed_url_info = parse_url(url: url)
        
        switch parsed_url_info {
        case .profile(let pubkey):
            return .route(.ProfileByKey(pubkey: pubkey))
        case .relay(let relayURL):
            let metadata = damus_state.relay_model_cache.model(with_relay_id: relayURL)?.metadata
            return .route(.RelayDetail(relay: relayURL, metadata: metadata))
        case .filter(let nostrFilter):
            let search = SearchModel(state: damus_state, search: nostrFilter)
            return .route(.Search(search: search))
        case .event(let nostrEvent):
            let thread = await ThreadModel(event: nostrEvent, damus_state: damus_state)
            return .route(.Thread(thread: thread))
        case .event_reference(let event_reference):
            return .route(.LoadableNostrEvent(note_reference: event_reference))
        case .wallet_connect(let walletConnectURL):
            damus_state.wallet.new(walletConnectURL)
            return .route(.Wallet(wallet: damus_state.wallet))
        case .script(let data):
            let model = ScriptModel(data: data, state: .not_loaded)
            return .route(.Script(script: model))
        case .purple(let purple_url):
            return await damus_state.purple.handle(purple_url: purple_url)
        case .invoice(let invoice):
            if damus_state.settings.show_wallet_selector {
                return .sheet(.select_wallet(invoice: invoice.string))
            } else {
                guard let url = try? getUrlToOpen(invoice: invoice.string, with: damus_state.settings.default_wallet.model) else {
                    return .sheet(.select_wallet(invoice: invoice.string))
                }
                return .external_url(url)
            }
        case nil:
            break
        }
        return .sheet(.error(ErrorView.UserPresentableError(
            user_visible_description: NSLocalizedString("Could not parse the URL you are trying to open.", comment: "User visible error description"),
            tip: NSLocalizedString("Please try again, check the URL for typos, or contact support for further help.", comment: "User visible error tips"),
            technical_info: "Could not find a suitable open action. User tried to open this URL: \(url.absoluteString)"
        )))
    }
    
    /// Parses a URL into a structured information object.
    ///
    /// This function does not cause any mutations on the app, or any side-effects.
    ///
    /// - Parameter url: The URL to be parsed
    /// - Returns: Structured information about the contents inside the URL. Returns `nil` if URL is not compatible, invalid, or could not be parsed for some reason.
    static func parse_url(url: URL) -> ParsedURLInfo? {
        if let purple_url = DamusPurpleURL(url: url) {
            return .purple(purple_url)
        }
        
        if let nwc = WalletConnectURL(str: url.absoluteString) {
            return .wallet_connect(nwc)
        }

        if let parsedRelay = parse_relay_url(url: url) {
            return parsedRelay
        }
        
        guard let link = decode_nostr_uri(url.absoluteString) else {
            return nil
        }
        
        switch link {
        case .ref(let ref):
            switch ref {
            case .pubkey(let pk):
                return .profile(pk)
            case .event(let noteid):
                return .event_reference(.note_id(noteid))
            case .hashtag(let ht):
                return .filter(.filter_hashtag([ht.hashtag]))
            case .param, .quote, .reference:
                // doesn't really make sense here
                break
            case .naddr(let naddr):
                return .event_reference(.naddr(naddr))
            }
        case .filter(let filt):
            return .filter(filt)
        case .script(let script):
            return .script(script)
        case .invoice(let bolt11):
            if let invoice = decode_bolt11(bolt11) {
                return .invoice(invoice)
            }
            return nil
        }
        return nil
    }
    
    enum ParsedURLInfo {
        case profile(Pubkey)
        case relay(RelayURL)
        case filter(NostrFilter)
        case event(NostrEvent)
        case event_reference(LoadableNostrEventViewModel.NoteReference)
        case wallet_connect(WalletConnectURL)
        case script([UInt8])
        case purple(DamusPurpleURL)
        case invoice(Invoice)
    }

    private static func parse_relay_url(url: URL) -> ParsedURLInfo? {
        guard let scheme = url.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "damus":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }

            let host = components.host?.lowercased()
            var potentialRelayString: String?

            if host == "relay" {
                potentialRelayString = components.queryItems?.first(where: { $0.name == "url" })?.value
                if potentialRelayString == nil {
                    let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    potentialRelayString = trimmedPath.isEmpty ? nil : trimmedPath
                }
            } else {
                let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if trimmedPath.lowercased().hasPrefix("relay:") {
                    potentialRelayString = String(trimmedPath.dropFirst("relay:".count))
                }
            }

            guard let rawRelay = potentialRelayString else {
                return nil
            }

            let decodedRelay = rawRelay.removingPercentEncoding ?? rawRelay
            guard let relay = RelayURL(decodedRelay) else {
                return nil
            }

            return .relay(relay)

        case "ws", "wss":
            return RelayURL(url.absoluteString).map { .relay($0) }

        default:
            return nil
        }
    }
}
