//
//  WalletConnect+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

// TODO: Eventually we should move these convenience functions into structured classes responsible for managing this type of functionality, such as `WalletModel`

extension WalletConnect {
    /// Creates and sends a subscription to an NWC relay requesting NWC responses to be sent back.
    ///
    /// Notes: This assumes there is already a listener somewhere else
    ///
    /// - Parameters:
    ///   - url: The Nostr Wallet Connect URL containing connection info to the NWC wallet
    ///   - pool: The RelayPool to send the subscription request through
    static func subscribe(url: WalletConnectURL, pool: RelayPool) {
        var filter = NostrFilter(kinds: [.nwc_response])
        filter.authors = [url.pubkey]
        filter.pubkeys = [url.keypair.pubkey]
        filter.limit = 0
        let sub = NostrSubscribe(filters: [filter], sub_id: "nwc")

        pool.send(.subscribe(sub), to: [url.relay], skip_ephemeral: false)
    }

    /// Sends out a request to pay an invoice to the NWC relay, and ensures that:
    /// 1. the NWC relay is connected and we are listening to NWC events
    /// 2. the NWC relay is connected and we are listening to NWC
    ///
    /// Note: This does not return information about whether the payment is succesful or not. The actual confirmation is handled elsewhere around `HomeModel` and `WalletModel`
    ///
    /// - Parameters:
    ///   - url: The NWC wallet connection URL
    ///   - pool: The relay pool to connect to
    ///   - post: The postbox to send events in
    ///   - delay: The delay before actually sending the request to the network _(this makes it possible to cancel a zap)_
    ///   - on_flush: A callback to call after the event has been flushed to the network
    /// - Returns: The Nostr Event that was sent to the network, representing the request that was made
    @discardableResult
    static func pay(url: WalletConnectURL, pool: RelayPool, post: PostBox, invoice: String, zap_request: NostrEvent?, delay: TimeInterval? = 5.0, on_flush: OnFlush? = nil) -> NostrEvent? {
        
        let req = WalletConnect.Request.payZapRequest(invoice: invoice, zapRequest: zap_request)
        guard let ev = req.to_nostr_event(to_pk: url.pubkey, keypair: url.keypair) else {
            return nil
        }

        try? pool.add_relay(.nwc(url: url.relay))   // Ensure the NWC relay is connected
        WalletConnect.subscribe(url: url, pool: pool)      // Ensure we are listening to NWC updates from the relay
        post.send(ev, to: [url.relay], skip_ephemeral: false, delay: delay, on_flush: on_flush)
        return ev
    }

    /// Sends out a wallet balance request to the NWC relay, and ensures that:
    /// 1. the NWC relay is connected and we are listening to NWC events
    /// 2. the NWC relay is connected and we are listening to NWC
    ///
    /// Note: This does not return the actual balance information. The actual balance is handled elsewhere around `HomeModel` and `WalletModel`
    ///
    /// - Parameters:
    ///   - url: The NWC wallet connection URL
    ///   - pool: The relay pool to connect to
    ///   - post: The postbox to send events in
    ///   - delay: The delay before actually sending the request to the network
    ///   - on_flush: A callback to call after the event has been flushed to the network
    /// - Returns: The Nostr Event that was sent to the network, representing the request that was made
    @discardableResult
    static func request_balance_information(url: WalletConnectURL, pool: RelayPool, post: PostBox, delay: TimeInterval? = 0.0, on_flush: OnFlush? = nil) -> NostrEvent? {
        let req = WalletConnect.Request.getBalance
        guard let ev = req.to_nostr_event(to_pk: url.pubkey, keypair: url.keypair) else {
            return nil
        }

        try? pool.add_relay(.nwc(url: url.relay))   // Ensure the NWC relay is connected
        WalletConnect.subscribe(url: url, pool: pool)      // Ensure we are listening to NWC updates from the relay
        post.send(ev, to: [url.relay], skip_ephemeral: false, delay: delay, on_flush: on_flush)
        return ev
    }

