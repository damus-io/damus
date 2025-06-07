//
//  TipViewModifier.swift
//  damus
//
//  Created by Terry Yiu on 6/7/25.
//  Copied from https://medium.com/@navinkumar7582/tipkit-handling-tip-on-view-refresh-and-flickering-issues-2caee3dc7dfb
//

import Foundation
import TipKit

struct TipViewModifier: ViewModifier {
    let tipSupport: TipSupport?
    let arrowEdge: Edge

    init(_ tip: TipSupport?, arrowEdge: Edge) {
        self.tipSupport = tip
        self.arrowEdge = arrowEdge
    }

    func body(content: Content) -> some View {
        mainView(content)
    }

    @ViewBuilder
    func mainView(_ content: Content) -> some View {
        if #available(iOS 17, *), let tip = tipSupport?.tip {
            content.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func popupTip(_ tip: TipSupport?, arrowEdge: Edge = .top) -> some View {
        modifier(TipViewModifier(tip, arrowEdge: arrowEdge))
    }
}
