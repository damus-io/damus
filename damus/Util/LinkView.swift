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

struct LinkViewRepresentable: UIViewRepresentable {
 
    typealias UIViewType = CustomLinkView
    
    var metadata: LPLinkMetadata?
    var url: URL?
 
    func makeUIView(context: Context) -> CustomLinkView {
        
        if let metadata {
            let linkView = CustomLinkView(metadata: metadata)
            return linkView
        }
        
        if let url {
            let linkView = CustomLinkView(url: url)
            return linkView
        }
        
        return CustomLinkView()
    }
 
    func updateUIView(_ uiView: CustomLinkView, context: Context) {
    }
}