    /// Sends out a wallet transaction list request to the NWC relay, and ensures that:
    /// 1. the NWC relay is connected and we are listening to NWC events
    /// 2. the NWC relay is connected and we are listening to NWC
    ///
    /// Note: This does not return the actual transaction list. The actual transaction list is handled elsewhere around `HomeModel` and `WalletModel`
    ///
    /// - Parameters:
    ///   - url: The NWC wallet connection URL
    ///   - pool: The relay pool to connect to
    ///   - post: The postbox to send events in
    ///   - delay: The delay before actually sending the request to the network
    ///   - on_flush: A callback to call after the event has been flushed to the network
    /// - Returns: The Nostr Event that was sent to the network, representing the request that was made
    @discardableResult
    static func request_transaction_list(url: WalletConnectURL, pool: RelayPool, post: PostBox, delay: TimeInterval? = 0.0, on_flush: OnFlush? = nil) -> NostrEvent? {
        let req = WalletConnect.Request.getTransactionList(from: nil, until: nil, limit: 10, offset: 0, unpaid: false, type: "")
        guard let ev = req.to_nostr_event(to_pk: url.pubkey, keypair: url.keypair) else {
            return nil
        }

        try? pool.add_relay(.nwc(url: url.relay))   // Ensure the NWC relay is connected
        WalletConnect.subscribe(url: url, pool: pool)      // Ensure we are listening to NWC updates from the relay
        post.send(ev, to: [url.relay], skip_ephemeral: false, delay: delay, on_flush: on_flush)
        return ev
    }
    
    @MainActor
    static func refresh_wallet_information(damus_state: DamusState) async {
        damus_state.wallet.resetWalletStateInformation()
        await Self.update_wallet_information(damus_state: damus_state)
    }
    
    @MainActor
    static func update_wallet_information(damus_state: DamusState) async {
        guard let url = damus_state.settings.nostr_wallet_connect,
              let nwc = WalletConnectURL(str: url) else {
            return
        }
        
        let flusher: OnFlush? = nil
        
        let delay = 0.0     // We don't need a delay when fetching a transaction list or balance

        damus_state.nostrNetwork.requestTransactionList(url: nwc, delay: delay, on_flush: flusher)
        damus_state.nostrNetwork.requestBalanceInformation(url: nwc, delay: delay, on_flush: flusher)
        return
    }

    static func handle_zap_success(state: DamusState, resp: WalletConnect.FullWalletResponse) {
        // find the pending zap and mark it as pending-confirmed
        for kv in state.zaps.our_zaps {
            let zaps = kv.value
            
            for zap in zaps {
                guard case .pending(let pzap) = zap,
                      case .nwc(let nwc_state) = pzap.state,
                      case .postbox_pending(let nwc_req) = nwc_state.state,
                      nwc_req.id == resp.req_id
                else {
                    continue
                }
                
                if nwc_state.update_state(state: .confirmed) {
                    // notify the zaps model of an update so it can mark them as paid
                    state.events.get_cache_data(NoteId(pzap.target.id)).zaps_model.objectWillChange.send()
                    print("NWC success confirmed")
                }
                
                return
            }
        }
    }

    /// Handles a received Nostr Wallet Connect error
    static func handle_error(zapcache: Zaps, evcache: EventCache, resp: WalletConnect.FullWalletResponse) {
        // find a pending zap with the nwc request id associated with this response and remove it
        for kv in zapcache.our_zaps {
            let zaps = kv.value
            
            for zap in zaps {
                guard case .pending(let pzap) = zap,
                      case .nwc(let nwc_state) = pzap.state,
                      case .postbox_pending(let req) = nwc_state.state,
                      req.id == resp.req_id
                else {
                    continue
                }
                
                // remove the pending zap if there was an error
                let reqid = ZapRequestId(from_pending: pzap)
                remove_zap(reqid: reqid, zapcache: zapcache, evcache: evcache)
                return
            }
        }
    }
}
