//
//  ExtraFonts.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-13.
//
import SwiftUI

extension Font {
    // Note: When changing the font size accessibility setting, these styles only update after an app restart. It's a current limitation of this.
    
    static let veryLargeTitle: Font = .system(size: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize * 1.5, weight: .bold) // Makes a bigger title while allowing for iOS dynamic font sizing to take effect
    static let veryVeryLargeTitle: Font = .system(size: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize * 2.1, weight: .bold) // Makes a bigger title while allowing for iOS dynamic font sizing to take effect
}

