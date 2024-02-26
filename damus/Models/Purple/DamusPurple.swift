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
    var checkout_ids_in_progress: Set<String> = []

    @MainActor
    var account_cache: [Pubkey: Account]
    @MainActor
    var account_uuid_cache: [Pubkey: UUID]

    init(settings: UserSettingsStore, keypair: Keypair) {
        self.settings = settings
        self.keypair = keypair
        self.account_cache = [:]
        self.account_uuid_cache = [:]
        self.storekit_manager = StoreKitManager.standard    // Use singleton to avoid losing local purchase data
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
    
    func make_iap_purchase(product: Product) async throws {
        let account_uuid = try await self.get_maybe_cached_uuid_for_account()
        let result = try await self.storekit_manager.purchase(product: product, id: account_uuid)
        switch result {
            case .success(.verified(let tx)):
                // Record the purchase with the storekit manager, to make sure we have the update on the UIs as soon as possible.
                // During testing I found that the purchase initiated via `purchase` was not emitted via the listener `StoreKit.Transaction.updates` until the app was restarted.
                self.storekit_manager.record_purchased_product(StoreKitManager.PurchasedProduct(tx: tx, product: product))
                // Send the receipt to the server
                await self.send_receipt()
            default:
                // Any time we get a non-verified result, it means that the purchase was not successful, and thus we should throw an error.
                throw PurpleError.iap_purchase_error(result: result)
        }
    }
    
    @MainActor
    func get_maybe_cached_uuid_for_account() async throws -> UUID {
        if let account_uuid = self.account_uuid_cache[self.keypair.pubkey] {
            return account_uuid
        }
        return try await fetch_uuid_for_account()
    }
    
    @MainActor
    func fetch_uuid_for_account() async throws -> UUID {
        let url = self.environment.api_base_url().appending(path: "/accounts/\(self.keypair.pubkey)/account-uuid")
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
                    Log.info("Got user UUID from Damus Purple server", for: .damus_purple)
                default:
                    Log.error("Error in getting user UUID with Damus Purple. HTTP status code: %d; Response: %s", for: .damus_purple, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw PurpleError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        let account_uuid_info = try JSONDecoder().decode(AccountUUIDInfo.self, from: data)
        self.account_uuid_cache[self.keypair.pubkey] = account_uuid_info.account_uuid
        return account_uuid_info.account_uuid
    }
    
    func send_receipt() async {
        // Get the receipt if it's available.
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
            FileManager.default.fileExists(atPath: appStoreReceiptURL.path) {

            do {
                let receiptData = try Data(contentsOf: appStoreReceiptURL, options: .alwaysMapped)
                let receipt_base64_string = receiptData.base64EncodedString()
                let account_uuid = try await self.get_maybe_cached_uuid_for_account()
                let json_text: [String: String] = ["receipt": receipt_base64_string, "account_uuid": account_uuid.uuidString]
                let json_data = try JSONSerialization.data(withJSONObject: json_text)
                
                let url = environment.api_base_url().appendingPathComponent("accounts/\(keypair.pubkey.hex())/apple-iap/app-store-receipt")
                
                Log.info("Sending in-app purchase receipt to Damus Purple server", for: .damus_purple)
                
                let (data, response) = try await make_nip98_authenticated_request(
                    method: .post,
                    url: url,
                    payload: json_data,
                    payload_type: .json,
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
    
    @MainActor
    func fetch_ln_checkout_object(checkout_id: String) async throws -> LNCheckoutInfo? {
        let url = environment.api_base_url().appendingPathComponent("ln-checkout/\(checkout_id)")
        
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
                    return try JSONDecoder().decode(LNCheckoutInfo.self, from: data)
                case 404:
                    return nil
                default:
                    throw PurpleError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw PurpleError.error_processing_response
    }
    
    @MainActor
    /// This function checks the status of all checkout objects in progress with the server, and it does two things:
    /// - It returns the ones that were freshly completed
    /// - It internally marks them as "completed"
    /// Important note: If you call this function, you must use the result, as those checkouts will not be returned the next time you call this function
    ///
    /// - Returns: An array of checkout objects that have been successfully completed.
    func check_status_of_checkouts_in_progress() async throws -> [String] {
        var freshly_completed_checkouts: [String] = []
        for checkout_id in self.checkout_ids_in_progress {
            let checkout_info = try await self.fetch_ln_checkout_object(checkout_id: checkout_id)
            if checkout_info?.is_all_good() == true {
                freshly_completed_checkouts.append(checkout_id)
            }
            if checkout_info?.completed == true {
                self.checkout_ids_in_progress.remove(checkout_id)
            }
        }
        return freshly_completed_checkouts
    }
    
    @MainActor
    /// This function checks the status of a specific checkout id with the server
    /// You should use this result immediately, since it will internally be marked as handled
    ///
    /// - Returns: true if this checkout is all good to go. false if not. nil if checkout was not found.
    func check_and_mark_ln_checkout_is_good_to_go(checkout_id: String) async throws -> Bool? {
        let checkout_info = try await self.fetch_ln_checkout_object(checkout_id: checkout_id)
        if checkout_info?.completed == true {
            self.checkout_ids_in_progress.remove(checkout_id)    // Remove if from the list of checkouts in progress
        }
        return checkout_info?.is_all_good()
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
    
    struct LNCheckoutInfo: Codable {
        // Note: Swift will decode a JSON full of extra fields into a Struct with only a subset of them, but not the other way around
        // Therefore, to avoid compatibility concerns and complexity, we should only use the fields we need
        // The ones we do not need yet will be left commented out until we need them.
        let id: UUID
        /*
        let product_template_name: String
        let verified_pubkey: String?
        */
        let invoice: Invoice?
        let completed: Bool
        
        
        struct Invoice: Codable {
            /*
            let bolt11: String
            let label: String
            let connection_params: ConnectionParams
            */
            let paid: Bool?
            
            /*
            struct ConnectionParams: Codable {
                let nodeid: String
                let address: String
                let rune: String
            }
            */
        }
        
        /// Indicates whether this checkout is all good to go.
        /// The checkout is good to go if it is marked as complete and the invoice has been successfully paid
        /// - Returns: true if this checkout is all good to go. false otherwise
        func is_all_good() -> Bool {
            return self.completed == true && self.invoice?.paid == true
        }
    }
    
    fileprivate struct AccountUUIDInfo: Codable {
        let account_uuid: UUID
    }
}

// MARK: Helper structures

extension DamusPurple {
    enum PurpleError: Error {
        case translation_error(status_code: Int, response: Data)
        case http_response_error(status_code: Int, response: Data)
        case error_processing_response
        case iap_purchase_error(result: Product.PurchaseResult)
        case translation_no_response
        case checkout_npub_verification_error
    }
    
    struct TranslationResult: Codable {
        let text: String
    }
}
