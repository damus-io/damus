//
//  SaveAccountPrompt.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import SwiftUI

struct SaveAccountPrompt: View {
    let keypair: Keypair
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Save this account", comment: "Title for prompt asking user to save the currently active account.")
                    .font(.headline)
                Text("Keep your keys safely in the device keychain to avoid losing access.", comment: "Subtitle explaining why the account should be saved.")
                    .font(.subheadline)
                    .foregroundColor(DamusColors.neutral6)
            }

            Spacer()

            Button(action: onSave) {
                Text("Save", comment: "Button label to save the current account to the device.")
                    .fontWeight(.semibold)
            }
            .buttonStyle(GradientButtonStyle())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.damusAdaptableWhite)
                .shadow(color: DamusColors.purple.opacity(0.15), radius: 6)
        )
        .padding(.horizontal)
        .padding(.top, 12)
    }
}

/// Sheet version of save account prompt - uses sheet presentation for better view isolation
struct SaveAccountSheet: View {
    let keypair: Keypair
    let onSave: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(DamusColors.purple)

                Text("Save this account?", comment: "Title for sheet asking user to save the currently active account.")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Keep your keys safely in the device keychain to avoid losing access.", comment: "Subtitle explaining why the account should be saved.")
                    .font(.body)
                    .foregroundColor(DamusColors.neutral6)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 12) {
                Button(action: {
                    onSave()
                    dismiss()
                }) {
                    Text("Save Account", comment: "Button label to save the current account to the device.")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())

                Button(action: {
                    onDismiss()
                    dismiss()
                }) {
                    Text("Not now", comment: "Button to dismiss save account prompt without saving.")
                        .foregroundColor(DamusColors.neutral6)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}
