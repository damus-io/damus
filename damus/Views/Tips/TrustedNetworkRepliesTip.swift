//
//  TrustedNetworkRepliesTip.swift
//  damus
//
//  Created by Terry Yiu on 6/7/25.
//

import Foundation
import TipKit

@available(iOS 17, *)
struct TrustedNetworkRepliesTip: Tip {
    static let shared = TrustedNetworkRepliesTip()

    var title: Text {
        Text("Toggle visibility of replies from outside your trusted network", comment: "Title of tip that informs users what trusted network means and that they can toggle the visibility of threaded replies from outside their trusted network.")
    }

    var message: Text? {
        Text("Your trusted network is comprised of profiles you follow and profiles that they follow.", comment: "Description of the tip that informs users what trusted network means.")
    }

    var image: Image? {
        Image(systemName: "network.badge.shield.half.filled")
    }
}
