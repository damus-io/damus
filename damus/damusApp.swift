//
//  damusApp.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import Kingfisher
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
            SuggestedHashtagsView.lastRefresh_hashtags.removeAll()
            // We need to disconnect and reconnect to all relays when the user signs out
            // This is to conform to NIP-42 and ensure we aren't persisting old connections
            notify(.disconnect_relays)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientationTracker.setDeviceMajorAxis()
        }
        .onAppear {
            orientationTracker.setDeviceMajorAxis()
            keypair = get_saved_keypair()
        }
    }
}

func registerNotificationCategories() {
    // Define the communication category
    let communicationCategory = UNNotificationCategory(
        identifier: "COMMUNICATION",
        actions: [],
        intentIdentifiers: ["INSendMessageIntent"],
        options: []
    )

    // Register the category with the notification center
    UNUserNotificationCenter.current().setNotificationCategories([communicationCategory])
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var state: DamusState? = nil
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
        // Only configure network simulator in main app (not extensions)
        if !Bundle.main.bundlePath.contains(".appex") {
            NetworkConditionSimulator.configureFromLaunchArguments()
        }
        #endif

        UNUserNotificationCenter.current().delegate = self
        SKPaymentQueue.default().add(StoreObserver.standard)
        registerNotificationCategories()
        ImageCacheMigrations.migrateKingfisherCacheIfNeeded()
        configureKingfisherCache()

        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let state else {
            return
        }
        
        Task {
            try await state.push_notification_client.set_device_token(new_device_token: deviceToken)
        }
    }

    // Handle the notification in the foreground state
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Display the notification in the foreground
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Log.info("App delegate is handling a push notification", for: .push_notifications)
        let userInfo = response.notification.request.content.userInfo
        guard let notification = LossyLocalNotification.from_user_info(user_info: userInfo) else {
            Log.error("App delegate could not decode notification information", for: .push_notifications)
            return
        }
        Log.info("App delegate notifying the app about the received push notification", for: .push_notifications)
        Task { await QueueableNotify<LossyLocalNotification>.shared.add(item: notification) }
        completionHandler()
    }

    private func configureKingfisherCache() {
        let cachePath = ImageCacheMigrations.kingfisherCachePath()
        if let cache = try? ImageCache(name: "sharedCache", cacheDirectoryURL: cachePath) {
            KingfisherManager.shared.cache = cache
        }
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
