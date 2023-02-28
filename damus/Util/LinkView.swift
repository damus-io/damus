//
//  LinkView.swift
//  damus
//
//  Created by Sam DuBois on 12/27/22.
//

import SwiftUI
import LinkPresentation

class CustomLinkView: LPLinkView {
    override var intrinsicContentSize: CGSize { CGSize(width: 0, height: super.intrinsicContentSize.height) }
    
}

enum Metadata {
    case linkmeta(CachedMetadata)
    case url(URL)
}

struct LinkViewRepresentable: UIViewRepresentable {
 
    typealias UIViewType = CustomLinkView
    
    let meta: Metadata
 
    func makeUIView(context: Context) -> CustomLinkView {
        switch meta {
        case .linkmeta(let linkmeta):
            return CustomLinkView(metadata: linkmeta.meta)
        case .url(let url):
            return CustomLinkView(url: url)
        }
    }
 
    func updateUIView(_ uiView: CustomLinkView, context: Context) {
        switch meta {
        case .linkmeta(let cached):
            cached.intrinsic_height = uiView.intrinsicContentSize.height
        case .url:
            return
        }
        
    }
}
