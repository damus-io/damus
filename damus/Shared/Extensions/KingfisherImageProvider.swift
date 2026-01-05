//
//  KingfisherImageProvider.swift
//  damus
//
//  Created by alltheseas on 2026-01-03.
//

import SwiftUI
import Kingfisher
import MarkdownUI

/// A custom image provider for MarkdownUI that uses Kingfisher for image loading.
/// This provides proper aspect ratio handling and caching for images in longform markdown content.
struct KingfisherImageProvider: ImageProvider {
    let disable_animation: Bool

    init(disable_animation: Bool = false) {
        self.disable_animation = disable_animation
    }

    func makeImage(url: URL?) -> some View {
        KingfisherMarkdownImage(url: url, disable_animation: disable_animation)
    }
}

extension ImageProvider where Self == KingfisherImageProvider {
    /// A Kingfisher-based image provider for loading images with proper caching and aspect ratio handling.
    static var kingfisher: Self { .init() }

    /// A Kingfisher-based image provider with animation disabled.
    static func kingfisher(disable_animation: Bool) -> Self {
        .init(disable_animation: disable_animation)
    }
}

// MARK: - InlineImageProvider (for images mixed with text)

/// A custom inline image provider for MarkdownUI that uses Kingfisher for loading inline images.
/// This handles images that appear within text content (not standalone image paragraphs).
struct KingfisherInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        return try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let imageResult):
                    continuation.resume(returning: Image(uiImage: imageResult.image))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension InlineImageProvider where Self == KingfisherInlineImageProvider {
    /// A Kingfisher-based inline image provider for loading images within text.
    static var kingfisher: Self { .init() }
}

// MARK: - ImageProvider View (for standalone image paragraphs)

/// Internal view that handles the actual Kingfisher image loading for markdown content.
/// Uses state to track loaded image dimensions for proper aspect ratio sizing.
private struct KingfisherMarkdownImage: View {
    let url: URL?
    let disable_animation: Bool
    @State private var imageSize: CGSize?

    /// Returns a valid aspect ratio, guarding against zero/invalid dimensions.
    private var safeAspectRatio: CGSize {
        guard let size = imageSize, size.width > 0, size.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return size
    }

    var body: some View {
        if let url {
            KFAnimatedImage(url)
                .callbackQueue(.dispatch(.global(qos: .background)))
                .backgroundDecode(true)
                .imageContext(.note, disable_animation: disable_animation)
                .image_fade(duration: 0.25)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .observe_image_size { size in
                    imageSize = size
                }
                .aspectRatio(safeAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .kfClickable()
        } else {
            EmptyView()
        }
    }
}
