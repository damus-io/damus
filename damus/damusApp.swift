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
    @ObservedObject private var accountsStore = AccountsStore.shared
    @ObservedObject private var onboardingSession = OnboardingSession.shared
    @State private var showSavePrompt = false
    @State private var savePromptDismissed = false
    @State private var savePromptScheduledFor: Pubkey?
    @State private var isSwitchingAccount = false
    @State private var isHandlingLoginSwitch = false
    @State private var showStorageMigrationPrompt = false
    var appDelegate: AppDelegate

    @ViewBuilder
    var mainContent: some View {
        if isSwitchingAccount {
            AccountSwitchingView()
        } else if let kp = keypair, !needs_setup {
            ContentView(keypair: kp, appDelegate: appDelegate)
                .environmentObject(orientationTracker)
                .id(kp.pubkey) // Force recreation when keypair changes
        } else {
            SetupView()
        }
    }

    var body: some View {
        mainContent
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .onReceive(handle_notify(.login)) { notif in
            onboardingSession.end()
            isHandlingLoginSwitch = true
            // Clear transient session flag now that login handler is taking over
            accountsStore.clearTransientSessionFlag()
            // If already logged in, close current state first
            if keypair != nil {
                isSwitchingAccount = true
                Task { @MainActor in
                    if let state = appDelegate.state {
                        await state.closeAsync()
                        appDelegate.state = nil
                    }
                    keypair = notif
                    needs_setup = false
                    isSwitchingAccount = false
                    isHandlingLoginSwitch = false
                    // Delay save prompt to let timeline load first
                    scheduleShowSavePromptIfNeeded()
                }
            } else {
                keypair = notif
                needs_setup = false
                isHandlingLoginSwitch = false
                // Delay save prompt to let timeline load first
                scheduleShowSavePromptIfNeeded()
            }
        }
        .onReceive(handle_notify(.logout)) { () in
            closeCurrentState()
            accountsStore.clearTransientSessionFlag()  // Clear in case of abandoned login
            accountsStore.clearActiveSelection()
            keypair = nil
            showSavePrompt = false
            savePromptDismissed = false  // Reset for next login
            savePromptScheduledFor = nil  // Cancel any pending prompt
            SuggestedHashtagsView.lastRefresh_hashtags.removeAll()
            notify(.disconnect_relays)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientationTracker.setDeviceMajorAxis()
        }
        .onAppear {
            orientationTracker.setDeviceMajorAxis()
            keypair = accountsStore.activeKeypair
            needs_setup = keypair == nil
            // Don't show prompt immediately on appear - schedule it if needed
            scheduleShowSavePromptIfNeeded()
            // Check if we need to show the storage mode migration prompt
            checkAndShowStorageMigrationPrompt()
        }
        .onChange(of: accountsStore.activePubkey) { newPubkey in
            // Prevent double-close when login handler is already switching
            guard !isHandlingLoginSwitch else { return }
            // Prevent double-close when transient login is in progress
            guard !accountsStore.isSettingTransientSession else { return }
            handleAccountSwitch(to: newPubkey)
        }
        .sheet(isPresented: $showSavePrompt) {
            if let kp = keypair {
                SaveAccountSheet(keypair: kp) {
                    saveActive(keypair: kp)
                } onDismiss: {
                    showSavePrompt = false
                    savePromptDismissed = true
                }
            }
        }
        .sheet(isPresented: $showStorageMigrationPrompt) {
            KeyStorageMigrationSheet {
                showStorageMigrationPrompt = false
                KeyStorageSettings.migrationPromptShown = true
            }
        }
    }

    /// Checks if we need to show the storage mode migration prompt for existing accounts
    private func checkAndShowStorageMigrationPrompt() {
        // Only show if not already shown
        guard !KeyStorageSettings.migrationPromptShown else { return }
        // Only show if user has existing accounts with private keys
        guard accountsStore.hasAccountsWithPrivateKeys else { return }
        // Show the prompt after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            guard !KeyStorageSettings.migrationPromptShown else { return }
            showStorageMigrationPrompt = true
        }
    }

    private func handleAccountSwitch(to newPubkey: Pubkey?) {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("DIAG[\(startTime)] handleAccountSwitch: START to \(newPubkey?.npub.prefix(12) ?? "nil")")

        // Skip if the pubkey matches current (no change needed)
        guard newPubkey != keypair?.pubkey else {
            print("DIAG[\(startTime)] handleAccountSwitch: SKIP (same pubkey)")
            return
        }

        // End onboarding if we're switching accounts mid-flow
        if onboardingSession.isOnboarding {
            onboardingSession.end()
        }

        // Increment generation so old subscription tasks know to exit
        appDelegate.ndbGeneration &+= 1
        print("DIAG[\(startTime)] handleAccountSwitch: incremented ndbGeneration to \(appDelegate.ndbGeneration)")

        // Reset prompt state for new account
        showSavePrompt = false
        savePromptDismissed = false
        savePromptScheduledFor = nil  // Cancel any pending prompt from previous account

        // Show switching indicator
        isSwitchingAccount = true
        print("DIAG[\(startTime)] handleAccountSwitch: showing switching indicator")

        Task { @MainActor in
            // Await proper shutdown of the current state
            if let state = appDelegate.state {
                print("DIAG[\(startTime)] handleAccountSwitch: closing old state...")
                await state.closeAsync()
                appDelegate.state = nil
                print("DIAG[\(startTime)] handleAccountSwitch: old state closed")
            } else {
                print("DIAG[\(startTime)] handleAccountSwitch: no old state to close")
            }

            // Re-check that activePubkey hasn't changed during close (rapid switching protection)
            guard accountsStore.activePubkey == newPubkey else {
                print("DIAG[\(startTime)] handleAccountSwitch: activePubkey changed during close, aborting")
                if accountsStore.activePubkey == nil {
                    keypair = nil
                    needs_setup = true
                    isSwitchingAccount = false
                }
                return
            }

            guard let newPubkey else {
                // Logged out or cleared - go to setup
                print("DIAG[\(startTime)] handleAccountSwitch: no newPubkey, going to setup")
                keypair = nil
                needs_setup = true
                isSwitchingAccount = false
                return
            }

            print("DIAG[\(startTime)] handleAccountSwitch: setting keypair for \(newPubkey.npub.prefix(12))...")
            // Use activeKeypair to support both saved and transient logins
            keypair = accountsStore.activeKeypair
            needs_setup = keypair == nil
            isSwitchingAccount = false
            // Delay save prompt to let timeline load first
            scheduleShowSavePromptIfNeeded()
            print("DIAG[\(startTime)] handleAccountSwitch: DONE (keypair set: \(keypair != nil), needs_setup: \(needs_setup))")
        }
    }

    private func needsSaving(keypair: Keypair?) -> Bool {
        guard let kp = keypair else { return false }
        guard kp.privkey != nil else { return false }
        return AccountsStore.shared.keypair(for: kp.pubkey)?.privkey == nil
    }

    /// Schedules showing the save prompt after a delay to let the timeline load first.
    /// Respects user dismissal - won't show again if they already dismissed.
    /// Tracks which account scheduled the prompt to prevent showing for wrong account.
    private func scheduleShowSavePromptIfNeeded() {
        // Don't show if user already dismissed or prompt is already showing
        guard !savePromptDismissed && !showSavePrompt else { return }
        guard needsSaving(keypair: keypair) else { return }
        guard let pubkey = keypair?.pubkey else { return }

        // Track which account scheduled this prompt
        savePromptScheduledFor = pubkey

        // Delay 3 seconds to let timeline load
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // Verify this is still the account that scheduled the prompt
            guard savePromptScheduledFor == pubkey else { return }
            // Re-check conditions after delay (user may have saved or logged out)
            guard !savePromptDismissed && !showSavePrompt else { return }
            guard needsSaving(keypair: keypair) else { return }
            showSavePrompt = true
        }
    }

    private func saveActive(keypair: Keypair) {
        AccountsStore.shared.addOrUpdate(keypair, savePriv: true)
        AccountsStore.shared.setActive(keypair.pubkey)
        showSavePrompt = false
    }

    /// Closes the current DamusState asynchronously (fire-and-forget for logout)
    private func closeCurrentState() {
        Task { @MainActor in
            if let state = appDelegate.state {
                await state.closeAsync()
                appDelegate.state = nil
            }
        }
    }
}

