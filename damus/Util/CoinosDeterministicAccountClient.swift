//
//  CoinosDeterministicClient.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-14.
//

import Foundation

/// Implements a client that can talk to the Coinos API server with a deterministic account derived from the user's private key.
///
/// This is NOT a general-purpose Coinos client, and only works with the user's own deterministic "one-click setup" Coinos wallet account.
class CoinosDeterministicAccountClient {
    // MARK: - State
    
    /// The user's normal keypair for using Nostr
    private let userKeypair: FullKeypair
    /// The JWT authentication token with Coinos
    private var jwtAuthToken: String? = nil
    
    
    // MARK: - Computed properties for a deterministic wallet
    
    /// A deterministic keypair for the NWC connection derived from the user's private key
    private var nwcKeypair: FullKeypair? {
        let nwcPrivateKey: Privkey = Privkey(sha256(self.userKeypair.privkey.id))   // SHA256 is an irreversible operation, user's nsec should not be deriveable from this new private key
        return FullKeypair(privkey: nwcPrivateKey)
    }
    
    /// A deterministic username for a Coinos account
    private var username: String? {
        // Derive from private key because deriving from a pubkey would mean that anyone could compute the username and take that username before our user
        // Add some prefix so that we can ensure this will NOT match the password nor the NWC keypair
        guard let fullText = sha256Hex(text: "coinos_username:" + self.userKeypair.privkey.hex()) else { return nil }
        // There is very little risk of a birthday attack on getting only the first 16 characters, because:
        // 1. before this user creates an account, no one else knows the private key in order to know the expected username and create an account before them
        // 2. after the account is created and username is revealed, finding collisions is pointless as duplicate usernames will be rejected by Coinos
        //
        // In terms of the risk of an accidental collision due to the birthday problem, 16 characters should be enough to pragmatically avoid any collision.
        // According to `https://en.wikipedia.org/wiki/Birthday_problem#Probability_table`,
        // even if we have 610 million Damus users connected to Coinos, the probability of even a single collision is still as low as 1%.
        return String(fullText.prefix(16))
    }
    
    /// A deterministic password for a Coinos account
    private var password: String? {
        // Add some prefix so that we can ensure this will NOT match the user nor the NWC private key
        return sha256Hex(text: "coinos_password:" + self.userKeypair.privkey.hex())
    }
    
    /// A deterministic NWC app connection name
    private var nwcConnectionName: String { return "Damus" }
    
    
    // MARK: - Initialization
    
    /// Initializes the client with the user's keypair
    init(userKeypair: FullKeypair) {
        self.userKeypair = userKeypair
    }
    
    
    // MARK: - Authentication and registration
    
    /// Tries to login to the user's deterministic account. If it cannot be found, it will register for one and log into that.
    func loginOrRegister() async throws {
        do {
            // Check if client has an account
            try await self.login()
        }
        catch {
            guard let error = error as? CoinosDeterministicAccountClient.ClientError, error == .unauthorized else { throw error }
            // Client does not seem to have an account, create one
            try await self.register()
            try await self.login()
        }
    }
    
