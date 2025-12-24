//
//  AccountPickerView.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import SwiftUI
import Kingfisher

struct AccountPickerView: View {
    @ObservedObject private var accountsStore = AccountsStore.shared
    private let onAddAccount: () -> Void
    private let onCreateAccount: () -> Void
    private let showActions: Bool

    init(onAddAccount: @escaping () -> Void, onCreateAccount: @escaping () -> Void, showActions: Bool = true) {
        self.onAddAccount = onAddAccount
        self.onCreateAccount = onCreateAccount
        self.showActions = showActions
    }

    var body: some View {
        if accountsStore.accounts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Accounts on this device", comment: "Header shown above a list of accounts already saved on this device.")
                    .font(.headline)

                ForEach(accountsStore.accounts) { account in
                    AccountRow(account: account)
                        .onTapGesture {
                            switchToAccount(account)
                        }
                }

                if showActions {
                    HStack(spacing: 12) {
                        Button(action: onAddAccount) {
                            Label {
                                Text("Add account", comment: "Button to add another existing account.")
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                        }

                        Button(action: onCreateAccount) {
                            Label {
                                Text("Create new", comment: "Button to create a new account.")
                            } icon: {
                                Image(systemName: "sparkles")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.damusAdaptableWhite)
                    .shadow(color: DamusColors.purple.opacity(0.15), radius: 6)
            )
        }
    }

    private func switchToAccount(_ account: SavedAccount) {
        AccountsStore.shared.setActive(account.pubkey, allowDuringOnboarding: true)
        guard let keypair = AccountsStore.shared.keypair(for: account.pubkey) else { return }
        notify(.login(keypair))
    }
}

private struct AccountRow: View {
    let account: SavedAccount

    var body: some View {
        HStack {
            profilePicture
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(abbreviatedPubkey)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if account.hasPrivateKey == false {
                    Text("View only", comment: "Label shown when an account has no private key stored.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(DamusColors.neutral6)
                .font(.footnote)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DamusColors.neutral1.opacity(0.8))
        )
    }

    @ViewBuilder
    private var profilePicture: some View {
        let url = account.avatarURL ?? URL(string: robohash(account.pubkey))
        KFImage.url(url)
            .resizable()
            .placeholder { _ in
                placeholderCircle
            }
            .fade(duration: 0.1)
            .scaledToFill()
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(DamusColors.purple.opacity(0.15))
            .overlay(
                Text(String(account.pubkey.npub.suffix(4)))
                    .font(.caption2.monospaced())
                    .foregroundColor(DamusColors.purple)
            )
    }

    private var displayName: String {
        if let name = account.displayName, !name.isEmpty {
            return name
        }
        return abbreviatedPubkey
    }

    private var abbreviatedPubkey: String {
        let npub = account.pubkey.npub
        return String(npub.prefix(8)) + "..." + String(npub.suffix(4))
    }
}
