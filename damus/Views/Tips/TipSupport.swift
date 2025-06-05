//
//  TipSupport.swift
//  damus
//
//  Created by Terry Yiu on 6/7/25.
//  Copied from https://medium.com/@navinkumar7582/tipkit-handling-tip-on-view-refresh-and-flickering-issues-2caee3dc7dfb
//

import Foundation
import TipKit

/// Protocol for ensuring compatibility.
/// Enables tips to be passed and stored as properties without availability issues.
protocol TipSupport {
    @available(iOS 17, *)
    var tip: AnyTip { get }
}

@available(iOS 17, *)
extension Tip where Self : TipSupport {
    var tip: AnyTip { AnyTip(self) }
}
