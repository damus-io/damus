//
//  WalletConnect.swift
//  damus
//
//  Created by William Casarin on 2023-03-22.
//

import Foundation

struct WalletConnect {}

typealias WalletConnectURL = WalletConnect.ConnectURL   // Declared to facilitate refactor

extension WalletConnect {
    /// Models a decoded NWC URL, containing information to connect to an NWC wallet.
    struct ConnectURL: Equatable {
        let relay: RelayURL
        let keypair: FullKeypair
        let pubkey: Pubkey
        let lud16: String?
        
        static func == (lhs: ConnectURL, rhs: ConnectURL) -> Bool {
            return lhs.keypair == rhs.keypair &&
            lhs.pubkey == rhs.pubkey &&
            lhs.relay == rhs.relay
        }
        
        func to_url() -> URL {
            var urlComponents = URLComponents()
            urlComponents.scheme = "nostrwalletconnect"
            urlComponents.host = pubkey.hex()
            urlComponents.queryItems = [
                URLQueryItem(name: "relay", value: relay.absoluteString),
                URLQueryItem(name: "secret", value: keypair.privkey.hex())
            ]
            
            if let lud16 {
                urlComponents.queryItems?.append(URLQueryItem(name: "lud16", value: lud16))
            }
            
            return urlComponents.url!
        }
        
        init?(str: String) {
            if let cached = ConnectURL.parseCache.url(for: str) {
                self = cached
                return
            }

            guard let components = URLComponents(string: str),
                  components.scheme == "nostrwalletconnect" || components.scheme == "nostr+walletconnect",
                  // The line below provides flexibility for both `nostrwalletconnect://` (non-compliant, but commonly used) and `nostrwalletconnect:` (NIP-47 compliant) formats
                  let encoded_pubkey = components.path == "" ? components.host : components.path,
                  let pubkey = hex_decode_pubkey(encoded_pubkey),
                  let items = components.queryItems,
                  let relay = items.first(where: { qi in qi.name == "relay" })?.value,
                  let relay_url = RelayURL(relay),
                  let secret = items.first(where: { qi in qi.name == "secret" })?.value,
                  secret.utf8.count == 64,
                  let decoded = hex_decode(secret)
            else {
                return nil
            }
            
            let privkey = Privkey(Data(decoded))
            guard let our_pk = privkey_to_pubkey(privkey: privkey) else { return nil }
            
            let lud16 = items.first(where: { qi in qi.name == "lud16" })?.value
            let keypair = FullKeypair(pubkey: our_pk, privkey: privkey)
            let url = ConnectURL(pubkey: pubkey, relay: relay_url, keypair: keypair, lud16: lud16)
            ConnectURL.parseCache.store(url, for: str)
            self = url
        }
        
        init(pubkey: Pubkey, relay: RelayURL, keypair: FullKeypair, lud16: String?) {
            self.pubkey = pubkey
            self.relay = relay
            self.keypair = keypair
            self.lud16 = lud16
        }

        // MARK: - Parse caching

        private static let parseCache = ParseCache()

        /// Forgets every memoized parse, so that a disconnected wallet's secret is not
        /// kept alive in memory by the cache.
        static func forgetCachedParses() {
            ConnectURL.parseCache.removeAll()
        }

        /// Memoizes `ConnectURL(str:)` results.
        ///
        /// Parsing an NWC URL derives our pubkey from the connection secret, and secp256k1
        /// key generation is slow enough that doing it for every incoming NWC response shows
        /// up as a main thread stall (~18% of a profiled sample). Parsing is a pure function
        /// of the URL string, so the result can simply be reused.
        ///
        /// This is a mutex rather than an actor so that callers on any isolation can use
        /// `ConnectURL(str:)` synchronously, as they always have.
        private final class ParseCache {
            /// How many distinct URLs to keep, so that repeatedly parsing strings we do not
            /// control (scanned QR codes, deep links) cannot grow this without bound.
            private static let capacity = 8

            private let lock = NSLock()
            private var urls: [String: ConnectURL] = [:]

            func url(for str: String) -> ConnectURL? {
                lock.withLock { urls[str] }
            }

            func store(_ url: ConnectURL, for str: String) {
                lock.withLock {
                    if urls.count >= Self.capacity { urls.removeAll() }
                    urls[str] = url
                }
            }

            func removeAll() {
                lock.withLock { urls.removeAll() }
            }
        }
    }
    
    /// Models an NWC wallet transaction
    struct Transaction: Decodable, Equatable, Hashable {
        let type: String
        let invoice: String?
        let description: String?
        let description_hash: String?
        let preimage: String?
        let payment_hash: String?
        let amount: Int64
        let fees_paid: Int64?
        let created_at: UInt64 // unixtimestamp, // invoice/payment creation time
        let expires_at: UInt64?  // unixtimestamp, // invoice expiration time, optional if not applicable
        let settled_at: UInt64? // unixtimestamp, // invoice/payment settlement time, optional if unpaid
        let metadata: WalletConnect.Request.Metadata?    // generic metadata that can be used to add things like zap/boostagram details for a payer name/comment/etc.
    }
}

