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
    
    func store(evid: String, preview: LPLinkMetadata?)  {
        switch preview {
        case .none:
            previews[evid] = .failed
        case .some(let meta):
            previews[evid] = .value(CachedMetadata(meta: meta))
        }
    }
    
    init() {
        self.previews = [:]
        self.image_meta = [:]
    }
}
