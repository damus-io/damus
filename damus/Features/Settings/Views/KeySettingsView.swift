//
//  KeySettingsView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI
import LocalAuthentication

struct KeySettingsView: View {
    let keypair: Keypair

    @State var privkey: String
    @State var privkey_copied: Bool = false
    @State var pubkey_copied: Bool = false
    @State var show_privkey: Bool = false
    @State var has_authenticated_locally: Bool = false
    @State private var keyStorageMode: KeyStorageMode = KeyStorageSettings.mode
    @State private var showStorageModeChangeAlert: Bool = false
    @State private var pendingStorageMode: KeyStorageMode? = nil
    @State private var showMigrationResultAlert: Bool = false
    @State private var migrationResult: (success: Int, failed: Int)? = nil

    @Environment(\.dismiss) var dismiss

    init(keypair: Keypair) {
        _privkey = State(initialValue: keypair.privkey?.nsec ?? "")
        self.keypair = keypair
    }
    
    var ShowSecToggle: some View {
        Toggle(NSLocalizedString("Show", comment: "Toggle to show or hide user's secret account login key."), isOn: $show_privkey)
            .onChange(of: show_privkey) { newValue in
                if newValue {
                    authenticate_locally(has_authenticated_locally) { success in
                        self.has_authenticated_locally = success
                        self.show_privkey = success
                    }
                }
            }
    }
    
    // TODO: (jb55) could be more general but not gonna worry about it atm
    func CopyButton(is_pk: Bool) -> some View {
        return Button(action: {
            let copyKey = {
                UIPasteboard.general.string = is_pk ? self.keypair.pubkey.npub : self.privkey
                self.privkey_copied = !is_pk
                self.pubkey_copied = is_pk
    
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            
            if is_pk {
                copyKey()
                return
            }
            
            if has_authenticated_locally {
                copyKey()
                return
            }
            
            authenticate_locally(has_authenticated_locally) { success in
                self.has_authenticated_locally = success
                if success {
                    copyKey()
                }
            }
        }) {
            let copied = is_pk ? self.pubkey_copied : self.privkey_copied
            Image(copied ? "check-circle" : "copy2")
        }
    }
    
    var body: some View {
        Form {
            Section(NSLocalizedString("Public Account ID", comment: "Section title for the user's public account ID.")) {
                HStack {
                    Text(keypair.pubkey.npub)

                    CopyButton(is_pk: true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            if let sec = keypair.privkey?.nsec {
                Section {
                    HStack {
                        if show_privkey == false || !has_authenticated_locally {
                            SecureField(NSLocalizedString("Private Key", comment: "Title of the secure field that holds the user's private key."), text: $privkey)
                                .disabled(true)
                        } else {
                            Text(sec)
                                .privacySensitive()
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }

                        CopyButton(is_pk: false)
                    }

                    ShowSecToggle
                } header: {
                    Text(NSLocalizedString("Secret Account Login Key", comment: "Section title for user's secret account login key."))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.footnote)
                            Text(NSLocalizedString("Your secret key is like a master password. Anyone who has it can control your account. Never share it or paste it into websites.", comment: "Warning about secret key security"))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Key Storage Mode section
            Section {
                Picker(selection: $keyStorageMode) {
                    ForEach(KeyStorageMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                            #if targetEnvironment(simulator)
                            .disabled(mode == .localOnly)
                            #endif
                    }
                } label: {
                    Text(NSLocalizedString("Key Storage", comment: "Label for key storage mode picker"))
                }
                .onChange(of: keyStorageMode) { newMode in
                    if newMode != KeyStorageSettings.mode {
                        pendingStorageMode = newMode
                        showStorageModeChangeAlert = true
                        // Reset picker until confirmed
                        keyStorageMode = KeyStorageSettings.mode
                    }
                }

                // Show current mode description
                Text(KeyStorageSettings.mode.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text(NSLocalizedString("Key Storage", comment: "Section header for key storage settings"))
            } footer: {
                if KeyStorageSettings.mode == .localOnly && !SecureEnclaveStorage.isAvailable {
                    Text(NSLocalizedString("Secure Enclave is not available on this device. Keys will be stored locally without hardware encryption.", comment: "Warning when Secure Enclave is not available"))
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Keys", comment: "Navigation title for managing keys."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .alert(
            NSLocalizedString("Change Key Storage Mode?", comment: "Alert title for changing key storage mode"),
            isPresented: $showStorageModeChangeAlert,
            presenting: pendingStorageMode
        ) { newMode in
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                pendingStorageMode = nil
            }
            Button(newMode == .localOnly
                   ? NSLocalizedString("Switch to Local Only", comment: "Confirm switching to local-only key storage")
                   : NSLocalizedString("Switch to iCloud Sync", comment: "Confirm switching to iCloud sync key storage")
            ) {
                let previousMode = KeyStorageSettings.mode
                KeyStorageSettings.mode = newMode
                // Migrate all existing keys to new mode
                let result = AccountsStore.shared.migrateAllKeysToCurrentMode()
                migrationResult = result

                if result.failed > 0 {
                    // Rollback on failure
                    KeyStorageSettings.mode = previousMode
                    keyStorageMode = previousMode
                } else {
                    keyStorageMode = newMode
                }
                pendingStorageMode = nil
                showMigrationResultAlert = true
            }
        } message: { newMode in
            Text(newMode.description)
        }
        .alert(
            migrationResult?.failed ?? 0 > 0
                ? NSLocalizedString("Migration Failed", comment: "Alert title when key migration fails")
                : NSLocalizedString("Migration Complete", comment: "Alert title when key migration succeeds"),
            isPresented: $showMigrationResultAlert
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) {
                showMigrationResultAlert = false
                migrationResult = nil
            }
        } message: {
            if let result = migrationResult {
                if result.failed > 0 {
                    Text("Failed to migrate \(result.failed) key(s). Your keys remain in the previous storage mode. Please try again or contact support.", comment: "Alert message when key migration fails")
                } else if result.success > 0 {
                    Text("Successfully migrated \(result.success) key(s) to the new storage mode.", comment: "Alert message when key migration succeeds")
                } else {
                    Text("No keys needed migration.", comment: "Alert message when no keys needed migration")
                }
            }
        }
    }
}

struct KeySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let kp = generate_new_keypair()
        KeySettingsView(keypair: kp.to_keypair())
    }
}

func authenticate_locally(_ has_authenticated_locally: Bool, completion: @escaping (Bool) -> Void) {
    // Need to authenticate only once while ConfigView is presented
    guard !has_authenticated_locally else {
        completion(true)
        return
    }
    let context = LAContext()
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: NSLocalizedString("Local authentication to access private key", comment: "Face ID usage description shown when trying to access private key")) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    } else {
        // If there's no authentication set up on the device, let the user copy the key without it
        completion(true)
    }
}
