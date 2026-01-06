//
//  RelativeTime.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct RelativeTime: View {
    @ObservedObject var time: RelativeTimeModel
    let size: EventViewKind
    let font_size: Double
    
    var body: some View {
        Text(verbatim: "\(time.value)")
            .font(eventviewsize_to_font(size, font_size: font_size))
            .foregroundColor(DamusColors.mediumGrey)
    }
}


struct RelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        RelativeTime(time: RelativeTimeModel(), size: .normal, font_size: 1.0)
    }
}
