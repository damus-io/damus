//
//  LongformMarkdownView.swift
//  damus
//
//  Created by Claude on 2026-01-03.
//

import SwiftUI
import MarkdownUI

/// A view that renders longform markdown content with optional sepia mode that adapts to light/dark color scheme.
struct LongformMarkdownView: View {
    let markdown: MarkdownContent
    let disableAnimation: Bool
    /// Line height multiplier (e.g., 1.5 means 1.5x line height)
    let lineHeightMultiplier: CGFloat
    let sepiaEnabled: Bool

    @Environment(\.colorScheme) var colorScheme

    /// Relative line spacing in em units (1.5x multiplier = 0.5em extra spacing)
    /// Guarded against negative values for safety
    private var relativeLineSpacing: CGFloat {
        max(0, lineHeightMultiplier - 1.0)
    }

    var body: some View {
        // Full-width background container
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Markdown(markdown)
                // Override only paragraph style, preserving all other default formatting (headings, lists, etc.)
                .markdownBlockStyle(\.paragraph) { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(relativeLineSpacing))
                        .markdownMargin(top: 0, bottom: 16)
                }
                .markdownImageProvider(.kingfisher(disable_animation: disableAnimation))
                .markdownInlineImageProvider(.kingfisher)
                .frame(maxWidth: 600, alignment: .leading)
                .padding([.leading, .trailing])
            Spacer(minLength: 0)
        }
        .padding(.top)
        .background(sepiaEnabled ? DamusColors.sepiaBackground(for: colorScheme) : Color.clear)
        .foregroundStyle(sepiaEnabled ? DamusColors.sepiaText(for: colorScheme) : Color.primary)
    }
}
