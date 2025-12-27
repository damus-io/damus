//
//  AccountSwitcherSheet.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import SwiftUI
import Kingfisher

/// A sheet that allows quickly switching between saved accounts
struct AccountSwitcherSheet: View {
    let damus_state: DamusState
    @ObservedObject var accountsStore: AccountsStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var navigationCoordinator = NavigationCoordinator()

    var body: some View {
        NavigationStack(path: $navigationCoordinator.path) {
            List {
                Section {
                    ForEach(accountsStore.accounts) { account in
                        Button {
                            if account.pubkey != accountsStore.activePubkey {
                                switchToAccount(account)
                            }
                        } label: {
                            AccountSwitcherRow(
                                account: account,
                                isActive: account.pubkey == accountsStore.activePubkey,
                                profiles: damus_state.profiles
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("Switch Account", comment: "Section header for account switcher")
                }

                Section {
                    NavigationLink(value: Route.Login) {
                        Label {
                            Text("Add Account", comment: "Button to add a new account")
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    NavigationLink(destination: ManageAccountsSettingsView(state: damus_state, accountsStore: accountsStore, showAddAccount: false)) {
                        Label {
                            Text("Manage Accounts", comment: "Button to manage accounts")
                        } icon: {
                            Image(systemName: "gearshape")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Accounts", comment: "Navigation title for account switcher"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                route.view(navigationCoordinator: navigationCoordinator, damusState: damus_state)
            }
        }
    }

    private func switchToAccount(_ account: SavedAccount) {
        accountsStore.setActive(account.pubkey, allowDuringOnboarding: true)
        dismiss()
    }
}

struct AccountSwitcherRow: View {
    let account: SavedAccount
    let isActive: Bool
    let profiles: Profiles

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            profilePicture
                .frame(width: 40, height: 40)

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
                    .font(.title3)
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

/// A small badge showing the number of saved accounts
struct AccountCountBadge: View {
    let count: Int

    var body: some View {
        if count > 1 {
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    AccountSwitcherSheet(
        damus_state: test_damus_state,
        accountsStore: AccountsStore.shared
    )
}
