//
//  KFOptionSetter+.swift
//  damus
//
//  Created by Oleg Abalonski on 2/15/23.
//

import UIKit
import Kingfisher

extension KFOptionSetter {
    
    func imageContext(_ imageContext: ImageContext) -> Self {
        options.callbackQueue = .dispatch(.global(qos: .background))
        options.processingQueue = .dispatch(.global(qos: .background))
        options.downloader = CustomImageDownloader.shared
        options.backgroundDecode = true
        options.cacheOriginalImage = true
        options.scaleFactor = UIScreen.main.scale
        
        options.processor = CustomImageProcessor(
            maxSize: imageContext.maxMebibyteSize(),
            downsampleSize: imageContext.downsampleSize()
        )
        
        options.cacheSerializer = CustomCacheSerializer(
            maxSize: imageContext.maxMebibyteSize(),
            downsampleSize: imageContext.downsampleSize()
        )
        
        return self
    }
    
    func onFailure(fallbackUrl: URL?, cacheKey: String?) -> Self {
        guard let url = fallbackUrl, let key = cacheKey else { return self }
        let imageResource = ImageResource(downloadURL: url, cacheKey: key)
        let source = imageResource.convertToSource()
        options.alternativeSources = [source]
        
        return self
    }
}

let MAX_FILE_SIZE = 20_971_520 // 20MiB

enum ImageContext {
    case pfp
    case banner
    case note
    
    func maxMebibyteSize() -> Int {
        switch self {
        case .pfp:
            return 5_242_880 // 5Mib
        case .banner, .note:
            return 20_971_520 // 20MiB
        }
    }
    
    func downsampleSize() -> CGSize {
        switch self {
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
        case .image(_):
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
            
            return DefaultImageProcessor.default.process(item: item, options: options)
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
        if data.count > maxSize {
            return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
        }

        return DefaultCacheSerializer.default.image(with: data, options: options)
    }
}

class CustomSessionDelegate: SessionDelegate {
    override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let contentLength = response.expectedContentLength
        
        // Content-Length header is optional (-1 when missing)
        if (contentLength != -1 && contentLength > MAX_FILE_SIZE) {
            return super.urlSession(session, dataTask: dataTask, didReceive: URLResponse(), completionHandler: completionHandler)
        }
        
        super.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }
}

class CustomImageDownloader: ImageDownloader {
    
    static let shared = CustomImageDownloader(name: "shared")
    
    override init(name: String) {
        super.init(name: name)
        sessionDelegate = CustomSessionDelegate()
    }
}
