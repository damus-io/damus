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
    
    mutating func set_device_token(new_device_token: Data) async throws {
        self.device_token = new_device_token
        if settings.enable_experimental_push_notifications && settings.notifications_mode == .push {
            try await self.send_token()
        }
    }
    
    func send_token() async throws {
        guard let device_token else { return }
        // Send the device token and pubkey to the server
        let token = device_token.map { String(format: "%02.2hhx", $0) }.joined()
        
        Log.info("Sending device token to server: %s", for: .push_notifications, token)

        let pubkey = self.keypair.pubkey

        // Send those as JSON to the server
        let json: [String: Any] = ["deviceToken": token, "pubkey": pubkey.hex()]

        // create post request
        let url = self.settings.send_device_token_to_localhost ? Constants.DEVICE_TOKEN_RECEIVER_TEST_URL : Constants.DEVICE_TOKEN_RECEIVER_PRODUCTION_URL
        let json_data = try JSONSerialization.data(withJSONObject: json)
        
        
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
                    Log.info("Sent device token to Damus push notification server successfully", for: .push_notifications)
                default:
                    Log.error("Error in sending device_token to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        return
    }
    
    func revoke_token() async throws {
        guard let device_token else { return }
        // Send the device token and pubkey to the server
        let token = device_token.map { String(format: "%02.2hhx", $0) }.joined()
        
        Log.info("Revoking device token from server: %s", for: .push_notifications, token)

        let pubkey = self.keypair.pubkey

        // Send those as JSON to the server
        let json: [String: Any] = ["deviceToken": token, "pubkey": pubkey.hex()]

        // create post request
        let url = self.settings.send_device_token_to_localhost ? Constants.DEVICE_TOKEN_REVOKER_TEST_URL : Constants.DEVICE_TOKEN_REVOKER_PRODUCTION_URL
        let json_data = try JSONSerialization.data(withJSONObject: json)
        
        
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
                    Log.info("Sent device token removal request to Damus push notification server successfully", for: .push_notifications)
                default:
                    Log.error("Error in sending device_token removal to Damus push notification server. HTTP status code: %d; Response: %s", for: .push_notifications, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                    throw ClientError.http_response_error(status_code: httpResponse.statusCode, response: data)
            }
        }
        
        return
    }
}

// MARK: Helper structures

extension PushNotificationClient {
    enum ClientError: Error {
        case http_response_error(status_code: Int, response: Data)
    }
}
