//
//  DamusPurple.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-12-08.
//

import Foundation

class DamusPurple: StoreObserverDelegate {
    let environment: ServerEnvironment
    let keypair: Keypair
    var starred_profiles_cache: [Pubkey: Bool]
    
    init(environment: ServerEnvironment, keypair: Keypair) {
        self.environment = environment
        self.keypair = keypair
        self.starred_profiles_cache = [:]
    }
    
    // MARK: Functions
    func is_profile_subscribed_to_purple(pubkey: Pubkey) async -> Bool? {
        if let cached_result = self.starred_profiles_cache[pubkey] {
            return cached_result
        }
        
        guard let data = await self.get_account_data(pubkey: pubkey) else { return nil }
        
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let active = json["active"] as? Bool {
            self.starred_profiles_cache[pubkey] = active
            return active
        }
        
        return nil
    }
    
    func account_exists(pubkey: Pubkey) async -> Bool? {
        guard let account_data = await self.get_account_data(pubkey: pubkey) else { return nil }
        
        if let account_info = try? JSONDecoder().decode(AccountInfo.self, from: account_data) {
            return account_info.pubkey == pubkey.hex()
        }
        
        return false
    }
    
    func get_account_data(pubkey: Pubkey) async -> Data? {
        let url = environment.get_base_url().appendingPathComponent("accounts/\(pubkey.hex())")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            print("Failed to fetch data: \(error)")
        }
        
        return nil
    }
    
    func create_account(pubkey: Pubkey) async throws {
        let url = environment.get_base_url().appendingPathComponent("accounts")
        
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
    
    func send_receipt() async {
        // Get the receipt if it's available.
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
            FileManager.default.fileExists(atPath: appStoreReceiptURL.path) {

            try? await create_account_if_not_existing(pubkey: keypair.pubkey)

            do {
                let receiptData = try Data(contentsOf: appStoreReceiptURL, options: .alwaysMapped)
                let url = environment.get_base_url().appendingPathComponent("accounts/\(keypair.pubkey.hex())/app-store-receipt")
                
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
        var url = environment.get_base_url()
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
        var url = environment.get_base_url()
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
    enum ServerEnvironment {
        case local_test
        case production
        
        func get_base_url() -> URL {
            switch self {
                case .local_test:
                    Constants.PURPLE_API_TEST_BASE_URL
                case .production:
                    Constants.PURPLE_API_PRODUCTION_BASE_URL
            }
        }
    }
    
    enum PurpleError: Error {
        case translation_error(status_code: Int, response: Data)
        case translation_no_response
        case checkout_npub_verification_error
    }
    
    struct TranslationResult: Codable {
        let text: String
    }
}
