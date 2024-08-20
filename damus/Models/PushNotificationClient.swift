//
//  PushNotificationClient.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-05-17.
//

import Foundation

struct PushNotificationClient {
    let keypair: Keypair
    let settings: UserSettingsStore
    private(set) var device_token: Data? = nil
    var device_token_hex: String? {
        guard let device_token else { return nil }
        return device_token.map { String(format: "%02.2hhx", $0) }.joined()
    }
    
    mutating func set_device_token(new_device_token: Data) async throws {
        self.device_token = new_device_token
        if settings.enable_experimental_push_notifications && settings.notifications_mode == .push {
            try await self.send_token()
        }
    }
    
    func send_token() async throws {
        // Send the device token and pubkey to the server
        guard let token = device_token_hex else { return }
        
        Log.info("Sending device token to server: %s", for: .push_notifications, token)

        // create post request
        let url = self.current_push_notification_environment().api_base_url()
            .appendingPathComponent("user-info")
            .appendingPathComponent(self.keypair.pubkey.hex())
            .appendingPathComponent(token)
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .put,
            url: url,
            payload: nil,
            payload_type: .json,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    Log.info("Sent device token to Damus push notification server successfully", for: .push_notifications)
                default:
                    Log.error("Error in sending device_token to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        return
    }
    
    func revoke_token() async throws {
        guard let token = device_token_hex else { return }
        
        Log.info("Revoking device token from server: %s", for: .push_notifications, token)

        let pubkey = self.keypair.pubkey

        // create post request
        let url = self.current_push_notification_environment().api_base_url()
            .appendingPathComponent("user-info")
            .appendingPathComponent(pubkey.hex())
            .appendingPathComponent(token)
        
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .delete,
            url: url,
            payload: nil,
            payload_type: .json,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    Log.info("Sent device token removal request to Damus push notification server successfully", for: .push_notifications)
                default:
                    Log.error("Error in sending device_token removal to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        return
    }
    
    func set_settings(_ new_settings: NotificationSettings? = nil) async throws {
        // Send the device token and pubkey to the server
        guard let token = device_token_hex else { return }
        
        Log.info("Sending notification preferences to the server", for: .push_notifications)

        let url = self.current_push_notification_environment().api_base_url()
            .appendingPathComponent("user-info")
            .appendingPathComponent(self.keypair.pubkey.hex())
            .appendingPathComponent(token)
            .appendingPathComponent("preferences")

        let json_payload = try JSONEncoder().encode(new_settings ?? NotificationSettings.from(settings: settings))
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .put,
            url: url,
            payload: json_payload,
            payload_type: .json,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    Log.info("Sent notification settings to Damus push notification server successfully", for: .push_notifications)
                default:
                    Log.error("Error in sending notification settings to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        return
    }
    
    func get_settings() async throws -> NotificationSettings {
        // Send the device token and pubkey to the server
        guard let token = device_token_hex else {
            throw ClientError.no_device_token
        }

        let url = self.current_push_notification_environment().api_base_url()
            .appendingPathComponent("user-info")
            .appendingPathComponent(self.keypair.pubkey.hex())
            .appendingPathComponent(token)
            .appendingPathComponent("preferences")
        
        let (data, response) = try await make_nip98_authenticated_request(
            method: .get,
            url: url,
            payload: nil,
            payload_type: .json,
            auth_keypair: self.keypair
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 200:
                    guard let notification_settings = NotificationSettings.from(json_data: data) else { throw ClientError.json_decoding_error }
                    return notification_settings
                default:
                    Log.error("Error in getting notification settings to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.could_not_process_response
    }
    
    func current_push_notification_environment() -> Environment {
        return self.settings.send_device_token_to_localhost ? .local_test(host: nil) : .production
    }
}

// MARK: Helper structures

extension PushNotificationClient {
    enum ClientError: Error {
        case http_response_error(status_code: Int, response: Data)
        case could_not_process_response
        case no_device_token
        case json_decoding_error
    }
    
    struct NotificationSettings: Codable, Equatable {
        let zap_notifications_enabled: Bool
        let mention_notifications_enabled: Bool
        let repost_notifications_enabled: Bool
        let reaction_notifications_enabled: Bool
        let dm_notifications_enabled: Bool
        let only_notifications_from_following_enabled: Bool
        
        static func from(json_data: Data) -> Self? {
            guard let decoded = try? JSONDecoder().decode(Self.self, from: json_data) else { return nil }
            return decoded
        }
        
        static func from(settings: UserSettingsStore) -> Self {
            return NotificationSettings(
                zap_notifications_enabled: settings.zap_notification,
                mention_notifications_enabled: settings.mention_notification,
                repost_notifications_enabled: settings.repost_notification,
                reaction_notifications_enabled: settings.like_notification,
                dm_notifications_enabled: settings.dm_notification,
                only_notifications_from_following_enabled: settings.notification_only_from_following
            )
        }
        
    }
    
    enum Environment: CaseIterable, Codable, Identifiable, StringCodable, Equatable, Hashable {
        static var allCases: [Environment] = [.local_test(host: nil), .production]
        
        case local_test(host: String?)
        case production

        func text_description() -> String {
            switch self {
                case .local_test:
                    return NSLocalizedString("Test (local)", comment: "Label indicating a local test environment for Push notification functionality (Developer feature)")
                case .production:
                    return NSLocalizedString("Production", comment: "Label indicating the production environment for Push notification functionality")
            }
        }

        func api_base_url() -> URL {
            switch self {
                case .local_test(let host):
                    URL(string: "http://\(host ?? "localhost:8000")") ?? Constants.PUSH_NOTIFICATION_SERVER_TEST_BASE_URL
                case .production:
                    Constants.PUSH_NOTIFICATION_SERVER_PRODUCTION_BASE_URL
                    
            }
        }
        
        func custom_host() -> String? {
            switch self {
                case .local_test(let host):
                    return host
                default:
                    return nil
            }
        }

        init?(from string: String) {
            switch string {
                case "local_test":
                    self = .local_test(host: nil)
                case "production":
                    self = .production
                default:
                    let components = string.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    if components.count == 2 && components[0] == "local_test" {
                        self = .local_test(host: String(components[1]))
                    } else {
                        return nil
                    }
            }
        }

        func to_string() -> String {
            switch self {
                case .local_test(let host):
                    if let host {
                        return "local_test:\(host)"
                    }
                    return "local_test"
                case .production:
                    return "production"
            }
        }

        var id: String {
            switch self {
                case .local_test(let host):
                    if let host {
                        return "local_test:\(host)"
                    }
                    else {
                        return "local_test"
                    }
                case .production:
                    return "production"
            }
        }
    }
}
