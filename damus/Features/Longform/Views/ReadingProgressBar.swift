//
//  ReadingProgressBar.swift
//  damus
//
//  Created by Claude on 2026-01-03.
//

import SwiftUI

/// A thin progress bar that indicates reading progress through longform content.
struct ReadingProgressBar: View {
    /// Reading progress from 0.0 to 1.0.
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(DamusColors.purple)
                .frame(width: geometry.size.width * min(max(progress, 0), 1))
        }
        .frame(height: 4)
        .background(Color.gray.opacity(0.3))
    }
}

struct ReadingProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ReadingProgressBar(progress: 0)
            ReadingProgressBar(progress: 0.25)
            ReadingProgressBar(progress: 0.5)
            ReadingProgressBar(progress: 0.75)
            ReadingProgressBar(progress: 1.0)
        }
        .padding()
    }
}
