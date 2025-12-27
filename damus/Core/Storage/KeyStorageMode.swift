//
//  KeyStorageMode.swift
//  damus
//
//  Key Storage Architecture:
//  ─────────────────────────
//  Users choose between two storage modes for their private keys:
//
//  1. iCloud Sync (default): Keys stored as plaintext hex with kSecAttrSynchronizable=true.
//     Syncs across Apple devices. Convenient but requires trusting Apple.
//
//  2. Local Only: Keys encrypted with Secure Enclave (ECIES), stored with
//     kSecAttrSynchronizable=false. Never leaves device. Lost if app uninstalled.
//
//  Migration: When switching modes, keys are decrypted/re-encrypted and moved.
//  The old key is only deleted AFTER successful save to the new mode.
//

import Foundation

/// Determines how private keys are stored on this device.
/// This is a global setting that applies to all accounts.
enum KeyStorageMode: String, CaseIterable, Identifiable {
    /// Private keys sync across the user's Apple devices via iCloud Keychain.
    /// More convenient but requires trusting Apple.
    case iCloudSync = "icloud_sync"

    /// Private keys are encrypted with a Secure Enclave key and stay on this device only.
    /// More secure but keys are lost if device is lost/wiped or app is uninstalled.
    case localOnly = "local_only"

    var id: String { rawValue }

    /// User-facing title for this storage mode
    var title: String {
        switch self {
        case .iCloudSync:
            return NSLocalizedString("Backed up to iCloud", comment: "Key storage mode: sync across devices via iCloud")
        case .localOnly:
            return NSLocalizedString("This device only", comment: "Key storage mode: device-only with Secure Enclave")
        }
    }

    /// User-facing description of this storage mode
    var description: String {
        switch self {
        case .iCloudSync:
            return NSLocalizedString("Your key syncs across your Apple devices. Lose your phone? Sign in on another Apple device.", comment: "Description for iCloud sync key storage mode")
        case .localOnly:
            return NSLocalizedString("Your key stays on this phone only. Lose it or delete the app? It's gone forever unless you backed it up yourself.", comment: "Description for local-only key storage mode")
        }
    }

    /// Short warning shown during account actions (delete/remove)
    var warningForDeletion: String {
        switch self {
        case .iCloudSync:
            return NSLocalizedString("Your key may still exist on other synced devices.", comment: "Warning when deleting account with iCloud sync enabled")
        case .localOnly:
            return NSLocalizedString("Your key will be permanently deleted. This cannot be undone.", comment: "Warning when deleting account with local-only storage")
        }
    }
}

/// Global settings for key storage that apply across all accounts.
/// These are stored in UserDefaults.standard (not pubkey-scoped).
enum KeyStorageSettings {
    private static let storageKey = "key_storage_mode"
    private static let migrationPromptShownKey = "key_storage_migration_prompt_shown"

    /// The current key storage mode. Defaults to iCloud sync for convenience.
    static var mode: KeyStorageMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
                  let mode = KeyStorageMode(rawValue: rawValue) else {
                return .iCloudSync // Default for new users
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// Whether the user has been shown the migration prompt after updating to the version with storage mode choice.
    static var migrationPromptShown: Bool {
        get { UserDefaults.standard.bool(forKey: migrationPromptShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: migrationPromptShownKey) }
    }

    /// Whether the user has explicitly chosen a storage mode (vs using the default).
    /// Used to determine if we should prompt them during account creation.
    static var hasExplicitChoice: Bool {
        UserDefaults.standard.string(forKey: storageKey) != nil
    }
}

import SwiftUI

/// A sheet that prompts existing users to choose their key storage mode when updating to a version with storage mode choice.
struct KeyStorageMigrationSheet: View {
    @State private var selectedMode: KeyStorageMode = .iCloudSync
    @State private var isMigrating: Bool = false
    @State private var migrationError: String? = nil
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Key Storage Options", comment: "Title for key storage migration sheet")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Choose how your private keys are stored on this device.", comment: "Subtitle for key storage migration sheet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    ForEach(KeyStorageMode.allCases) { mode in
                        StorageModeOptionView(mode: mode, isSelected: selectedMode == mode) {
                            selectedMode = mode
                        }
                    }
                }
                .padding(.horizontal)

                #if targetEnvironment(simulator)
                if selectedMode == .iCloudSync {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Simulator: iCloud sync may not work. Sign into iCloud in Settings to test, or use a real device.", comment: "Warning about iCloud sync in simulator")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }
                #endif

                if selectedMode == .localOnly {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Make sure to back up your keys separately!", comment: "Warning about local-only key storage")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }

                if let error = migrationError {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        isMigrating = true
                        migrationError = nil
                        let previousMode = KeyStorageSettings.mode
                        KeyStorageSettings.mode = selectedMode
                        // Migrate existing keys to the new mode
                        Task { @MainActor in
                            let result = AccountsStore.shared.migrateAllKeysToCurrentMode()
                            isMigrating = false
                            if result.failed > 0 {
                                // Rollback on failure
                                KeyStorageSettings.mode = previousMode
                                selectedMode = previousMode
                                migrationError = NSLocalizedString("Failed to migrate some keys. Please try again.", comment: "Error when key migration fails")
                                // Keep the sheet open so user can try again
                            } else {
                                onDismiss()
                            }
                        }
                    }) {
                        if isMigrating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .cornerRadius(12)
                        } else {
                            Text("Continue", comment: "Button to confirm storage mode choice")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(isMigrating)

                    Text("You can change this later in Settings > Keys.", comment: "Note about changing storage mode later")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A view representing a single storage mode option
private struct StorageModeOptionView: View {
    let mode: KeyStorageMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mode.title)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if mode == .iCloudSync {
                            Text("Recommended", comment: "Label for recommended storage mode")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }

                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
