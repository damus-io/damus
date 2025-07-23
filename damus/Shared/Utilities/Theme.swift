//
//  Theme.swift
//  damus
//
//  Created by Ben Weeks on 1/1/23.
//

import Foundation
import UIKit

class Theme {
    
    static var safeAreaInsets: UIEdgeInsets? {
        return this_app
                .connectedScenes
                .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                .first { $0.isKeyWindow }?.safeAreaInsets
    }
}
