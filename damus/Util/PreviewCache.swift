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
    var previews: [String: Preview]
    
    func lookup(_ evid: String) -> Preview? {
        return previews[evid]
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
    }
}
