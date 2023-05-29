//
//  PreviewCache.swift
//  damus
//
//  Created by William Casarin on 2023-01-02.
//

import Foundation
import LinkPresentation

class CachedMetadata {
    let meta: LPLinkMetadata
    var intrinsic_height: CGFloat?
    
    init(meta: LPLinkMetadata) {
        self.meta = meta
        self.intrinsic_height = nil
    }
}

enum Preview {
    case value(CachedMetadata)
    case failed
    
    init(meta: LPLinkMetadata?) {
        if let meta {
            self = .value(CachedMetadata(meta: meta))
        } else {
            self = .failed
        }
    }
    
    static func fetch_metadata(for url: URL) async -> LPLinkMetadata? {
        // iOS 15 is crashing for some reason
        guard #available(iOS 16, *) else {
            return nil
        }
        
        let provider = LPMetadataProvider()
        
        do {
            return try await provider.startFetchingMetadata(for: url)
        } catch {
            return nil
        }
    }
    
}

enum PreviewState {
    case not_loaded
    case loading
    case loaded(Preview)
    
    var should_preload: Bool {
        switch self {
        case .loaded:
            return false
        case .loading:
            return false
        case .not_loaded:
            return true
        }
    }
}

class PreviewCache {
    private var previews: [String: Preview]
    private var image_meta: [String: ImageFill]
    
    func lookup(_ evid: String) -> Preview? {
        return previews[evid]
    }
    
    func lookup_image_meta(_ evid: String) -> ImageFill? {
        return image_meta[evid]
    }
    
    func cache_image_meta(evid: String, image_fill: ImageFill) {
        self.image_meta[evid] = image_fill
    }
    
    init() {
        self.previews = [:]
        self.image_meta = [:]
    }
}
