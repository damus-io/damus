//
//  damusApp.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import StoreKit

@main
struct damusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            MainView(appDelegate: appDelegate)
        }
    }
}

struct MainView: View {
    @State var needs_setup = false;
    @State var keypair: Keypair? = nil;
    @StateObject private var orientationTracker = OrientationTracker()
    var appDelegate: AppDelegate
    
    var body: some View {
        Group {
            if let kp = keypair, !needs_setup {
                ContentView(keypair: kp, appDelegate: appDelegate)
                    .environmentObject(orientationTracker)
            } else {
                SetupView()
                    .onReceive(handle_notify(.login)) { notif in
                        needs_setup = false
                        keypair = get_saved_keypair()
                        if keypair == nil, let tempkeypair = notif.to_full()?.to_keypair() {
                            keypair = tempkeypair
                        }
                    }
            }
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .onReceive(handle_notify(.logout)) { () in
            try? clear_keypair()
            keypair = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientationTracker.setDeviceMajorAxis()
        }
        .onAppear {
            orientationTracker.setDeviceMajorAxis()
            keypair = get_saved_keypair()
            appDelegate.keypair = keypair
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var keypair: Keypair? = nil
    var settings: UserSettingsStore? = nil
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        SKPaymentQueue.default().add(StoreObserver.standard)
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Return if this feature is disabled
        guard let settings = self.settings else { return }
        if !settings.enable_experimental_push_notifications {
            return
        }
        
        // Send the device token and pubkey to the server
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        print("Received device token: \(token)")

        guard let pubkey = keypair?.pubkey else {
            return
        }

        // Send those as JSON to the server
        let json: [String: Any] = ["deviceToken": token, "pubkey": pubkey.hex()]

        // create post request
        let url = settings.send_device_token_to_localhost ? Constants.DEVICE_TOKEN_RECEIVER_TEST_URL : Constants.DEVICE_TOKEN_RECEIVER_PRODUCTION_URL
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

    // Handle the notification in the foreground state
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Display the notification in the foreground
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let notification = LossyLocalNotification.from_user_info(user_info: userInfo) else {
            return
        }
        notify(.local_notification(notification))
        completionHandler()
    }
}

class OrientationTracker: ObservableObject {
    var deviceMajorAxis: CGFloat = 0
    func setDeviceMajorAxis() {
        let bounds = UIScreen.main.bounds
        let height = max(bounds.height, bounds.width) /// device's longest dimension
        let width = min(bounds.height, bounds.width)  /// device's shortest dimension
        let orientation = UIDevice.current.orientation
        deviceMajorAxis = (orientation == .portrait || orientation == .unknown) ? height : width
    }
}
