//
//  DamusPurple.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-12-08.
//

import Foundation
import StoreKit

class DamusPurple: StoreObserverDelegate {
    let settings: UserSettingsStore
    let keypair: Keypair
    var storekit_manager: StoreKitManager

    @MainActor
    var account_cache: [Pubkey: Account]

    init(settings: UserSettingsStore, keypair: Keypair) {
        self.settings = settings
        self.keypair = keypair
        self.account_cache = [:]
        self.storekit_manager = .init()
    }
    
    // MARK: Functions
    func is_profile_subscribed_to_purple(pubkey: Pubkey) async -> Bool? {
        return try? await self.get_maybe_cached_account(pubkey: pubkey)?.active
    }
    
    var environment: DamusPurpleEnvironment {
        return self.settings.purple_enviroment
    }
    
    var enable_purple: Bool {
        return true
        // TODO: On release, we could just replace this with `true` (or some other feature flag)
        //return self.settings.enable_experimental_purple_api
    }
    
    // Whether to enable Apple In-app purchase support
    var enable_purple_iap_support: Bool {
        // TODO: When we have full support for Apple In-app purchases, we can replace this with `true` (or another feature flag)
        return self.settings.enable_experimental_purple_iap_support
    }

    func account_exists(pubkey: Pubkey) async -> Bool? {
        guard let account_data = try? await self.get_account_data(pubkey: pubkey) else { return nil }
        
        if let account_info = try? JSONDecoder().decode(AccountInfo.self, from: account_data) {
            return account_info.pubkey == pubkey.hex()
        }
        
        return false
    }

    @MainActor
    func get_maybe_cached_account(pubkey: Pubkey) async throws -> Account? {
        if let account = self.account_cache[pubkey] {
            return account
        }
        return try await fetch_account(pubkey: pubkey)
    }

    @MainActor
    func fetch_account(pubkey: Pubkey) async throws -> Account? {
        guard let data = try await self.get_account_data(pubkey: pubkey) ,
              let account = Account.from(json_data: data) else {
            return nil
        }
        self.account_cache[pubkey] = account
        return account
    }
    
    func get_account_data(pubkey: Pubkey) async throws -> Data? {
        let url = environment.api_base_url().appendingPathComponent("accounts/\(pubkey.hex())")
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .get,
            url: url,
            payload: nil,
            payload_type: nil,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    return data
                case 404:
                    return nil
                default:
                    throw PurpleError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw PurpleError.error_processing_response
    }
    
    func create_account(pubkey: Pubkey) async throws {
        let url = environment.api_base_url().appendingPathComponent("accounts")
        
        Log.info("Creating account with Damus Purple server", for: .damus_purple)
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .post,
            url: url,
            payload: nil,
            payload_type: nil,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    Log.info("Created an account with Damus Purple server", for: .damus_purple)
                default:
                    Log.error("Error in creating account with Damus Purple. HTTP status code: %d; Response: %s", for: .damus_purple, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
            }
        }
        
        return
    }
    
    func create_account_if_not_existing(pubkey: Pubkey) async throws {
        guard await !(self.account_exists(pubkey: pubkey) ?? false) else { return }
        try await self.create_account(pubkey: pubkey)
    }
    
    func make_iap_purchase(product: Product) async throws -> Product.PurchaseResult {
        return try await self.storekit_manager.purchase(product: product)
    }
    
    func send_receipt() async {
        // Get the receipt if it's available.
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
            FileManager.default.fileExists(atPath: appStoreReceiptURL.path) {

            try? await create_account_if_not_existing(pubkey: keypair.pubkey)

            do {
                let receiptData = try Data(contentsOf: appStoreReceiptURL, options: .alwaysMapped)
                let url = environment.api_base_url().appendingPathComponent("accounts/\(keypair.pubkey.hex())/app-store-receipt")
                
                Log.info("Sending in-app purchase receipt to Damus Purple server", for: .damus_purple)
                
                let (data, response) = try await make_nip98_authenticated_request(
                    method: .post,
                    url: url,
                    payload: receiptData,
                    payload_type: .binary,
                    auth_keypair: self.keypair
                )
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                        case 200:
                            Log.info("Sent in-app purchase receipt to Damus Purple server successfully", for: .damus_purple)
                        default:
                            Log.error("Error in sending in-app purchase receipt to Damus Purple. HTTP status code: %d; Response: %s", for: .damus_purple, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    }
                }
                
            }
            catch {
                Log.error("Couldn't read receipt data with error: %s", for: .damus_purple, error.localizedDescription)
            }
        }
    }
    
    func translate(text: String, source source_language: String, target target_language: String) async throws -> String {
        var url = environment.api_base_url()
        url.append(path: "/translate")
        url.append(queryItems: [
            .init(name: "source", value: source_language),
            .init(name: "target", value: target_language),
            .init(name: "q", value: text)
        ])
        let (data, response) = try await make_nip98_authenticated_request(
            method: .get,
            url: url,
            payload: nil,
            payload_type: nil,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    return try JSONDecoder().decode(TranslationResult.self, from: data).text
                default:
                    Log.error("Translation error with Damus Purple. HTTP status code: %d; Response: %s", for: .damus_purple, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw PurpleError.translation_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        else {
            throw PurpleError.translation_no_response
        }
    }
    
    func verify_npub_for_checkout(checkout_id: String) async throws {
        var url = environment.api_base_url()
        url.append(path: "/ln-checkout/\(checkout_id)/verify")
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .put,
            url: url,
            payload: nil,
            payload_type: nil,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    Log.info("Verified npub for checkout id `%s` with Damus Purple server", for: .damus_purple, checkout_id)
                default:
                    Log.error("Error in verifying npub with Damus Purple. HTTP status code: %d; Response: %s; Checkout id: ", for: .damus_purple, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown", checkout_id)
                    throw PurpleError.checkout_npub_verification_error
            }
        }
        
    }
    
    struct Account {
        let pubkey: Pubkey
        let created_at: Date
        let expiry: Date
        let subscriber_number: Int
        let active: Bool

        func ordinal() -> String? {
            let number = Int(self.subscriber_number)
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            return formatter.string(from: NSNumber(integerLiteral: number))
        }

        static func from(json_data: Data) -> Self? {
            guard let payload = try? JSONDecoder().decode(Payload.self, from: json_data) else { return nil }
            return Self.from(payload: payload)
        }
        
        static func from(payload: Payload) -> Self? {
            guard let pubkey = Pubkey(hex: payload.pubkey) else { return nil }
            return Self(
                pubkey: pubkey,
                created_at: Date.init(timeIntervalSince1970: TimeInterval(payload.created_at)),
                expiry: Date.init(timeIntervalSince1970: TimeInterval(payload.expiry)),
                subscriber_number: Int(payload.subscriber_number),
                active: payload.active
            )
        }
        
        struct Payload: Codable {
            let pubkey: String              // Hex-encoded string
            let created_at: UInt64          // Unix timestamp
            let expiry: UInt64              // Unix timestamp
            let subscriber_number: UInt
            let active: Bool
        }
    }
}

// MARK: API types

extension DamusPurple {
    fileprivate struct AccountInfo: Codable {
        let pubkey: String
        let created_at: UInt64
        let expiry: UInt64?
        let active: Bool
    }
}

// MARK: Helper structures

extension DamusPurple {
    enum PurpleError: Error {
        case translation_error(status_code: Int, response: Data)
        case http_response_error(status_code: Int, response: Data)
        case error_processing_response
        case translation_no_response
        case checkout_npub_verification_error
    }
    
    struct TranslationResult: Codable {
        let text: String
    }
}
