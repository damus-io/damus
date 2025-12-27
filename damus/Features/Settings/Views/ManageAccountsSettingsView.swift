//
//  ManageAccountsSettingsView.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import SwiftUI
import Kingfisher

struct ManageAccountsSettingsView: View {
    let state: DamusState
    @ObservedObject var accountsStore: AccountsStore
    /// Whether to show the Add Account button (should be false when in sheet context)
    var showAddAccount: Bool = true
    @Environment(\.dismiss) var dismiss
    @State private var accountToRemove: SavedAccount?
    @State private var showRemoveConfirmation = false

    var body: some View {
        List {
            if accountsStore.accounts.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Accounts", comment: "Empty state title when no accounts are saved")
                            .font(.headline)

                        Text("Add an account to get started. You can add multiple accounts and switch between them.", comment: "Empty state description")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section {
                    ForEach(accountsStore.accounts) { account in
                        Button {
                            if account.pubkey != accountsStore.activePubkey {
                                switchToAccount(account)
                            }
                        } label: {
                            ManageAccountsRow(
                                account: account,
                                isActive: account.pubkey == accountsStore.activePubkey,
                                profiles: state.profiles
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                accountToRemove = account
                                showRemoveConfirmation = true
                            } label: {
                                Label(NSLocalizedString("Remove", comment: "Swipe action to remove an account"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Saved Accounts", comment: "Section header for saved accounts list")
                }
            }

            if showAddAccount {
                Section {
                    NavigationLink(value: Route.Login) {
                        Label {
                            Text("Add Account", comment: "Button to add a new account")
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Manage Accounts", comment: "Navigation title for Manage Accounts view"))
        .navigationBarTitleDisplayMode(.large)
        .alert(
            NSLocalizedString("Remove Account", comment: "Alert title for removing an account"),
            isPresented: $showRemoveConfirmation,
            presenting: accountToRemove
        ) { account in
            Button(NSLocalizedString("Cancel", comment: "Cancel removing account"), role: .cancel) {
                accountToRemove = nil
            }
            Button(NSLocalizedString("Remove", comment: "Confirm removing account"), role: .destructive) {
                removeAccount(account)
            }
        } message: { account in
            let displayName = account.displayName ?? abbreviatedPubkey(account.pubkey)
            let storageWarning = account.hasPrivateKey ? KeyStorageSettings.mode.warningForDeletion : ""
            let baseMessage = NSLocalizedString("Are you sure you want to remove \(displayName)?", comment: "Alert message confirming account removal")
            if account.hasPrivateKey {
                Text("\(baseMessage)\n\n\(storageWarning)")
            } else {
                Text(baseMessage)
            }
        }
    }

    private func switchToAccount(_ account: SavedAccount) {
        accountsStore.setActive(account.pubkey, allowDuringOnboarding: true)
        dismiss()
    }

    private func removeAccount(_ account: SavedAccount) {
        accountsStore.remove(account.pubkey)
        accountToRemove = nil
    }

    private func abbreviatedPubkey(_ pubkey: Pubkey) -> String {
        let hex = pubkey.npub
        return String(hex.prefix(8)) + "..." + String(hex.suffix(4))
    }
}

struct ManageAccountsRow: View {
    let account: SavedAccount
    let isActive: Bool
    let profiles: Profiles

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            profilePicture
                .frame(width: 44, height: 44)

            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(abbreviatedPubkey)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Key type badge (right-aligned, fixed width for alignment)
            HStack(spacing: 8) {
                if account.hasPrivateKey {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .frame(width: 28, height: 28)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }

                // Active indicator (always reserve space for alignment)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                    .frame(width: 24, height: 24)
                    .opacity(isActive ? 1 : 0)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.1) : nil)
    }

    @ViewBuilder
    private var profilePicture: some View {
        if let avatarURL = account.avatarURL {
            KFAnimatedImage(avatarURL)
                .imageContext(.pfp, disable_animation: true)
                .cancelOnDisappear(true)
                .placeholder { _ in
                    placeholderCircle
                }
                .scaledToFill()
                .clipShape(Circle())
        } else if let profilePic = profiles.lookup(id: account.pubkey)?.picture,
                  let url = URL(string: profilePic) {
            KFAnimatedImage(url)
                .imageContext(.pfp, disable_animation: true)
                .cancelOnDisappear(true)
                .placeholder { _ in
                    placeholderCircle
                }
                .scaledToFill()
                .clipShape(Circle())
        } else {
            // Robohash fallback
            KFAnimatedImage(URL(string: robohash(account.pubkey)))
                .imageContext(.pfp, disable_animation: true)
                .cancelOnDisappear(true)
                .placeholder { _ in
                    placeholderCircle
                }
                .scaledToFill()
                .clipShape(Circle())
        }
    }

    private var placeholderCircle: some View {
        Circle()
            .foregroundColor(DamusColors.mediumGrey)
    }

    private var displayName: String {
        if let name = account.displayName, !name.isEmpty {
            return name
        }
        // Try to get name from profiles
        if let profile = profiles.lookup(id: account.pubkey) {
            if let displayName = profile.display_name, !displayName.isEmpty {
                return displayName
            }
            if let name = profile.name, !name.isEmpty {
                return name
            }
        }
        return abbreviatedPubkey
    }

    private var abbreviatedPubkey: String {
        let npub = account.pubkey.npub
        return String(npub.prefix(8)) + "..." + String(npub.suffix(4))
    }
}

#Preview {
    NavigationStack {
        ManageAccountsSettingsView(
            state: test_damus_state,
            accountsStore: AccountsStore.shared
        )
    }
}
