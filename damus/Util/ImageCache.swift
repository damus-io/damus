//
//  ImageCache.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation
import SwiftUI
import UIKit

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
    
    lazy var cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 1024 * 1024 * 100 // 100MB
        return cache
    }()
    
    // simple polling until I can figure out a better way to do this
    func wait_for_image(_ key: String) async {
        while true {
            let why_would_this_happen: ()? = try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if why_would_this_happen == nil {
                return
            }
            if get_state(key) == .done {
                return
            }
        }
    }
    
    func lookup_sync(key: String) -> UIImage? {
        let status = get_state(key)
        
        switch status {
        case .done:
            break
        case .processing:
            return nil
        case .none:
            return nil
        }
        
        if let decoded = cache.object(forKey: NSString(string: key)) {
            return decoded
        }
            
        return nil
    }
    
    func lookup_or_load_image(key: String, url: URL?) async -> UIImage? {
        if let img = await lookup(key: key) {
            return img
        }
        
        guard let url = url else {
            return nil
        }

        return await load_image(cache: self, from: url, key: key)
    }
    
    func get_cache_url(key: String, suffix: String, ext: String = "png") -> URL? {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        
        guard let root = urls.first else {
            return nil
        }
        
        return root.appendingPathComponent("\(key)\(suffix).\(ext)")
    }
    
    private func lookup_file_cache(key: String, suffix: String = "_pfp") -> UIImage? {
        guard let img_file = get_cache_url(key: key, suffix: suffix) else {
            return nil
        }
        
        guard let img = UIImage(contentsOfFile: img_file.path) else {
            //print("failed to load \(key)\(suffix).png from file cache")
            return nil
        }
        
        save_to_memory_cache(key: key, img: img)
        
        return img
    }
    
    func lookup(key: String) async -> UIImage? {
        let status = get_state(key)
        
        switch status {
        case .done:
            break
        case .processing:
            await wait_for_image(key)
        case .none:
            return lookup_file_cache(key: key)
        }
        
        if let decoded = cache.object(forKey: NSString(string: key)) {
            return decoded
        }
            
        return nil
    }
    
    func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        cache.removeObject(forKey: NSString(string: key))
    }
    
    func insert(_ image: UIImage, key: String) async -> UIImage? {
        let scale = await UIScreen.main.scale
        let size = CGSize(width: PFP_SIZE * scale, height: PFP_SIZE * scale)
        
        set_state(key, new_state: .processing)
        
        let decoded_image = await image.byPreparingThumbnail(ofSize: size)
        
        save_to_memory_cache(key: key, img: decoded_image ?? UIImage())
        if let img = decoded_image {
            if !save_to_file_cache(key: key, img: img) {
                print("failed saving \(key) pfp to file cache")
            }
        }
        
        return decoded_image
    }
    
    func save_to_file_cache(key: String, img: UIImage, suffix: String = "_pfp") -> Bool {
        guard let url = get_cache_url(key: key, suffix: suffix) else {
            return false
        }
        
        guard let data = img.pngData() else {
            return false
        }
        
        return (try? data.write(to: url)) != nil
    }
    
    func save_to_memory_cache(key: String, img: UIImage) {
        lock.lock()
        cache.setObject(img, forKey: NSString(string: key))
        state[key] = .done
        lock.unlock()
    }
}

func load_image(cache: ImageCache, from url: URL, key: String) async -> UIImage? {
    guard let (data, _) = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    
    guard let img = UIImage(data: data) else {
        return nil
    }
    
    return await cache.insert(img, key: key)
}


func hashed_hexstring(_ str: String) -> String {
    guard let data = str.data(using: .utf8) else {
        return str
    }
    
    return hex_encode(sha256(data))
}
    
func pfp_cache_key(url: URL) -> String {
    return hashed_hexstring(url.absoluteString)
}
