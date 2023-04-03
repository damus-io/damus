//
//  ThiccDivider.swift
//  damus
//
//  Created by William Casarin on 2023-04-03.
//

import SwiftUI

struct ThiccDivider: View {
    var body: some View {
        Rectangle()
            .frame(height: 4)
            .foregroundColor(DamusColors.adaptableGrey)
    }
}

struct ThiccDivider_Previews: PreviewProvider {
    static var previews: some View {
        ThiccDivider()
    }
}
