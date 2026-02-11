//
//  KFOptionSetter+.swift
//  damus
//
//  Created by Oleg Abalonski on 2/15/23.
//

import UIKit
import Kingfisher

extension KFOptionSetter {
    
    func imageContext(_ imageContext: ImageContext, disable_animation: Bool) -> Self {
        options.callbackQueue = .dispatch(.global(qos: .background))
        options.processingQueue = .dispatch(.global(qos: .background))
        options.downloader = CustomImageDownloader.shared
        options.processor = CustomImageProcessor(
            maxSize: imageContext.maxMebibyteSize(),
            downsampleSize: imageContext.downsampleSize()
        )
        options.cacheSerializer = CustomCacheSerializer(
            maxSize: imageContext.maxMebibyteSize(),
            downsampleSize: imageContext.downsampleSize()
        )
        options.loadDiskFileSynchronously = false
        options.backgroundDecode = true
        options.cacheOriginalImage = true
        options.scaleFactor = UIScreen.main.scale
        options.onlyLoadFirstFrame = disable_animation
        
        switch imageContext {
        case .pfp, .favicon:
            options.diskCacheExpiration = .days(60)
            break
        case .banner:
            options.diskCacheExpiration = .days(5)
            break
        case .note:
            options.diskCacheExpiration = .days(1)
            break
        }
        
        return self
    }
    
    func image_fade(duration: TimeInterval) -> Self {
        options.transition = ImageTransition.fade(duration)
        options.keepCurrentImageWhileLoading = false
        
        return self
    }
    
    func onFailure(fallbackUrl: URL?, cacheKey: String?) -> Self {
        guard let url = fallbackUrl, let key = cacheKey else { return self }
        let imageResource = Kingfisher.KF.ImageResource(downloadURL: url, cacheKey: key)
        let source = imageResource.convertToSource()
        options.alternativeSources = [source]
        
        return self
    }
    
    /// This allows you to observe the size of the image, and get a callback when the size changes
    /// This is useful for when you need to layout views based on the size of the image
    /// - Parameter size_changed: A callback that will be called when the size of the image changes
    /// - Returns: The same KFOptionSetter instance
    func observe_image_size(size_changed: @escaping (CGSize) -> Void) -> Self {
        let modifier = AnyImageModifier { image -> KFCrossPlatformImage in
            let image_size = image.size
            DispatchQueue.main.async { [size_changed, image_size] in
                size_changed(image_size)
            }
            return image
        }
        options.imageModifier = modifier
        return self
    }
}

let MAX_FILE_SIZE = 20_971_520 // 20MiB

enum ImageContext {
    case pfp
    case banner
    case note
    case favicon

    func maxMebibyteSize() -> Int {
        switch self {
        case .favicon:
            return 512_000 // 500KiB
        case .pfp:
            return 5_242_880 // 5MiB
        case .banner, .note:
            return 20_971_520 // 20MiB
        }
    }
    
    func downsampleSize() -> CGSize {
        switch self {
        case .favicon:
            return CGSize(width: 18, height: 18)
        case .pfp:
            return CGSize(width: 200, height: 200)
        case .banner:
            return CGSize(width: 750, height: 250)
        case .note:
            return CGSize(width: 500, height: 500)
        }
    }
}

/// Quick check for SVG signatures without converting the entire Data to String.
/// SVGs start with "<svg" or "<?xml" (possibly after whitespace/BOM).
private func data_looks_like_svg(_ data: Data) -> Bool {
    // Skip leading whitespace and BOM
    let limit = min(data.count, 256)
    var i = 0
    while i < limit {
        let b = data[i]
        if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0xEF || b == 0xBB || b == 0xBF {
            i += 1
            continue
        }
        // Must start with '<'
        return b == 0x3C // '<'
    }
    return false
}

struct CustomImageProcessor: ImageProcessor {
    
    let maxSize: Int
    let downsampleSize: CGSize
    
    let identifier = "com.damus.customimageprocessor"
    
    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {

        switch item {
        case .image:
            // This case will never run
            return DefaultImageProcessor.default.process(item: item, options: options)
        case .data(let data):

            // Handle SVG image — check magic bytes before attempting
            // a full String conversion to avoid allocating on binary data
            if data.count > 4, data_looks_like_svg(data),
               let dataString = String(data: data, encoding: .utf8),
               let svg = SVG(dataString) {

                    let render = UIGraphicsImageRenderer(size: svg.size)
                    let image = render.image { context in
                        svg.draw(in: context.cgContext)
                    }

                    return image.kf.scaled(to: options.scaleFactor)
            }

            // Always downsample to target size. This uses
            // CGImageSourceCreateThumbnailAtIndex which decodes directly at
            // the target resolution, avoiding a full-size decode that CA
            // would otherwise redo on the main thread during commit.
            return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
        }
    }
}

struct CustomCacheSerializer: CacheSerializer {
    
    let maxSize: Int
    let downsampleSize: CGSize

    func data(with image: Kingfisher.KFCrossPlatformImage, original: Data?) -> Data? {
        return DefaultCacheSerializer.default.data(with: image, original: original)
    }

    func image(with data: Data, options: Kingfisher.KingfisherParsedOptionsInfo) -> Kingfisher.KFCrossPlatformImage? {
        return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
    }
}

class CustomSessionDelegate: SessionDelegate, @unchecked Sendable {
    override func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let contentLength = response.expectedContentLength
        
        // Content-Length header is optional (-1 when missing)
        if (contentLength != -1 && contentLength > MAX_FILE_SIZE) {
            return await super.urlSession(session, dataTask: dataTask, didReceive: URLResponse())
        }
        
        return await super.urlSession(session, dataTask: dataTask, didReceive: response)
    }
}


class CustomImageDownloader: ImageDownloader, @unchecked Sendable {
    
    static let shared = CustomImageDownloader(name: "shared")
    
    override init(name: String) {
        super.init(name: name)
        sessionDelegate = CustomSessionDelegate()
    }
}
