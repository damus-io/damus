//
//  TimeDot.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct TimeDot: View {
    var body: some View {
        Text(verbatim: "⋅")
            .font(.footnote)
            .foregroundColor(DamusColors.mediumGrey)
    }
}

struct TimeDot_Previews: PreviewProvider {
    static var previews: some View {
        TimeDot()
    }
}