/// A brief loading view shown while switching between accounts
struct AccountSwitchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(NSLocalizedString("Switching account...", comment: "Loading text shown when switching between accounts"))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

func registerNotificationCategories() {
    let communicationCategory = UNNotificationCategory(
        identifier: "COMMUNICATION",
        actions: [],
        intentIdentifiers: ["INSendMessageIntent"],
        options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([communicationCategory])
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var state: DamusState? = nil

    /// Shared Ndb instance that persists across account switches to avoid LMDB lock issues.
    ///
    /// ## Privacy Note
    /// All accounts share the same underlying nostrdb database. This is an existing
    /// architectural constraint. DM **content** is encrypted and can only be read by
    /// the account with the matching private key. However, DM **metadata** (who talked
    /// to whom, timestamps) is visible across all accounts using this device.
    ///
    /// True per-account data isolation would require Ndb to support separate database
    /// directories per account, which is a larger architectural change.
    var sharedNdb: Ndb? = nil

    /// Generation counter for Ndb/subscription tasks. Incremented on each account switch.
    /// Tasks compare their captured generation to this value to detect staleness and exit
    /// even if cooperative cancellation is swallowed.
    ///
    /// Thread-safety note: This is written on main thread (account switch) and read from
    /// background tasks. The potential race is benign - worst case a background task runs
    /// one extra loop iteration before seeing the new value. UInt64 reads/writes are atomic
    /// on 64-bit platforms.
    var ndbGeneration: UInt64 = 0

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
