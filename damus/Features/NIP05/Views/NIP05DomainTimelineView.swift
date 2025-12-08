//
//  NIP05DomainTimelineView.swift
//  damus
//
//  Created by Terry Yiu on 4/11/25.
//

import FaviconFinder
import Kingfisher
import SwiftUI

// MARK: - Timeline View

/// Main view for displaying posts from a NIP-05 domain.
/// Supports both grouped (by author) and chronological timeline modes.
///
/// Features:
/// - Custom header with domain info and filter controls
/// - Grouped mode shows one row per author with post counts
/// - Timeline mode shows all posts chronologically
/// - Filter settings sheet for customizing the view
struct NIP05DomainTimelineView: View {
    let damus_state: DamusState
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    /// Filter settings that control display mode, time range, and content filters.
    @StateObject private var filterSettings = NIP05FilterSettings(enableGroupedMode: true)

    /// Controls visibility of the filter settings sheet.
    @State private var showFilterSheet: Bool = false

    @Environment(\.presentationMode) var presentationMode

    // MARK: - Content Filters

    /// Standard content filters (mutes, blocks, etc.) applied to all events.
    /// Domain-specific filtering is handled by the subscription filter.
    private var contentFilters: ContentFilters {
        ContentFilters(filters: ContentFilters.defaults(damus_state: damus_state))
    }

    // MARK: - Subviews

    /// Custom back button matching iOS navigation style but overlaid on gradient background.
    private var backButton: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 33, height: 33)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
    }

    /// Header section with gradient background, domain info, and filter controls.
    private var headerContent: some View {
        let height: CGFloat = 160.0

        return ZStack(alignment: .topLeading) {
            // Gradient background that fades to transparent at the bottom
            DamusBackground(maxHeight: height)
                .mask(LinearGradient(
                    gradient: Gradient(colors: [.black, .black, .black, .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                ))

            VStack(alignment: .leading, spacing: 8) {
                // Top row: back button, domain title, filter button
                HStack(alignment: .center, spacing: 12) {
                    backButton
                    NIP05DomainTitleView(model: model, nip05_domain_favicon: nip05_domain_favicon)
                    Spacer()
                    NIP05FilterButton(
                        settings: filterSettings,
                        showFilterSheet: $showFilterSheet,
                        isLoading: model.loading || model.loading_more
                    )
                }

                // Second row: author avatars and "Notes from..." text
                NIP05DomainFriendsView(
                    damus_state: damus_state,
                    model: model,
                    nip05_domain_favicon: nip05_domain_favicon
                )
                .padding(.leading, 45) // Align with domain title (after back button width)
            }
            .padding(.horizontal, 16)
            .padding(.top, 50) // Account for status bar / notch
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if filterSettings.enableGroupedMode {
                groupedModeView
            } else {
                timelineModeView
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSettingsSheet
        }
        .onAppear(perform: handleOnAppear)
        .onDisappear(perform: handleOnDisappear)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }

    /// Grouped mode: one row per author with post counts.
    private var groupedModeView: some View {
        ScrollView {
            headerContent

            NIP05GroupedListView(
                damus_state: damus_state,
                events: model.events,
                filter: contentFilters.filter(ev:),
                settings: filterSettings
            )
            .redacted(reason: model.loading ? .placeholder : [])
            .shimmer(model.loading)
            .disabled(model.loading)
        }
        .ignoresSafeArea()
        .padding(.bottom, tabHeight)
    }

    /// Timeline mode: chronological list of all posts.
    private var timelineModeView: some View {
        TimelineView(
            events: model.events,
            loading: .constant(model.loading),
            damus: damus_state,
            show_friend_icon: true,
            filter: contentFilters.filter(ev:)
        ) {
            headerContent
        }
        .ignoresSafeArea()
        .padding(.bottom, tabHeight)
    }

    /// Filter settings sheet for customizing view options.
    private var filterSettingsSheet: some View {
        GroupedFilterSettingsView(settings: filterSettings) {
            // Re-subscribe with updated `since` so the relay returns the full time window.
            // Local filters (keywords, short notes, etc.) are applied by the grouped view's
            // computed properties and don't need a refetch.
            model.unsubscribe()
            model.subscribe(resetEvents: false, since: groupedSince)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Event Handlers

    /// Computes the `since` timestamp for grouped mode relay queries.
    private var groupedSince: UInt32? {
        guard filterSettings.enableGroupedMode else { return nil }
        return UInt32(Date().timeIntervalSince1970) - filterSettings.timeRange.seconds
    }

    /// Subscribes to events on first appearance.
    private func handleOnAppear() {
        guard model.events.all_events.isEmpty else { return }
        model.subscribe(since: groupedSince)
    }

    /// Unsubscribes when view disappears.
    private func handleOnDisappear() {
        model.unsubscribe()
    }
}

// MARK: - Preview

#Preview {
    let damus_state = test_damus_state
    let model = NIP05DomainEventsModel(state: damus_state, domain: "damus.io")
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    NIP05DomainTimelineView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
}
