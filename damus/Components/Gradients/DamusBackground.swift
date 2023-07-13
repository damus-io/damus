//
//  DamusBackground.swift
//  damus
//
//  Created by William Casarin on 2023-07-12.
//

import Foundation
import SwiftUI

struct DamusBackground: View {
    let maxHeight: CGFloat

    init(maxHeight: CGFloat = 250.0) {
        self.maxHeight = maxHeight
    }

    var body: some View {
        Image("login-header")
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
            .ignoresSafeArea()
    }
}

struct DamusBackground_Previews: PreviewProvider {
    static var previews: some View {
        DamusBackground()
    }
}
