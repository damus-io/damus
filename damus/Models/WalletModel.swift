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
}

/// Models and manages the user's NWC wallet based on the app's settings
class WalletModel: ObservableObject {
    var settings: UserSettingsStore
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
    
    func resetWalletStateInformation() {
        self.transactions = nil
        self.balance = nil
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
