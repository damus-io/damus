//
//  OfflineConnectivityViews.swift
//  damus
//
//  Created by OpenAI Codex on 2025-01-04.
//

import SwiftUI
import UIKit

struct OfflineStatusPill: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Label {
            Text("Offline", comment: "Short title that indicates the app is offline.")
                .font(.subheadline)
                .bold()
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.subheadline)
        }
        .foregroundColor(DamusColors.deepPurple)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(DamusColors.purple.opacity(colorScheme == .dark ? 0.25 : 0.18))
                )
        )
        .accessibilityElement(children: .combine)
    }
}

struct OfflineConnectivityBanner: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OfflineStatusPill()
            Text("nostr network connectivity unavailable", comment: "Explains that nostr connectivity is unavailable while the user is offline.")
                .font(.footnote)
                .foregroundColor(DamusColors.adaptableBlack.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DamusColors.purple.opacity(colorScheme == .dark ? 0.28 : 0.14))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DamusColors.purple.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 6)
        .accessibilityIdentifier("offline-connectivity-banner")
    }
}

struct FloatingOfflineIndicator: View {
    var body: some View {
        OfflineStatusPill()
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 4)
    }
}

struct ConnectivityBannerHost: View {
    @ObservedObject var signal: SignalModel
    @State private var isVisible = false
    @State private var pendingWorkItem: DispatchWorkItem?
    @State private var didPlayHaptic = false
    
    private let offlineDisplayDelay: TimeInterval = 3
    
    var body: some View {
        Group {
            if isVisible {
                OfflineConnectivityBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            evaluateVisibility()
        }
        .onChange(of: signal.signal) { _ in
            evaluateVisibility()
        }
        .onChange(of: signal.max_signal) { _ in
            evaluateVisibility()
        }
        .onDisappear {
            pendingWorkItem?.cancel()
        }
        .accessibilityAddTraits(.isStaticText)
    }
    
    private var shouldShowBanner: Bool {
        signal.isOffline
    }
    
    private func evaluateVisibility() {
        pendingWorkItem?.cancel()
        
        if shouldShowBanner {
            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = true
                }
                playFeedbackIfNeeded()
            }
            pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + offlineDisplayDelay, execute: workItem)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = false
            }
            didPlayHaptic = false
        }
    }
    
    private func playFeedbackIfNeeded() {
        guard !didPlayHaptic else { return }
        didPlayHaptic = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
