//
//  ZapDescription.swift
//  damus
//
//  Created by eric on 4/5/23.
//

import Foundation

struct ZapDesc {
    let zaptarget: String
}

func make_zap_description(_ tags: [[String]]) -> ZapDesc {
    var target: String = ""
    var i = tags.count - 1
        
    while i >= 0 {
        let tag = tags[i]
        if tag.count >= 2 && tag[0] == "zap" {
            target = tag[1]
        }
        i -= 1
    }
        
    return ZapDesc(zaptarget: target)
}
