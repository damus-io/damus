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
    private var image_heights: [String: CGFloat]
    
    func lookup(_ evid: String) -> Preview? {
        return previews[evid]
    }
    
    func lookup_image_height(_ evid: String) -> CGFloat? {
        return image_heights[evid]
    }
    
    func cache_image_height(evid: String, height: CGFloat) {
        self.image_heights[evid] = height
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
        self.image_heights = [:]
    }
}
