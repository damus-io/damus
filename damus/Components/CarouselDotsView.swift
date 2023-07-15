//
//  CarouselDotsView.swift
//  damus
//
//  Created by Terry Yiu on 7/15/23.
//

import SwiftUI

struct CarouselDotsView: View {
    let maxCount: Int
    let maxVisibleCount: Int
    @Binding var selectedIndex: Int

    var body: some View {
        if maxCount > 1 {
            HStack {
                let visibleRange = visibleRange()
                ForEach(0 ..< maxCount, id: \.self) { index in
                    if visibleRange.contains(index) {
                        Circle()
                            .fill(index == selectedIndex ? Color("DamusPurple") : Color("DamusLightGrey"))
                            .frame(width: 10, height: 10)
                            .onTapGesture {
                                selectedIndex = index
                            }
                    }
                }
            }
            .padding(.top, CGFloat(8))
            .id(UUID())
        }
    }

    private func visibleRange() -> ClosedRange<Int> {
        let visibleCount = min(maxCount, maxVisibleCount)

        let half = Int(visibleCount / 2)

        // Keep the selected dot in the middle of the visible dots when possible.
        var minVisibleIndex: Int
        var maxVisibleIndex: Int

        if visibleCount % 2 == 0 {
            minVisibleIndex = max(0, selectedIndex - half)
            maxVisibleIndex = min(maxCount - 1, selectedIndex + half - 1)
        } else {
            minVisibleIndex = max(0, selectedIndex - half)
            maxVisibleIndex = min(maxCount - 1, selectedIndex + half)
        }

        // Adjust min and max to be within the bounds of what is visibly allowed.
        if (maxVisibleIndex - minVisibleIndex + 1) < visibleCount {
            if minVisibleIndex == 0 {
                maxVisibleIndex = visibleCount - 1
            } else if maxVisibleIndex == maxCount - 1 {
                minVisibleIndex = maxVisibleIndex - visibleCount + 1
            }
        } else if (maxVisibleIndex - minVisibleIndex + 1) > visibleCount {
            minVisibleIndex = maxVisibleIndex - maxVisibleCount + 1
        }

        return minVisibleIndex...maxVisibleIndex
    }
}
