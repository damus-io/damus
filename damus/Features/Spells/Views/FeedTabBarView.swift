//
//  FeedTabBarView.swift
//  damus
//
//  Scrollable horizontal tab bar for switching between feeds.
//  The first tab is always "Following", followed by spell feeds.
//  A [+] button at the end opens the feed discovery sheet.
//

import SwiftUI

/// A horizontal scrollable tab bar for switching between feeds.
///
/// Design follows NN Group best practices:
/// - Single row only (no stacked rows)
/// - Labels: 1-2 words max
/// - High-use content (Following) first and selected by default
/// - 44pt minimum touch target
/// - Underline + bold for selected tab (two visual indicators)
struct FeedTabBarView: View {
    @ObservedObject var store: FeedTabStore
    let onAddTapped: () -> Void

    @Namespace private var tabNamespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.tabs) { tab in
                    tabButton(tab)
                }
                addButton
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Feed tabs", comment: "Accessibility label for the feed tab bar"))
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: FeedTab) -> some View {
        let isSelected = tab.id == store.selectedTabId
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.selectTab(tab.id)
            }
        } label: {
            VStack(spacing: 4) {
                Text(tab.label)
                    .font(.system(size: 14, weight: isSelected ? .heavy : .medium))
                    .foregroundColor(isSelected ? .primary : .gray)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if isSelected {
                    Rectangle()
                        .fill(RECTANGLE_GRADIENT)
                        .frame(height: 2.5)
                        .cornerRadius(2.5)
                        .matchedGeometryEffect(id: "feed_tab_indicator", in: tabNamespace)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityHint(isSelected
            ? NSLocalizedString("Currently selected feed", comment: "VoiceOver hint for the selected feed tab")
            : String(format: NSLocalizedString("Switch to %@ feed", comment: "VoiceOver hint for unselected feed tab"), tab.label)
        )
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: onAddTapped) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(NSLocalizedString("Add feed", comment: "Accessibility label for the add feed button"))
    }
}
