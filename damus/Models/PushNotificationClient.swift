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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // insert json data to the request
        request.httpBody = try? JSONSerialization.data(withJSONObject: json, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }

            if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                print("Unexpected status code: \(response.statusCode)")
                return
            }

            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: Any] {
                print(responseJSON)
            }
        }

        task.resume()
    }
}