    /// Registers for a Coinos account using deterministic account details.
    ///
    /// It succeeds if it returns without throwing errors.
    func register() async throws {
        guard let username, let password else { throw ClientError.errorFormingRequest }
        let registerPayload = RegisterRequest(user: UserCredentials(username: username, password: password))
        let jsonData = try JSONEncoder().encode(registerPayload)
        
        let url = URL(string: "https://coinos.io/api/register")!
        let (data, response) = try await makeRequest(method: .post, url: url, payload: jsonData, payload_type: .json)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return
        } else {
            throw ClientError.unexpectedHTTPResponse(status_code: (response as? HTTPURLResponse)?.statusCode ?? -1, response: data)
        }
    }
    
    /// Logs into the deterministic account, if an auth token is not present
    func loginIfNeeded() async throws {
        if self.jwtAuthToken == nil { try await self.login() }
    }
    
    /// Logs into to our deterministic account.
    ///
    /// Succeeds if it returns without returning errors.
    ///
    /// Mutating function, will update the client's internal state.
    func login() async throws {
        self.jwtAuthToken = try await sendLoginRequest().token
    }
    
    /// Sends the login request and return the response
    ///
    /// Does NOT update the internal login state.
    private func sendLoginRequest() async throws -> AuthResponse {
        guard let url = URL(string: "https://coinos.io/api/login") else { throw ClientError.errorFormingRequest }
        guard let username, let password else { throw ClientError.errorFormingRequest }
        let credentials = UserCredentials(username: username, password: password)
        let jsonData = try JSONEncoder().encode(credentials)
        
        let (data, response) = try await makeRequest(method: .post, url: url, payload: jsonData, payload_type: .json)
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: return try JSONDecoder().decode(AuthResponse.self, from: data)
            case 401: throw ClientError.unauthorized
            default: throw ClientError.unexpectedHTTPResponse(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }
    
    
    // MARK: - Managing NWC connections
    
    /// Creates a new NWC connection
    ///
    /// Note: Account must exist before calling this endpoint
    func createNWCConnection() async throws -> WalletConnectURL {
        guard let nwcKeypair else { throw ClientError.errorFormingRequest }
        guard let urlEndpoint = URL(string: "https://coinos.io/api/app") else { throw ClientError.errorFormingRequest }
        
        try await self.loginIfNeeded()
        
        let config = try defaultWalletConnectionConfig()
        let configData = try encode_json_data(config)
        
        let (data, response) = try await self.makeAuthenticatedRequest(
            method: .post,
            url: urlEndpoint,
            payload: configData,
            payload_type: .json
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                guard let nwc = try await self.getNWCUrl() else { throw ClientError.errorProcessingResponse }
                return nwc
            case 401: throw ClientError.unauthorized
            default: throw ClientError.unexpectedHTTPResponse(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }
    
    /// Returns the default wallet connection config
    private func defaultWalletConnectionConfig() throws -> NewWalletConnectionConfig {
        guard let nwcKeypair else { throw ClientError.errorFormingRequest }
        return NewWalletConnectionConfig(
            name: self.nwcConnectionName,
            secret: nwcKeypair.privkey.hex(),
            pubkey: nwcKeypair.pubkey.hex(),
            max_amount: 30000,  // 30K sats per week maximum
            budget_renewal: .weekly
        )
    }
    
    /// Gets the NWC URL for the deterministic NWC app connection
    ///
    /// Account must already exist before calling this
    ///
    /// Returns `nil` if no NWC url is found, (e.g. if app connection has not been configured yet)
    func getNWCUrl() async throws -> WalletConnectURL? {
        guard let connectionConfig = try await self.getNWCAppConnectionConfig(), let nwc = connectionConfig.nwc else { return nil }
        return WalletConnectURL(str: nwc)
    }
    
    /// Gets the deterministic NWC app connection configuration details, if it exists
    ///
    /// Account must already exist before calling this
    ///
    /// Returns `nil` if no connection is found, (e.g. if app connection has not been configured yet)
    func getNWCAppConnectionConfig() async throws -> WalletConnectionConfig? {
        guard let nwcKeypair else { throw ClientError.errorFormingRequest }
        guard let url = URL(string: "https://coinos.io/api/app/" + nwcKeypair.pubkey.hex()) else { throw ClientError.errorFormingRequest }
        
        try await self.loginIfNeeded()
        
        let (data, response) = try await self.makeAuthenticatedRequest(
            method: .get,
            url: url,
            payload: nil,
            payload_type: nil
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: return try JSONDecoder().decode(WalletConnectionConfig.self, from: data)
            case 401: throw ClientError.unauthorized
            case 404: return nil
            default: throw ClientError.unexpectedHTTPResponse(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }
    
    
    // MARK: - Lower level request convenience functions
    
    /// Makes a request without any authorization
    func makeRequest(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?) async throws -> (data: Data, response: URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = payload

        if let payload_type {
            request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
        }
        return try await URLSession.shared.data(for: request)
    }
    
    /// Makes an authenticated request with our JWT auth token.
    ///
    /// Client must be logged-in before calling this, otherwise an error will be thrown.
    func makeAuthenticatedRequest(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?) async throws -> (data: Data, response: URLResponse) {
        guard let jwtAuthToken else { throw ClientError.errorFormingRequest }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = payload

        request.setValue("Bearer " + jwtAuthToken, forHTTPHeaderField: "Authorization")
        if let payload_type {
            request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
        }
        return try await URLSession.shared.data(for: request)
    }
    
    
    // MARK: - Helper structures
    
    /// Payload for registering for a new Coinos account
    struct RegisterRequest: Codable {
        /// New user credentials
        let user: UserCredentials
    }
    
    /// Payload for user credentials (sign-up and login)
    struct UserCredentials: Codable {
        /// The username
        let username: String
        /// The user password
        let password: String
    }
    
    /// A successful response to a login auth endpoint
    struct AuthResponse: Codable {
        /// The JWT token to be applied to any authenticated API calls
        let token: String
    }
    
    /// Used by the client to define new NWC configurations
    struct NewWalletConnectionConfig: Codable {
        /// The name of the connection
        let name: String
        /// 32 Hex-encoded bytes containing a shared private key secret
        let secret: String
        /// 32 Hex-encoded bytes containing the pubkey for the secret
        let pubkey: String
        /// Max amount that can be spent in each renewal period (measured in sats)
        let max_amount: UInt64
        /// The period of time it takes for the budget limits to reset
        let budget_renewal: BudgetRenewalPeriod
    }
    
    /// The NWC connection configuration details
    ///
    /// ## Implementation notes
    ///
    /// - All items defined as optionals because the Coinos API may change in the future, so this may help increase future compatibility.
    struct WalletConnectionConfig: Codable {
        /// The name of the connection
        let name: String?
        /// 32 Hex-encoded bytes containing a shared private key secret
        let secret: String?
        /// 32 Hex-encoded bytes containing the pubkey for the secret
        let pubkey: String?
        /// Max amount that can be spent in every renewal period (measured in sats)
        let max_amount: UInt64?
        /// The NWC url generated by the server
        let nwc: String?
        /// Budget renewal information
        let budget_renewal: BudgetRenewalPeriod?
    }
    
    /// A period of time it takes for budget limits to be reset
    enum BudgetRenewalPeriod: String, Codable {
        /// Resets once a week
        case weekly
    }
    
    /// A client error occured
    enum ClientError: Error, Equatable {
        /// Received an unexpected HTTP response
        ///
        /// Could be for a variety of reasons.
        case unexpectedHTTPResponse(status_code: Int, response: Data)
        /// Error forming the request, generally due to missing or inconsistent internal data
        ///
        /// Probably caused by a programming error.
        case errorFormingRequest
        /// The client could not process the response from the server
        ///
        /// Might be a sign of an incompatibility bug
        case errorProcessingResponse
        /// The action performed is not authorized
        /// Generally thrown if user does not exist, credentials do not match what Coinos has on file, or programming error
        case unauthorized
        /// Client not logged in on a call that expected login
        case notLoggedIn
    }
}

/// Computes a SHA256 hash digest from a piece of UTF-8 text, and returns the result as a "hex" string
///
/// When working only with strings, this can be more convenient than transforming text to data, and data back to text
fileprivate func sha256Hex(text: String) -> String? {
    guard let data = text.data(using: .utf8) else { return nil }
    return sha256(data).toHexString()
}
