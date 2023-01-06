//
//  PreviewCache.swift
//  damus
//
//  Created by William Casarin on 2023-01-02.
//

import Foundation
import LinkPresentation

enum Preview {
    case value(LinkViewRepresentable)
    case failed
}

class PreviewCache {
    var previews: [String: Preview]
    
    func lookup(_ evid: String) -> Preview? {
        return previews[evid]
    }
    
    func store(evid: String, preview: LinkViewRepresentable?)  {
        switch preview {
        case .none:
            previews[evid] = .failed
        case .some(let meta):
            previews[evid] = .value(meta)
        }
    }
    
    init() {
        self.previews = [:]
    }
}
