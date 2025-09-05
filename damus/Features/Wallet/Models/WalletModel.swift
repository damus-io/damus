//
//  WalletModel.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import Foundation

enum WalletConnectState {
    case new(WalletConnectURL)
    case existing(WalletConnectURL)
    case none
    
    /// Gets the currently connected NWC URL
    func currentNwcUrl() -> WalletConnectURL? {
        switch self {
        case .new:
            return nil  // User has not confirmed they want to use this yet, so we cannot call it "current"
        case .existing(let nwcUrl):
            return nwcUrl
        case .none:
            return nil
        }
    }
}

/// Models and manages the user's NWC wallet based on the app's settings
class WalletModel: ObservableObject {
    var settings: UserSettingsStore
    var nostrNetwork: NostrNetworkManager? = nil
    private(set) var previous_state: WalletConnectState
    var initial_percent: Int
    /// The wallet's balance, in sats.
    /// Starts with `nil` to signify it is not loaded yet
    @Published private(set) var balance: Int64? = nil
    /// The list of NWC transactions made in the wallet
    /// Starts with `nil` to signify it is not loaded yet
    @Published private(set) var transactions: [WalletConnect.Transaction]? = nil
    
    @Published private(set) var connect_state: WalletConnectState
    
    /// A dictionary listing continuations waiting for a response for each request note id.
    ///
    /// Please see the `waitForResponse` method for context.
    private var continuations: [NoteId: CheckedContinuation<WalletConnect.Response.Result, any Error>] = [:]
    
    init(state: WalletConnectState, settings: UserSettingsStore) {
        self.connect_state = state
        self.previous_state = .none
        self.settings = settings
        self.initial_percent = settings.donation_percent
        self.nostrNetwork = nil
    }
    
    init(settings: UserSettingsStore) {
        self.settings = settings
        if let str = settings.nostr_wallet_connect,
           let nwc = WalletConnectURL(str: str) {
            self.previous_state = .existing(nwc)
            self.connect_state = .existing(nwc)
        } else {
            self.previous_state = .none
            self.connect_state = .none
        }
        self.initial_percent = settings.donation_percent
        self.nostrNetwork = nil
    }
    
    func cancel() {
        self.connect_state = previous_state
        self.objectWillChange.send()
    }
    
    func disconnect() {
        self.settings.nostr_wallet_connect = nil
        self.connect_state = .none
        self.previous_state = .none
    }
    
    func new(_ nwc: WalletConnectURL) {
        self.connect_state = .new(nwc)
    }
    
    func connect(_ nwc: WalletConnectURL) {
        self.settings.nostr_wallet_connect = nwc.to_url().absoluteString
        notify(.attached_wallet(nwc))
        self.connect_state = .existing(nwc)
        self.previous_state = .existing(nwc)
    }

    /// Handles an NWC response event and updates the model.
    /// 
    /// This takes a response received from the NWC relay and updates the internal state of this model.
    /// 
    /// - Parameter response: The NWC response received from the network
    func handle_nwc_response(response: WalletConnect.FullWalletResponse) {
        if let error = response.response.error {
            self.resume(request: response.req_id, throwing: error)
            return
        }
        guard let result = response.response.result else { return }
        self.resume(request: response.req_id, with: result)
        switch result {
        case .get_balance(let balanceResp):
            self.balance = balanceResp.balance / 1000
        case .pay_invoice(_):
            return
        case .list_transactions(let transactionsResp):
            self.transactions = transactionsResp.transactions
        }
    }
    
    
    // MARK: - Wallet internal state lifecycle functions
    
    @MainActor
    func resetWalletStateInformation() {
        self.transactions = nil
        self.balance = nil
    }
    
    
    func refreshWalletInformation() async throws {
        await self.resetWalletStateInformation()
        try await loadWalletInformation()
    }
    
    func loadWalletInformation() async throws {
        try await loadBalance()
        try await loadTransactionList()
    }
    
    func loadBalance() async throws {
        let balance = try await fetchBalance()
        DispatchQueue.main.async {
            self.balance = balance
        }
    }
    
    func loadTransactionList() async throws {
        let transactions = try await fetchTransactions(from: nil, until: nil, limit: 50, offset: 0, unpaid: false, type: "")
        DispatchQueue.main.async {
            self.transactions = transactions
        }
    }
    
    // MARK: - Easy wallet info fetching interface
    
