//
//  KFImageModel.swift
//  damus
//
//  Created by Oleg Abalonski on 1/11/23.
//

import Foundation
import Kingfisher
import SVGKit

class KFImageModel: ObservableObject {
    
    let url: URL?
    let fallbackUrl: URL?
    let processor: ImageProcessor
    let serializer: CacheSerializer
    
    @Published var refreshID = ""
    
    init(url: URL?, fallbackUrl: URL?, maxByteSize: Int, downsampleSize: CGSize) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.processor = CustomImageProcessor(maxSize: maxByteSize, downsampleSize: downsampleSize)
        self.serializer = CustomCacheSerializer(maxSize: maxByteSize, downsampleSize: downsampleSize)
    }
    
    func refresh() -> Void {
        DispatchQueue.main.async {
            self.refreshID = UUID().uuidString
        }
    }
    
    func cache(_ image: UIImage, forKey key: String) -> Void {
        KingfisherManager.shared.cache.store(image, forKey: key, processorIdentifier: processor.identifier) { _ in
            self.refresh()
        }
    }
    
    func downloadFailed() -> Void {
        guard let url = url, let fallbackUrl = fallbackUrl else { return }
        
        DispatchQueue.global(qos: .background).async {
            KingfisherManager.shared.downloader.downloadImage(with: fallbackUrl) { result in
                
                var fallbackImage: UIImage {
                    switch result {
                    case .success(let imageLoadingResult):
                        return imageLoadingResult.image
                    case .failure(let error):
                        print(error)
                        return UIImage()
                    }
                }
                
                self.cache(fallbackImage, forKey: url.absoluteString)
            }
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
            if let svgImage = SVGKImage(data: data), let image = svgImage.uiImage {
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
