//
//  SpellOnboardingView.swift
//  damus
//
//  First-encounter education sheet explaining custom feeds (spells).
//

import SwiftUI

/// A brief education sheet shown once when the user first sees feed tabs.
///
/// Explains what custom feeds are and how to discover or create them.
struct SpellOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DamusColors.purple, .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Custom Feeds", comment: "Onboarding title for spell feeds")
                .font(.title2.weight(.bold))

            VStack(spacing: 16) {
                featureRow(
                    icon: "rectangle.stack",
                    text: NSLocalizedString("Swipe between feeds using the tabs at the top", comment: "Onboarding feature 1")
                )
                featureRow(
                    icon: "plus.circle",
                    text: NSLocalizedString("Tap + to discover feeds from the network or create your own", comment: "Onboarding feature 2")
                )
                featureRow(
                    icon: "slider.horizontal.3",
                    text: NSLocalizedString("Filter by event type, author, time range, hashtags, and more", comment: "Onboarding feature 3")
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Get Started", comment: "Onboarding dismiss button")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [DamusColors.purple, .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DamusColors.adaptableWhite.ignoresSafeArea())
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DamusColors.purple)
                .frame(width: 28)

            Text(text)
                .font(.callout)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}