    func fetchTransactions(from: UInt64?, until: UInt64?, limit: Int?, offset: Int?, unpaid: Bool?, type: String?) async throws -> [WalletConnect.Transaction] {
        let response = try await self.request(.getTransactionList(from: from, until: until, limit: limit, offset: offset, unpaid: unpaid, type: type))
        guard case .list_transactions(let transactionResponse) = response else { throw FetchError.responseMismatch }
        return transactionResponse.transactions
    }
    
    
    /// Fetches the balance amount from the network and returns the amount in sats
    func fetchBalance() async throws -> Int64 {
        let response = try await self.request(.getBalance)
        guard case .get_balance(let balanceResponse) = response else { throw FetchError.responseMismatch }
        return balanceResponse.balance / 1000
    }
    
    enum FetchError: Error {
        case responseMismatch
    }
    
    // MARK: - Easy request/response interface
    
    func request(_ request: WalletConnect.Request, timeout: Duration = .seconds(10)) async throws(WalletRequestError) -> WalletConnect.Response.Result {
        guard let nostrNetwork else { throw .notConnectedToTheNostrNetwork }
        guard let currentNwcUrl = self.connect_state.currentNwcUrl() else { throw .noConnectedWallet }
        guard let requestEvent = request.to_nostr_event(to_pk: currentNwcUrl.pubkey, keypair: currentNwcUrl.keypair) else { throw .errorFormattingRequest }

        let responseFilters = [
            NostrFilter(
                kinds: [.nwc_response],
                referenced_ids: [requestEvent.id],
                pubkeys: [currentNwcUrl.keypair.pubkey],
                authors: [currentNwcUrl.pubkey]
            )
        ]
        
        nostrNetwork.send(event: requestEvent, to: [currentNwcUrl.relay], skipEphemeralRelays: false)
        for await item in nostrNetwork.reader.subscribe(filters: responseFilters, to: [currentNwcUrl.relay], timeout: timeout) {
            switch item {
            case .event(borrow: let borrow):
                var responseEvent: NostrEvent? = nil
                try? borrow { ev in responseEvent = ev.toOwned() }
                guard let responseEvent else { throw .internalError }
                
                let fullWalletResponse: WalletConnect.FullWalletResponse
                do { fullWalletResponse = try WalletConnect.FullWalletResponse(from: responseEvent, nwc: currentNwcUrl) }
                catch { throw WalletRequestError.walletResponseDecodingError(error) }
                
                guard fullWalletResponse.req_id == requestEvent.id else { continue }    // Our filters may match other responses
                if let responseError = fullWalletResponse.response.error { throw .walletResponseError(responseError) }
                
                guard let result = fullWalletResponse.response.result else { throw .walletEmptyResponse }
                return result
            case .eose:
                continue
            }
        }
        do { try Task.checkCancellation() } catch { throw .cancelled }
        throw .responseTimeout
    }
    
    enum WalletRequestError: Error {
        case notConnectedToTheNostrNetwork
        case noConnectedWallet
        case errorFormattingRequest
        case internalError
        case walletResponseDecodingError(WalletConnect.FullWalletResponse.InitializationError)
        case walletResponseMismatch
        case walletResponseError(WalletConnect.WalletResponseErr)
        case walletEmptyResponse
        case responseTimeout
        case cancelled
    }
    
    // MARK: - Async wallet response waiting mechanism
    
    func waitForResponse(for requestId: NoteId, timeout: Duration = .seconds(10)) async throws -> WalletConnect.Response.Result {
        return try await withCheckedThrowingContinuation({ continuation in
            self.continuations[requestId] = continuation
            
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                self.resume(request: requestId, throwing: WaitError.timeout)    // Must resume the continuation exactly once even if there is no response
            }
        })
    }
    
    private func resume(request requestId: NoteId, with result: WalletConnect.Response.Result) {
        continuations[requestId]?.resume(returning: result)
        continuations[requestId] = nil      // Never resume a continuation twice
    }
    
    private func resume(request requestId: NoteId, throwing error: any Error) {
        if let continuation = continuations[requestId] {
            continuation.resume(throwing: error)
            continuations[requestId] = nil      // Never resume a continuation twice
            return      // Error will be handled by the listener, no need for the generic error sheet
        }
        
        // No listeners to catch the error, show generic error sheet
        if let error = error as? WalletConnect.WalletResponseErr,
           let humanReadableError = error.humanReadableError {
            present_sheet(.error(humanReadableError))
        }
    }
    
    enum WaitError: Error {
        case timeout
    }
}
