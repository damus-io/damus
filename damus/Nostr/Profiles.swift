//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation
import UIKit
import Combine

class ImageCache {
    private let lock = NSLock()
    
    lazy var cache: NSCache<AnyObject, AnyObject> = {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.totalCostLimit = 1024 * 1024 * 100 // 100MB
        return cache
    }()
    
    func lookup(for url: URL) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        
        if let decoded = cache.object(forKey: url as AnyObject) as? UIImage {
            return decoded
        }
        
        return nil
    }
    
    func remove(for url: URL) {
        lock.lock(); defer { lock.unlock() }
        cache.removeObject(forKey: url as AnyObject)
    }
    
    func insert(_ image: UIImage?, for url: URL) {
        guard let image = image else { return remove(for: url) }
        let decodedImage = image.decodedImage(Int(PFP_SIZE!))
        lock.lock(); defer { lock.unlock() }
        cache.setObject(decodedImage, forKey: url as AnyObject)
    }
    
    subscript(_ key: URL) -> UIImage? {
        get {
            return lookup(for: key)
        }
        set {
            return insert(newValue, for: key)
        }
    }
}

func load_image(cache: ImageCache, from url: URL) -> AnyPublisher<UIImage?, Never> {
    if let image = cache[url] {
        return Just(image).eraseToAnyPublisher()
    }
    return URLSession.shared.dataTaskPublisher(for: url)
        .map { (data, response) -> UIImage? in return UIImage(data: data) }
        .catch { error in return Just(nil) }
        .handleEvents(receiveOutput: { image in
            guard let image = image else { return }
            cache[url] = image
        })
        .subscribe(on: DispatchQueue.global(qos: .background))
        .receive(on: RunLoop.main)
        .eraseToAnyPublisher()
}

class Profiles: ObservableObject {
    @Published var profiles: [String: TimestampedProfile] = [:]
    
    func add(id: String, profile: TimestampedProfile) {
        profiles[id] = profile
        objectWillChange.send()
    }
    
    func lookup(id: String) -> Profile? {
        return profiles[id]?.profile
    }
    
    func lookup_with_timestamp(id: String) -> TimestampedProfile? {
        return profiles[id]
    }
}
