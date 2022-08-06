//
//  ImageCache.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation
import SwiftUI
import Combine

enum ImageProcessingStatus {
    case processing
    case done
}

class ImageCache {
    private let lock = NSLock()
    private var state: [String: ImageProcessingStatus] = [:]
        
    private func get_state(_ key: String) -> ImageProcessingStatus? {
        lock.lock(); defer { lock.unlock() }
        
        return state[key]
    }
    
    private func set_state(_ key: String, new_state: ImageProcessingStatus) {
        lock.lock(); defer { lock.unlock() }
        
        state[key] = new_state
    }
    
    lazy var cache: NSCache<AnyObject, UIImage> = {
        let cache = NSCache<AnyObject, UIImage>()
        cache.totalCostLimit = 1024 * 1024 * 100 // 100MB
        return cache
    }()
    
    // simple polling until I can figure out a better way to do this
    func wait_for_image(_ url: URL) async {
        while true {
            let why_would_this_happen: ()? = try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if why_would_this_happen == nil {
                return
            }
            if get_state(url.absoluteString) == .done {
                return
            }
        }
    }
    
    func lookup_sync(for url: URL) -> UIImage? {
        let status = get_state(url.absoluteString)
        
        switch status {
        case .done:
            break
        case .processing:
            return nil
        case .none:
            return nil
        }
        
        if let decoded = cache.object(forKey: url as AnyObject) {
            return decoded
        }
            
        return nil
    }
    
    func lookup(for url: URL) async -> UIImage? {
        let status = get_state(url.absoluteString)
        
        switch status {
        case .done:
            break
        case .processing:
            await wait_for_image(url)
        case .none:
            return nil
        }
        
        if let decoded = cache.object(forKey: url as AnyObject) {
            return decoded
        }
            
        return nil
    }
    
    func remove(for url: URL) {
        lock.lock(); defer { lock.unlock() }
        cache.removeObject(forKey: url as AnyObject)
    }
    
    func insert(_ image: UIImage, for url: URL) async -> UIImage? {
        let scale = await UIScreen.main.scale
        let size = CGSize(width: PFP_SIZE * scale, height: PFP_SIZE * scale)
        
        let key = url.absoluteString
        
        set_state(key, new_state: .processing)
        
        let decoded_image = await image.byPreparingThumbnail(ofSize: size)
        
        lock.lock()
        cache.setObject(decoded_image ?? UIImage(), forKey: url as AnyObject)
        state[key] = .done
        lock.unlock()
        
        return decoded_image
    }
}

func load_image(cache: ImageCache, from url: URL) async -> UIImage? {
    if let image = await cache.lookup(for: url) {
        return image
    }
    
    guard let (data, _) = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    
    guard let img = UIImage(data: data) else {
        return nil
    }
    
    return await cache.insert(img, for: url)
}
