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
            .foregroundColor(.gray)
    }
}

struct TimeDot_Previews: PreviewProvider {
    static var previews: some View {
        TimeDot()
    }
}
