//
//  KFOptionSetter+.swift
//  damus
//
//  Created by Oleg Abalonski on 2/15/23.
//

import UIKit
import ImageIO
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
            
            // Handle large image size
            if data.count > maxSize {
                return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
            }
            
            // Handle SVG image
            if let dataString = String(data: data, encoding: .utf8),
                let svg = SVG(dataString) {
                
                    let render = UIGraphicsImageRenderer(size: svg.size)
                    let image = render.image { context in
                        svg.draw(in: context.cgContext)
                    }

                    return image.kf.scaled(to: options.scaleFactor)
            }
            
            // Handle animated WebP image
            if let image = animated_webp_image(data: data, options: options) {
                return image
            }
            
            return DefaultImageProcessor.default.process(item: item, options: options)
        }
    }
}

struct CustomCacheSerializer: CacheSerializer {
    
    let maxSize: Int
    let downsampleSize: CGSize

    func data(with image: Kingfisher.KFCrossPlatformImage, original: Data?) -> Data? {
        // Kingfisher would re-encode WebP as a static PNG, so keep the original bytes to preserve animation
        if let original, is_webp_data(original) {
            return original
        }

        return DefaultCacheSerializer.default.data(with: image, original: original)
    }

    func image(with data: Data, options: Kingfisher.KingfisherParsedOptionsInfo) -> Kingfisher.KFCrossPlatformImage? {
        if data.count > maxSize {
            return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
        }

        if let image = animated_webp_image(data: data, options: options) {
            return image
        }

        return DefaultCacheSerializer.default.image(with: data, options: options)
    }
}

/// Checks the RIFF container header for the WebP signature
func is_webp_data(_ data: Data) -> Bool {
    guard data.count >= 12 else {
        return false
    }

    let start = data.startIndex
    return data[start..<start + 4].elementsEqual("RIFF".utf8)
        && data[start + 8..<start + 12].elementsEqual("WEBP".utf8)
}

/// Kingfisher only creates animated images from GIF data and decodes everything else as a single
/// static frame, so animated WebP needs to go through its animated image path explicitly.
///
/// Returns `nil` if the data is not a multi-frame WebP, or if animations are disabled.
func animated_webp_image(data: Data, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
    guard !options.onlyLoadFirstFrame,
          is_webp_data(data),
          let source = WebPFrameSource(data: data),
          source.frameCount > 1 else {
        return nil
    }

    let creating_options = ImageCreatingOptions(
        scale: options.scaleFactor,
        duration: 0.0,
        preloadAll: options.preloadAllAnimationData,
        onlyFirstFrame: false
    )
    return KingfisherWrapper.animatedImage(source: source, options: creating_options)
}

/// Frame source for animated WebP images.
///
/// Mirrors Kingfisher's internal `CGImageFrameSource`, but reads frame delays from the WebP
/// properties dictionary instead of the GIF one.
struct WebPFrameSource: ImageFrameSource {
    static let default_frame_duration: TimeInterval = 0.1

    let data: Data?
    let image_source: CGImageSource
    let source_options: [CFString: Any] = [kCGImageSourceShouldCache: true]

    init?(data: Data) {
        guard let image_source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        self.data = data
        self.image_source = image_source
    }

    var frameCount: Int {
        return CGImageSourceGetCount(image_source)
    }

    /// `maxSize` is ignored to match Kingfisher's GIF frames, which are decoded at full resolution
    func frame(at index: Int, maxSize: CGSize?) -> CGImage? {
        return CGImageSourceCreateImageAtIndex(image_source, index, source_options as CFDictionary)
    }

    func duration(at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(image_source, index, nil) as? [CFString: Any],
              let webp_info = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any],
              let delay = (webp_info[kCGImagePropertyWebPUnclampedDelayTime] ?? webp_info[kCGImagePropertyWebPDelayTime]) as? NSNumber,
              delay.doubleValue > 0.011 else {
            return WebPFrameSource.default_frame_duration
        }
        return delay.doubleValue
    }

    func copy() -> WebPFrameSource {
        guard let data, let copy = WebPFrameSource(data: data) else {
            return self
        }
        return copy
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
