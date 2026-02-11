//
//  VineTimelineView.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI

/// Scrollable feed of Vine short-video cards with pull-to-refresh and full-screen pager.
public struct VineTimelineView: View {
    let damus_state: DamusState
    @StateObject private var model: VineFeedModel
    @State private var presentingFullScreen = false
    @State private var fullScreenIndex = 0

    init(damus_state: DamusState) {
        self.damus_state = damus_state
        _model = StateObject(wrappedValue: VineFeedModel(damus_state: damus_state))
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if let message = model.relayMessage {
                    infoBanner(text: message)
                }
                ForEach(Array(model.vines.enumerated()), id: \.1.id) { index, vine in
                    VineCard(
                        vine: vine,
                        damus_state: damus_state,
                        onAppear: { model.noteAppeared(at: index) },
                        onOpenFullScreen: {
                            fullScreenIndex = index
                            presentingFullScreen = true
                        }
                    )
                }
                if model.vines.isEmpty && !model.isLoading && model.relayMessage == nil {
                    Text(NSLocalizedString("No Vine videos yet. Pull down to refresh.", comment: "Empty state message when no Vine videos have loaded."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(DamusColors.adaptableWhite)
        .refreshable { await model.refresh() }
        .overlay {
            if model.isLoading {
                ProgressView()
                    .accessibilityLabel(Text("Loading Vines", comment: "Accessibility label for the Vine feed loading indicator."))
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
                    .shadow(radius: 4)
            }
        }
        .onAppear { model.subscribe() }
        .onDisappear { model.stop(disconnect: true) }
        .onReceive(damus_state.settings.objectWillChange) { _ in
            model.handleSettingsChange()
        }
        .damus_full_screen_cover($presentingFullScreen, damus_state: damus_state) {
            VineFullScreenPager(
                model: model,
                damus_state: damus_state,
                initialIndex: fullScreenIndex,
                onClose: { presentingFullScreen = false }
            )
        }
    }

    private func infoBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundColor(.purple)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
